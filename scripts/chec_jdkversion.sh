#!/bin/bash
LOG_FILE="/tmp/podlist.log"

# 获取所有Pod名称并循环处理
for PodName in $(kubectl get po | awk '{print $1}'); do
    # 检查/app目录下是否有包含191的文件
    kubectl exec $PodName -- ls /app |grep jdk1.8.0_191; 
    if [ $? = 0 ];then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 匹配到191的Pod: $PodName" | tee -a "$LOG_FILE"
    else
       exit
    fi
done