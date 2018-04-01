#!/bin/bash
# POSIX
#
#description:    AIOCC workload generaor
#     author:    ShijunDeng
#      email:    dengshijun1992@gmail.com
#       time:    2017-09-08
#

#initialization
cd "$( dirname "${BASH_SOURCE[0]}" )" #get  a Bash script tell what directory it's stored in
if [ ! -f ../ctrl/__init.sh ]; then
    echo "MULTEXU Error:multexu initialization failure:cannot find the file __init.sh... "
    exit 1
else
    source ../ctrl/__init.sh
fi

source "${MULTEXU_BATCH_CRTL_DIR}/multexu_lib.sh"  

start_time=$(date +%s%N)
start_time_ms=${start_time:0:16}

#时间同步服务器
time_syn_clock=192.168.3.4

sleeptime=30 #设置检测的睡眠时间
limit=10 #递减下限

#测试结果存放目录
time_str=`date +"%Y%m%d%H%M%S"`
result_dir="${MULTEXU_TESTRESULT_DIR}/lustre/fio/${time_str}"
EXIT_SIGNAL="cat ${MULTEXU_BATCH_TEST_DIR}/control.signal"
echo "RUN" > ${MULTEXU_BATCH_TEST_DIR}/control.signal

#测试参数
#test parameters
blocksize=1 #the blocksize
#测试目录
directory="/mnt/lustre/test"
direct=0
iodepth=5
allow_mounted_write=1
ioengine_name=("posixaio" "sync" "vsync" "psync")
special_cmd="-rwmixread=" #随机IO时的一些特殊参数
size="1G"
numjobs=30
runtime=600
name="aiocc_test"

blocksize_start=1
blocksize_end=1024
blocksize_multi_step=2

rwmixread_start=10
rwmixread_end=90
rwmixread_add_step=10

round_start=1
round_end=600
round_add_step=1

#设置检测测试是否结束的时间以及检测的下限
checktime_init=180
checktime_lower_limit=60
#IO方式
declare -a rw_array;#Type of I/O pattern. 

#fio的读写方式
rw_array=("readwrite" "randrw" "read" "randread" "write" "randwrite")

#获取客户端的ip地址,只需要其中一个即可,用作向服务器发命令,清除测试产生的文件
client_ip=`cat ${MULTEXU_BATCH_CONFIG_DIR}/nodes_client.out | head -1`

policy=
#调度算法的名称noop anticipatory [deadline] cfq tb new_sysdeadline
declare -a policy_name

#
#默认是以空格分割 所以用连字符先代替一下 后面再替换
#
#policy_name[0]="tbf-jobid"
#policy_name[1]="crrn-pid"
#policy_name[2]="orr-pid"
policy_name[0]="tbf-jobid"

#获取参数值
function get_parameter()
{
    while :; 
    do
        case $1 in
            -f=?*|--fio_cmd=?*) #特殊附加命令
                special_cmd=${1#*=}
                shift
                ;;
            -f|--fio_cmd=) # Handle the case of an empty 
                printf 'MULTEXU ERROR: "-f|--fio_cmd" requires a non-empty option argument.\n' >&2
                exit 1
                ;;
            -?*)
                printf 'MULTEXU WARN: Unknown option (ignored): %s\n' "$1" >&2
                shift
                ;;
            *)    # Default case: If no more options then break out of the loop.
                shift
                break
        esac
    done
}
get_parameter $@

sh ${MULTEXU_BATCH_CRTL_DIR}/multexu_ssh.sh  --test_host_available=nodes_all.out
sh ${MULTEXU_BATCH_CRTL_DIR}/multexu_ssh.sh  --test_host_ssh_enabled=nodes_all.out
wait_util_cluster_host_available "nodes_all.out"  ${sleeptime} ${limit}
wait_util_cluster_ssh_enabled "nodes_all.out"  ${sleeptime} ${limit}
#清除信号量  避免干扰
sh ${MULTEXU_BATCH_CRTL_DIR}/multexu.sh --iptable=nodes_all.out --cmd="sh ${MULTEXU_BATCH_CRTL_DIR}/multexu_ssh.sh  --clear_execute_statu_signal"

