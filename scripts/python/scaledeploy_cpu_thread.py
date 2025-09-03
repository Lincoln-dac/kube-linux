"""
# File       : scaledeploy_cpu_thread.py
# Time       ：2023/2/9 13:40
# Author     ：Lincoln
# version    ：python 3.8
# Description：
"""
from prometheus_api_client import PrometheusConnect
import subprocess

deployments = [
    {
        "name": "cabinet-base-server",
        "replicas": "30"
    },
    {
        "name": "cabinet-config-server",
        "replicas": "16"
    },
    {
        "name": "es-cabinet-stock-server",
        "replicas": "30"
    },
    {
        "name": "es-send-order",
        "replicas": "12"
    },
    {
        "name": "fcbox-boxservice-core",
        "replicas": "40"
    },
    {
        "name": "fcbox-activity-applet-web",
        "replicas": "18"
    },
    {
        "name": "es-marketing-benefit-server",
        "replicas": "9"
    },
    {
        "name": "fcbox-boxservice-login-biz",
        "replicas": "10"
    },
    {
        "name": "terminal-web",
        "replicas": "12"
    },
    {
        "name": "es-post-applet-web",
        "replicas": "24"
    },
    {
        "name": "fcbox-boxservice-sfnotify-web",
        "replicas": "10"
    },
    {
        "name": "app-manager",
        "replicas": "10"
    },
    {
        "name": "es-post-mobile-server",
        "replicas": "24"
    },
    {
        "name": "app-manager",
        "replicas": "9"
    },
    {
        "name": "fcbox-activity-core",
        "replicas": "24"
    },
    {
        "name": "es-base-service",
        "replicas": "8"
    },
    {
        "name": "es-courier-biz",
        "replicas": "9"
    },
    {
        "name": "es-post-data-server",
        "replicas": "8"
    },	
    {
        "name": "es-post-queryservice",
        "replicas": "12"
    },	
    {
        "name": "fcbox-esms-api-server",
        "replicas": "8"
    },	
    {
        "name": "fcbox-esms-web",
        "replicas": "8"
    },	
    {
        "name": "rent-server",
        "replicas": "12"
    },	
    {
        "name": "es-pick-calculator-server",
        "replicas": "9"
    },
    {
        "name": "es-pick-query-server",
        "replicas": "9"
    },
    {
        "name": "es-pick-server",
        "replicas": "16"
    },
    {
        "name": "fcbox-boxservice-custnotify-web",
        "replicas": "21"
    },
    {		
        "name": "es-post-userservice-biz",
        "replicas": "8"
    },
    {
        "name": "wechat-app-core",
        "replicas": "12"
    },
    {
        "name": "fcbox-ordercenter-system",
        "replicas": "12"
    }

]


try:
    prom = PrometheusConnect(url="http://prometheus-dcnnw.fcbox.com/", disable_ssl=True)
except Exception as e:
    print("error connecting to promethesu:", e)
    exit()

for deployment in deployments :
    replicas_query = 'kube_deployment_spec_replicas{deployment="%s"}' % (deployment['name'])
    cpu_usage_rate_query = 'sum(irate(container_cpu_usage_seconds_total{namespace="default",container="%s"}[1m])) by (container,job,namespace, pod, pod_name,deployname) / (sum(container_spec_cpu_quota{namespace="default",container="%s"}/100000) by (container,job,namespace, pod, pod_name,deployname )) * 100 ' % (
        deployment['name'], deployment['name'])
    cpu_usage_rate_avg_query = 'avg (sum(irate(container_cpu_usage_seconds_total{namespace="default",container="%s"}[1m])) by (container,job,namespace, pod, pod_name,deployname) / (sum(container_spec_cpu_quota{namespace="default",container="%s"}/100000) by (container,job,namespace, pod, pod_name,deployname )) * 100 )' % (
        deployment['name'], deployment['name'])
    #print(prom.custom_query(replicas_query))
    replicas_query_result = prom.custom_query(replicas_query)[0]['value'][1]
    if replicas_query_result == deployment['replicas']:
        print("ONLINE deploy %s replicas number is equal scale number,exit" % deployment['name'])
        continue
    else:
        cpu_usage_rate_result = prom.custom_query(cpu_usage_rate_query)
        cpu_usage_avg_rate_result = prom.custom_query(cpu_usage_rate_avg_query)
        #print(cpu_usage_rate_result)
        #print(cpu_usage_avg_rate_result)
        #查询当前副本数数量与预期扩容的副本数量是否一致
        if cpu_usage_rate_result is None or len(cpu_usage_rate_result) == 0:
            print("%s is none" % deployment['name'])
            exit
        else:
            # cpu_usage_rate_result = cpu_usage_rate_result[0]['value'][1]
            cpu_usage_rate = max([float(item['value'][1]) for item in cpu_usage_rate_result])
            #print(cpu_usage_rate)
            #单个POD CPU 90%扩容
            if cpu_usage_rate > 90:
                subprocess.run(
                '/usr/bin/kubectl  -n default scale deployment %s --replicas=%s' % (deployment['name'], deployment['replicas']))
                print("%s scale success" % deployment['name'])
            else:
                print("cpu max usage %s%%  %s not need scale"  % (cpu_usage_rate,deployment['name'] ))
        if cpu_usage_avg_rate_result is None or len(cpu_usage_avg_rate_result) == 0:
            print("%s is none" % deployment['name'])
            exit
        else:
             cpu_usage_avg_rate_result = cpu_usage_avg_rate_result[0]['value'][1]
             # deploy平均 CPU 80%扩容
             if float(cpu_usage_avg_rate_result) > 80:
                subprocess.run(
                '/usr/bin/kubectl  -n default scale deployment %s --replicas=%s' % (deployment['name'], deployment['replicas']))
                print("%s scale success" % deployment['name'])
             else:
                 print("cpu avg usage %s%%  %s not need scale" % (cpu_usage_avg_rate_result, deployment['name']))

