#!/bin/bash
set -e
HARBOR_URL=10.204.209.253
HARBOR_PASSWD=Admin@1qa
#最大保留镜像个数。超过后的删除。
OLD_VERSION_NUM=1

function get_repos_list(){
  repos_list=$(curl -s -k -u admin:${HARBOR_PASSWD} http://${HARBOR_URL}/api/projects?page=1&page_size=100)
  mkdir -p $PWD/reposList
  echo "${repos_list}" | jq '.[]' | jq -r '.project_id' > $PWD/reposList/reposList.txt
}

function get_images_list(){
  mkdir -p $PWD/imagesList
  #for repo in $(cat $PWD/reposList/reposList.txt);do
  #  images_list=$(curl -s -k -u admin:${HARBOR_PASSWD} http://${HARBOR_URL}/api/repositories?project_id=${repo})
  #  echo "${images_list}" | jq '.[]' | jq -r '.name' > $PWD/imagesList/${repo}.txt
  #done
  curl -u "admin:${HARBOR_PASSWD}" -X GET -H "Content-Type: application/json" "http://${HARBOR_URL}/api/search?" --insecure > $PWD/all_images.txt
  grep repository_name $PWD/all_images.txt |grep tomcat/|awk -F':' '{print $2}'|awk -F'"' '{print $2}'> $PWD/imagesList/tomcat.txt
  grep repository_name $PWD/all_images.txt |grep spring-boot/|awk -F':' '{print $2}'|awk -F'"' '{print $2}' > $PWD/imagesList/sprint-boot.txt
}

function delete_images(){
  htmlinfo=$(curl -s -k -u admin:${HARBOR_PASSWD} http://${HARBOR_URL}/api/repositories/$1/tags)
  tags=$(echo "${htmlinfo}" | jq ".[${index}]" | jq -r '.name')
  echo $tags
  for tag in `echo ${tags} | awk 'BEGIN{i=1}{gsub(/ /,"\n");i++;print}' | awk  '{print $NF}' | sort -nr | sed "1,${OLD_VERSION_NUM}d"`;do
    echo "images=$1 ************************** tag= ${tags}"
    curl -s -k -u admin:${HARBOR_PASSWD} -X DELETE http://${HARBOR_URL}/api/repositories/$1/tags/${tag}
  done

}

function clean_registry(){
  image_name=$(docker ps | grep registry | grep photon | awk -F " " '{print $2}')
  docker run -it --name gc --rm --volumes-from registry ${image_name} garbage-collect  /etc/registry/config.yml
}

function entrance(){
  #get_repos_list
  get_images_list
  for file in `ls $PWD/imagesList`;do
      for images in $(cat $PWD/imagesList/${file}); do  
        delete_images ${images}
      done
  done
  clean_registry
  }
entrance
