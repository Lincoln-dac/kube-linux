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

# 检查是否传入了参数
if [ $# -ne 1 ]; then
    handle_error "错误：只能输入一个变量。"
fi

# 定义允许的变量值
allowed_values=("xlesn" "xldcn" "nwdcn" "nwesn")
network_zone="$1"

# 检查输入的参数是否在允许的值列表中
if ! [[ " ${allowed_values[*]} " =~ " ${network_zone} " ]]; then
    handle_error "错误：变量${network_zone}无效，只允许输入 xlesn, xldcn, nwdcn, nwesn。"
fi

# 函数定义部分

# 安装基础包依赖
InstallPackage() {
    echo "安装基础包依赖"
    yum install -y epel-release || handle_error "安装epel-release失败"
    yum clean all
    yum makecache
    yum install -y keepalived mtr telnet ipvsadm ipset wget nfs-utils systemd yum-plugin-ovl jq psmisc socat perl iotop iftop fuse fuse-devel nload lscpu lrzsz sysstat conntrack libseccomp tuned nscd yum-utils device-mapper-persistent-data lvm2 conntrack-tools libtool libtool-ltdl pigz libcgroup container-selinux || handle_error "安装基础包依赖失败"
}

# 系统参数调优，参数配置
InitSystemConf() {
    echo  "系统参数调优,参数配置"
    /usr/sbin/tuned-adm profile throughput-performance || handle_error "设置tuned配置文件失败"
    systemctl restart nscd && systemctl enable nscd || handle_error "重启或启用nscd服务失败"
    /usr/sbin/nscd -i hosts || handle_error "刷新nscd缓存失败"

    cd /etc/security || handle_error "切换到 /etc/security 目录失败"
    wget -O limits.conf "${base_url}/k8s/config/limits.conf" || handle_error "下载limits.conf文件失败"

    cd /etc/security/limits.d/ || handle_error "切换到 /etc/security/limits.d/ 目录失败"
    wget -O 20-nproc.conf "${base_url}/k8s/config/20-nproc.conf" || handle_error "下载20-nproc.conf文件失败"

    # 开启ipvs模块
    cat > /etc/sysconfig/modules/ipvs.modules <<EOF
#!/bin/bash
ipvs_modules="ip_vs ip_vs_lc ip_vs_wlc ip_vs_rr ip_vs_wrr ip_vs_lblc ip_vs_lblcr ip_vs_dh ip_vs_sh ip_vs_fo ip_vs_nq ip_vs_sed ip_vs_ftp ip_conntrack nf_conntrack"
for kernel_module in \${ipvs_modules}; do
    /sbin/modinfo -F filename \${kernel_module} > /dev/null 2>&1
    if [ \$? -eq 0 ]; then
        /sbin/modprobe \${kernel_module}
    fi
done
EOF
    chmod 755 /etc/sysconfig/modules/ipvs.modules
    bash /etc/sysconfig/modules/ipvs.modules || handle_error "执行ipvs.modules脚本失败"
    /usr/sbin/lsmod | grep -e ip_vs -e nf_conntrack_ipv4
    if [ $? -ne 0 ]; then
        handle_error "异常：未找到ip_vs或nf_conntrack_ipv4模块。"
    fi

    # 参数优化
    cd /etc/ || handle_error "切换到 /etc/ 目录失败"
    wget -O  sysctl.conf "${base_url}/k8s/config/sysctl.conf" || handle_error "下载sysctl.conf文件失败"



    # 关闭IPV6
    if [ $(cat /etc/default/grub |grep 'ipv6.disable=1' |grep GRUB_CMDLINE_LINUX|wc -l) -eq 0 ]; then
        sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="ipv6.disable=1 /' /etc/default/grub
        /usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg 
        /usr/sbin/grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg
    fi

    # 关闭防火墙
    systemctl stop firewalld NetworkManager && systemctl disable firewalld NetworkManager && /usr/sbin/swapoff -a && /usr/sbin/setenforce 0 && /usr/sbin/iptables -F

    # 优化netfilter
    echo "modprobe br_netfilter" > /etc/sysconfig/modules/br_netfilter.modules

    # 优化网络
    echo "NOZEROCONF=yes" > /etc/sysconfig/network
    echo "NETWORKING_IPV6=no" >> /etc/sysconfig/network

    # 加载模块
    /usr/sbin/modprobe ip_conntrack || handle_error "加载ip_conntrack模块失败"
    /usr/sbin/sysctl -p || handle_error "应用sysctl参数失败"
}

# 初始化目录
InitNodeDir() {
    echo  "初始化目录"
    mkdir -p /app/kubernetes/{bin,logs,config,data,ssl} /app/kubernetes/data/kubelet /app/scripts /app/applogs/gray /etc/docker /data/dockerdata || handle_error "创建 /app/kubernetes 相关目录失败"
    chmod -R 700 /app/kubernetes || handle_error "修改 /app/kubernetes 目录权限失败"
    chown  mwopr:mwopr /app/applogs/gray || handle_error "修改 /app/applogs/gray 目录所有者失败"
    mkdir -p /nfsc/EDMS /data/EDMS /mall_admin /nfsc/epsp/custm/report /op_mount_data /epsp  /nfs /data/ADSP/exportArchive /tibet_internal/report /group1/M00/oa/fceformext /data/faceid/ /ailabmfs /data/adsp || handle_error "创建其他目录失败"
}

# 初始化Flanneld
InitFlanneld() {
    echo "初始化Flanneld"
    cd /app/kubernetes/ssl || handle_error "切换到 /app/kubernetes/ssl 目录失败"
    wget -O ssl.tar.gz "${base_url}/k8s/${network_zone}/ssl/ssl.tar.gz" || handle_error "下载ssl.tar.gz文件失败"
    tar zxvf ssl.tar.gz || handle_error "解压ssl.tar.gz文件失败"
    yum install flannel -y || handle_error "安装flannel失败"

    cd /usr/bin/ || handle_error "切换到 /usr/bin/ 目录失败"
    wget -O flanneld-amd64 "${base_url}/k8s/package/flanneld-amd64" || handle_error "下载flanneld-amd64文件失败"
    chmod +x flanneld-amd64

    cd /etc/sysconfig/ || handle_error "切换到 /etc/sysconfig/ 目录失败"
    wget -O flanneld "${base_url}/k8s/${network_zone}/config/flanneld" || handle_error "下载flanneld配置文件失败"

    cd /usr/lib/systemd/system/ || handle_error "切换到 /usr/lib/systemd/system/ 目录失败"
    wget -O flanneld.service  "${base_url}/k8s/config/flanneld.service" || handle_error "下载flanneld.service文件失败"
    flanneld-amd64 --version
}

# 初始化Docker
InitDocker() {
    echo "初始化Docker"
    cd /root/ || handle_error "切换到 /root 目录失败"
    wget -O  containerd.io-1.6.33-3.1.el7.x86_64.rpm "${base_url}/k8s/package/containerd.io-1.6.33-3.1.el7.x86_64.rpm" || handle_error "下载containerd.io-1.6.33-3.1.el7.x86_64.rpm文件失败"
    wget -O  docker-ce-18.03.0.ce-1.el7.centos.x86_64.rpm "${base_url}/k8s/package/docker-ce-18.03.0.ce-1.el7.centos.x86_64.rpm" || handle_error "下载docker-ce-18.03.0.ce-1.el7.centos.x86_64.rpm文件失败"
    rpm -ivh containerd.io-1.6.33-3.1.el7.x86_64.rpm || handle_error "安装containerd.io-1.6.33-3.1.el7.x86_64.rpm失败"
    rpm -ivh docker-ce-18.03.0.ce-1.el7.centos.x86_64.rpm || handle_error "安装docker-ce-18.03.0.ce-1.el7.centos.x86_64.rpm失败"

    cd /etc/docker || handle_error "切换到 /etc/docker 目录失败"
    wget -O daemon.json  "${base_url}/k8s/config/daemon.json" || handle_error "下载daemon.json文件失败"

    cd /usr/lib/systemd/system/ || handle_error "切换到 /usr/lib/systemd/system/ 目录失败"
    wget -O docker.service "${base_url}/k8s/config/docker.service" || handle_error "下载docker.service文件失败"

    cd /app/kubernetes/data/kubelet || handle_error "切换到 /app/kubernetes/data/kubelet 目录失败"
    wget -O config.json "${base_url}/k8s/${network_zone}/config/config.json" || handle_error "下载config.json文件失败"

}

# 初始化kubelet
InitKubelet() {
    echo "初始化kubelet"
    cd /app/kubernetes/config/ || handle_error "切换到 /app/kubernetes/config/ 目录失败"
    wget -O  kubelet "${base_url}/k8s/${network_zone}/config/kubelet" || handle_error "下载kubelet配置文件失败"
    wget -O  kubelet-config.yaml "${base_url}/k8s/${network_zone}/config/kubelet-config.yaml" || handle_error "下载kubelet-config.yaml文件失败"

    cd /usr/lib/systemd/system/ || handle_error "切换到 /usr/lib/systemd/system/ 目录失败"
    wget -O kubelet.service "${base_url}/k8s/config/kubelet.service" || handle_error "下载kubelet.service文件失败"

    cd /app/kubernetes/bin/ || handle_error "切换到 /app/kubernetes/bin/ 目录失败"
    wget -O kubelet "${base_url}/k8s/package/kubelet" || handle_error "下载kubelet文件失败"
    chmod +x /app/kubernetes/bin/kubelet
}

# 初始化kube-proxy
InitKubeProxy() {
    echo "初始化kube-proxy"
    cd /app/kubernetes/config/ || handle_error "切换到 /app/kubernetes/config/ 目录失败"
    wget -O proxy "${base_url}/k8s/${network_zone}/config/proxy" || handle_error "下载proxy配置文件失败"

    cd /usr/lib/systemd/system/ || handle_error "切换到 /usr/lib/systemd/system/ 目录失败"
    wget -O kube-proxy.service "${base_url}/k8s/config/kube-proxy.service" || handle_error "下载kube-proxy.service文件失败"

    cd /app/kubernetes/bin/ || handle_error "切换到 /app/kubernetes/bin/ 目录失败"
    wget -O kube-proxy "${base_url}/k8s/package/kube-proxy" || handle_error "下载kube-proxy文件失败"
    chmod +x /app/kubernetes/bin/kube-proxy

    echo "初始化组件配置文件IP信息"
    ipaddr=$(ip -o -4 addr show | grep '10.204.' | awk '{print $4}' | cut -d/ -f1)
    echo $ipaddr
    sed -i "s/127.0.0.1/$ipaddr/g" /app/kubernetes/config/kubelet
    sed -i "s/127.0.0.1/$ipaddr/g" /app/kubernetes/config/proxy
    sed -i "s/127.0.0.1/$ipaddr/g" /app/kubernetes/config/kubelet-config.yaml
    sed -i "s/127.0.0.1/$ipaddr/g" /etc/sysconfig/flanneld

    cat /app/kubernetes/config/kubelet | grep 10.204
    status1=$?
    cat /app/kubernetes/config/proxy | grep 10.204
    status2=$?
    cat /app/kubernetes/config/kubelet-config.yaml | grep 10.204
    status3=$?
    cat /etc/sysconfig/flanneld | grep 10.204
    status4=$?

    if [ $status1 -ne 0 ] || [ $status2 -ne 0 ] || [ $status3 -ne 0 ] || [ $status4 -ne 0 ]; then
        handle_error "配置修改失败"
    fi
}

# 初始化LogAgent
InitLogAgent() {
    echo "初始化LogAgent"
    cd /app || handle_error "切换到 /app 目录失败"
    local tar_files=("filebeat-app.tar.gz" "filebeat.tar.gz" "flume.tar.gz" "filebeat-order.tar.gz" "filebeat-os.tar.gz")
    for tar_file in "${tar_files[@]}"; do
        wget -O "$tar_file" "${base_url}/k8s/package/$tar_file" || handle_error "下载$tar_file文件失败"
        tar zxvf "$tar_file" || handle_error "解压$tar_file文件失败"
    done

    cd /app/scripts || handle_error "切换到 /app/scripts 目录失败"
    wget -O compensatelog.sh "${base_url}/k8s/scripts/compensatelog.sh" || handle_error "下载compensatelog.sh文件失败"
    wget -O logzip.sh "${base_url}/k8s/scripts/logzip.sh" || handle_error "下载logzip.sh文件失败"
    wget -O clean_dockimage.sh "${base_url}/k8s/scripts/clean_dockimage.sh" || handle_error "下载clean_dockimage.sh.sh文件失败"
    chmod +x compensatelog.sh && chmod +x logzip.sh && chmod +x clean_dockimage.sh || handle_error "修改脚本文件权限失败"

    cd /var/spool/cron || handle_error "切换到 /var/spool/cron 目录失败"
    wget -O  root "${base_url}/k8s/config/root" || handle_error "下载root文件失败"
}

# 初始化挂载目录
InitMountDir() {
    cd /usr/bin/ && wget -O  mfsmount "${base_url}/k8s/package/mfsmount"
    chmod +x  /usr/bin/mfsmount
    echo "初始化完成，请重启物理机。"
}

# 函数调用部分
InstallPackage
InitSystemConf
InitNodeDir
InitFlanneld
InitDocker
InitKubelet
InitKubeProxy
InitLogAgent
InitMountDir