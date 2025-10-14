#!/bin/bash

# 从kubelet配置文件获取Kubernetes内部域名
KUBELET_CONFIG_FILE="/app/kubernetes/config/kubelet-config.yaml"
if [ -f "$KUBELET_CONFIG_FILE" ]; then
    # 获取clusterDomain配置，并去除引号
    K8S_DOMAIN_NAME=$(cat "$KUBELET_CONFIG_FILE" | grep clusterDomain | awk '{print $2}' | tr -d '"')
    # 如果获取失败，使用默认值
    if [ -z "$K8S_DOMAIN_NAME" ]; then
        K8S_DOMAIN_NAME="cluster.local"
        echo "警告：无法从kubelet配置文件获取内部域名，使用默认值: $K8S_DOMAIN_NAME"
    fi
else
    # 如果配置文件不存在，使用默认值
    K8S_DOMAIN_NAME="cluster.local"
    echo "警告：kubelet配置文件不存在($KUBELET_CONFIG_FILE)，使用默认值: $K8S_DOMAIN_NAME"
fi

# 设置日志文件路径
LOG_FILE="/tmp/coredns.log"
RESULT_FILE="/tmp/coredns_analysis_result.txt"

# 全局变量
TIME_PERIOD=""
DOMAIN_FILTER=""
ERROR_ONLY=false

# 函数：收集coredns日志
collect_logs() {
    # 检查日志文件是否已存在
    if [ -f "$LOG_FILE" ]; then
        # 获取当前时间戳
        TIMESTAMP=$(date +%Y%m%d_%H%M%S) 
        # 备份现有日志文件
        BACKUP_FILE="/tmp/coredns.log.backup_$TIMESTAMP"
        echo "检测到已存在日志文件，正在备份到: $BACKUP_FILE"
        mv "$LOG_FILE" "$BACKUP_FILE"
    fi

    # 获取coredns的Pod名称
    POD_NAMES=$(kubectl get po -n kube-system | grep coredns | awk '{print $1}')

    # 检查是否获取到Pod
    if [ -z "$POD_NAMES" ]; then
        echo "未找到coredns Pod"
        # 如果没有找到Pod，恢复备份的日志文件（如果存在）
        if [ -f "$BACKUP_FILE" ]; then
            mv "$BACKUP_FILE" "$LOG_FILE"
            echo "已恢复原始日志文件"
        fi
        exit 1
    fi

    # 创建新的日志文件
    touch "$LOG_FILE"

    # 计算时间范围（如果指定了时间周期）
    SINCE_TIME=""
    if [ -n "$TIME_PERIOD" ]; then
        SINCE_TIME="--since=${TIME_PERIOD}s"
        echo "收集最近 ${TIME_PERIOD} 秒的日志..."
    fi

    # 循环处理每个Pod，将日志追加到同一个文件
    for POD_NAME in $POD_NAMES; do
        echo "===================== 开始导出: $POD_NAME =====================" >> "$LOG_FILE"
        kubectl logs $SINCE_TIME "$POD_NAME" -n kube-system >> "$LOG_FILE"
        echo "===================== 结束导出: $POD_NAME =====================" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"  # 添加空行分隔不同Pod的日志
    done

    echo "所有coredns日志已导出到: $LOG_FILE"
    if [ -n "$BACKUP_FILE" ]; then
        echo "原始日志已备份到: $BACKUP_FILE"
    fi
}

