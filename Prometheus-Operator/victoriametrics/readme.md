整体架构

VictoriaMetrics的集群主要由vmstorage、vminsert、vmselect等三部分组成，其中，vmstorage 负责提供数据存储服务; vminsert 是数据存储 vmstorage 的代理，使用一致性hash算法进行写入分片； vmselect 负责数据查询，根据输入的查询条件从 vmstorage 中查询数据。

VictoriaMetrics的这个三个组件每个组件都可以单独进行扩展，并运行在大多数合适软件上。vmstorage采用shared-nothing架构，优点是 vmstorage的节点相互之间无感知，相互之间无需通信，不共享任何数据，增加了集群的可用性、简化了集群的运维和集群的扩展。

![image](https://github.com/Lincoln-dac/kube-linux/blob/master/pic/v2-f3a1d4cd8a0f9abd6a2d0b812d9ddeab_720w.webp)
