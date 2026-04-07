#!/bin/bash
# 备份指定命名空间的K8s资源配置（kubectl 1.15版本）
set -euo pipefail
BACKUP="/app/appyaml/backup/$(date +%Y%m%d_%H%M%S)"
KUBECTL="$(which kubectl 2>/dev/null || echo /usr/local/bin/kubectl)"

# 检查kubectl是否可用
if ! command -v $KUBECTL >/dev/null 2>&1; then
    echo "错误: 无法找到kubectl命令"
    exit 1
fi

# 检查kubectl配置
if ! $KUBECTL config current-context >/dev/null 2>&1; then
    echo "错误: kubectl未配置或无法连接到集群"
    exit 1
fi

# 要备份的命名空间列表（用逗号分隔）
NAMESPACES="default,gray,ingress-system"

echo "开始备份指定命名空间: $NAMESPACES"
echo "备份时间: $(date)"
echo ""

# 创建备份根目录
mkdir -p "$BACKUP"

# 将逗号分隔的命名空间转换为数组
IFS=',' read -ra NS_ARRAY <<< "$NAMESPACES"

# 遍历每个命名空间
for NS in "${NS_ARRAY[@]}"; do
    echo "备份命名空间: $NS"
    
    # 创建命名空间目录
    mkdir -p "$BACKUP/$NS"
    
    # 备份Deployments
    echo "  备份Deployments..."
    mkdir -p "$BACKUP/$NS/deployments"
    DEPLOYS=$($KUBECTL get deploy -n $NS -o jsonpath='{.items[*].metadata.name}' 2>&1 || true)
    if [[ -z "$DEPLOYS" ]]; then
        echo "    无Deployments资源"
    else
        for DEPLOY in $DEPLOYS; do
            if $KUBECTL get deploy $DEPLOY -n $NS -o yaml > "$BACKUP/$NS/deployments/$DEPLOY.yaml" 2>&1; then
                if [[ -s "$BACKUP/$NS/deployments/$DEPLOY.yaml" ]]; then
                    echo "    ✓ $DEPLOY"
                else
                    echo "    ✗ $DEPLOY (空文件)"
                    rm -f "$BACKUP/$NS/deployments/$DEPLOY.yaml"
                fi
            else
                echo "    ✗ $DEPLOY (获取失败)"
            fi
        done
    fi
    
    # 备份Services
    echo "  备份Services..."
    mkdir -p "$BACKUP/$NS/services"
    SVCS=$($KUBECTL get svc -n $NS -o jsonpath='{.items[*].metadata.name}' 2>&1 || true)
    if [[ -z "$SVCS" ]]; then
        echo "    无Services资源"
    else
        for SVC in $SVCS; do
            if $KUBECTL get svc $SVC -n $NS -o yaml > "$BACKUP/$NS/services/$SVC.yaml" 2>&1; then
                if [[ -s "$BACKUP/$NS/services/$SVC.yaml" ]]; then
                    echo "    ✓ $SVC"
                else
                    echo "    ✗ $SVC (空文件)"
                    rm -f "$BACKUP/$NS/services/$SVC.yaml"
                fi
            else
                echo "    ✗ $SVC (获取失败)"
            fi
        done
    fi   
    
    # 备份Ingress
    echo "  备份Ingress..."
    mkdir -p "$BACKUP/$NS/ingress"
    INGS=$($KUBECTL get ingress -n $NS -o jsonpath='{.items[*].metadata.name}' 2>&1 || true)
    if [[ -z "$INGS" ]]; then
        echo "    无Ingress资源"
    else
        for ING in $INGS; do
            if $KUBECTL get ingress $ING -n $NS -o yaml > "$BACKUP/$NS/ingress/$ING.yaml" 2>&1; then
                if [[ -s "$BACKUP/$NS/ingress/$ING.yaml" ]]; then
                    echo "    ✓ $ING"
                else
                    echo "    ✗ $ING (空文件)"
                    rm -f "$BACKUP/$NS/ingress/$ING.yaml"
                fi
            else
                echo "    ✗ $ING (获取失败)"
            fi
        done
    fi
    
    # 备份IngressRoute
    echo "  备份IngressRoute..."
    mkdir -p "$BACKUP/$NS/ingressroute"
    IRS=$($KUBECTL get ingressroute -n $NS -o jsonpath='{.items[*].metadata.name}' 2>&1 || true)
    if [[ -z "$IRS" ]]; then
        echo "    无IngressRoute资源"
    else
        for IR in $IRS; do
            if $KUBECTL get ingressroute $IR -n $NS -o yaml > "$BACKUP/$NS/ingressroute/$IR.yaml" 2>&1; then
                if [[ -s "$BACKUP/$NS/ingressroute/$IR.yaml" ]]; then
                    echo "    ✓ $IR"
                else
                    echo "    ✗ $IR (空文件)"
                    rm -f "$BACKUP/$NS/ingressroute/$IR.yaml"
                fi
            else
                echo "    ✗ $IR (获取失败)"
            fi
        done
    fi
    
    echo ""
done

# 创建最新备份链接
LATEST="/app/appyaml/backup/latest"
rm -f "$LATEST" 2>/dev/null
ln -s "$BACKUP" "$LATEST"

# 显示备份结果
echo "========================================"
echo "备份完成!"
echo "备份位置: $BACKUP"
echo "最新备份链接: $LATEST"
echo ""
echo "各命名空间文件统计:"
for NS in "${NS_ARRAY[@]}"; do
    if [[ -d "$BACKUP/$NS" ]]; then
        echo "  $NS:"
        for RESOURCE_TYPE in deployments services ingress ingressroute; do
            if [[ -d "$BACKUP/$NS/$RESOURCE_TYPE" ]]; then
                COUNT=$(find "$BACKUP/$NS/$RESOURCE_TYPE" -name "*.yaml" -type f 2>/dev/null | wc -l)
                [[ $COUNT -gt 0 ]] && echo "    $RESOURCE_TYPE: $COUNT 个文件"
            fi
        done
    fi
done
echo "========================================"