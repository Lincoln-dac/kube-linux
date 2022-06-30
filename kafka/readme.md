Producer
消息发布者；即主要作用是生产数据，并将产生的数据推送给 Kafka 集群。

Consumer
消息消费者；即主要作用是 kafka 集群中的消息，并将处理结果推送到下游或者是写入 DB 资源等。

Zookeeper Cluster
存储 Kafka 集群的元数据信息，比如记录注册的 Broker 列表，topic 元数据信息，partition 元数据信息等等。

Broker
Kafka 集群由多台服务器构成，每台服务器称之为一个 Broker 节点。

Topic
主题，表示一类消息，consumer 通过订阅 Topic 来消费消息，一个 Broker 节点可以有多个 Topic，每个 Topic 又包含 N 个 partition(分区或者分片)。

Partition
partition 是一个有序且不可变的消息序列，它是以 append log 文件形式存储的，partition 用于存放 Producer 生产的消息，然后 Consumer 消费 partition 上的消息，每个 partition 只能被一个 Consumer 消费。partition 还有副本的概念，后面文章来详细介绍。



![image](https://github.com/Lincoln-dac/kube-linux/blob/master/pic/clipboard.png)


https://mp.weixin.qq.com/s/ju8CcOks2-2PlpVdACg8Zw

https://www.szzdzhp.com/kafka/
https://github.com/didi/LogiKM
https://www.szzdzhp.com/kafka/op/op-for-kafka-all.html
https://mp.weixin.qq.com/s/Ny_VRCotJNE_4ZRLlMGSzg
