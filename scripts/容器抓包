check-pod-id.sh podname namespace

cat  check-pod-id.sh

#!/bin/bash
#1 podname
#2 namespaces
dockerid=`kubectl get pod $1 -n $2 -o template --template='{{range .status.containerStatuses}}{{.containerID}}{{end}}' | sed 's/docker:\/\/\(.*\)$/\1/'`
dockerinnodeip=`kubectl get pod -n $2 -o wide |grep $1 | awk '{print $7}'`
echo "the pod is running $dockerinnodeip,please login $dockerinnodeip"
echo " please  use command docker inspect -f {{.State.Pid}} $dockerid  and  nsenter -n -t pid capture package"



docker inspect -f {{.State.Pid}} 69786dd8873d4879b7b98b35232ca011442f9082b8ee9b34a678f9a4d44e73cf   

nsenter -n -t 20512
tcpdump host -w a.cap
