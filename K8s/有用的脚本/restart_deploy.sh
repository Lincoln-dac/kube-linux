#! /bin/bash
deploy_name=$1
if [ "X$deploy_name" != "X" ] 
then
#backup ymal
echo "backup app ${deploy_name} yaml"
/usr/local/bin/kubectl get deploy ${deploy_name}  -o yaml > /app/appyaml/backup/deploy/${deploy_name}.yaml
#log
echo "$(date +'%Y-%m-%d-%H-%M-%S')" >>/tmp/restart_deploy.log
echo "backup app ${deploy_name} yaml /app/appyaml/backup/deploy/${deploy_name}.yaml">>/tmp/restart_deploy.log
#restart deploy
echo "restart app ${deploy_name}"
/usr/local/bin/kubectl patch -f /app/appyaml/backup/deploy/${deploy_name}.yaml -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"last-updated\":\"$(date +'%Y-%m-%d-%H-%M-%S')\"}}}}}"
echo "restart app ${deploy_name}" >>/tmp/restart_deploy.log
echo "=======================" >>/tmp/restart_deploy.log
else
echo "参数异常 （restart_deploy.sh  deploy_name）"
fi
