#!/usr/bin/env bash
# kubeadm-cert-rotate.sh

set -Eeuo pipefail

DRY_RUN=false
RENEW_THRESHOLD_DAYS=90
BACKUP_ROOT="/var/backups/kubeadm-certs"
NODE_NAME="$(hostname -s)"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
BACKUP_DIR="${BACKUP_ROOT}/${NODE_NAME}-${TIMESTAMP}"
LOCK_FILE="/var/run/kubeadm-cert-rotate.lock"
KUBECONFIG_PATH="/etc/kubernetes/admin.conf"

log() {
  local level="$1"
  shift
  printf '[%s] [%s] %s\n' "$(date '+%F %T')" "$level" "$*"
}

fail() {
  log "ERROR" "$*"
  exit 1
}

cleanup() {
  rm -f "${LOCK_FILE}"
}

trap cleanup EXIT
trap 'fail "脚本执行异常中断，请检查日志并确认是否需要回滚"' ERR

usage() {
  cat <<EOF
Usage: $0 [--dry-run] [--threshold-days N] [--backup-root DIR]
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --threshold-days)
        RENEW_THRESHOLD_DAYS="$2"
        shift 2
        ;;
      --backup-root)
        BACKUP_ROOT="$2"
        BACKUP_DIR="${BACKUP_ROOT}/${NODE_NAME}-${TIMESTAMP}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "未知参数: $1"
        ;;
    esac
  done
}

check_prerequisites() {
  [[ "${EUID}" -eq 0 ]] || fail "必须使用 root 运行"
  command -v kubeadm >/dev/null 2>&1 || fail "未找到 kubeadm"
  command -v openssl >/dev/null 2>&1 || fail "未找到 openssl"
  command -v python3 >/dev/null 2>&1 || fail "未找到 python3"
  command -v systemctl >/dev/null 2>&1 || fail "未找到 systemctl"
  [[ -f /etc/kubernetes/pki/ca.crt ]] || fail "当前节点不是 kubeadm 控制面节点"

  if [[ -e "${LOCK_FILE}" ]]; then
    fail "检测到锁文件 ${LOCK_FILE}，可能已有其他更新任务在执行"
  fi
  touch "${LOCK_FILE}"
}

detect_expiring_certs() {
  local found=0
  while IFS= read -r cert; do
    [[ -f "${cert}" ]] || continue
    local end_date remain_days
    end_date="$(openssl x509 -in "${cert}" -noout -enddate | cut -d= -f2)"
    remain_days="$(python3 - "${end_date}" <<'PY'
from datetime import datetime, timezone
import sys

raw = sys.argv[1]
expiry = datetime.strptime(raw, "%b %d %H:%M:%S %Y %Z").replace(tzinfo=timezone.utc)
now = datetime.now(timezone.utc)
print(int((expiry - now).total_seconds() // 86400))
PY
)"
    if (( remain_days <= RENEW_THRESHOLD_DAYS )); then
      log "WARN" "$(basename "${cert}") 剩余 ${remain_days} 天"
      found=$((found + 1))
    fi
  done < <(find /etc/kubernetes/pki -type f -name '*.crt' | sort)

  echo "${found}"
}

backup_files() {
  mkdir -p "${BACKUP_DIR}/pki" "${BACKUP_DIR}/kubeconfig" "${BACKUP_DIR}/manifests" "${BACKUP_DIR}/etcd"
  cp -R /etc/kubernetes/pki/. "${BACKUP_DIR}/pki/"
  cp /etc/kubernetes/*.conf "${BACKUP_DIR}/kubeconfig/" 2>/dev/null || true
  cp /etc/kubernetes/manifests/* "${BACKUP_DIR}/manifests/"
  log "INFO" "备份完成: ${BACKUP_DIR}"
}

backup_etcd_snapshot() {
  if [[ ! -f /etc/kubernetes/pki/etcd/healthcheck-client.crt ]]; then
    log "INFO" "未检测到本地 stacked etcd 证书，跳过 etcd 快照"
    return 0
  fi

  if ! command -v etcdctl >/dev/null 2>&1; then
    log "WARN" "未找到 etcdctl，跳过 etcd 快照"
    return 0
  fi

  ETCDCTL_API=3 etcdctl \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
    --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
    --endpoints=https://127.0.0.1:2379 \
    snapshot save "${BACKUP_DIR}/etcd/snapshot.db"

  log "INFO" "etcd 快照完成"
}

renew_certs() {
  log "INFO" "开始续签 kubeadm 证书"
  kubeadm certs renew all

  log "INFO" "刷新 kubeconfig"
  kubeadm init phase kubeconfig admin
  kubeadm init phase kubeconfig controller-manager
  kubeadm init phase kubeconfig scheduler
  kubeadm init phase kubeconfig kubelet --node-name "${NODE_NAME}"
}

restart_static_pods() {
  local manifests=(
    "/etc/kubernetes/manifests/etcd.yaml"
    "/etc/kubernetes/manifests/kube-apiserver.yaml"
    "/etc/kubernetes/manifests/kube-controller-manager.yaml"
    "/etc/kubernetes/manifests/kube-scheduler.yaml"
  )

  for manifest in "${manifests[@]}"; do
    [[ -f "${manifest}" ]] || continue
    local temp="${manifest}.bak-${TIMESTAMP}"
    log "INFO" "触发重建静态 Pod: $(basename "${manifest}")"
    mv "${manifest}" "${temp}"
    sleep 5
    mv "${temp}" "${manifest}"
    sleep 10
  done

  log "INFO" "重启 kubelet"
  systemctl restart kubelet
}

wait_for_apiserver() {
  local retries=30
  for ((i=1; i<=retries; i++)); do
    if curl -ks https://127.0.0.1:6443/healthz >/dev/null 2>&1; then
      log "INFO" "apiserver 健康检查通过"
      return 0
    fi
    sleep 5
  done
  fail "apiserver 健康检查超时"
}

verify_cluster() {
  log "INFO" "检查证书剩余时间"
  kubeadm certs check-expiration

  log "INFO" "检查节点状态"
  KUBECONFIG="${KUBECONFIG_PATH}" kubectl get nodes

  log "INFO" "检查 kube-system Pod"
  KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n kube-system get pods -o wide
}

main() {
  parse_args "$@"
  check_prerequisites

  log "INFO" "开始执行，dry-run=${DRY_RUN} threshold=${RENEW_THRESHOLD_DAYS}"

  local expiring_count
  expiring_count="$(detect_expiring_certs)"

  if (( expiring_count == 0 )); then
    log "INFO" "所有证书剩余时间大于阈值，无需更新"
    exit 0
  fi

  backup_files
  backup_etcd_snapshot

  if [[ "${DRY_RUN}" == "true" ]]; then
    log "INFO" "dry-run 模式结束，不执行实际续签"
    exit 0
  fi

  renew_certs
  restart_static_pods
  wait_for_apiserver
  verify_cluster

  log "INFO" "证书更新完成"
}

main "$@"