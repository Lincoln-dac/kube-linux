#!/bin/bash
#1=ingressroute name
#2=namespace
kubectl get ingressroute  -o=custom-columns=name:metadata.name,url:spec.routes[0].match $1 -n $2
