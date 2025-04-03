#!/bin/bash

# 定义错误处理函数
handle_error() {
    echo "$1"
    exit 1
}

# 获取命令行参数
if [ $# -ne 3 ]; then
    handle_error "错误：必须输入3个变量。标准输入示例：./config_keepalived_cluster.sh 192.168.1.100/24 100 MASTER 或 ./config_keepalived_cluster.sh 192.168.1.100/24 100 BACKUP"
fi

VIRTUAL_VIP=$1
VIRTUAL_ROUTER_ID=$2
NODE_TYPE=$3

echo "请使用tcpdump vrrp 验证VIRTUAL_ROUTER_ID是否冲突"

# 安装keepalived
Installkeepalived() {
    if ! rpm -q keepalived &> /dev/null; then
        echo "安装keepalived"
        yum install keepalived -y || handle_error "安装keepalived失败"
    else
        echo "keepalived 已经安装，跳过安装步骤。"
    fi
}

# 配置主节点的keepalived
ConfigMasterkeepalived() {
    cat > /etc/keepalived/keepalived.conf <<EOF
global_defs {
    router_id lb
}
vrrp_script checkscript {
    script "/etc/keepalived/check.sh"
    interval 5    # 执行监控脚本的间隔时间
    weight 2      # 利用权重值和优先级进行运算，从而降低主服务优先级使之变为备服务器（建议先忽略）
}
vrrp_instance VI_1 {
    state $NODE_TYPE
    interface bond0
    virtual_router_id $VIRTUAL_ROUTER_ID
    priority 100
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass 1111
    }
    track_script {
        checkscript
    }
    virtual_ipaddress {
        $VIRTUAL_VIP
    }
EOF
    echo "keepalived master配置完成，请注意配置/etc/keepalived/check.sh脚本文件,以及执行权限，配置完成再重启keepalived服务"
    systemctl restart keepalived && systemctl enable keepalived || handle_error "启动keepalived失败"
}

# 配置备份节点的keepalived
ConfigBackupKeepalived() {
    cat > /etc/keepalived/keepalived.conf <<EOF
global_defs {
    router_id lb
}
vrrp_script checkscript {
    script "/etc/keepalived/check.sh"
    interval 5    # 执行监控脚本的间隔时间
    weight 2      # 利用权重值和优先级进行运算，从而降低主服务优先级使之变为备服务器（建议先忽略）
}
vrrp_instance VI_1 {
    state $NODE_TYPE
    interface bond0
    virtual_router_id $VIRTUAL_ROUTER_ID
    priority 100
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass 1111
    }
    track_script {
        checkscript
    }
    virtual_ipaddress {
        $VIRTUAL_VIP
    }
EOF
    echo "keepalived backup配置完成，请注意配置/etc/keepalived/check.sh脚本文件以及执行权限，配置完成再重启keepalived服务"
    systemctl restart keepalived && systemctl enable keepalived || handle_error "启动keepalived失败"
}

# 执行安装和配置操作
Installkeepalived
if [ "$NODE_TYPE" = "MASTER" ]; then
    ConfigMasterkeepalived
else
    ConfigBackupKeepalived
fi