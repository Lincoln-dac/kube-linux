#!/bin/bash
# 检查参数是否为空
if [ -z "$1" ]; then
    echo "Usage: $0 <node_name>" 
    echo "没有输入node name"
    exit 1
fi
if [ $# -ne 1 ]; then
    echo "只能输入一个参数"
    exit 1
fi
node_name="$1"
# 使用 kubectl get node 获取节点列表
if kubectl get node | awk '{print $1}' | grep -Eq "^$node_name$"; then
    echo "$node_name is in Kubernetes cluster."
    #判断是否为核心节点
    kubectl get node | grep $node_name |grep tarefik || kubectl get node | grep $node_name |grep etcd  || kubectl get node | grep $node_name |grep master >> /dev/null
    if [ $? -eq 0 ]; then
        echo "核心节点,请手动缩容"
        exit 1
    else
        #kubectl drain $node_name --delete-local-data --force --ignore-daemonsets
        echo "驱除下线节点上的POD"
        sleep 30
        echo "驱除NODE $node_name"
        #kubectl delete node $node_name
    fi
        
else
    echo "$node_name is not in Kubernetes cluster or node name is invalid."
fi
