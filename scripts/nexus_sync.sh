#!/bin/bash

# 停止 Nexus 服务
/app/nexus/nexus-3.19.1-01/nexus-3.19.1-01/bin/nexus stop

if [ $? -eq 0 ]; then
    # 如果停止成功，进行同步
    /usr/bin/rsync -avz --delete /app/nexus/ mwopr@10.204.16.12:/app/nexus/
    echo `date`  "sync data to 10.204.16.12 finish" >> /tmp/syncdata.log
else
    # 获取 Nexus 进程 ID
    pid=$(ps uax | grep -E nexus | grep -v grep | awk '{print $2}')
    if [ -n "$pid" ]; then
        # 先尝试正常终止进程
        kill $pid
        # 等待一段时间，例如 10 秒
        sleep 10
        # 检查进程是否还在运行
        if ps -p $pid > /dev/null; then
            # 若进程仍在运行，使用 kill -9 强制终止
            kill -9 $pid
        fi
    fi
    # 进行同步
    /usr/bin/rsync -avz --delete /app/nexus/ mwopr@10.204.16.232:/app/nexus/
    echo `date`  "sync data to 10.204.16.12 finish" >> /tmp/syncdata.log
fi

# 启动 Nexus 服务
/app/nexus/nexus-3.19.1-01/nexus-3.19.1-01/bin/nexus start
echo `date`  "nexus start is ok " >> /tmp/syncdata.log
