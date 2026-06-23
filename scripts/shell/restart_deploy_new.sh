#!/bin/bash
set -euo pipefail

if [ $# -lt 2 ]; then
    echo "错误：必须指定 namespace 和至少一个 Deployment 名称"
    echo "用法: $0 <namespace> <deploy_name1> [deploy_name2 ...]"
    echo "示例: $0 default my-app1 my-app2 my-app3"
    exit 1
fi

namespace="$1"
shift  # 剩余参数为 deployment 列表

if [ -z "$namespace" ]; then
    echo "错误：namespace 不能为空"
    exit 1
fi

# 备份根目录
backup_base="/app/appyaml/backup/deploy"
log_file="/tmp/restart_deploy.log"

for deploy_name in "$@"; do
    if [ -z "$deploy_name" ]; then
        echo "警告：跳过空名称"
        continue
    fi

    # 名称格式校验
    if [[ ! "$deploy_name" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ ]]; then
        echo "错误：Deployment 名称 '${deploy_name}' 格式无效，跳过"
        continue
    fi

    # 验证 Deployment 是否存在
    echo "检查 Deployment '${namespace}/${deploy_name}' ..."
    if ! kubectl get deployment "${deploy_name}" -n "${namespace}" &> /dev/null; then
        echo "错误：Deployment '${namespace}/${deploy_name}' 不存在，跳过"
        continue
    fi

    # 备份 YAML
    backup_dir="${backup_base}/${namespace}"
    backup_file="${backup_dir}/${deploy_name}.yaml"
    mkdir -p "${backup_dir}"
    kubectl get deployment "${deploy_name}" -n "${namespace}" -o yaml > "${backup_file}"
    echo "备份: ${backup_file}"

    # 安全重启
    echo "重启 Deployment '${namespace}/${deploy_name}' ..."
    kubectl rollout restart "deployment/${deploy_name}" -n "${namespace}"

    # 日志记录
    {
        echo "$(date +'%Y-%m-%d-%H-%M-%S')"
        echo "重启 ${namespace}/${deploy_name}，备份: ${backup_file}"
        echo "======================="
    } >> "${log_file}"

    echo "成功触发 ${namespace}/${deploy_name} 重启"
done

#echo "批量重启完成"
