#/bin/bash
#补偿发版后，老节点日志不压缩的问题
yesday_date=$(date -d yesterday  +%Y-%m-%d)
base_directory="/app/applogs"
# 遍历基础目录下的所有文件
find "$base_directory" -type f -name "*.log" -newermt "$(date -d 'yesterday' '+%Y-%m-%d')" ! -newermt "$(date '+%Y-%m-%d')" | while read -r file_path; do
    echo $file_path
    echo `date` >> /app/scripts/compensate.log
    echo "######################START################################"  >> /app/scripts/compensate.log 
    echo $file_path >> /app/scripts/compensate.log
    echo "----------------------END----------------------------------"  >> /app/scripts/compensate.log
    gzip $file_path && mv $file_path.gz $file_path.$yesday_date.log.gz
done

