"""
# File       : node-monitor-status.py
# Time       ：2023/2/6 10:08
# Author     ：Lincoln
# version    ：python 3.8
# Description：
"""
import requests
from prometheus_api_client import PrometheusConnect

class monitor:
    """获取prometheus监控数据"""
    def __init__(self):
        #prometheus 地址
        self.url = 'http://prometheus-65.test.com'
        # up节点列表
        self.up_list = []
        # down节点列表
        self.down_list = []
    def getqueryvalue(self,query):
        base_url = self.url + 'api/v1/query?query='
        inquire = base_url + query
        print(inquire)
        response = requests.Request('GET',inquire)
        if response.status_code == 200:
            result = response.json()['data']['result'][0]
            return result
        else:
            return None
    def get_os_release(self,address):
        """
        获取系统内核版本
        :param address:
        :return:
        """
        query = 'node_uname_info{job="linux",instance=""' + address + '"}'
        result = self.getqueryvalue(query)
        value =result['metric']['release']
        return value
    print(get_os_release(value))

