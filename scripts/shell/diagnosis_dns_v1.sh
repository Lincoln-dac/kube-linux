#!/bin/bash
# DNS诊断工具 v1.0
# 功能：检查DNS服务器可用性、解析性能，并提供故障处理建议

# DNS服务器配置
INTERNAL_DNS_SERVERS=("10.204.179.5" "10.204.179.6" "10.204.179.7" "10.204.179.8" "10.204.179.9")
EXTERNAL_DNS_SERVERS=("202.96.128.86" "113.106.88.9" "119.29.29.29" "120.196.165.24")
DEFAULT_TEST_DOMAIN="www.baidu.com"
INTERNAL_TEST_DOMAIN="ib-gateway.fcbox.com"
TIMEOUT=2
HIGH_LATENCY_THRESHOLD=200  # 高延迟阈值（毫秒）

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 存储故障信息
declare -a port_failures
declare -a internal_failures
declare -a external_failures
declare -a high_latency_servers

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}错误: 未找到 $1 命令${NC}"
        exit 1
    fi
}

# 检查DNS端口连通性（使用telnet）
check_dns_port() {
    local server=$1
    # 使用telnet检查53端口连通性
    if echo -e "quit" | timeout $TIMEOUT telnet "$server" 53 2>&1 | grep -q "Connected"; then
        echo -e "${GREEN}端口 53 开放${NC}"
        return 0
    else
        echo -e "${RED}端口 53 关闭或无法访问${NC}"
        port_failures+=("$server")
        return 1
    fi
}

# 测试DNS解析
test_dns_resolution() {
    local server=$1
    local domain=$2
    local description=$3
    local is_external=$4  # 0=内部DNS, 1=外部DNS
    
    echo -n "测试 $description ($server -> $domain): "
    
    start_time=$(date +%s%N)
    result=$(dig +short +time=$TIMEOUT +tries=1 @"$server" "$domain" 2>&1)
    end_time=$(date +%s%N)
    
    duration=$(( (end_time - start_time) / 1000000 ))
    
    if [ $? -eq 0 ] && [ -n "$result" ] && [[ ! "$result" =~ "connection timed out" ]]; then
        # 检查延迟是否超过阈值
        if [ $duration -gt $HIGH_LATENCY_THRESHOLD ]; then
            echo -e "${GREEN}成功${RED} (耗时: ${duration}ms)${NC}"
            high_latency_servers+=("$server ($description - ${duration}ms)")
        else
            echo -e "${GREEN}成功 (耗时: ${duration}ms)${NC}"
        fi
        return 0
    else
        echo -e "${RED}失败 (耗时: ${duration}ms)${NC}"
        if [[ "$result" =~ "connection timed out" ]]; then
            echo "  错误: 连接超时"
        elif [ -z "$result" ]; then
            echo "  错误: 无解析结果"
        else
            echo "  错误: $result"
        fi
        
        # 记录故障信息
        if [ $is_external -eq 0 ]; then
            internal_failures+=("$server ($description)")
        else
            external_failures+=("$server ($description)")
        fi
        return 1
    fi
}

