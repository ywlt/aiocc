#!/bin/sh
#POSIX
#

#description:    start distributed filesystem automatic I/O congestion control
#     author:    ShijunDeng
#      email:    dengshijun1992@gmail.com
#       time:    2016-12-28
#
#运行本脚本时,假设主控制节点与所有节点(包括编译节点)已经进行SSH认证
#
#前置条件:lustre文件系统运行;workload运行;
#
#
sleeptime=60 #设置检测的睡眠时间
limit=10 #递减下限

#
#计算程序运行的时间
#
start_time=$(date +%s%N)
start_time_ms=${start_time:0:16}

#initialization
cd "$( dirname "${BASH_SOURCE[0]}" )" #get  a Bash script tell what directory it's stored in
if [ ! -f ./__aiocc_init.sh ]; then
    echo "AIOCC Error:initialization failure:cannot find the file __aiocc_init.sh... "
    exit 1
else
    source ./__aiocc_init.sh
    echo 'AIOCC INFO:initialization completed...'
fi

source "${MULTEXU_BATCH_CRTL_DIR}/multexu_lib.sh"
clear_execute_statu_signal 
clear_execute_statu_signal ${AIOCC_EXECUTE_SIGNAL_FILE}
#系统的位数
OS_TYPE="X64"
AX_INT=2147483648
#目录设置
#rule根目录
AIOCC_RULE_DATABASE_DIR=""
#候选规则目录
AIOCC_RULE_CANDIDATE_DIR=""
#从client收集回来的规则的存储目录
AIOCC_RULE_TESTED_DIR=""
#测试产生的结果信息.程序处理结果信息
AIOCC_RULE_RESULT_DIR=""

#EPOCH_DIR_PREFIX="epoch_" 
#搜索策略
search_policy=""
#是否指定初始规则,如指定初始规则,应该在调用本脚本前,将规则的参数值写入initial.rule文件中
initial_rule=0
category="default"
workloads_type=
#控制参数<m,b,t>中的m
enable_m=0
#是否显示输出日志
#根据quiet决定是否将运行中的日志输出到/dev/null,涉及到:scp分发/收集rule scp收集bandwidth统计信息
quiet=0

#benchmark失败次数统计以及上限设定
benchmark_failed_times=0
benchmark_failed_times_limit=10
#规则优化次数上限
candidate_try_limitation=3

#bandwidth最值统计及存储
max_bandwidth=0
max_bandwidth_file=
#var_percentage_threshold的临界值,判断稳定与否
var_percentage_threshold=200
#是否保留旧的测试文件
keep_old_testfiles=0
drop_cache=0

#参数选项
while :;
do
    case $1 in
        --search_policy=?*)
            search_policy=${1#*=}
            shift
            ;;
        --category=?*)
            category=${1#*=}
            shift
            ;;
        --initial_rule=?*)
            initial_rule=${1#*=}
            shift
            ;;
        --workloads_type=?*)
            workloads_type=${1#*=}
            shift
            ;;
        --quiet=?*)
            quiet=${1#*=}
            shift
            ;;
        -?*)
            printf 'WARN: Unknown option (ignored): %s\n' "(" >&2")"
            shift
            ;;
        *)    # Default case: If no more options then break out of the loop.
            shift
            break
    esac        
done

