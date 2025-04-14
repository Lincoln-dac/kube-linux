#!/bin/bash
LOG_FILE="/tmp/clerndockimages"

image_id=$(docker images | grep "6 months ago" | awk '{print $3}')

# 检查是否获取到了镜像 ID
if [ -n "$image_id" ]; then
    # 若获取到了镜像 ID，则强制删除这些镜像
    docker rmi $image_id >> "$LOG_FILE" 2>&1
    echo "$(date '+%Y-%m-%d %H:%M:%S') 已删除6个月前的镜像，ID: $image_id" >> "$LOG_FILE"
else
    # 若未获取到镜像 ID，则输出提示信息
    echo "$(date '+%Y-%m-%d %H:%M:%S') 未找到 6 个月前的镜像，无需删除。" >> "$LOG_FILE"
fi