"""
# File       : get_traefik_access.py
# Time       ：2023/2/7 15:12
# Author     ：Lincoln
# version    ：python 3.8
# Description：
"""
from prometheus_api_client import PrometheusConnect
from kubernetes import client, config
import json
import subprocess
import time
try:
    prom = PrometheusConnect(url ="http://prometheus-65.fcbox.com", disable_ssl=True)
except Exception as e:
    # 捕获异常
    print("Error connecting to Prometheus:", e)
    exit()
deployments = [
    {
        "appingressroute" : "default-docker-hello-26f513e5ebfd28919d77@kubernetescrd",
        "deploy_name" : "docker-helloworld",
        "accesscount": "500",
	    "targetscalenumber" : "4"
    }
]

for deployment in deployments:
    replicas_query = 'kube_deployment_spec_replicas{deployment="%s"}' % (deployment['deploy_name'])
    replicas_query_result = prom.custom_query(replicas_query)[0]['value'][1]
    traefik_access_count = prom.custom_query(query='sum(delta(traefik_service_requests_total{exported_service="%s"}[1m]))' % dic["appingressroute"])[0]['value'][1]
    if replicas_query_result == deployment['targetscalenumber']:
        print("ONLINE deploy %s replicas number is equal scale number,exit" % deployment['deploy_name'])
        continue
    if float(traefik_access_count) > float(deployment['accesscount']):
        subprocess.run('/usr/bin/kubectl scale deployment %s --replicas=%s' % (deployment['deploy_name'], deployment['targetscalenumber']))
