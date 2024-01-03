"""
# File       : connect_promethes.py
# Time       ：2023/2/3 10:38
# Author     ：Lincoln
# version    ：python 3.8
# Description：
"""
import  requests
import json
import pycurl
import os

from prometheus_api_client import PrometheusConnect
prom = PrometheusConnect(url="http://prometheus-65.fcbox.com",headers=None,disable_ssl=True)
ok = prom.check_prometheus_connection() #检查链接状态
print(f"连接Prometheus:{prom.url}, 状态:{'连接成功' if ok else '连接失败'}")
url = 'http://prometheus-65.fcbox.com'
pre_url = url + '/api/v1/query?query='
expr = 'node_load5'
url1 = pre_url + expr
print(url1)
#data = requests.get('http://prometheus-65.fcbox.com/api/v1/query?query=node_load5').text
data = requests.get(url1).text
print(data)
data_json = json.loads(data)
#os.system('curl http://prometheus-65.fcbox.com/api/v1/query?query=node_load5')
# print(data_json['data']['result'][0]['metric']['instance'])
for metric in data_json['data']['result']:
    print(metric['metric']['instance'])

