# CFS Burst Sidecar 逻辑说明

## 概述

CFS Burst Sidecar 通过监控容器的 cgroup CPU 统计信息，自动检测并缓解 CPU Throttle 问题。

## 核心概念

### CPU Throttle 原理

```
CFS (Completely Fair Scheduler) 调度周期：
- cfs_period_us = 100000 (默认 100ms)
- cfs_quota_us = 每周期可用的 CPU 时间

例如：CPU Limit = 2 核
→ cfs_quota_us = 200000 (100ms 内可用 200ms CPU 时间 = 2核)

当容器在 100ms 内使用的 CPU 时间超过 quota 时：
→ 触发 throttle，等待下一个周期
→ 导致请求延迟增加
```

### 突发场景

```
正常情况：容器平均使用 0.5 核（throttle = 0%）
         ↓
突发请求：100ms 内需要 1.5 核
         ↓
触发 throttle：0.5 核的配额在 66ms 用完
         ↓
等待下一个周期：RT 增加 30-100ms
```

## burst.sh 逻辑流程

### 1. 初始化阶段

```
┌─────────────────────────────────────────────────────────┐
│  1. 读取配置                                             │
│     ├── 环境变量：THRESHOLD, MULTIPLIER, DURATION       │
│     ├── Annotation 覆盖（优先级更高）                     │
│     └── 构造 cgroup 路径                                 │
│         /host_sys/fs/cgroup/cpu/kubepods/burstable/pod<UID> │
│     └── 获取 normal_quota（原始 cpu.cfs_quota_us）      │
└─────────────────────────────────────────────────────────┘
```

### 2. 主循环阶段

```
┌─────────────────────────────────────────────────────────┐
│                    while true                            │
│  ┌───────────────────────────────────────────────────┐  │
│  │  2. 读取 cpu.stat 计算 throttle ratio              │  │
│  │                                                    │  │
│  │  throttle_ratio = nr_throttled / nr_periods * 100 │  │
│  │                                                    │  │
│  │  cpu.stat 内容示例：                               │  │
│  │  nr_periods 1200                                  │  │
│  │  nr_throttled 60      → throttle_ratio = 5%      │  │
│  │  throttled_time 1234567                          │  │
│  └───────────────────────────────────────────────────┘  │
│                         ↓                                │
│  ┌───────────────────────────────────────────────────┐  │
│  │  3. 状态判断                                        │  │
│  │                                                    │  │
│  │  ┌─────────────────┐    ┌─────────────────────┐   │  │
│  │  │   in_burst = false   │   in_burst = true     │   │  │
│  │  └─────────────────┘    └─────────────────────┘   │  │
│  │           ↓                      ↓                 │  │
│  │  ┌─────────────────┐    ┌─────────────────────┐   │  │
│  │  │ throttle > 阈值? │    │ now < burst_end?    │   │  │
│  │  │     ↓ 是         │    │     ↓ 是             │   │  │
│  │  │ 触发 burst       │    │ throttle < 1%?      │   │  │
│  │  │ quota *= N       │    │     ↓ 是             │   │  │
│  │  │ in_burst = true  │    │ 恢复 quota          │   │  │
│  │  │ burst_end = now+D│    │ in_burst = false    │   │  │
│  │  └─────────────────┘    └─────────────────────┘   │  │
│  └───────────────────────────────────────────────────┘  │
│                         ↓                                │
│  ┌───────────────────────────────────────────────────┐  │
│  │  4. sleep CHECK_INTERVAL (默认 2秒)                │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## 状态机

```
                    ┌──────────────────┐
                    │    IDLE          │
                    │ (正常状态)        │
                    │ in_burst = false │
                    └────────┬─────────┘
                             │
                             │ throttle_ratio > THRESHOLD
                             ↓
                    ┌──────────────────┐
                    │    BURSTING      │
                    │ quota *= N       │
                    │ in_burst = true  │
                    │ burst_end = now+D│
                    └────────┬─────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
              ↓              ↓              ↓
    ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
    │ throttle<1%  │ │ now>=burst_end│ │ throttle>1%  │
    │  提前恢复     │ │ 超时恢复      │ │ 延长 burst   │
    └──────┬───────┘ └──────┬───────┘ └──────┬───────┘
           │                │                │
           └────────────────┴────────────────┘
                             │
                             ↓
                    ┌──────────────────┐
                    │    IDLE          │
                    │ (恢复正常)        │
                    └──────────────────┘
