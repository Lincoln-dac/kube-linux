#!/bin/bash

# 定义域名文件路径
DOMAIN_FILE="/tmp/domain.txt"

# 检查域名文件是否存在
if [ ! -f "$DOMAIN_FILE" ]; then
    echo "错误：域名文件 $DOMAIN_FILE 不存在"
    exit 1
fi

# 检查是否安装了 OpenSSL
if ! command -v openssl &> /dev/null; then
    echo "错误：未找到 openssl 命令，请先安装 OpenSSL"
    exit 1
fi

# 设置解析的IP地址
TARGET_IP="157.148.58.35"

# 读取域名文件并逐行处理
while IFS= read -r domain; do
    # 跳过空行和注释行
    if [[ -z "$domain" || "$domain" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    
    # 去除行首尾的空白字符
    domain=$(echo "$domain" | xargs)
    
    echo "检查域名: $domain"
    
    # 使用 OpenSSL 获取证书信息，指定解析到目标IP
    cert_info=$(echo | openssl s_client -servername "$domain" -connect "$TARGET_IP:443" 2>/dev/null)
    
    if [ -z "$cert_info" ]; then
        echo "  无法获取证书信息"
        continue
    fi
    
    # 提取证书过期时间
    expire_date=$(echo "$cert_info" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    
    if [ -z "$expire_date" ]; then
        echo "  无法解析证书过期时间"
        continue
    fi
    
    # 转换日期格式并计算剩余天数
    expire_timestamp=$(date -d "$expire_date" +%s)
    current_timestamp=$(date +%s)
    days_remaining=$(( (expire_timestamp - current_timestamp) / 86400 ))
    
    # 输出结果
    if [ $days_remaining -gt 0 ]; then
        echo "  证书过期时间: $expire_date"
        echo "  剩余天数: $days_remaining"
    else
        echo "  证书已过期于: $expire_date"
    fi
    
    echo "----------------------------------------"
done < "$DOMAIN_FILE"
