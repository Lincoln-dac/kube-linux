#!/bin/bash
###CPU mem大于指定值，则禁止调度
CpuUseSize=50
MemUseSize=75

Cordon_node() {
  # 使用 CpuUseSize 变量筛选 CPU 使用率大于等于阈值的节点
  CurrentCpuGtDefaultSize=$(kubectl  top node|awk  '{print $1,$3}'|grep -v NAME| awk -F'%' '{print $1,$3}'|awk '{if ($3>='"$CpuUseSize"') print $1}')
  # 使用 MemUseSize 变量筛选内存使用率大于等于阈值的节点
  CurrentMemGtDefaultSize=$(kubectl  top node|awk  '{print $1,$NF}'|grep -v NAME| awk -F'%' '{print $1,$NF}'|awk '{if ($NF>='"$MemUseSize"') print $1}')
  SchedulingNodes=$(kubectl get nodes | grep -v NAME | grep -v SchedulingDisabled | awk '{print$1}')
  CombinedList=$(echo -e "$CurrentCpuGtDefaultSize\n$CurrentMemGtDefaultSize" | sort | uniq)
  FinalList=$(echo "$CombinedList" | grep -Fx -f <(echo "$SchedulingNodes"))
  echo "超过阈值的节点列表"
  echo "$CombinedList"
  echo "允许调度的节点"
  echo "$SchedulingNodes"
  echo "超过阈值且是允许调度节点"
  echo "$FinalList"
  for NodeList in $FinalList;
    do
    kubectl cordon $NodeList;
    done
}

Ucordon_node()  {
  # 使用 CpuUseSize 变量筛选 CPU 使用率小于阈值的节点
  CurrentCpuLtDefaultSize=$(kubectl  top node|awk  '{print $1,$3}'|grep -v NAME| awk -F'%' '{print $1,$3}'|awk '{if ($3<'"$CpuUseSize"') print $1}')
  # 使用 MemUseSize 变量筛选内存使用率小于阈值的节点
  CurrentMemLtDefaultSize=$(kubectl  top node|awk  '{print $1,$NF}'|grep -v NAME| awk -F'%' '{print $1,$NF}'|awk '{if ($NF<'"$MemUseSize"') print $1}')
  SchedulingDisabledNodes=$(kubectl get nodes | grep -v NAME | grep SchedulingDisabled | awk '{print$1}')
  FinalList=$(echo "$CurrentCpuLtDefaultSize" | sort | grep -Fxf <(echo "$CurrentMemLtDefaultSize" | sort) | grep -Fxf <(echo "$SchedulingDisabledNodes" | sort))
  echo "CPU 利用率小于 $CpuUseSize% 清单"
  echo "$CurrentCpuLtDefaultSize"
  echo "MEM 利用率小于 $MemUseSize% 清单"
  echo "$CurrentMemLtDefaultSize"
  echo "禁止调度node清单"
  echo "$SchedulingDisabledNodes"
  echo "CPU 利用率低于 $CpuUseSize 且内存利用率低于 $MemUseSize 且是禁止调度的节点"
  echo "$FinalList"
  if [ -z "$FinalList" ];then
    exit
  else
    for NodeList in $FinalList;
    do
    kubectl uncordon $NodeList;
    done
  fi
}

Cordon_node
Ucordon_node