function __initialize()
{
    AIOCC_RULE_DATABASE_DIR="${AIOCC_RULE_DIR}/${category}"
    AIOCC_RULE_CANDIDATE_DIR="${AIOCC_RULE_DATABASE_DIR}/candidate_rules"
    AIOCC_RULE_TESTED_DIR="${AIOCC_RULE_DATABASE_DIR}/tested_rules" 
    AIOCC_RULE_RESULT_DIR="${AIOCC_RULE_DATABASE_DIR}/results" 
    auto_mkdir ${AIOCC_RULE_DATABASE_DIR} "weak"
    auto_mkdir ${AIOCC_RULE_CANDIDATE_DIR} "weak"
    auto_mkdir ${AIOCC_RULE_TESTED_DIR} "weak"
    auto_mkdir ${AIOCC_RULE_RESULT_DIR} "weak"
    max_bandwidth_file="${AIOCC_RULE_DATABASE_DIR}/max_bandwidth" 
    if [ $(getconf WORD_BIT) = '32' -a $(getconf LONG_BIT) = '64' ] ; then
        OS_TYPE="X64"
        #MAX_INT=18446744073709551615
        MAX_INT=18446744073709551615
    else
        OS_TYPE="X32"
        MAX_INT=2147483647
        print_message "MULTEXU_WARN" "Pay attention to the OS_TYPE:${OS_TYPE},X64 is suggested..."
    fi
    
    #非首次启动AIOCC算法时,max_bandwidth_file存在
    if [ -f ${max_bandwidth_file} ];then
        max_bandwidth=`cat $max_bandwidth_file`
    else
        echo $max_bandwidth > $max_bandwidth_file
    fi
    
    clear_execute_statu_signal ${AIOCC_CTROL_SIGNAL_FILE}
}
#
#程序退出时输出一些提示信息
#
function __cleanup()
{
    if [ x"$work_loop" == x"false" ];then
        print_message "MULTEXU_INFO" "work loop terminating SIGNAL detected..."
        exit 0
    else
        #计算程序运行的时间
        end_time=$(date +%s%N)
        end_time_ms=${end_time:0:16}
        #scale=6
        time_cost=0
        time_cost=`echo "scale=6;($end_time_ms - $start_time_ms)/1000000" | bc`
        print_message "MULTEXU_INFO" "AIOCC process finished..."
        print_message "MULTEXU_INFO" "Total time spent:${time_cost} s"
    fi
    rm -f ${AIOCC_CONFIG_DIR}/*.cfg
}

function delete_candidate_rule()
{
    local candidate_rule=$1
    local cmd_var="rm -f ${AIOCC_RULE_CANDIDATE_DIR}/$candidate_rule"
    `$cmd_var`
    sh ${MULTEXU_BATCH_CRTL_DIR}/multexu.sh --iptable=nodes_client.out --cmd="${cmd_var}"
}
#
#检测benchmark是否正常:若正常不做任何操作;不正常程序退出
#$1 benchmark_failed_times $2 benchmark_failed_times_limit
#
function check_benchmark()
{
    if [ $1 -gt $2 ];then
        print_message "MULTEXU_ERROR" "AIOCC terminated abnormally,benchmark failed times: $1,the current limitation of fail times:$2 ..."
        __cleanup
        exit 7
    fi
}

#
#将候选规则发送到client节点
#
function deploy_candidate_rules()
{
    if [ ${quiet} -eq 1 ];then
        sh ${MULTEXU_BATCH_CRTL_DIR}/multexu.sh --iptable=nodes_client.out --sendfile="${AIOCC_RULE_CANDIDATE_DIR}/*" --location="${AIOCC_RULE_CANDIDATE_DIR}" >/dev/null
    else
        sh ${MULTEXU_BATCH_CRTL_DIR}/multexu.sh --iptable=nodes_client.out --sendfile="${AIOCC_RULE_CANDIDATE_DIR}/*" --location="${AIOCC_RULE_CANDIDATE_DIR}"
    fi
}

function run_workloads()
{
    local choice=$1
    local option=
    case $1 in
        fio)
            option="--skip_fio_install=1"
            ;;
        iozone)
            option=""
            ;;
        ?*)
            option=""
            ;;
    esac
    sh ${MULTEXU_BATCH_CRTL_DIR}/multexu.sh --iptable=nodes_client.out --cmd="sh ${AIOCC_WORKLOADS_DIR}/$choice/${choice}_start.sh ${option}"
    echo ${choice}
}
# get rule from a score line
_get_rule_of_scoreline() {
    local score_line=$1
    echo `echo "$score_line" | cut -d',' -f 1`
}

# get score from a score line
_get_score_of_scoreline() {
    local score_line=$1
    echo `echo "$score_line" | cut -d',' -f 2`
}

#
#粗略的检测一个规则文件是否有效:有效的规则文件是指文件存在且其中规则的行数等于第一行的rule_no;
#是有效的规则文件返回0,否则返回1
#
#$1给出规则文件的绝对路径
#
function is_valid_rule()
{
    local candidate=$1
    if [ ! -f ${candidate} ];then
        return 1
    fi
    local rule_no=`head -1 ${candidate} | cut -d , -f 1`
    local rule_file_lines=`wc -l ${candidate} | cut -d ' ' -f 1`
    rule_file_lines=`echo "${rule_file_lines} - 1" | bc`
    if [ ${rule_no} -eq ${rule_file_lines} ];then
       return 0
    fi
    return 1
}

#
#过滤不完整的规则文件
#$1候选规则存储目录
#
function _candidate_filter()
{
    for candidate in $( ls $1 )
    do        
        if ! is_valid_rule $1/${candidate} ;then
            print_message "MULTEXU_WARN" "invalid rule file founded:rule ${candidate},it will be discarded ..."
            rm -f $1/${candidate}
        fi
    done
}

function next_round()
{
    local round_best_score_line=$1
    local epoch=`cat ${AIOCC_RULE_DATABASE_DIR}/epoch.cfg`
    local round=`cat ${epoch_result_dir}/round.cfg`
    local epoch_result_dir=${AIOCC_RULE_DATABASE_DIR}/"epoch_${epoch}"
    local round_best_score=`_get_score_of_scoreline "${round_best_score_line}"`
    local next_rule_sn_file="${AIOCC_RULE_DATABASE_DIR}/next_rule_sn.cfg"

    if [ -f ${next_rule_sn_file} ]; then
        next_rule_sn=`cat ${next_rule_sn_file}`
        if [ x${next_rule_sn} = x ];then
            next_rule_sn=1
        fi
    else
        next_rule_sn=1
        echo ${next_rule_sn} > ${next_rule_sn_file}
    fi

    epoch_best_score_file="${epoch_result_dir}/epoch_${epoch}_best_score.csv"
    if [ ! -f $epoch_best_score_file ]; then
        epoch_best_score_line="0,0"
    else
        epoch_best_score_line=`cat $epoch_best_score_file`
    fi
    epoch_best_score=`_get_score_of_scoreline "${epoch_best_score_line}"`
    # is this round's best score better than current epoch best score?
    # $round_best_score_line = $epoch_best_score_line is possible if
    # the processing of the last round results was interrupted before
    # it can finish
    if [ $round_best_score -gt $epoch_best_score -o $round_best_score_line = $epoch_best_score_line ]; then
        epoch_best_score_line=$round_best_score_line
        echo $epoch_best_score_line >$epoch_best_score_file
        epoch_best_rule=`_get_rule_of_scoreline $epoch_best_score_line`
        if ! is_valid_rule ${AIOCC_RULE_TESTED_DIR}/${epoch_best_rule}/merged_rule.rule ;then
            #退出:它是被用作产生新的规则/split
            print_message "MULTEXU_ERROR" "abnormal program termination:please check ${AIOCC_RULE_TESTED_DIR}/${epoch_best_rule}/merged_rule.rule ..."
            exit 1
        fi
        python ${AIOCC_BATCH_DIR}/generate_candidate_rules.py ${AIOCC_RULE_TESTED_DIR}/${epoch_best_rule}/merged_rule.rule ${AIOCC_RULE_CANDIDATE_DIR} $next_rule_sn ${next_rule_sn_file}
        local generate_rule_str=`cat ${next_rule_sn_file}`
        next_rule_sn=`echo ${generate_rule_str} | cut -d',' -f 1`
        echo $next_rule_sn > ${next_rule_sn_file}
        round=$(( $round + 1 ))
        echo $round > ${epoch_result_dir}/round.cfg
    else
        epoch_best_rule=`_get_rule_of_scoreline $epoch_best_score_line`
        if ! is_valid_rule ${AIOCC_RULE_TESTED_DIR}/${epoch_best_rule}/merged_rule.rule ;then
            #退出:它是被用作产生新的规则/split
            print_message "MULTEXU_ERROR" "abnormal program termination:please check ${AIOCC_RULE_TESTED_DIR}/${epoch_best_rule}/merged_rule.rule ..."
            exit 1
        fi        
        python ${AIOCC_BATCH_DIR}/split_rule.py "${AIOCC_RULE_TESTED_DIR}/${epoch_best_rule}/merged_rule.rule" "${AIOCC_RULE_CANDIDATE_DIR}" $next_rule_sn ${next_rule_sn_file}
        local generate_rule_str=`cat ${next_rule_sn_file}`
        next_rule_sn=`echo ${generate_rule_str} | cut -d',' -f 1`
        echo $next_rule_sn > ${next_rule_sn_file}
        # start a new epoch
        epoch=$(( $epoch + 1 ))
        echo $epoch > ${AIOCC_RULE_DATABASE_DIR}/epoch.cfg
        epoch_result_dir=${AIOCC_RULE_DATABASE_DIR}/"epoch_${epoch}"
        auto_mkdir ${epoch_result_dir} "force"
        round=0
        echo $round >${epoch_result_dir}/round.cfg
    fi
}

function benchmark_rule()
{
    local rs=$1
    local candidate_rule=$2
    local round_summary_file=$3
    local candidate_test_dir=${AIOCC_RULE_TESTED_DIR}/${candidate_rule}
    local candidate_result_dir=${AIOCC_RULE_RESULT_DIR}/${candidate_rule}
    local old_score_line=""
    if [ -f ${round_summary_file} ];then
        old_score_line=`grep "^${candidate_rule}," ${round_summary_file}`
    fi
    if [ x${old_score_line} = x ];then
        local candidate_old_score=0
        local candidate_avg_bandwidth=0
        local candidate_avg_bandwidth_var=0
        local candidate_try=0
    else
        local candidate_old_score=`echo ${old_score_line} | cut -d, -f 2`
        local candidate_avg_bandwidth=`echo ${old_score_line} | cut -d, -f 3`
        local candidate_avg_bandwidth_var=`echo ${old_score_line} | cut -d, -f 4`
        local candidate_try=`echo ${old_score_line} | cut -d, -f 5`
    fi
    
    #
    #再次测试得分最高的规则时会遇到这种情况
    #
    if [ -f ${AIOCC_RULE_CANDIDATE_DIR}/${candidate_rule} ];then
        local candidate_rule_to_use=${AIOCC_RULE_CANDIDATE_DIR}/${candidate_rule}        
    else
        local candidate_rule_to_use="${candidate_test_dir}/merged_rule.rule"
    fi
    
    candidate_try=$(( $candidate_try + 1 ))
    #if [ $candidate_try -eq 1 ];then
    #    auto_mkdir "${candidate_result_dir}" "force"
    #fi
        
    auto_mkdir "${candidate_result_dir}/${candidate_try}" "force"

    auto_mkdir ${candidate_test_dir} "force"
    sh ${MULTEXU_BATCH_CRTL_DIR}/multexu.sh --iptable=nodes_client.out --cmd="sh ${AIOCC_BATCH_DIR}/_set_qos_rules.sh ${candidate_rule_to_use} ${quiet}" 
    print_message "MULTEXU_INFO" "using rule ${candidate_rule_to_use} ..."
    cat ${candidate_rule_to_use}
    #这里需要等待一段时间
    ${PAUSE_CMD}
    sh ${AIOCC_BATCH_DIR}/gather_qos_rules.sh ${candidate_test_dir} ${quiet}
    local_check_status "${AIOCC_EXECUTE_STATUS_FINISHED}"  "1" "1" "${AIOCC_EXECUTE_SIGNAL_FILE}"
    
    python ${AIOCC_BATCH_DIR}/merge_qos_rule_files.py ${candidate_test_dir} ${candidate_test_dir}/"merged_rule.rule"
    wait
    if ! is_valid_rule ${candidate_test_dir}/merged_rule.rule ;then
        #这里暂不退出 因为如果它不是被用作产生新的规则/split 则是无关紧要的
        print_message "MULTEXU_WARN" "invalid merged_rule.rule:please check ${candidate_test_dir}/merged_rule.rule ..."
    fi
    #
    #注意还要处理benchmark失败的情况返回一个值,get_best_round_score重新测试阶段最优规则时会用到
    #if [ benchmark_failed ];then
    #   handle it
    #   return 2
    #fi
    #
    sh ${AIOCC_BATCH_DIR}/extract_bandwidth.sh ${candidate_result_dir}/${candidate_try} ${quiet}
    local bandwidth=`grep "bandwidth_mean" ${candidate_result_dir}/${candidate_try}/bandwidth.statistic | cut -d: -f 2`
    if [ $bandwidth -eq 0 ];then
        print_message "MULTEXU_ECHOX" "1>&2" "warning:the value of bandwidth is ${bandwidth}..."
        #print_message "MULTEXU_WARN" "warning:the value of bandwidth is ${bandwidth}..."
        benchmark_failed_times=$((benchmark_failed_times+1))
        #算作本次测试不成功,占用一次candidate_try机会,var_percentage_threshold + 10是为了使得上层检测不通过
        var_percentage=$(( var_percentage_threshold + 10 ))
        local score_line="${candidate_rule},${candidate_old_score},${candidate_avg_bandwidth},${candidate_avg_bandwidth_var},${candidate_try}"
        if [ -f ${round_summary_file} ];then
            sed -i "s/^${candidate_rule},.*/${score_line}/g" ${round_summary_file}
        else
            echo ${score_line} >> ${round_summary_file}    
        fi
        eval "$rs='${var_percentage},${candidate_try}'"
        #失败的情况返回一个值,get_best_round_score重新测试阶段最优规则时会用到
        return 1
    else
        candidate_avg_bandwidth=`echo "${candidate_avg_bandwidth} + ( ${bandwidth} - ${candidate_avg_bandwidth} ) / ${candidate_try} " | bc`
        if [ ${candidate_avg_bandwidth} -gt ${max_bandwidth} ];then
            max_bandwidth=$candidate_avg_bandwidth
            echo $max_bandwidth > $max_bandwidth_file
        fi
    fi
    local var=`grep "bandwidth_stddev" ${candidate_result_dir}/${candidate_try}/bandwidth.statistic | cut -d: -f 2`
    candidate_avg_bandwidth_var=`echo "$candidate_avg_bandwidth_var + ( $var - $candidate_avg_bandwidth_var ) / $candidate_try " | bc`
    #candidate_avg_bandwidth candidate_avg_bandwidth_var objective_model
    local score=`python ${AIOCC_BATCH_DIR}/calculate_score.py ${candidate_avg_bandwidth} ${candidate_avg_bandwidth_var} "afactor"`
    #${candidate_rule},${score},${candidate_avg_bandwidth},${candidate_avg_bandwidth_var},${candidate_try}
    local score_line="${candidate_rule},${score},${candidate_avg_bandwidth},${candidate_avg_bandwidth_var},${candidate_try}"
    if [ -f ${round_summary_file} ];then
        sed -i "s/^${candidate_rule},.*/${score_line}/g" ${round_summary_file}
    else
        echo ${score_line} >> ${round_summary_file}    
    fi
    #采用变异系数
    local var_percentage=`echo "100 * $candidate_avg_bandwidth_var / $candidate_avg_bandwidth" | bc`
    eval "$rs='${var_percentage},${candidate_try}'"
}


