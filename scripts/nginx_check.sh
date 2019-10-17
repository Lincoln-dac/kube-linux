#!/bin/bash
A=`ps -C nginx --no-header | wc -l`
if [ $A -eq 0 ];then
    /opt/nginx/sbin/nginx 
    sleep 2 
    if [ `ps -C nginx --no-header | wc -l` -eq 0 ];then
        systemctl stop keepalived && killall keepalived
    fi
fi
