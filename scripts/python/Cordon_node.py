"""
# File       : Cordon_node.py.py
# Time       ：2023/4/3 13:52
# Author     ：Lincoln
# version    ：python 3.8
# Description：定义k8s node 内存和cpu使用率 ，超过阈值就禁止调度
"""
from prometheus_api_client import PrometheusConnect
import os

try:
    prom = PrometheusConnect(url="http://prometheus-65.test.com/", disable_ssl=True)
except Exception as e:
    print("error connecting to promethesu:", e)
    exit()
# 查询node CPU使用率表达式
node_cpu_usage_result = prom.custom_query('node:node_cpu_utilisation:avg1m')
# 查询node状态
node_status_result = prom.custom_query('kube_node_spec_unschedulable')
# node_list= []
Scheduled_node_list = []
# print(node_status_result)
if node_status_result is not None and len(node_status_result) > 0:
    for node_status in node_status_result:
        if int(node_status["value"][1]) == 0:
            Scheduled_node = node_status["metric"]["node"]
            print(Scheduled_node)
            # Scheduled_node_list.append(Scheduled_node)
            # print(Scheduled_node_list)
        else:
            print("%s node  is  SchedulingDisabled" % node_status["metric"]["node"])
else:
    print("query node status error")
if node_cpu_usage_result is not None and len(node_status_result) > 0:
    for node_cpu_usage in node_cpu_usage_result:
        if float(node_cpu_usage["value"][1]) * 100 > 5:
            node_cpu_usage_list=node_cpu_usage["metric"]["node"]
            print(node_cpu_usage_list)
# else:
# print("all node is cpu usage above %5")
