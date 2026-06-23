#!/bin/bash
#
# CFS Burst Sidecar Script
# 用于解决容器偶发性 CPU 限流问题
# 版本: v2.0 - 增强可观察性
#

set -u

# 默认配置
THRESHOLD=${THRESHOLD:-5}           # throttle 阈值(%)
MULTIPLIER=${MULTIPLIER:-3}         # quota 放大倍数
DURATION=${DURATION:-10}            # burst 持续时间(秒)
CHECK_INTERVAL=${CHECK_INTERVAL:-2} # 检查间隔(秒)
CGROUP_ROOT=${CGROUP_ROOT:-/host_sys/fs/cgroup}
LOG_LEVEL=${LOG_LEVEL:-3}           # 日志级别: 1=ERROR, 2=WARN, 3=INFO, 4=DEBUG

# Pod 信息（通过 downward API 注入）
POD_NAME=${POD_NAME:-""}
POD_UID=${POD_UID:-""}
NAMESPACE=${NAMESPACE:-""}

# 统计信息
STATS_FILE="/tmp/burst_stats"
init_stats() {
    echo "burst_count=0" > $STATS_FILE
    echo "restore_count=0" >> $STATS_FILE
    echo "extend_count=0" >> $STATS_FILE
    echo "total_throttle_time=0" >> $STATS_FILE
    echo "last_throttle_ratio=0" >> $STATS_FILE
    echo "start_time=$(date +%s)" >> $STATS_FILE
}
inc_stats() {
    local key=$1
    local val=$(grep "^${key}=" $STATS_FILE | cut -d'=' -f2)
    echo "${key}=$((val + 1))" > $STATS_FILE
    sed -i "s/^${key}=.*/${key}=$((val + 1))/" $STATS_FILE
}
get_stats() {
    grep "^${1}=" $STATS_FILE | cut -d'=' -f2
}

# 日志函数
log() {
    local level=$1
    shift
    local msg="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local pod_info="[${POD_NAME}]"

    # 级别: 1=ERROR, 2=WARN, 3=INFO, 4=DEBUG
    case $level in
        1) echo "[${timestamp}] ${pod_info} [ERROR] $msg" >&2 ;;
        2) echo "[${timestamp}] ${pod_info} [WARN]  $msg" ;;
        3) echo "[${timestamp}] ${pod_info} [INFO]  $msg" ;;
        4) [ "$LOG_LEVEL" -ge 4 ] && echo "[${timestamp}] ${pod_info} [DEBUG] $msg" ;;
    esac
}

# 解析 annotation（K8s annotation 格式: "key: value"）
get_annotation() {
    local key=$1
    # annotation 文件格式: "cfs-burst.threshold: value"
    local value=$(grep -E "^${key}[[:space:]]*:" /etc/pod-info/annotations 2>/dev/null | sed 's/^[^:]*:[[:space:]]*//' | tr -d ' ')
    echo "${value:-}"
}

# 格式化时间
format_duration() {
    local seconds=$1
    if [ $seconds -lt 60 ]; then
        echo "${seconds}s"
    else
        echo "$((seconds / 60))m$((seconds % 60))s"
    fi
}

# 获取 cgroup 路径
get_cgroup_path() {
    local uid=${POD_UID:0:63}
    echo "${CGROUP_ROOT}/cpu/kubepods/burstable/pod${uid}"
}

# 读取 cpu.stat 计算详细指标
get_cpu_stats() {
    local stat_file="$1/cpu.stat"
    if [ ! -f "$stat_file" ]; then
        echo "0|0|0"
        return
    fi

    local nr_periods=$(grep -E "^nr_periods " "$stat_file" 2>/dev/null | awk '{print $2}')
    local nr_throttled=$(grep -E "^nr_throttled " "$stat_file" 2>/dev/null | awk '{print $2}')
    local throttled_time=$(grep -E "^throttled_time " "$stat_file" 2>/dev/null | awk '{print $2}')

    nr_periods=${nr_periods:-0}
    nr_throttled=${nr_throttled:-0}
    throttled_time=${throttled_time:-0}

    echo "${nr_periods}|${nr_throttled}|${throttled_time}"
}

