# CFS Burst Sidecar

轻量级 Sidecar 方案，用于解决容器偶发性 CPU 限流问题。

## 方案特点

| 特点 | 说明 |
|------|------|
| **轻量** | 仅一个 shell 脚本，无额外依赖 |
| **简单** | 手动添加到 Deployment，不依赖 Webhook |
| **隔离** | 每个 Pod 独立运行，不影响其他 Pod |
| **可控** | 通过 annotation 按服务配置 |

## 工作原理

```
Pod 内共享 cgroup
        ↓
Sidecar 通过 downward API 获取 POD_UID
        ↓
构造 cgroup 路径，读取 cpu.stat
        ↓
检测到 throttle > 阈值 → 调大 cpu.cfs_quota_us
        ↓
超时自动恢复
```

## 文件结构

```
sidecar/
├── burst-sidecar.sh      # 独立脚本（备用）
├── configmap.yaml        # ConfigMap（包含脚本）
├── deployment-example.yaml # Deployment 示例
└── README.md
```

## 文档目录

| 文档 | 说明 |
|------|------|
| [README.md](README.md) | 概述和使用说明 |
| [DEPLOY.md](DEPLOY.md) | **完整部署手册** |
| [LOGIC.md](LOGIC.md) | 触发逻辑说明 |

---

## 使用步骤

### 1. 创建 ConfigMap

```bash
# 修改 namespace 为你的应用所在命名空间
vim configmap.yaml

kubectl apply -f configmap.yaml
```

### 2. 修改 Deployment

在 Deployment spec 中添加 sidecar：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: your-app
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
        # 你的主容器配置...
        volumeMounts:
        - name: pod-info
          mountPath: /etc/pod-info
        - name: sys-fs
          mountPath: /host_sys/fs
          mountPropagation: HostToContainer

      - name: cfs-burst-sidecar
        image: busybox:1.34
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
        command: ["/bin/sh", "-c", "chmod 755 /burst.sh && /burst.sh"]
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

### 3. 验证

```bash
# 查看 sidecar 日志
kubectl logs -f <pod-name> -c cfs-burst-sidecar

# 预期输出
[2024-01-01 12:00:00] [your-app-xxx] Started: threshold=5%, multiplier=3x, quota=200000
```

## 配置说明

通过 annotation 配置（Pod 级别）：

| Annotation | 说明 | 默认值 |
|------------|------|--------|
| `cfs-burst/enable` | 是否启用 | "true" |
| `cfs-burst/threshold` | throttle 阈值(%) | 5 |
| `cfs-burst/multiplier` | quota 放大倍数 | 3 |
| `cfs-burst/duration` | burst 持续时间(秒) | 10 |

## 注意事项

1. **cgroup 路径**：K8s 1.15 使用 `kubepods/burstable/`，其他版本可能不同
2. **权限**：需要 `privileged: true` 和 `mountPropagation: HostToContainer`
3. **命名空间**：ConfigMap 需要和 Pod 在同一个命名空间