# 生成故障处理建议
generate_recommendations() {
    echo -e "\n${YELLOW}=== 故障处理建议 ===${NC}"
    
    local has_recommendations=0
    
    # 端口故障建议
    if [ ${#port_failures[@]} -gt 0 ]; then
        has_recommendations=1
        echo -e "${YELLOW}1. 端口不可用建议:${NC}"
        for failure in "${port_failures[@]}"; do
            echo "   - 服务器 $failure 的53端口不可访问"
            echo "     建议: 检查服务器是否运行正常，防火墙设置，以及DNS服务是否启动"
            echo "     如问题持续存在，建议将其从DNS负载均衡中剔除"
        done
        echo
    fi
    
    # 内部DNS故障建议
    if [ ${#internal_failures[@]} -gt 0 ]; then
        has_recommendations=1
        echo -e "${YELLOW}2. 内部DNS解析失败建议:${NC}"
        for failure in "${internal_failures[@]}"; do
            server_ip=$(echo "$failure" | awk '{print $1}')
            description=$(echo "$failure" | cut -d'(' -f2 | cut -d')' -f1)
            echo "   - 服务器 $server_ip ($description) 解析失败"
            echo "     建议: 检查服务器配置，确保其能正确解析内部和外部域名"
            echo "     如问题持续存在，建议将其从DNS负载均衡中剔除"
        done
        echo
    fi
    
    # 外部DNS故障建议
    if [ ${#external_failures[@]} -gt 0 ]; then
        has_recommendations=1
        echo -e "${YELLOW}3. 外部DNS解析失败建议:${NC}"
        for failure in "${external_failures[@]}"; do
            server_ip=$(echo "$failure" | awk '{print $1}')
            description=$(echo "$failure" | cut -d'(' -f2 | cut -d')' -f1)
            echo "   - 服务器 $server_ip ($description) 解析失败"
            echo "     建议: 检查网络连接，确保服务器能访问外部网络"
            echo "     如问题持续存在，建议将其从DNS配置中移除或替换"
        done
        echo
    fi
    
    # 高延迟建议
    if [ ${#high_latency_servers[@]} -gt 0 ]; then
        has_recommendations=1
        echo -e "${YELLOW}4. 高延迟服务器建议:${NC}"
        for server in "${high_latency_servers[@]}"; do
            server_ip=$(echo "$server" | awk '{print $1}')
            details=$(echo "$server" | cut -d'(' -f2 | cut -d')' -f1)
            echo "   - 服务器 $server_ip ($details) 响应时间超过阈值($HIGH_LATENCY_THRESHOLD ms)"
            echo "     建议: 检查服务器负载和网络状况，考虑优化或从负载均衡中暂时移除"
        done
        echo
    fi
    
    # 无故障情况
    if [ $has_recommendations -eq 0 ]; then
        echo -e "${GREEN}未检测到需要处理的故障${NC}"
        echo "  所有DNS服务器运行正常，没有高延迟问题"
    fi
}

# 显示使用说明
show_usage() {
    echo -e "${YELLOW}DNS诊断工具使用说明${NC}"
    echo "用法: $0 [自定义域名]"
    echo "功能:"
    echo "  1. 检查内部DNS服务器端口连通性"
    echo "  2. 测试内部DNS服务器的内网解析能力"
    echo "  3. 测试内部DNS服务器的外网解析能力"
    echo "  4. 测试外部DNS服务器的解析能力"
    echo "  5. (可选)测试自定义域名的解析"
    echo
    echo "示例:"
    echo "  $0                  # 执行所有默认测试"
    echo "  $0 example.com      # 执行默认测试并添加自定义域名测试"
}

# 主诊断函数
main() {
    local custom_domain="${1:-}"
    
    # 显示标题
    echo -e "\n${YELLOW}=== DNS组件故障诊断 ===${NC}"
    echo -e "检测阈值: 延迟超过 ${RED}${HIGH_LATENCY_THRESHOLD}ms${NC} 将标记为红色"
    echo -e "当前时间: $(date)"
    echo
    
    # 显示DNS服务器配置
    echo -e "${YELLOW}配置信息:${NC}"
    echo "内部DNS服务器: ${INTERNAL_DNS_SERVERS[*]}"
    echo "外部DNS服务器: ${EXTERNAL_DNS_SERVERS[*]}"
    echo "测试域名:"
    echo "  内网: $INTERNAL_TEST_DOMAIN"
    echo "  外网: $DEFAULT_TEST_DOMAIN"
    [ -n "$custom_domain" ] && echo "自定义域名: $custom_domain"
    echo
    
    # 检查必要命令
    check_command telnet
    check_command dig
    
    # 重置故障信息
    port_failures=()
    internal_failures=()
    external_failures=()
    high_latency_servers=()
    
    # 1. 诊断内部DNS服务端口
    echo -e "${YELLOW}1. 检查内部DNS服务端口${NC}"
    for server in "${INTERNAL_DNS_SERVERS[@]}"; do
        echo -n "检查 $server: "
        check_dns_port "$server"
    done
    echo
    
    # 2. 诊断内部DNS内网解析
    echo -e "${YELLOW}2. 检查内部DNS内网解析${NC}"
    for server in "${INTERNAL_DNS_SERVERS[@]}"; do
        test_dns_resolution "$server" "$INTERNAL_TEST_DOMAIN" "内网解析" 0
    done
    echo
    
    # 3. 诊断内部DNS外网解析
    echo -e "${YELLOW}3. 检查内部DNS外网解析${NC}"
    for server in "${INTERNAL_DNS_SERVERS[@]}"; do
        test_dns_resolution "$server" "$DEFAULT_TEST_DOMAIN" "外网解析" 0
    done
    echo
    
    # 4. 诊断外部DNS解析
    echo -e "${YELLOW}4. 检查外部DNS解析${NC}"
    for server in "${EXTERNAL_DNS_SERVERS[@]}"; do
        test_dns_resolution "$server" "$DEFAULT_TEST_DOMAIN" "外部DNS解析" 1
    done
    
    # 5. 如果指定了自定义域名，则进行额外测试
    if [ -n "$custom_domain" ]; then
        echo
        echo -e "${YELLOW}5. 检查自定义域名解析: $custom_domain${NC}"
        
        echo "  使用内部DNS解析:"
        for server in "${INTERNAL_DNS_SERVERS[@]}"; do
            test_dns_resolution "$server" "$custom_domain" "内部DNS" 0
        done
        
        echo
        echo "  使用外部DNS解析:"
        for server in "${EXTERNAL_DNS_SERVERS[@]}"; do
            test_dns_resolution "$server" "$custom_domain" "外部DNS" 1
        done
    fi
    
    # 生成故障处理建议
    generate_recommendations
}

# 显示使用说明
if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    show_usage
    exit 0
fi

# 执行主函数，传递第一个参数作为自定义域名
main "$1"
