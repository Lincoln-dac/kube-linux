#!/bin/bash
#######java dump scripts##
pod_name=$1
app_namespace=$2
ARGS=2
if [ $# -ne "$ARGS" ];
  then
    echo "Please input POD NAME AND NAMESPACES , scripts exit "
  else
    appid=`kubectl -n $app_namespace exec $pod_name -- pidof java`
    kubectl -n $app_namespace exec $pod_name -- jmap -histo $appid  >>  /tmp/$pod_name.txt
    echo "java dump success file with /tmp dir"
    exit
fi