#
#安装fio
#
print_message "MULTEXU_INFO" "now start to check fio tool in client nodes..."
sh ${MULTEXU_BATCH_CRTL_DIR}/multexu.sh --iptable=nodes_client.out --supercmd="sh ${MULTEXU_BATCH_TEST_DIR}/_fio_install.sh"
ssh_check_cluster_status "nodes_client.out" "${MULTEXU_STATUS_EXECUTE}" $((sleeptime/2)) ${limit}
print_message "MULTEXU_INFO" "finished fio checking..."
#清除信号量  避免干扰
sh ${MULTEXU_BATCH_CRTL_DIR}/multexu.sh --iptable=nodes_client.out --cmd="sh ${MULTEXU_BATCH_CRTL_DIR}/multexu_ssh.sh  --clear_execute_statu_signal"

#
#删除oss上因为测试产生的文件和测试目录
#
sh ${MULTEXU_BATCH_CRTL_DIR}/multexu.sh --iptable=${client_ip} --cmd="rm -rf ${directory}"
sleep ${sleeptime}s
#建立测试目录
sh ${MULTEXU_BATCH_CRTL_DIR}/multexu.sh --iptable=${client_ip} --cmd="mkdir ${directory}/"
#设置lustre的stripe
sh ${MULTEXU_BATCH_CRTL_DIR}/multexu.sh --iptable=${client_ip} --cmd="lfs setstripe -c -1 ${directory}"
print_message "MULTEXU_INFO" "all ost have been used..."

cd ${MULTEXU_BATCH_TEST_DIR}/
print_message "MULTEXU_INFO" "enter directory ${MULTEXU_BATCH_TEST_DIR}..."
`${PAUSE_CMD}`
#rm -rf "${result_dir}"

