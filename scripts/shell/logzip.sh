
#!/bin/bash

function ZIP_LOGS()
{
    dir=$1
    file=$2

    cd $dir 
    if [ -f $file.tar.gz ]; then
        rm -rf $file
    else
        gzip $file && rm -rf $file
        chmod g+w $file.gz
    fi
}

function DEL_LOG()
{
    log_path=$1

    find $log_path -name "*.gz" -type f -mtime +15 -exec rm -rf {} \;

    #find $log_path -path $log_path/edmsdcn -prune -o -name "*.tar"*.gz" -type f -mtime +15 -exec rm -rf {} \;
}

function TRAVERSE_DIRS()
{
     day=`date -d "0 day ago" +%Y%m%d`

     for element in `ls $1`; do
        dir_or_file=$1"/"$element

        if [ -d $dir_or_file ]; then
            TRAVERSE_DIRS $dir_or_file
        else
            #echo $dir_or_file
            file=`echo $dir_or_file|grep ".*.log$"|grep "20[0-9]\{2\}-[0-9]\{2\}-[0-9]\{2\}"`
            log_day=`echo $dir_or_file|grep ".*.log$"|grep -o "20[0-9]\{2\}-[0-9]\{2\}-[0-9]\{2\}"|sed -n 's/-//g p'`
            if [ ! -z "$file" ]; then
                if [ "$log_day" -lt "$day" ]; then
                    ZIP_LOGS $1 $element
                    echo ZIP_LOGS $1 $element
                fi              
            fi
        fi

    done
}

function MAIN()
{
  
    TRAVERSE_DIRS /app/applogs
    DEL_LOG /app/applogs
    TRAVERSE_DIRS /app/applogs3
    DEL_LOG /app/applogs3
}

MAIN

