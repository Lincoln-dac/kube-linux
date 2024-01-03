#!/usr/bin/env python
# -*- coding:utf-8 -*-
import commands
def Cordon_node():
    (status,output) = commands.getstatusoutput("/usr/local/bin/kubectl  top node|awk  '{print $1,$NF}'|grep -v NAME| awk -F'%' '{print $1,$NF}'|awk '{if ($NF>85) print $1}'")
    Than_list = output.split('\n')
    print "%s负载高" % Than_list


    (status,output) = commands.getstatusoutput("/usr/local/bin/kubectl get node |grep -v NAME|grep -v SchedulingDisabled|awk '{print $1}'")
    Scheduling_list = output.split('\n')
    print "%s可调度" %  Scheduling_list
    
    for Than_ip in Than_list:
        if Than_ip in Scheduling_list:
            print " %s 负载高且没有被禁止调度" % Than_ip
            commands.getstatusoutput("/usr/local/bin/kubectl cordon " + Than_ip) 



def Uncordon_node():
    (status,output) = commands.getstatusoutput("/usr/local/bin/kubectl  top node|awk  '{print $1,$NF}'|grep -v NAME| awk -F'%' '{print $1,$NF}'|awk '{if ($NF<80) print $1}'")
    Less_list = output.split('\n')
    print "%s负载低" % Less_list

    (status,output) = commands.getstatusoutput("/usr/local/bin/kubectl get node |grep -v NAME|grep SchedulingDisabled|awk '{print $1}'")
    SchedulingDisabled_list = output.split('\n')
    print "%s不可调度" %  SchedulingDisabled_list

    for Less_ip in Less_list:
        if Less_ip in SchedulingDisabled_list:
            print " %s 负载低且被禁止调度" % Less_ip
            commands.getstatusoutput("/usr/local/bin/kubectl uncordon " + Less_ip)
           


Cordon_node()
Uncordon_node()
