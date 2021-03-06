#!/bin/sh
#POSIX
#

#description:    clear the temporary file/output file of a aiocc process
#     author:    ShijunDeng
#      email:    dengshijun1992@gmail.com
#       time:    2017-02-10
#
#运行本脚本时,假设主控制节点与所有节点(包括编译节点)已经进行SSH认证
#
#清除AIOCC运行的结果文件/临时文件,运行本脚本之后再次运行aiocc_start.sh的效果等同于首次全新的运行aiocc_start.sh
#
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
clear_execute_statu_signal 
clear_execute_statu_signal ${AIOCC_EXECUTE_SIGNAL_FILE}
category="default"
function __clear()
{
    AIOCC_RULE_DATABASE_DIR="${AIOCC_RULE_DIR}/${category}"
    AIOCC_RULE_CANDIDATE_DIR="${AIOCC_RULE_DATABASE_DIR}/candidate_rules"
    AIOCC_RULE_TESTED_DIR="${AIOCC_RULE_DATABASE_DIR}/tested_rules" 
    AIOCC_RULE_RESULT_DIR="${AIOCC_RULE_DATABASE_DIR}/results" 
    auto_mkdir ${AIOCC_RULE_DATABASE_DIR} "force"
    auto_mkdir ${AIOCC_RULE_CANDIDATE_DIR} "force"
    auto_mkdir ${AIOCC_RULE_TESTED_DIR} "force"
    auto_mkdir ${AIOCC_RULE_RESULT_DIR} "force"
    clear_execute_statu_signal ${AIOCC_CTROL_SIGNAL_FILE}
    clear_execute_statu_signal ${AIOCC_EXECUTE_SIGNAL_FILE}
}
__clear
