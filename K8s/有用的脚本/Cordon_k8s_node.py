#!/usr/bin/env python
# -*- coding:utf-8 -*-
import subprocess

def run_command(command):
    """
    执行 shell 命令并返回状态码和输出结果
    :param command: 要执行的 shell 命令
    :return: 状态码和输出结果
    """
    try:
        result = subprocess.run(command, shell=True, capture_output=True, text=True)
        return result.returncode, result.stdout.strip()
    except Exception as e:
        print(f"执行命令时出错: {e}")
        return 1, ""

def Cordon_node():
    # 获取负载高于 85% 的节点列表
    status, output = run_command("/usr/local/bin/kubectl  top node|awk  '{print $1,$NF}'|grep -v NAME| awk -F'%' '{print $1,$NF}'|awk '{if ($NF>85) print $1}'")
    Than_list = output.split('\n')
    print(f"{Than_list} 负载高")

    # 获取可调度的节点列表
    status, output = run_command("/usr/local/bin/kubectl get node |grep -v NAME|grep -v SchedulingDisabled|awk '{print $1}'")
    Scheduling_list = output.split('\n')
    print(f"{Scheduling_list} 可调度")

    for Than_ip in Than_list:
        if Than_ip in Scheduling_list:
            print(f" {Than_ip} 负载高且没有被禁止调度")
            status, _ = run_command("/usr/local/bin/kubectl cordon " + Than_ip)
            if status == 0:
                print(f"成功禁止 {Than_ip} 调度")
            else:
                print(f"禁止 {Than_ip} 调度失败")

def Uncordon_node():
    # 获取负载低于 80% 的节点列表
    status, output = run_command("/usr/local/bin/kubectl  top node|awk  '{print $1,$NF}'|grep -v NAME| awk -F'%' '{print $1,$NF}'|awk '{if ($NF<80) print $1}'")
    Less_list = output.split('\n')
    print(f"{Less_list} 负载低")

    # 获取不可调度的节点列表
    status, output = run_command("/usr/local/bin/kubectl get node |grep -v NAME|grep SchedulingDisabled|awk '{print $1}'")
    SchedulingDisabled_list = output.split('\n')
    print(f"{SchedulingDisabled_list} 不可调度")

    for Less_ip in Less_list:
        if Less_ip in SchedulingDisabled_list:
            print(f" {Less_ip} 负载低且被禁止调度")
            status, _ = run_command("/usr/local/bin/kubectl uncordon " + Less_ip)
            if status == 0:
                print(f"成功允许 {Less_ip} 调度")
            else:
                print(f"允许 {Less_ip} 调度失败")

if __name__ == "__main__":
    Cordon_node()
    Uncordon_node()