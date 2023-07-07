#!/bin/bash
FILE=/app/applogs/traefik/traefik-access.log
if [ -e $FILE ];
  then
  echo "file exist" 
  cd /app/applogs/traefik && > ./traefik-access.log
else
  echo "file not exist,script exit"
fi
