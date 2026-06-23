# CFS Burst Sidecar 部署手册

## 目录

- [概述](#概述)
- [前置条件](#前置条件)
- [部署步骤](#部署步骤)
- [配置说明](#配置说明)
- [验证部署](#验证部署)
- [日志查看](#日志查看)
- [故障排查](#故障排查)
- [回滚方案](#回滚方案)

---

## 概述

CFS Burst Sidecar 是解决容器偶发性 CPU 限流的轻量级方案，通过动态调整 `cpu.cfs_quota_us` 来缓解 CPU Throttle 问题。

### 架构图

```
┌─────────────────────────────────────────────────────────┐
│                    Kubernetes Pod                        │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────────┐    ┌──────────────────────────┐   │
│  │  Main Container  │    │   CFS Burst Sidecar      │   │
│  │                  │    │                          │   │
│  │  [Your App]      │    │  while true:             │   │
│  │                  │    │    read cpu.stat         │   │
│  │                  │ ←  │    if throttle > 5%:     │   │
│  │                  │    │      quota *= 3          │   │
│  │                  │    │    if recovered:         │   │
│  │                  │    │      restore quota       │   │
│  └──────────────────┘    └──────────────────────────┘   │
│           ↑                          ↑                   │
│           └─────── 共享 cgroup ──────┘                   │
│                                                          │
│  /sys/fs/cgroup/cpu/kubepods/burstable/pod<uid>/        │
│                        ↓                                 │
│              cpu.cfs_quota_us (可写)                     │
│              cpu.stat (可读)                             │
└─────────────────────────────────────────────────────────┘
```

---

## 前置条件

### 1. Kubernetes 版本

- K8s 1.15.x ✅
- K8s 1.18.x ✅
- K8s 1.20+ ✅

### 2. 容器运行时

- Docker ✅
- containerd ✅
- CRI-O ✅

### 3. 权限要求

DaemonSet 需要以下权限：
- `privileged: true`
- `hostPID: true`
- `mountPropagation: HostToContainer`

### 4. cgroup 路径确认

不同 K8s 版本 cgroup 路径可能不同：

| K8s 版本 | cgroup 路径 |
|----------|------------|
| 1.15 | `/sys/fs/cgroup/cpu/kubepods/burstable/pod<uid>` |
| 1.18-1.24 | `/sys/fs/cgroup/cpu/kubepods/burstable/pod<uid>` |
| 1.25+ (cgroup v2) | `/sys/fs/cgroup/cpu.k8s.io/pod<uid>` |

**确认方法**：
```bash
# 在节点上执行，查看你的 Pod 的 cgroup 路径
docker inspect <container-id> | grep -i cgroup
# 或
crictl inspect <container-id> | grep -i cgroup
```

---

## 部署步骤

### 步骤 1：创建 ConfigMap

```bash
# 修改 namespace 为你的应用所在命名空间
vim sidecar/configmap.yaml
# 将 metadata.namespace 改为你的应用命名空间，如：production

# 创建 ConfigMap
kubectl apply -f sidecar/configmap.yaml

# 验证
kubectl get cm cfs-burst-sidecar-script -n <your-namespace>
```

### 步骤 2：修改目标 Deployment

有两种方式：

#### 方式 A：直接编辑 YAML

```bash
kubectl edit deployment <your-app> -n <your-namespace>
```

在 `spec.template.spec` 下添加：

```yaml
spec:
  template:
    metadata:
      annotations:
        cfs-burst/enable: "true"
        cfs-burst/threshold: "5"
        cfs-burst/multiplier: "3"
        cfs-burst/duration: "10"
    spec:
      containers:
      # 你的主容器需要添加 volumeMounts
      - name: main
        volumeMounts:
        - name: pod-info
          mountPath: /etc/pod-info
        - name: sys-fs
          mountPath: /host_sys/fs
          mountPropagation: HostToContainer

      # 添加 sidecar 容器
      - name: cfs-burst-sidecar
        image: busybox:1.34
        imagePullPolicy: IfNotPresent
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_UID
          valueFrom:
            fieldRef:
              fieldPath: metadata.uid
        - name: NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: LOG_LEVEL
          value: "3"
        command:
        - /bin/sh
        - -c
        - |
          chmod 755 /burst.sh && /burst.sh
        volumeMounts:
        - name: burst-script
          mountPath: /burst.sh
          subPath: burst.sh
        - name: pod-info
          mountPath: /etc/pod-info
        - name: sys-fs
          mountPath: /host_sys/fs
          mountPropagation: HostToContainer
        securityContext:
          privileged: true

      volumes:
      - name: burst-script
        configMap:
          name: cfs-burst-sidecar-script
          defaultMode: 0755
      - name: pod-info
        downwardAPI:
          items:
          - path: "annotations"
            fieldRef:
              fieldPath: metadata.annotations
      - name: sys-fs
        hostPath:
          path: /sys/fs
```

#### 方式 B：使用 kubectl patch

```bash
# 先创建 patch 文件
cat > sidecar-patch.yaml << 'EOF'
spec:
  template:
    metadata:
      annotations:
        cfs-burst/enable: "true"
        cfs-burst/threshold: "5"
        cfs-burst/multiplier: "3"
        cfs-burst/duration: "10"
    spec:
      containers:
      - name: main
        volumeMounts:
        - name: pod-info
          mountPath: /etc/pod-info
        - name: sys-fs
          mountPath: /host_sys/fs
          mountPropagation: HostToContainer
      - name: cfs-burst-sidecar
        image: busybox:1.34
        imagePullPolicy: IfNotPresent
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_UID
          valueFrom:
            fieldRef:
              fieldPath: metadata.uid
        - name: NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: LOG_LEVEL
          value: "3"
        command:
        - /bin/sh
        - -c
        - "chmod 755 /burst.sh && /burst.sh"
        volumeMounts:
        - name: burst-script
          mountPath: /burst.sh
          subPath: burst.sh
        - name: pod-info
          mountPath: /etc/pod-info
        - name: sys-fs
          mountPath: /host_sys/fs
          mountPropagation: HostToContainer
        securityContext:
          privileged: true
      volumes:
      - name: burst-script
        configMap:
          name: cfs-burst-sidecar-script
          defaultMode: 0755
      - name: pod-info
        downwardAPI:
          items:
          - path: annotations
            fieldRef:
              fieldPath: metadata.annotations
      - name: sys-fs
        hostPath:
          path: /sys/fs
EOF

# 应用 patch
kubectl patch deployment <your-app> -n <your-namespace> --patch "$(cat sidecar-patch.yaml)"
```

### 步骤 3：滚动更新

Deployment 会自动触发滚动更新，sidecar 会被添加到每个 Pod 中。

```bash
# 查看滚动更新状态
kubectl rollout status deployment/<your-app> -n <your-namespace>

# 确认新 Pod 已启动
kubectl get pods -n <your-namespace> -l app=<your-app> -w
```

---

## 配置说明

### 通过 Annotation 配置

在 Deployment 的 `spec.template.metadata.annotations` 中设置：

| Annotation | 说明 | 默认值 | 示例 |
|------------|------|--------|------|
| `cfs-burst/enable` | 是否启用 | "true" | "true" / "false" |
| `cfs-burst/threshold` | throttle 阈值(%) | 5 | 5 |
| `cfs-burst/multiplier` | quota 放大倍数 | 3 | 3 |
| `cfs-burst/duration` | burst 持续时间(秒) | 10 | 10 |

### 示例配置

```yaml
# 高敏感服务 - 更激进
annotations:
  cfs-burst/enable: "true"
  cfs-burst/threshold: "3"
  cfs-burst/multiplier: "5"
  cfs-burst/duration: "15"

# 普通服务 - 默认
annotations:
  cfs-burst/enable: "true"
  cfs-burst/threshold: "5"
  cfs-burst/multiplier: "3"
  cfs-burst/duration: "10"

# 低敏感服务 - 更保守
annotations:
  cfs-burst/enable: "true"
  cfs-burst/threshold: "10"
  cfs-burst/multiplier: "2"
  cfs-burst/duration: "5"
```

### 通过环境变量配置

在 sidecar 容器中设置：

| 环境变量 | 说明 | 默认值 |
|----------|------|--------|
| `LOG_LEVEL` | 日志级别 (1-4) | 3 |
| `CHECK_INTERVAL` | 检查间隔(秒) | 2 |

---

## 验证部署

### 1. 检查 Pod 状态

```bash
kubectl get pods -n <your-namespace> -l app=<your-app>
```

预期输出：
```
NAME                        READY   STATUS    RESTARTS   AGE
your-app-abc123-xyz456      2/2     Running   0          2m
your-app-def789-ghi012      2/2     Running   0          2m
```

注意 `READY` 列应该是 `2/2`，表示主容器和 sidecar 都在运行。

### 2. 查看 Sidecar 日志

```bash
kubectl logs <pod-name> -n <your-namespace> -c cfs-burst-sidecar
```

预期输出：
```
[2024-01-01 12:00:00] [your-app-abc123] [INFO]  ==========================================
[2024-01-01 12:00:00] [your-app-abc123] [INFO]  CFS Burst Sidecar Started
[2024-01-01 12:00:00] [your-app-abc123] [INFO]  ==========================================
[2024-01-01 12:00:00] [your-app-abc123] [INFO]  Pod:       your-app-abc123-xyz456
[2024-01-01 12:00:00] [your-app-abc123] [INFO]  Namespace: production
[2024-01-01 12:00:00] [your-app-abc123] [INFO]  Cgroup:    /host_sys/fs/cgroup/cpu/kubepods/burstable/pod<uid>
[2024-01-01 12:00:00] [your-app-abc123] [INFO]  Threshold: 5%
[2024-01-01 12:00:00] [your-app-abc123] [INFO]  Multiplier: 3x
[2024-01-01 12:00:00] [your-app-abc123] [INFO]  Duration:  10s
[2024-01-01 12:00:00] [your-app-abc123] [INFO]  Normal Quota:  200000 (~2 cores)
[2024-01-01 12:00:00] [your-app-abc123] [INFO]  Burst Quota:   600000 (~6 cores)
[2024-01-01 12:00:00] [your-app-abc123] [INFO]  ==========================================
```

### 3. 验证 cgroup 文件可访问

```bash
# 进入 sidecar 容器
kubectl exec -it <pod-name> -n <your-namespace> -c cfs-burst-sidecar -- sh

# 查看 cgroup 路径
ls -la /host_sys/fs/cgroup/cpu/kubepods/burstable/pod<uid>/

# 查看当前 quota
cat /host_sys/fs/cgroup/cpu/kubepods/burstable/pod<uid>/cpu.cfs_quota_us

# 查看 cpu.stat
cat /host_sys/fs/cgroup/cpu/kubepods/burstable/pod<uid>/cpu.stat
```

### 4. 模拟 throttle 测试

```bash
# 在主容器中执行 CPU 密集型任务
kubectl exec -it <pod-name> -n <your-namespace> -c main -- sh

# 运行 CPU 压力测试
while true; do echo "scale=10000; 4*a(1)" | bc -l; done &

# 观察 sidecar 日志
kubectl logs -f <pod-name> -n <your-namespace> -c cfs-burst-sidecar

# 预期看到：BURST ACTIVATED
```

---

## 日志查看

### 实时查看日志

```bash
kubectl logs -f <pod-name> -n <your-namespace> -c cfs-burst-sidecar
```

### 查看历史日志

```bash
kubectl logs --tail=100 <pod-name> -n <your-namespace> -c cfs-burst-sidecar
```

### 过滤 burst 事件

```bash
# 只看 burst 触发的日志
kubectl logs <pod-name> -n <your-namespace> -c cfs-burst-sidecar | grep "BURST ACTIVATED"

# 只看 WARN 及以上级别
kubectl logs <pod-name> -n <your-namespace> -c cfs-burst-sidecar | grep -E "\[WARN\]|\[ERROR\]"
```

### 日志级别说明

| 级别 | 值 | 输出到 |
|------|-----|--------|
| ERROR | 1 | stderr |
| WARN | 2 | stdout |
| INFO | 3 | stdout |
| DEBUG | 4 | stdout (需设置 LOG_LEVEL=4) |

---

## 故障排查

### 问题 1：Sidecar 没有启动

**症状**：`kubectl get pods` 显示 `READY 1/2`

**排查**：
```bash
# 查看 sidecar 状态
kubectl describe pod <pod-name> -n <your-namespace> | grep -A 10 "cfs-burst-sidecar"

# 查看主容器日志
kubectl logs <pod-name> -n <your-namespace> -c main
```

**可能原因**：
1. ConfigMap 未创建或命名空间错误
2. 镜像拉取失败（busybox:1.34）
3. 权限不足

**解决方案**：
```bash
# 检查 ConfigMap
kubectl get cm cfs-burst-sidecar-script -n <your-namespace>

# 如果不存在，重新创建
kubectl apply -f sidecar/configmap.yaml -n <your-namespace>
```

### 问题 2：Cgroup 路径不存在

**症状**：日志显示 `Cgroup path not found`

**排查**：
```bash
# 在节点上执行，查看实际的 cgroup 路径
docker exec <container-id> cat /proc/1/cgroup | grep cpu
```

**解决方案**：
修改 `burst.sh` 中的 cgroup 路径构造逻辑，或挂载正确的 cgroup 目录。

### 问题 3：无法写入 cpu.cfs_quota_us

**症状**：日志显示 `Failed to set quota`

**排查**：
```bash
# 检查权限
kubectl exec -it <pod-name> -n <your-namespace> -c cfs-burst-sidecar -- sh
ls -la /host_sys/fs/cgroup/cpu/kubepods/burstable/pod<uid>/cpu.cfs_quota_us
```

**解决方案**：
1. 确认 `securityContext.privileged: true`
2. 确认 `mountPropagation: HostToContainer`
3. 检查节点内核参数

### 问题 4：Annotation 解析失败

**症状**：日志显示配置都是默认值，没有读取到 annotation

**排查**：
```bash
# 检查 annotation 是否正确设置
kubectl get pod <pod-name> -n <your-namespace> -o jsonpath='{.metadata.annotations}'

# 检查 downwardAPI 是否正确挂载
kubectl exec -it <pod-name> -n <your-namespace> -c cfs-burst-sidecar -- cat /etc/pod-info/annotations
```

**解决方案**：
确保 Deployment 的 `spec.template.metadata.annotations` 中有正确的 annotation，并且 `spec.template.spec.volumes` 中有 `downwardAPI` 配置。

---

## 回滚方案

### 方案 A：移除 Annotation

```bash
# 编辑 Deployment，移除或设置 enable 为 false
kubectl edit deployment <your-app> -n <your-namespace>

# 修改 annotation
metadata:
  annotations:
    cfs-burst/enable: "false"  # 改为 false
```

### 方案 B：移除 Sidecar

```bash
# 恢复原来的 Deployment 配置
kubectl rollout undo deployment/<your-app> -n <your-namespace>

# 或者手动移除 sidecar 相关配置
kubectl edit deployment <your-app> -n <your-namespace>
```

### 方案 C：删除 ConfigMap

```bash
# 如果确定不再使用，可以删除 ConfigMap
kubectl delete cm cfs-burst-sidecar-script -n <your-namespace>
```

---

## 附录

### 快速部署检查清单

- [ ] ConfigMap 已创建（namespace 正确）
- [ ] Deployment 已添加 sidecar 容器
- [ ] 主容器已添加 volumeMounts
- [ ] volumes 配置完整（burst-script, pod-info, sys-fs）
- [ ] securityContext.privileged: true
- [ ] mountPropagation: HostToContainer
- [ ] Pod 状态为 Running，READY 为 2/2
- [ ] Sidecar 日志正常输出
- [ ] Annotation 配置正确

### 相关文件

| 文件 | 说明 |
|------|------|
| `sidecar/configmap.yaml` | 包含 burst.sh 脚本的 ConfigMap |
| `sidecar/deployment-example.yaml` | Deployment 示例 |
| `sidecar/burst-sidecar.sh` | 独立脚本（备用）|
| `sidecar/LOGIC.md` | 逻辑说明文档 |