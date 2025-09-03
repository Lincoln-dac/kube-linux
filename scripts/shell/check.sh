#!/bin/bash
netstat -naltp|grep 0.0.0.0:6443
if [ $? = 0 ];
  then
    exit 0
  else
    exit 1 
fi

