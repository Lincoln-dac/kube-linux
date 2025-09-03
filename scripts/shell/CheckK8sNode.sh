#!/bin/bash
# 定义基础URL变量
base_url="http://yum-xl-repo.test.com"

# 通用错误处理函数
handle_error() {
    local message="$1"
    echo "$message"
    exit 1
}

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    handle_error "错误：此脚本必须以root用户身份执行。"
fi


Checkflannled() {

    # 只有当用户输入 Y 时，才执行以下操作
    echo "配置flanneld"
    systemctl stop flanneld && systemctl start flanneld && systemctl enable flanneld || handle_error "启动或启用flanneld服务失败"
}
ConfigDocker() {
    docker login -u admin -p Harbor12345 harbor.test.com || handle_error "登录Harbor失败"
    cp /root/.docker/config.json /app/kubernetes/data/kubelet || handle_error "复制docker配置文件失败"
    systemctl stop docker && systemctl start docker && systemctl enable docker || handle_error "启动或启用docker服务失败"
    cd /etc/rc.d/ || handle_error "切换到 /etc/rc.d/ 目录失败"
    wget -O rc.local "${base_url}/k8s/${network_zone}/config/rc.local" || handle_error "下载rc.local文件失败"
    chmod +x /etc/rc.d/rc.local || handle_error "设置rc.local文件可执行权限失败"
}

ConfigKubelet() {
    systemctl stop kubelet && systemctl start kubelet && systemctl enable kubelet || handle_error "启动或启用kubelet服务失败"
    echo "kubelet配置完成,请在控制台执行kubectl certificate approve `kubectl get csr | awk '{ print $1}'` 将新节点加入集群,脚本将等待120秒"
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