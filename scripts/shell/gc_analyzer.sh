#!/bin/bash

# GC日志快速分析脚本
# 用法: ./gc_analyzer.sh <pod_name> [options]

# 默认值
DEFAULT_NAMESPACE="default"
DEFAULT_GC_PATH="/app/spring-boot/gc_logs/"

# 变量初始化
pod_name=""
namespace=""
gc_logs_path=""
temp_dir=""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# 使用说明
usage() {
    cat << EOF
用法: $0 [选项] <pod_name>

选项:
    -n, --namespace <namespace>  指定命名空间 (默认: default)
    -p, --path <gc_log_path>     GC日志路径 (默认: /app/spring-boot/gc_logs/)
    -h, --help                   显示帮助信息

示例:
    $0 my-app-pod
    $0 -n production -p /app/logs/gc/ my-app-pod
EOF
    exit 1
}

# 解析命令行参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--namespace)
                namespace="$2"
                shift 2
                ;;
            -p|--path)
                gc_logs_path="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            -*)
                log_error "未知选项: $1"
                usage
                ;;
            *)
                pod_name="$1"
                shift
                ;;
        esac
    done

    namespace=${namespace:-$DEFAULT_NAMESPACE}
    gc_logs_path=${gc_logs_path:-$DEFAULT_GC_PATH}
    
    if [ -z "$pod_name" ]; then
        log_error "必须指定Pod名称!"
        usage
    fi
}

# 检查参数有效性
check_params() {
    log_info "检查Pod: $pod_name (命名空间: $namespace)"
    
    if ! kubectl get namespace "$namespace" > /dev/null 2>&1; then
        log_error "命名空间 '$namespace' 不存在!"
        exit 1
    fi

    if ! kubectl -n "$namespace" get pod "$pod_name" > /dev/null 2>&1; then
        log_error "在命名空间 '$namespace' 中未找到Pod '$pod_name'!"
        exit 1
    fi

    # 创建临时目录
    temp_dir=$(mktemp -d)
}

# 检查并收集GC日志
collect_gc_logs() {
    log_info "检查GC日志路径: $gc_logs_path"
    
    # 检查目录是否存在
    if ! kubectl -n "$namespace" exec "$pod_name" -- ls "$gc_logs_path" > /dev/null 2>&1; then
        log_error "GC日志目录 '$gc_logs_path' 在Pod中不存在!"
        exit 1
    fi
    
    # 查找GC日志文件
    local file_list
    file_list=$(kubectl -n "$namespace" exec "$pod_name" -- find "$gc_logs_path" -type f \( -name "*.log" -o -name "gc*" -o -name "*gc*" \) 2>/dev/null)
    
    if [ -z "$file_list" ]; then
        log_error "在路径 '$gc_logs_path' 中未找到GC日志文件!"
        exit 1
    fi
    
    # 复制文件
    local file_count=0
    while IFS= read -r file; do
        if [ -n "$file" ]; then
            local filename=$(basename "$file")
            if kubectl -n "$namespace" cp "$pod_name:$file" "$temp_dir/$filename" > /dev/null 2>&1; then
                file_count=$((file_count + 1))
            fi
        fi
    done <<< "$file_list"
    
    if [ "$file_count" -eq 0 ]; then
        log_error "未能复制任何GC日志文件!"
        exit 1
    fi
    
    log_success "找到并复制 $file_count 个GC日志文件"
}

# 安全的数字比较函数
safe_gt() {
    local num1=$1
    local num2=$2
    # 确保两个参数都是数字
    if [[ "$num1" =~ ^[0-9]+$ ]] && [[ "$num2" =~ ^[0-9]+$ ]]; then
        [ "$num1" -gt "$num2" ]
    else
        return 1
    fi
}

