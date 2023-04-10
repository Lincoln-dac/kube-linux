from prometheus_api_client import PrometheusConnect
import subprocess

deployments = [
    {
        "name": "boxservice-login-biz-sit1",
        "replicas": "6"
    },
    {
        "name": "app-manager-sit1",
        "replicas": "6"
    },
    {
        "name": "fcad-dsp-service-sit1",
        "replicas": "3"
    },
    {
        "name": "cabinet-base-server-sit1",
        "replicas": "4"
    }
]

try:
    prom = PrometheusConnect(url="http://prometheus-dev.ops.com/", disable_ssl=True)
except Exception as e:
    print("Error connecting to Prometheus:", e)
    exit()

for deployment in deployments:
    # 查询dubbo线程池的使用率
    dubbo_thread_query = 'dubbo_thread_pool_active_count{app="%s",job="DUBBO",namespace="sit1"}/dubbo_thread_pool_max_size{app="%s",job="DUBBO",namespace="sit1"}*100' % (
        deployment['name'], deployment['name'])
    dubbo_thread_result = prom.custom_query(dubbo_thread_query)
    replicas_query = 'kube_deployment_spec_replicas{deployment="%s"}' % (deployment['name'])
    replicas_query_result = prom.custom_query(replicas_query)[0]['value'][1]
    replicas_num = deployment['replicas']
    if replicas_query_result == replicas_num:
        print("ONLINE deploy %s replicas number is equal scale number,exit" % deployment['name'])
        continue
    if dubbo_thread_result and len(dubbo_thread_result) > 0:
        ## 如果使用率超过80%，则进行扩容
        dubbo_thread_usage = dubbo_thread_result[0]['value'][1]
        if float(dubbo_thread_usage) > 80:
            subprocess.run(
                '/usr/bin/kubectl --kubeconfig /root/.kube/config-test -n sit1 scale deployment %s --replicas=%s' % (
                    deployment['name'], deployment['replicas']))
            print("%s scale success" % deployment['name'])
        else:
            print("DUBBO thread usage for %s is %s%%" % (deployment['name'], dubbo_thread_usage))
    else:
        print("Query result is empty for %s" % deployment['name'])
    # 查询tomcat1线程池的使用率
    tomcat_thread_query = 'tomcat_threads_current_threads{app="%s",job="DUBBO",namespace="sit1"}/tomcat_threads_config_max_threads{app="%s",job="DUBBO",namespace="sit1"}*100' % (
    deployment['name'], deployment['name'])
    tomcat_thread_result = prom.custom_query(tomcat_thread_query)
    if tomcat_thread_result is None or len(tomcat_thread_result) == 0:
        tomcat_thread_query = 'tomcat_threads_current{app="%s",job="DUBBO",namespace="sit1"}/tomcat_threads_config_max{app="%s",job="DUBBO",namespace="sit1"}*100' % (
        deployment['name'], deployment['name'])
        tomcat_thread_result = prom.custom_query(tomcat_thread_query)
    if tomcat_thread_result and len(tomcat_thread_result) > 0:
        # 如果使用率超过80%，则进行扩容
        tomcat_thread_usage = tomcat_thread_result[0]['value'][1]
        if float(tomcat_thread_usage) > 80:
            subprocess.run(
                '/usr/bin/kubectl --kubeconfig /root/.kube/config-test -n sit1 scale deployment %s --replicas=%s' % (
                    deployment['name'], deployment['replicas']))
            print("%s scale success" % deployment['name'])
        else:
            print("Tomcat thread usage for %s is %s%%" % (deployment['name'], tomcat_thread_usage))
    else:
        print("Query result is empty for %s" % deployment['name'])