# 计算 throttle ratio (百分比)
get_throttle_ratio() {
    local stats=$1
    local nr_periods=$(echo $stats | cut -d'|' -f1)
    local nr_throttled=$(echo $stats | cut -d'|' -f2)

    if [ "$nr_periods" = "0" ] || [ -z "$nr_periods" ]; then
        echo "0"
        return
    fi

    # 保留两位小数
    echo "$((nr_throttled * 10000 / nr_periods / 100)).$((nr_throttled * 10000 / nr_periods % 100))"
}

# 获取当前 quota
get_quota() {
    local quota_file="$1/cpu.cfs_quota_us"
    if [ ! -f "$quota_file" ]; then
        echo "0"
        return
    fi
    local quota=$(cat "$quota_file" 2>/dev/null)
    if [ -z "$quota" ] || [ "$quota" = "-1" ]; then
        echo "0"
    else
        echo "$quota"
    fi
}

# 设置 quota
set_quota() {
    local quota_file="$1/cpu.cfs_quota_us"
    local new_quota=$2
    if echo "$new_quota" > "$quota_file" 2>/dev/null; then
        return 0
    else
        log 1 "Failed to set quota: $new_quota"
        return 1
    fi
}

# 打印 Pod 状态摘要
print_status() {
    local cgroup_path=$1
    local stats=$2
    local current_quota=$3
    local in_burst=$4
    local throttle_ratio=$5

    local nr_periods=$(echo $stats | cut -d'|' -f1)
    local nr_throttled=$(echo $stats | cut -d'|' -f2)
    local throttled_time=$(echo $stats | cut -d'|' -f3)
    local throttled_ms=$((throttled_time / 1000000))

    local burst_status="IDLE"
    [ "$in_burst" = "true" ] && burst_status="BURST"

    log 4 "Status: burst=${burst_status}, quota=${current_quota}, throttle=${throttle_ratio}%, " \
          "nr_periods=${nr_periods}, nr_throttled=${nr_throttled}, throttled_time=${throttled_ms}ms"
}

# 打印统计摘要
print_summary() {
    local burst_count=$(get_stats burst_count)
    local restore_count=$(get_stats restore_count)
    local extend_count=$(get_stats extend_count)
    local start_time=$(get_stats start_time)
    local uptime=$(( $(date +%s) - start_time ))

    log 3 "=========================================="
    log 3 "CFS Burst Sidecar Summary"
    log 3 "=========================================="
    log 3 "Uptime:    $(format_duration $uptime)"
    log 3 "Burst:     ${burst_count} times"
    log 3 "Restored:  ${restore_count} times"
    log 3 "Extended:  ${extend_count} times"
    log 3 "=========================================="
}

# 信号处理
cleanup() {
    log 2 "Received signal, restoring quota and exiting..."
    local cgroup_path=$(get_cgroup_path)
    local normal_quota=$(get_quota "$cgroup_path")
    local current_quota=$(get_quota "$cgroup_path")
    if [ "$current_quota" != "$normal_quota" ]; then
        set_quota "$cgroup_path" "$normal_quota"
        log 2 "Restored quota on exit: $normal_quota"
    fi
    print_summary
    exit 0
}
trap cleanup SIGTERM SIGINT

