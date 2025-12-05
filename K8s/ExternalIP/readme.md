    在私有网络下如何使用external-ip,且保持高可用
    缺陷：
    keepalived + externalIPs 方案本质是一个 4层（TCP/UDP）负载均衡器。它只能根据“IP地址 + 端口”的组合来区分流量，一个 <IP>:<端口> 组合只能对应后端一个Service，无法识别HTTP协议中的域名（Host头），因此确实无法直接实现“单IP多域名”路由。