```

## 配置参数

| 参数 | 来源 | 说明 | 默认值 |
|------|------|------|--------|
| `THRESHOLD` | 环境变量 | throttle 阈值(%) | 5 |
| `MULTIPLIER` | 环境变量 | quota 放大倍数 | 3 |
| `DURATION` | 环境变量 | burst 持续时间(秒) | 10 |
| `CHECK_INTERVAL` | 环境变量 | 检查间隔(秒) | 2 |
| `CGROUP_ROOT` | 环境变量 | cgroup 根目录 | /host_sys/fs/cgroup |

Annotation 优先级更高（`cfs-burst.threshold` 等）

## 时间线示例

```
假设：THRESHOLD=5%, MULTIPLIER=3, DURATION=10s, CHECK_INTERVAL=2s

时间轴：
0s   ──────────────────────────────────────────────────
     Pod 启动，sidecar 初始化
     normal_quota = 200000 (2核)
     burst_quota = 600000 (6核)

5s   ──────────────────────────────────────────────────
     throttle_ratio = 8% > 5%
     → 触发 burst
     → quota: 200000 → 600000
     → in_burst = true, burst_end = 15s

7s   ──────────────────────────────────────────────────
     throttle_ratio = 3% < 5%
     → 提前恢复
     → quota: 600000 → 200000
     → in_burst = false

12s  ──────────────────────────────────────────────────
     throttle_ratio = 12% > 5%
     → 触发 burst
     → quota: 200000 → 600000
     → in_burst = true, burst_end = 22s

20s  ──────────────────────────────────────────────────
     burst_end = 22s，现在 20s < 22s，还在 burst 期间
     throttle_ratio = 6% > 1%
     → 继续 burst，延长 burst_end = 30s

25s  ──────────────────────────────────────────────────
     throttle_ratio = 0%
     → 恢复 quota: 600000 → 200000
     → in_burst = false
```

## cgroup 文件说明

| 文件 | 说明 |
|------|------|
| `cpu.cfs_quota_us` | 每周期可用 CPU 时间（微秒），-1 表示无限制 |
| `cpu.cfs_period_us` | 调度周期（微秒），默认 100000 (100ms) |
| `cpu.stat` | CPU 统计信息 |
| `cpu.stat.nr_periods` | 总调度周期数 |
| `cpu.stat.nr_throttled` | 被限流的周期数 |
| `cpu.stat.throttled_time` | 总限流时间（纳秒） |

## Quota 计算

```
CPU Limit (核) → cfs_quota_us 计算：

1核 = 100000 (100ms)
2核 = 200000 (200ms)
4核 = 400000 (400ms)

burst_quota = normal_quota * MULTIPLIER

例如：CPU Limit = 2 核
  normal_quota = 200000
  MULTIPLIER = 3
  burst_quota = 600000 (相当于 6 核)
