#!/bin/bash
# 通用错误处理函数
handle_error() {
    local message="$1"
    echo "$message"
    exit 1
}

Configflannled() {
    read -p "初始化节点需要提前在etcd写入新节点POD网点，请确认操作是否执行，是选择Y 不是选择N: " confirm
    if [ "$confirm" != "Y" ]; then
        echo "操作已取消。"
        exit 1
    fi
    # 只有当用户输入 Y 时，才执行以下操作
    echo "配置flanneld"
    systemctl stop flanneld && systemctl start flanneld && systemctl enable flanneld || handle_error "启动或启用flanneld服务失败"
}
ConfigDocker() {
    docker login -u admin -p Harbor12345 harbor.fcbox.com || handle_error "登录Harbor失败"
    cp /root/.docker/config.json /app/kubernetes/data/kubelet || handle_error "复制docker配置文件失败"
    systemctl stop docker && systemctl start docker && systemctl enable docker || handle_error "启动或启用docker服务失败"

}

ConfigKubelet() {
    systemctl stop kubelet && systemctl start kubelet && systemctl enable kubelet || handle_error "启动或启用kubelet服务失败"
    echo "kubelet配置完成,请在控制台执行kubectl certificate approve `kubectl get csr | awk '{ print $1}'` 将新节点加入集群"
    sleep 120
}
ConfigKubeProxy() {
    systemctl stop kube-proxy && systemctl start kube-proxy && systemctl enable kube-proxy || handle_error "启动或启用kube-proxy服务失败"
}
handle_error
Configflannled
ConfigDocker
ConfigKubelet
ConfigKubeProxy
echo "配置完成"