function get_best_round_score()
{
    local rs=$1
    local round_summary_file=$2
    while [ x"$work_loop" == x"true" ];
    do
        candidate_num=`ls ${AIOCC_RULE_CANDIDATE_DIR} | wc -l`
        if [ $candidate_num -eq 0 ];then
            print_message "MULTEXU_INFO" "All calculate rules have been tested..."
            break
        fi
        local candidate_rule=`ls ${AIOCC_RULE_CANDIDATE_DIR} | head -1`
        while true;
        do
            local rs_benchmark_rule=""
            benchmark_rule rs_benchmark_rule ${candidate_rule} ${round_summary_file}
            check_benchmark ${benchmark_failed_times} ${benchmark_failed_times_limit}
            local var_percentage=`echo $rs_benchmark_rule | cut -d, -f 1`
            local candidate_try=`echo $rs_benchmark_rule | cut -d, -f 2`
            if [ `echo "$var_percentage < $var_percentage_threshold" | bc -l` -eq 1 ];then
                print_message "MULTEXU_INFO" "Candidate rule ${candidate_rule} is stable enough:var_percentage ${var_percentage}, proceeding to next rule..."
                break
            elif [ ${candidate_try} -gt ${candidate_try_limitation} ];then
                print_message "MULTEXU_ECHOX" "1>&2"  "AIOCC has tried rule $candidate_rule $candidate_try times,and still not stable enough:var_percentage ${var_percentage}, giving up trying this rule, proceeding to next rule..."
                #print_message  "MULTEXU_INFO"  "AIOCC has tried rule $candidate_rule $candidate_try times,and still not stable enough, giving up trying this rule, proceeding to next rule..."
                break
            fi
            print_message "MULTEXU_ECHOX" "1>&2" "var_percentage is $var_percentage, too high, trying rule ${candidate_rule} one more time..."
            #print_message  "MULTEXU_INFO" "var_percentage is $var_percentage, too high, trying rule ${candidate_rule}  one more time..."
        done #
        delete_candidate_rule ${candidate_rule} 
    done #work_loop
    
    #重新选择得分最高的规则,如果其尝试次数不超过candidate_try_limitation次,重新优化之
    while true; do
        local score_line=`sh ${AIOCC_BATCH_DIR}/_get_highest_score.sh $round_summary_file`
        local score_line_num=`wc -l $round_summary_file | awk '{print $1}'`
        local candidate_rule=`echo $score_line | cut -d, -f 1`
        local candidate_try=`echo $score_line | cut -d, -f 5`
        if [ ${candidate_try} -ge ${candidate_try_limitation} -o ${score_line_num} -eq 1 ]; then
            eval "$rs=$score_line"
            return
        fi
        print_message "MULTEXU_ECHOX" "1>&2" "Re-test best round candidate $candidate_rule"
        local rs_benchmark_rule=""
        if ! benchmark_rule rs_benchmark_rule $candidate_rule $round_summary_file ; then
               check_benchmark ${benchmark_failed_times} ${benchmark_failed_times_limit}
        fi
    done
}

