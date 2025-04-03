#!/bin/bash
nc -z localhost 80 && netstat -naltp|grep traefik|grep -w 80
if [ $? = 0 ];
  then
    exit 0
  else
    exit 1 
fi

