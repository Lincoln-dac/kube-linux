#!/bin/bash
#$1=pod_name
if [ $# -eq 1 ];then
 kubectl  get po |grep $1 >>/dev/null
 if [ $? == 0 ];then
  javapid=`kubectl exec $1 -- jps|grep -v Jps| awk '{print $1}'`
  echo $javapid
  kubectl exec $1 -- jmap -dump:live,format=b,file=/tmp/$1.hprof $javapid
  kubectl cp $1:/tmp/$1.hprof /tmp/$1.hprof
 else 
  echo "podname有异常,或者不存在"
 fi
else
 echo "输入参数不符合要求，脚本退出"
 exit
fi