#############################################################################################
#                                        开始AIOCC                                            
#############################################################################################
print_message "MULTEXU_INFO" "Now start AIOCC ..."
print_message "MULTEXU_INFO" "Entering directory ${AIOCC_RULE_DATABASE_DIR} ..."
__initialize
cd ${AIOCC_RULE_DATABASE_DIR}
#
#参数意义：rule
#rule_num,rules_per_sec ack_ewma_lower,ack_ewma_upper,send_ewma_lower,send_ewma_upper,rtt_ratio100_lower,rtt_ratio100_upper,m100,b100,tau
#
if [ -f "${AIOCC_RULE_DATABASE_DIR}/epoch.cfg" -a `ls ${AIOCC_RULE_CANDIDATE_DIR} | wc -l` -gt 0 ]; then
    epoch=`cat ${AIOCC_RULE_DATABASE_DIR}/epoch.cfg`
    epoch_result_dir=${AIOCC_RULE_DATABASE_DIR}/"epoch_${epoch}"
    auto_mkdir ${epoch_result_dir} "weak"
    if [ ! -f ${epoch_result_dir}/round.cfg ];then
        echo 0 >  ${epoch_result_dir}/round.cfg
    fi
else
    epoch=0
    echo $epoch>${AIOCC_RULE_DATABASE_DIR}/epoch.cfg
    epoch_result_dir=${AIOCC_RULE_DATABASE_DIR}/"epoch_${epoch}"
    auto_mkdir ${epoch_result_dir} "force"
    echo 0 >  ${epoch_result_dir}/round.cfg
    
    if [ ${initial_rule} -eq 0 ]; then
        :>${AIOCC_RULE_CANDIDATE_DIR}/0
        print_message "MULTEXU_INFO" "Starting Epoch 0 with default rule"
        if [ $enable_m -eq 0 ]; then
            cat >${AIOCC_RULE_CANDIDATE_DIR}/0 <<EOF
