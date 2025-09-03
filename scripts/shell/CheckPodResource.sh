#!/bin/bash
#查看node上POD 资源 使用情况
node_name=$1
# 检查参数是否为空
if [ -z "$1" ]; then
    echo "Usage: $0 <node_name>" 
    echo "没有输入node name"
    exit 1
fi
if [ $# -eq 1 ];then
  node_names=$(kubectl get nodes -o=jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
  if echo "$node_names" | grep -q "$1$"; then
    for i in `kubectl  get po -o wide -A |grep $1|awk '{print $2}'`; do kubectl top po -A |grep $i; done;
    else
  echo "input node_name is not in k8s cluster,exit"
    exit
  fi
fi