```

## 日志输出

### 日志级别

| 级别 | 值 | 说明 |
|------|-----|------|
| ERROR | 1 | 错误日志（输出到 stderr） |
| WARN | 2 | 警告日志 |
| INFO | 3 | 信息日志（默认） |
| DEBUG | 4 | 调试日志 |

通过环境变量 `LOG_LEVEL` 设置，默认为 3。

### 日志示例

```
启动日志：
[2024-01-01 12:00:00] [pod-name] [INFO]  ==========================================
[2024-01-01 12:00:00] [pod-name] [INFO]  CFS Burst Sidecar Started
[2024-01-01 12:00:00] [pod-name] [INFO]  ==========================================
[2024-01-01 12:00:00] [pod-name] [INFO]  Pod:       your-app-abc123
[2024-01-01 12:00:00] [pod-name] [INFO]  Namespace: default
[2024-01-01 12:00:00] [pod-name] [INFO]  Cgroup:    /host_sys/fs/cgroup/cpu/kubepods/burstable/pod<uid>
[2024-01-01 12:00:00] [pod-name] [INFO]  Threshold: 5%
[2024-01-01 12:00:00] [pod-name] [INFO]  Multiplier: 3x
[2024-01-01 12:00:00] [pod-name] [INFO]  Duration:  10s
[2024-01-01 12:00:00] [pod-name] [INFO]  Normal Quota:  200000 (~2 cores)
[2024-01-01 12:00:00] [pod-name] [INFO]  Burst Quota:   600000 (~6 cores)

触发 burst（使用 WARN 级别，高亮显示）：
[2024-01-01 12:00:05] [pod-name] [WARN]  BURST ACTIVATED: quota 200000 -> 600000, throttle=8.50%, burst_end=10s

延长 burst：
[2024-01-01 12:00:08] [pod-name] [INFO]  Burst extended: +10s, burst_end=18s left, throttle=6.23%

提前恢复：
[2024-01-01 12:00:10] [pod-name] [INFO]  Burst restored early: quota=200000 (throttle=0%)

超时恢复：
[2024-01-01 12:00:15] [pod-name] [INFO]  Burst timeout, restored: quota=200000

状态摘要（每 60 秒）：
[2024-01-01 12:01:00] [pod-name] [DEBUG] Status: burst=IDLE, quota=200000, throttle=0.00%, nr_periods=1200, nr_throttled=0, throttled_time=0ms

退出时摘要：
[2024-01-01 12:30:00] [pod-name] [WARN]  Received signal, restoring quota and exiting...
[2024-01-01 12:30:00] [pod-name] [INFO]  ==========================================
[2024-01-01 12:30:00] [pod-name] [INFO]  CFS Burst Sidecar Summary
[2024-01-01 12:30:00] [pod-name] [INFO]  ==========================================
[2024-01-01 12:30:00] [pod-name] [INFO]  Uptime:    30m0s
[2024-01-01 12:30:00] [pod-name] [INFO]  Burst:     5 times
[2024-01-01 12:30:00] [pod-name] [INFO]  Restored:  5 times
[2024-01-01 12:30:00] [pod-name] [INFO]  Extended:  12 times
[2024-01-01 12:30:00] [pod-name] [INFO]  ==========================================
```

### 可观察性增强点

| 功能 | 说明 |
|------|------|
| **多级别日志** | ERROR/WARN/INFO/DEBUG 四级，方便过滤 |
| **启动横幅** | 启动时打印完整配置，便于排查 |
| **状态摘要** | 每 60 秒打印当前状态（DEBUG 级别） |
| **高亮触发** | burst 触发使用 WARN 级别，容易识别 |
| **统计报告** | 退出时打印统计：burst次数、恢复次数、延长次数 |
| **Uptime** | 显示运行时长 |
| **时间格式** | 统一时间格式，便于日志分析 |
| **信号处理** | SIGTERM/SIGINT 时自动恢复 quota 并打印摘要 |

## 注意事项

1. **配额单位**：cfs_quota_us 是微秒 (μs)，不是毫秒
2. **cgroup 路径**：不同 K8s 版本路径可能不同
   - K8s 1.15: `kubepods/burstable/pod<uid>`
   - K8s 1.25+: 可能是 cgroup v2
3. **Pod UID 长度**：cgroup 中 UID 可能有长度限制，取前 63 字符
4. **权限**：需要 privileged 模式才能写入 cgroup 文件