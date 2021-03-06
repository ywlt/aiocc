#!/bin/bash
# POSIX
#
#description:    install lustre server 2.9
#     author:    ShijunDeng
#      email:    dengshijun1992@gmail.com
#       time:    2018-01-20

#initialization
cd "$( dirname "${BASH_SOURCE[0]}" )" #get  a Bash script tell what directory it's stored in
if [ ! -f ../ctrl/__init.sh ]; then
    echo "MULTEXU Error:multexu initialization failure:cannot find the file __init.sh... "
    exit 1
else
    source ../ctrl/__init.sh
fi

source "${MULTEXU_BATCH_CRTL_DIR}"/multexu_lib.sh #调入multexu库
clear_execute_statu_signal
                                                
print_message "MULTEXU_INFO" "install dependencies..."                                       
cd ${MULTEXU_SOURCE_INSTALL_DIR}
print_message "MULTEXU_INFO" "enter directory ${MULTEXU_SOURCE_INSTALL_DIR}..."

yum remove libss -y
wait
rpm -ivh libcom_err-1.42.13.wc6-7.el7.x86_64.rpm --nodeps --force
wait
rpm -ivh libcom_err-devel-1.42.13.wc6-7.el7.x86_64.rpm
wait
rpm -ivh  e2fsprogs-libs-1.42.13.wc6-7.el7.x86_64.rpm --nodeps --force
wait
rpm -ivh  e2fsprogs-devel-1.42.13.wc6-7.el7.x86_64.rpm
wait
rpm -ivh libss-1.42.13.wc6-7.el7.x86_64.rpm --nodeps --force
wait
rpm -ivh libss-devel-1.42.13.wc6-7.el7.x86_64.rpm 
wait
rpm -ivh  e2fsprogs-1.42.13.wc6-7.el7.x86_64.rpm --nodeps --force
wait

rpm -ivh lustre-osd-ldiskfs-mount-2.9.0*.rpm --force --nodeps
wait
rpm -ivh kmod-lustre-2.9.0*.rpm --force --nodeps
wait
rpm -ivh kmod-lustre-osd-ldiskfs-2.9.0*.rpm --force --nodeps
wait
rpm -ivh lustre-2.9.0*.rpm  --force --nodeps
wait
#lustre-modules-2.8.0-3.10.0_3.10.0_327.3.1.el7_lustre.x86_64.x86_64 has missing requires of kernel = ('0', '3.10.0', '3.10.0-327.3.1.el7_lustre')
#yum clean all &&yum update glibc glibc-headers glibc-devel nscd && yum update
wait
send_execute_statu_signal "${MULTEXU_STATUS_EXECUTE}"
print_message "MULTEXU_INFO" "leave directory $( dirname "${BASH_SOURCE[0]}" )..."

`${PAUSE_CMD}`
