#!/bin/bash
A=`ps -C nginx --no-header | wc -l`
if [ $A -eq 0 ];
  then
    systemctl restart nginx
    sleep 2
    if [ `ps -C nginx --no-header | wc -l` -eq 0 ];
      then
        exit 1
      else
        exit 0
     fi
    else
      exit 0
fi