# 主循环
main() {
    init_stats

    # 读取配置（优先使用 annotation）
    local anno_threshold=$(get_annotation "cfs-burst.threshold")
    local anno_multiplier=$(get_annotation "cfs-burst.multiplier")
    local anno_duration=$(get_annotation "cfs-burst.duration")
    local anno_enable=$(get_annotation "cfs-burst.enable")

    [ "$anno_enable" = "false" ] && log 2 "Burst disabled by annotation, exit" && exit 0

    [ -n "$anno_threshold" ] && THRESHOLD=$anno_threshold
    [ -n "$anno_multiplier" ] && MULTIPLIER=$anno_multiplier
    [ -n "$anno_duration" ] && DURATION=$anno_duration

    # 获取 cgroup 路径
    local cgroup_path=$(get_cgroup_path)

    if [ ! -d "$cgroup_path" ]; then
        log 1 "Cgroup path not found: $cgroup_path, exit"
        exit 1
    fi

    # 获取正常 quota
    local normal_quota=$(get_quota "$cgroup_path")
    if [ "$normal_quota" = "0" ]; then
        normal_quota=100000
        log 2 "No quota set, using default: 100000 (1 core)"
    fi

    local burst_quota=$((normal_quota * MULTIPLIER))

    log 3 "=========================================="
    log 3 "CFS Burst Sidecar Started"
    log 3 "=========================================="
    log 3 "Pod:       ${POD_NAME}"
    log 3 "Namespace: ${NAMESPACE}"
    log 3 "Cgroup:    ${cgroup_path}"
    log 3 "Threshold: ${THRESHOLD}%"
    log 3 "Multiplier: ${MULTIPLIER}x"
    log 3 "Duration:  ${DURATION}s"
    log 3 "Check:     ${CHECK_INTERVAL}s"
    log 3 "Normal Quota:  ${normal_quota} (~$((normal_quota / 100000)) cores)"
    log 3 "Burst Quota:   ${burst_quota} (~$((burst_quota / 100000)) cores)"
    log 3 "=========================================="

    local in_burst=false
    local burst_end=0
    local last_summary=$(date +%s)

    while true; do
        local stats=$(get_cpu_stats "$cgroup_path")
        local throttle_ratio=$(get_throttle_ratio "$stats")
        local current_quota=$(get_quota "$cgroup_path")
        local now=$(date +%s)

        # 定期打印状态（每 60 秒）
        if [ $((now - last_summary)) -ge 60 ]; then
            print_status "$cgroup_path" "$stats" "$current_quota" "$in_burst" "$throttle_ratio"
            last_summary=$now
        fi

        # 正在 burst 中
        if [ "$in_burst" = "true" ]; then
            if [ $now -lt $burst_end ]; then
                # 还在 burst 期间
                if [ "$throttle_ratio" = "0" ] || [ "$throttle_ratio" = "0.00" ]; then
                    # 不再 throttle，提前恢复正常
                    set_quota "$cgroup_path" "$normal_quota"
                    in_burst=false
                    inc_stats restore_count
                    log 3 "Burst restored early: quota=${normal_quota} (throttle=0%)"
                else
                    # 继续 throttle，延长 burst 时间
                    burst_end=$((now + DURATION))
                    inc_stats extend_count
                    log 3 "Burst extended: +${DURATION}s, burst_end=$(format_duration $((burst_end - now))) left, throttle=${throttle_ratio}%"
                fi
            else
                # burst 时间到，恢复正常
                set_quota "$cgroup_path" "$normal_quota"
                in_burst=false
                inc_stats restore_count
                log 3 "Burst timeout, restored: quota=${normal_quota}"
            fi
        else
            # 检查是否需要触发 burst
            # 精确比较：throttle_ratio 字符串比较
            local threshold_int=${THRESHOLD}
            local throttle_int=${throttle_ratio%.*}

            if [ -n "$throttle_int" ] && [ "$throttle_int" -gt "$threshold_int" ] 2>/dev/null; then
                set_quota "$cgroup_path" "$burst_quota"
                in_burst=true
                burst_end=$((now + DURATION))
                inc_stats burst_count
                log 2 "BURST ACTIVATED: quota ${normal_quota} -> ${burst_quota}, throttle=${throttle_ratio}%, burst_end=$(format_duration $DURATION)"
            elif [ "$LOG_LEVEL" -ge 4 ]; then
                # DEBUG 模式打印每次检查结果
                log 4 "Check: throttle=${throttle_ratio}% (threshold=${THRESHOLD}%), quota=${current_quota}"
            fi
        fi

        sleep $CHECK_INTERVAL
    done
}

main