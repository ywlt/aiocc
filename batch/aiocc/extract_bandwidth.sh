#!/bin/sh
#POSIX
#

#description:    extract bandwidth from client nodes 
#     author:    ShijunDeng
#      email:    dengshijun1992@gmail.com
#       time:    2017-01-05
#
#运行本脚本时,假设主控制节点与所有节点(包括编译节点)已经进行SSH认证
#

#initialization
cd "$( dirname "${BASH_SOURCE[0]}" )" #get  a Bash script tell what directory it's stored in
if [ ! -f ./__aiocc_init.sh ]; then
    echo "AIOCC Error:initialization failure:cannot find the file __aiocc_init.sh... "
    exit 1
else
    source ./__aiocc_init.sh
fi

source "${MULTEXU_BATCH_CRTL_DIR}/multexu_lib.sh"
clear_execute_statu_signal "${AIOCC_EXECUTE_SIGNAL_FILE}"
#
#获取各个节点的参数信息
#
print_message "MULTEXU_INFO" "extracting bandwidth of nodes_client.out..."
local_import_file_dir=$1
quiet=$2

sh ${MULTEXU_BATCH_CRTL_DIR}/multexu.sh --iptable=nodes_client.out --cmd="sh ${AIOCC_BATCH_DIR}/__extract_bandwidth.sh ${local_import_file_dir}"
ssh_check_cluster_status "nodes_client.out" "${AIOCC_EXECUTE_STATUS_FINISHED}" "1" "1" "${AIOCC_EXECUTE_SIGNAL_FILE}"
read_bandwidth=0
write_bandwidth=0
bandwidth=0
bandwidth_record=""
COUNT=0
#统计T次
T=10
if [ -z "${local_import_file_dir}" ];then
    print_message "MULTEXU_ERROR" "parameter missing..."
    exit 1
fi
auto_mkdir "${local_import_file_dir}" "force"

function __extract_bandwidth_loop()
{
    while [ $COUNT -lt $T ];
    do
        rm -f ${local_import_file_dir}/*.import
        #
        #复制各节点${local_import_file_dir}目录下的qos_rules文件到当前节点的${local_import_file_dir}目录下
        #
        for host_ip in $(cat "${MULTEXU_BATCH_CONFIG_DIR}/nodes_client.out")
        do 
            scp root@${host_ip}:${local_import_file_dir}/*.import ${local_import_file_dir}/
        done

        IMPORT_FILE_ARRY=($(ls ${local_import_file_dir}/*.import))
        IMPORT_FILE_NUM=${IMPORT_FILE_ARRY}
        cd ${local_import_file_dir}

        for FILE in ${IMPORT_FILE_ARRY[*]}
        do
            read_bandwidth=$(grep 'read_bandwidth' ${FILE} | cut -d : -f 2)
            if [ "x$read_bandwidth" = "x" ];then
                read_bandwidth=0
            fi
            write_bandwidth=$(grep 'write_bandwidth' ${FILE} | cut -d : -f 2 )
            if [ "x$write_bandwidth" = "x" ];then
                write_bandwidth=0
            fi
            bw=$(( ${read_bandwidth}+${write_bandwidth} ))
            bandwidth_record="${bandwidth_record} ${bw}"
        done
        (( COUNT+=1 ))
    done
}  
 
if [ ${quiet} -eq 1 ];then
    __extract_bandwidth_loop >/dev/null
else
    __extract_bandwidth_loop 
fi

echo ${bandwidth_record} > ${local_import_file_dir}/bandwidth.record
python ${AIOCC_BATCH_DIR}/bandwidth_statistic.py ${local_import_file_dir}/bandwidth.record ${local_import_file_dir}/bandwidth.statistic


#echo ${read_bandwidth}
#echo ${write_bandwidth}
#echo $(( (${read_bandwidth}+ ${write_bandwidth})/(${IMPORT_FILE_NUM}*${T}) )) > ${local_import_file_dir}/realtime_avg.bandwidth
#echo "scale=2;(${read_bandwidth}+ ${write_bandwidth})/(${IMPORT_FILE_NUM}*${T})" | bc > ${local_import_file_dir}/realtime_avg.bandwidth
send_execute_statu_signal "${AIOCC_EXECUTE_STATUS_FINISHED}" "${AIOCC_EXECUTE_SIGNAL_FILE}"


