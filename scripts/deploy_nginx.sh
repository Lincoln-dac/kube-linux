#!/bin/bash
# 定义基础URL变量
base_url="http://yum-xl-repo.test.com"

# 判断当前用户是否为mwopr
if [ "$USER" = "mwopr" ]; then
    cd /app && wget http://yum-xl-repo.test.com/nginx/openresty.tgz && tar zxvf openresty.tgz 
else
    echo "当前用户不是mwopr，当前用户是 $USER"
fi