for deployment in deployments:
    # 查询dubbo线程池的使用率
    dubbo_thread_query = 'dubbo_thread_pool_active_count{app="%s",job="DUBBO",namespace="default"}/dubbo_thread_pool_max_size{app="%s",job="DUBBO",namespace="default"}*100' % (
        deployment['name'], deployment['name'])
    dubbo_thread_result = prom.custom_query(dubbo_thread_query)
    replicas_query = 'kube_deployment_spec_replicas{deployment="%s"}' % (deployment['name'])
    replicas_query_result = prom.custom_query(replicas_query)[0]['value'][1]
    replicas_num = deployment['replicas']
    # 查询当前副本数数量与预期扩容的副本数量是否一致
    if replicas_query_result == replicas_num:
        print("ONLINE deploy %s replicas number is equal scale number,exit" % deployment['name'])
        continue
    if dubbo_thread_result and len(dubbo_thread_result) > 0:
        ## 如果使用率超过80%，则进行扩容
        dubbo_thread_usage = dubbo_thread_result[0]['value'][1]
        if float(dubbo_thread_usage) > 80:
            subprocess.run(
                '/usr/bin/kubectl  -n default scale deployment %s --replicas=%s' % (
                    deployment['name'], deployment['replicas']))
            print("%s scale success" % deployment['name'])
        else:
            print("DUBBO thread usage for %s is %s%% not need scale" % (deployment['name'], dubbo_thread_usage))
    else:
        print("Query dubbo_thread result is empty for %s" % deployment['name'])
    # 查询tomcat1线程池的使用率
    tomcat_thread_query = 'tomcat_threads_current_threads{app="%s",job="DUBBO",namespace="default"}/tomcat_threads_config_max_threads{app="%s",job="DUBBO",namespace="default"}*100' % (
    deployment['name'], deployment['name'])
    tomcat_thread_result = prom.custom_query(tomcat_thread_query)
    if tomcat_thread_result is None or len(tomcat_thread_result) == 0:
        tomcat_thread_query = 'tomcat_threads_current{app="%s",job="DUBBO",namespace="default"}/tomcat_threads_config_max{app="%s",job="DUBBO",namespace="default"}*100' % (
        deployment['name'], deployment['name'])
        tomcat_thread_result = prom.custom_query(tomcat_thread_query)
    if tomcat_thread_result and len(tomcat_thread_result) > 0:
        # 如果使用率超过80%，则进行扩容
        tomcat_thread_usage = tomcat_thread_result[0]['value'][1]
        if float(tomcat_thread_usage) > 80:
            subprocess.run(
                '/usr/bin/kubectl  -n default scale deployment %s --replicas=%s' % (
                    deployment['name'], deployment['replicas']))
            print("%s scale success" % deployment['name'])
        else:
            print("Tomcat thread usage for %s is %s%% not need scale" % (deployment['name'], tomcat_thread_usage))
    else:
        print("Query Tomcat thread result is empty for %s" % deployment['name'])