1,2
0,${MAX_INT},0,${MAX_INT},0,${MAX_INT},-1,0,20000
EOF
        else
            cat >${AIOCC_RULE_CANDIDATE_DIR}/0 <<EOF
1,2
0,${MAX_INT},0,${MAX_INT},0,${MAX_INT},100,0,20000
EOF
        fi
    else
        print_message "MULTEXU_INFO" "Starting Epoch 0 with rule..."
        cp ${AIOCC_CONFIG_DIR}/initial.rule ${AIOCC_RULE_CANDIDATE_DIR}/0
    fi
fi

#run_workloads ${workloads_type}
echo "true" > ${AIOCC_CONFIG_DIR}/work_loop.cfg
# main work loop
work_loop=`cat ${AIOCC_CONFIG_DIR}/work_loop.cfg`
while [ x"$work_loop" == x"true" ];
do
    epoch=`cat ${AIOCC_RULE_DATABASE_DIR}/epoch.cfg`
    epoch_result_dir=${AIOCC_RULE_DATABASE_DIR}/"epoch_${epoch}"
    #同一平台上多次学习可以使用auto_mkdir ${epoch_result_dir} "weak",即保留以前的数据信息
    auto_mkdir ${epoch_result_dir} "weak"   
    round=`cat ${epoch_result_dir}/round.cfg`
    round_summary_file="${epoch_result_dir}/round_${round}_summary.csv"
    candidate_num=`ls ${AIOCC_RULE_CANDIDATE_DIR} | wc -l`
    if [ $candidate_num -eq 0 ];then
            print_message "MULTEXU_ERROR" "No calculate rules,abnormal program termination..."
            break
    fi
    deploy_candidate_rules
    get_best_round_score rt_round_best_score_line $round_summary_file
    check_benchmark ${benchmark_failed_times} ${benchmark_failed_times_limit}
    next_round ${rt_round_best_score_line}
    _candidate_filter ${AIOCC_RULE_CANDIDATE_DIR}
done # epoch loop

__cleanup