# 函数：分析coredns日志
analyze_logs() {
    # 检查日志文件是否存在
    if [ ! -f "$LOG_FILE" ]; then
        echo "错误: 日志文件 $LOG_FILE 不存在"
        exit 1
    fi

    # 检查日志文件是否为空
    if [ ! -s "$LOG_FILE" ]; then
        echo "错误: 日志文件 $LOG_FILE 为空"
        exit 1
    fi

    # 临时文件用于处理数据
    TEMP_FILE="/tmp/coredns_analysis.tmp"

    # 提取域名和响应时间数据
    echo "正在分析coredns日志..."
    
    # 构建grep命令
    GREP_CMD="grep -v \"$K8S_DOMAIN_NAME\" \"$LOG_FILE\" | grep \"A IN\""
    
    # 如果设置了只分析非NXDOMAIN|NOERROR记录
    if [ "$ERROR_ONLY" = true ]; then
        GREP_CMD="$GREP_CMD | grep -v \"NXDOMAIN\" | grep -v \"NOERROR\""
        echo "只分析非NXDOMAIN|NOERROR的记录"
    fi
    
    # 添加域名过滤（如果指定）
    if [ -n "$DOMAIN_FILTER" ]; then
        GREP_CMD="$GREP_CMD | grep \"$DOMAIN_FILTER\""
        echo "分析域名: $DOMAIN_FILTER"
    fi
    
    # 执行过滤并提取数据
    eval "$GREP_CMD" | awk '{print $8, $NF}' > "$TEMP_FILE"

    # 检查是否提取到有效数据
    if [ ! -s "$TEMP_FILE" ]; then
        echo "错误: 未找到有效的域名解析记录"
        if [ -n "$DOMAIN_FILTER" ]; then
            echo "提示: 指定的域名 '$DOMAIN_FILTER' 可能不存在于日志中"
        fi
        rm -f "$TEMP_FILE"
        exit 1
    fi

    # 处理时间格式（移除's'后缀并转换为数字）
    awk '{
        # 移除时间字符串末尾的's'
        time_str = $2
        sub(/s$/, "", time_str)
        
        # 将时间转换为秒（浮点数）
        time_sec = time_str + 0
        
        # 输出域名和处理后的时间
        print $1, time_sec
    }' "$TEMP_FILE" > "${TEMP_FILE}_processed"

    # 计算每个域名的平均响应时间
    echo "域名解析统计结果:" > "$RESULT_FILE"
    echo "==========================================" >> "$RESULT_FILE"
    echo "域名 | 请求次数 | 平均响应时间(秒) | 总响应时间(秒)" >> "$RESULT_FILE"
    echo "------------------------------------------" >> "$RESULT_FILE"

    awk '
    {
        domain = $1
        time = $2
        
        count[domain]++
        sum[domain] += time
        total_time[domain] = sum[domain]
    }
    END {
        for (d in count) {
            avg = sum[d] / count[d]
            printf "%-40s %8d %18.9f %18.9f\n", d, count[d], avg, total_time[d]
        }
    }
    ' "${TEMP_FILE}_processed" | sort -k3 -nr >> "$RESULT_FILE"

    # 输出总结信息
    echo "==========================================" >> "$RESULT_FILE"
    total_requests=$(wc -l < "${TEMP_FILE}_processed")
    echo "总请求数: $total_requests" >> "$RESULT_FILE"
    
    # 添加过滤条件信息
    if [ -n "$TIME_PERIOD" ]; then
        echo "时间范围: 最近 ${TIME_PERIOD} 秒" >> "$RESULT_FILE"
    fi
    if [ -n "$DOMAIN_FILTER" ]; then
        echo "域名过滤: $DOMAIN_FILTER" >> "$RESULT_FILE"
    fi
    if [ "$ERROR_ONLY" = true ]; then
        echo "记录类型: 非NXDOMAIN|NOERROR" >> "$RESULT_FILE"
    fi
    
    # 在结果输出部分添加K8S内部域名信息
    # 在"分析时间"前添加
    echo "Kubernetes内部域名: $K8S_DOMAIN_NAME" >> "$RESULT_FILE"
    echo "分析时间: $(date)" >> "$RESULT_FILE"

    # 清理临时文件
    rm -f "$TEMP_FILE" "${TEMP_FILE}_processed"

    # 显示结果
    echo "分析完成! 结果已保存到: $RESULT_FILE"
    echo ""
    echo "前10个最慢的域名解析:"
    head -n 15 "$RESULT_FILE" | tail -n 10
}

# 函数：显示使用说明
show_usage() {
    echo "使用说明: $0 [选项]"
    echo "选项:" 
    echo "  -c, --collect          只收集coredns日志"
    echo "  -a, --analyze          只分析已收集的日志"
    echo "  -t, --time-period N    分析最近N秒内的日志（仅与-c或默认模式一起使用）"
    echo "  -d, --domain DOMAIN    只分析指定域名的日志"
    echo "  -e, --error-only       只分析非NXDOMAIN|NOERROR的记录"
    echo "  -h, --help             显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 -t 3600             收集并分析最近一小时的日志"
    echo "  $0 -a -d example.com   分析已收集的日志，只关注example.com域名"
    echo "  $0 -t 1800 -d google.com 收集并分析最近半小时内google.com的日志"
    echo "  $0 -a -e               分析已收集的日志，只关注非NXDOMAIN|NOERROR的记录"
}

# 主程序
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--collect)
            COLLECT_LOGS=true
            shift
            ;;
        -a|--analyze)
            ANALYZE_LOGS=true
            shift
            ;;
        -t|--time-period)
            TIME_PERIOD="$2"
            if ! [[ "$TIME_PERIOD" =~ ^[0-9]+$ ]]; then
                echo "错误: 时间周期必须是整数"
                exit 1
            fi
            shift 2
            ;;
        -d|--domain)
            DOMAIN_FILTER="$2"
            shift 2
            ;;
        -e|--error-only)
            ERROR_ONLY=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "错误: 未知选项 '$1'"
            show_usage
            exit 1
            ;;
    esac
done

if [ -z "$COLLECT_LOGS" ] && [ -z "$ANALYZE_LOGS" ]; then
    # 无参数：收集并分析
    echo "开始收集coredns日志..."
    collect_logs
    echo ""
    echo "开始分析coredns日志..."
    analyze_logs
else
    if [ "$COLLECT_LOGS" = true ]; then
        collect_logs
    fi
    
    if [ "$ANALYZE_LOGS" = true ]; then
        analyze_logs
    fi
fi

