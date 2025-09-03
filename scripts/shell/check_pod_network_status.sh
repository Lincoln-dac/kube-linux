#!/bin/bash
#$1 node ip 
#$2  node port
ip=$1
port=$2


for i in `kubectl get pod -o wide |grep ${ip}| awk '{print $1}'`;

   do 
      
       result=`kubectl exec $i -- netstat -natlp |grep ${port}; `
       #echo "####" ${result}
       if [ ! $result 2>/dev/null ]; then  
	  echo "${i} IS NULL"  
       else 
          #echo -e  "\033[31m 红色字 \033[0m" 
          echo -e  "\033[31m  ${i}  NOT NULL \033[0m" 
          echo -e "\033[31m  $result  \033[0m"
       fi    

done
