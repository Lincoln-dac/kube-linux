#!/bin/bash

LOG_FILE="/app/scripts/irq_affinity.log"

# 函数：添加时间戳并记录日志
log_message() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then
    log_message "错误: 请以root权限运行此脚本"
    exit 1
fi

log_message "开始设置中断亲和性"

# 获取bond0的当前活跃Slave网卡名称
active_slave=$(cat /proc/net/bonding/bond0 2>/dev/null | grep "Currently Active Slave" | awk '{print $NF}')

if [ -z "$active_slave" ]; then
    log_message "错误: 无法获取bond0的活跃Slave网卡"
    exit 1
fi

log_message "当前活跃Slave网卡: $active_slave"

# 获取系统CPU核心数量
CPU_COUNT=$(nproc)
log_message "系统CPU核心数量: $CPU_COUNT"

# CPU编号从0到(CPU_COUNT-1)
CPU_NUMBERS=$(seq 0 $((CPU_COUNT-1)))
log_message "CPU编号范围: 0 到 $((CPU_COUNT-1))"

# 获取网卡的所有中断号
IRQ_NUMBERS=$(grep "$active_slave" /proc/interrupts | awk '{print $1}' | sed 's/://' | sort -n)

if [ -z "$IRQ_NUMBERS" ]; then
    log_message "错误: 无法找到网卡 $active_slave 的中断号"
    exit 1
fi

log_message "找到的中断号: $IRQ_NUMBERS"
IRQ_COUNT=$(echo "$IRQ_NUMBERS" | wc -w)
log_message "中断数量: $IRQ_COUNT"

# 检查中断数量是否与CPU核心数量匹配
if [ $IRQ_COUNT -ne $CPU_COUNT ]; then
    log_message "错误: 中断数量($IRQ_COUNT)与CPU核心数量($CPU_COUNT)不匹配"
    log_message "脚本将退出，请检查系统配置"
    exit 1
fi

# 将中断一一绑定到CPU核心
log_message "开始设置中断亲和性..."
i=0
for irq in $IRQ_NUMBERS; do
    # 获取当前要绑定的CPU编号
    cpu_index=$i
    
    # 设置中断亲和性
    echo $cpu_index > /proc/irq/$irq/smp_affinity_list 2>/dev/null
    
    if [ $? -eq 0 ]; then
        log_message "中断 $irq 已绑定到 CPU $cpu_index"
    else
        log_message "错误: 无法设置中断 $irq 的亲和性"
        exit 1
    fi
    
    i=$((i+1))
done

log_message "中断亲和性设置完成"