#定时清除服务器上的日志,因为测试的过程中会产生大量的日志,很可能会占用大量的日志空间或者影响服务器的性能
sh ${MULTEXU_BATCH_CRTL_DIR}/multexu.sh --iptable=nodes_all.out --cmd="sh ${MULTEXU_BATCH_TEST_DIR}/_clear_var_log_messages.sh"
print_message "MULTEXU_INFO" "the script clear_var_log_messages.sh is running in ipall.out set..."
#
#开始测试
#
print_message "MULTEXU_INFO" "now start the test processes..."
for ioengine in ${ioengine_name[*]}
do
    for policy in ${policy_name[*]}
    do
        #修改调度器 并显示修改后的调度器名称  注意调度器实际命令需要引号 故传入的参数需要转义
        sh ${MULTEXU_BATCH_CRTL_DIR}/multexu.sh --iptable=nodes_oss.out --supercmd="lctl set_param ost.OSS.ost_io.nrs_policies=\"${policy/-/ }\""
        print_message "MULTEXU_INFO" "policy_name:${policy/-/ }"
        for ((blocksize=${blocksize_end}; blocksize>=${blocksize_start}; blocksize/=${blocksize_multi_step}))
        do
            for rw_pattern in ${rw_array[*]}
            do
                #测试结果的存放目录
                rs_store_dir="${result_dir}/${ioengine}/${rw_pattern}"
                auto_mkdir "${rs_store_dir}" "weak"    
                print_message "MULTEXU_ECHO" "    rw_array:${rw_pattern}"
                for ((rwmixread=${rwmixread_start}; rwmixread<=${rwmixread_end}; rwmixread+=${rwmixread_add_step}))
                do
                    special_cmd_io_choice=
                    if [[ ${rw_pattern} == "readwrite" ]] || [[ ${rw_pattern} == "randrw" ]];then
                        special_cmd_io_choice="${special_cmd}${rwmixread}"
                    else
                        #跳出循环
                        rwmixread=$(( ${rwmixread_end} * 2 ))
                    fi
                    #for policy in ${policy_name[*]}
                    for ((round_index=${round_start}; round_index<=${round_end}; round_index+=${round_add_step}))
                    do
                        if [ x`$EXIT_SIGNAL` = x"EXIT" ];then
                            print_message "MULTEXU_ECHO" "EXIT SIGNAL detected..."
                            exit 0
                        fi
                        source ./agency_cmd.sh
                        print_message "MULTEXU_ECHO" "        start a test:round=${round_index}..."   
                        #删除测试文件,一定放在最内循环
                        sh ${MULTEXU_BATCH_CRTL_DIR}/multexu.sh --iptable=${client_ip} --cmd="rm -rf ${directory}/*"
                        sleep ${sleeptime}s
                        cmd_var="${MULTEXU_SOURCE_TOOL_DIR}/fio/fio -direct=${direct} -iodepth ${iodepth} -thread -rw=${rw_pattern} ${special_cmd_io_choice} -allow_mounted_write=${allow_mounted_write} -ioengine=${ioengine} -bs=${blocksize}k -size=${size} -numjobs=${numjobs} -runtime=${runtime} -group_reporting -name=${name}"
                        print_message "MULTEXU_ECHO" "        test command:${cmd_var}"
                        #测试结果文件名称,组成方式:读写模式-调度器-块大小k-混合读写比例.txt
                        if [[ ${rw_pattern} == "readwrite" ]] || [[ ${rw_pattern} == "randrw" ]];then
                            filename="${rw_pattern}-round${round_index}-${blocksize}k-${rwmixread}.txt"
                        else
                            filename="${rw_pattern}-round${round_index}-${blocksize}k.txt"
                        fi
                        touch "${rs_store_dir}/${filename}"
                        `${PAUSE_CMD}`    
                        echo "${cmd_var}" > ${rs_store_dir}/${filename}
                        #测试结果写入文件
                        sh ${MULTEXU_BATCH_CRTL_DIR}/multexu.sh --iptable=nodes_client.out --supercmd="sh "${MULTEXU_BATCH_TEST_DIR}"/_test_exe.sh \"${cmd_var}\" \"${directory}\"" >> ${rs_store_dir}/${filename}
                        #检测测试是否完成
                        ssh_check_cluster_status "nodes_client.out" "${MULTEXU_STATUS_EXECUTE}" ${checktime_init} ${checktime_lower_limit}
                        #清除标记
                        sh ${MULTEXU_BATCH_CRTL_DIR}/multexu.sh --iptable=nodes_client.out --cmd="sh ${MULTEXU_BATCH_CRTL_DIR}/multexu_ssh.sh  --clear_execute_statu_signal"            
                        print_message "MULTEXU_ECHO" "        finish this test..."
                        `${PAUSE_CMD}`
                    done #round
                done #rwmixread
            done #block_size
        done #rw_pattern
    done #policy
done #ioengine

sh ${MULTEXU_BATCH_CRTL_DIR}/multexu.sh --iptable=nodes_client.out --cmd="sh ${MULTEXU_BATCH_CRTL_DIR}/multexu_ssh.sh  --clear_execute_statu_signal"
#清除测试产生的垃圾文件
sh ${MULTEXU_BATCH_CRTL_DIR}/multexu.sh --iptable=${client_ip} --cmd="rm -rf ${directory}/*"
echo "false" > ${MULTEXU_BATCH_TEST_DIR}/_clear_var_log_messages.cfg
`${PAUSE_CMD}`
print_message "MULTEXU_INFO" "all test jobs has been finished..."

end_time=$(date +%s%N)
end_time_ms=${end_time:0:16}
#scale=6
time_cost=0
time_cost=`echo "scale=6;($end_time_ms - $start_time_ms)/1000000" | bc`
print_message "MULTEXU_INFO" "Total time spent:${time_cost} s"

exit 0