# 快速分析GC日志
quick_analyze() {
    echo "==========================================="
    echo "          GC日志快速分析报告"
    echo "==========================================="
    echo "Pod: $pod_name"
    echo "命名空间: $namespace"
    echo "分析时间: $(date)"
    echo "-------------------------------------------"
    
    local has_issues=0
    local total_full_gc=0
    local total_oom=0
    local total_long_pauses=0
    
    # 分析每个文件
    for gc_file in "$temp_dir"/*; do
        if [ -f "$gc_file" ] && [ -s "$gc_file" ]; then
            local filename=$(basename "$gc_file")
            echo -e "\n������ 文件: $filename"
            echo "-------------------------------------------"
            
            # 检查文件内容
            if analyze_single_file "$gc_file"; then
                has_issues=1
            fi
        fi
    done
    
    echo "==========================================="
    
    # 总结
    if [ $has_issues -eq 0 ]; then
        log_success "✅ GC状态正常，未发现严重问题"
    else
        log_warn "⚠️  发现GC问题，建议进一步分析"
    fi
    
    # 清理临时文件
    rm -rf "$temp_dir"
}

# 分析单个文件
analyze_single_file() {
    local gc_file=$1
    local file_issues=0
    
    # Full GC检查 - 使用安全的数字比较
    local full_gc_count=$(grep -c "Full GC" "$gc_file" 2>/dev/null)
    full_gc_count=${full_gc_count:-0}  # 如果为空，设为0
    
    if safe_gt "$full_gc_count" 0; then
        echo "❌ Full GC次数: $full_gc_count"
        file_issues=1
    else
        echo "✅ 无Full GC"
    fi
    
    # OOM检查 - 使用安全的数字比较
    local oom_count=$(grep -c "OutOfMemoryError\|Java heap space" "$gc_file" 2>/dev/null)
    oom_count=${oom_count:-0}  # 如果为空，设为0
    
    if safe_gt "$oom_count" 0; then
        echo "������ 内存溢出错误: $oom_count"
        file_issues=1
    else
        echo "✅ 无内存溢出错误"
    fi
    
    # GC暂停时间检查
    local pause_times=$(grep -E "secs]|real=[0-9]+\.[0-9]+" "$gc_file" 2>/dev/null | \
        sed -E 's/.*[[:space:]]([0-9]+\.[0-9]+)[[:space:]]*secs[].*|.*real=([0-9]+\.[0-9]+).*/\1\2/' 2>/dev/null | \
        grep -E "^[0-9]+\.[0-9]+$" 2>/dev/null)
    
    local long_pauses=0
    local max_pause=0
    
    if [ -n "$pause_times" ]; then
        long_pauses=$(echo "$pause_times" | awk '$1 > 1.0 {count++} END {print count+0}')
        max_pause=$(echo "$pause_times" | sort -nr 2>/dev/null | head -1)
        max_pause=${max_pause:-0}
    fi
    
    long_pauses=${long_pauses:-0}
    
    if safe_gt "$long_pauses" 0; then
        echo "⚠️  长时间暂停(>1s): $long_pauses 次, 最长: ${max_pause}s"
        file_issues=1
    else
        echo "✅ GC暂停时间正常"
    fi
    
    # 分配失败检查 - 使用安全的数字比较
    local allocation_failures=$(grep -c "Allocation Failure" "$gc_file" 2>/dev/null)
    allocation_failures=${allocation_failures:-0}  # 如果为空，设为0
    
    if safe_gt "$allocation_failures" 0; then
        echo "⚠️  分配失败: $allocation_failures 次"
        file_issues=1
    fi
    
    # 如果有问题，显示最近事件
    if [ $file_issues -eq 1 ]; then
        echo "������ 最近事件:"
        local recent_events=$(grep -E "Full GC|Allocation Failure|OutOfMemoryError" "$gc_file" 2>/dev/null | tail -2)
        if [ -n "$recent_events" ]; then
            while IFS= read -r line; do
                # 截断过长的行
                local truncated_line=$(echo "$line" | cut -c1-80)
                echo "   - $truncated_line"
            done <<< "$recent_events"
        else
            echo "   - 无相关事件"
        fi
    fi
    
    return $file_issues
}

# 主函数
main() {
    echo "������ 开始GC日志快速分析..."
    
    parse_arguments "$@"
    check_params
    collect_gc_logs
    quick_analyze
    
    echo -e "\n������ 分析完成!"
}

# 运行主函数
main "$@"
