Flannel 是一个非常简单的 overlay 网络（VXLAN），是 Kubernetes 网络 CNI 的解决方案之一。Flannel 在每台主机上运行一个简单的轻量级 agent flanneld 来监听集群中节点的变更，并对地址空间进行预配置。Flannel 还会在每台主机上安装 vtep flannel.1（VXLAN tunnel endpoints），与其他主机通过 VXLAN 隧道相连。

flanneld 监听在 8472 端口，通过 UDP 与其他节点的 vtep 进行数据传输。到达 vtep 的二层包会被原封不动地通过 UDP 的方式发送到对端的 vtep，然后拆出二层包进行处理。简单说就是用四层的 UDP 传输二层的数据帧。


![image](https://github.com/Lincoln-dac/kube-linux/blob/master/pic/640.jfif)

