#!/bin/bash

set -e

# 安装依赖包
echo "安装依赖包..."
yum install -y autoconf libtool glib2-devel ncurses-devel

# 检查安装是否成功
if [ $? -ne 0 ]; then
    echo "错误：依赖包安装失败！"
    exit 1
fi

# 下载源码包（使用提供的内部地址）
echo "下载 irqbalance 1.9 源码包..."
wget -O /tmp/irqbalance-1.9.0.tar.gz http://yum-repo.test.com/k8s/package/irqbalance-1.9.0.tar.gz

# 编译安装
echo "编译安装 irqbalance..."
cd /tmp
tar zxvf irqbalance-1.9.0.tar.gz
cd irqbalance-1.9.0

./autogen.sh
./configure
make
make install

# 停止服务
echo "停止 irqbalance 服务..."
systemctl stop irqbalance || true

# 杀死可能残存的进程
pkill irqbalance || true

# 备份原有程序
echo "备份原有 irqbalance..."
[ -f /usr/sbin/irqbalance ] && cp /usr/sbin/irqbalance /tmp/irqbalance.bak

# 替换新版本
echo "安装新版本..."
cp -f /usr/local/sbin/irqbalance /usr/sbin/

# 验证版本
echo "验证版本..."
/usr/sbin/irqbalance --version || true

# 修改服务配置文件
echo "修改 systemd 服务配置..."
cd /usr/lib/systemd/system/ && wget -O irqbalance.service http://yum-repo.test.com/k8s/scripts/irqbalance.service

# 重新加载 systemd 并启动服务
echo "重启服务..."
systemctl daemon-reload
systemctl restart irqbalance
systemctl enable irqbalance

echo "升级完成！"
