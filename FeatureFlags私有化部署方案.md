# E2B Feature Flags 完整分析与部署方案

> 本文档是 **Feature Flags 私有化部署主文档**：负责维护当前 Flag 清单、默认值、LaunchDarkly 离线行为与私有化替代方案。
>
> 基线：上游 `e2b-dev/infra` tag `2026.28`，以 `packages/shared/pkg/featureflags/flags.go` 为准。
>
> 相关文档：
> - [`README.md`](./README.md)：仓库总入口与文档导航
> - [`LaunchDarkly私有化部署方案.md`](./LaunchDarkly私有化部署方案.md)：LaunchDarkly 现状、离线模式与阅读路径索引
> - [`核心组件详解.md`](./核心组件详解.md)：Feature Flags 在整体架构里的作用
> - [`启动参数详解.md`](./启动参数详解.md)：运行时环境变量（如 `LAUNCH_DARKLY_API_KEY`）

---

## 1. 阅读导航

### 如果你只想知道“不配置 LaunchDarkly 能不能跑”

可以跑。`LAUNCH_DARKLY_API_KEY` 为空时，`featureflags.NewClient()` 使用本地 offline store，并返回代码中注册的 fallback 值。

### 如果你想知道“代码里到底有哪些 Flag”

看 [2. Feature Flags 完整列表](#2-feature-flags-完整列表)。该清单按 `flags.go` 的 `NewBoolFlag`、`NewIntFlag`、`NewStringFlag`、`NewJSONFlag` 生成。

### 如果你想接入 YAML / Unleash / 自建配置

当前 `2026.28` 代码没有 `FEATURE_FLAGS_PROVIDER=yaml` 或 `FEATURE_FLAGS_PROVIDER=unleash` 这类 provider 选择环境变量。YAML/Unleash 是可选改造方案，不是现有无代码改动能力。

---

## 2. Feature Flags 完整列表

默认值中的 `dev: true` 表示 `ENVIRONMENT=dev` 或 `ENVIRONMENT=local` 时为 `true`，生产环境通常为 `false`。

### 2.1 Boolean Flags

| Flag 名称 | 默认值 | 说明 |
|-----------|--------|------|
| `use-nfs-for-snapshots` | dev: true | 快照读取/写入使用 NFS cache |
| `use-nfs-for-templates` | dev: true | 模板读取/写入使用 NFS cache |
| `write-to-cache-on-writes` | false | 写入时同时写缓存 |
| `use-nfs-for-building-templates` | dev: true | 构建模板时使用 NFS cache |
| `create-storage-cache-spans` | dev: true | 创建存储缓存 trace span |
| `orch-accepts-combined-host` | false | Orchestrator 是否接受 combined host |
| `storage-soft-delete-check` | false | 读取 storage-index soft-delete tombstone |
| `storage-soft-delete-enforce` | false | soft-deleted 对象读取失败关闭 |
| `use-memfd` | true | Firecracker guest memory 使用 memfd |
| `memfd-background-copy` | true | memfd snapshot cache 后台复制 |
| `peer-to-peer-chunk-transfer` | false | 启用 P2P chunk routing |
| `peer-to-peer-async-checkpoint` | false | checkpoint 异步上传 |
| `can-use-persistent-volumes` | dev: true | 是否允许持久卷 |
| `sandbox-label-based-scheduling` | false | Sandbox 基于标签调度 |
| `sandbox-placement-optimistic-resource-accounting` | false | 乐观资源记账 |
| `free-page-reporting` | false | Firecracker free page reporting |
| `freeze-user-cgroup` | dev: true | pause 前 freeze 用户 cgroup |
| `collapse-envd-heap` | false | pause 前让 envd 折叠匿名堆页 |
| `volume-fallback-to-unmatched-nodes` | true | volume 调度允许回退到未匹配节点 |
| `sandbox-volume-label-based-scheduling` | false | 按 volume 类型标签过滤节点 |
| `network-transform-rules` | dev: true | 允许网络规则 transform |
| `byop-proxy-enabled` | dev: true | 启用 BYOP egress proxy 配置 |
| `v4-header-for-uncompressed` | false | 未压缩上传使用 V4 header |
| `header-v5-write` | false | pause 写 V5 header |
| `resume-origin-node-remap` | false | resume 超时后重映射 origin node |
| `expiration-index-healer` | true | Redis 过期索引 healer |
| `disable-e2b-access-token-provisioning` | false | 停止签发旧 E2B access token |
| `disable-e2b-access-token-auth` | false | 停止接受旧 E2B access token |
| `nbd-async-write-zeroes` | false | NBD WRITE_ZEROES/TRIM 异步处理 |
| `pause-resume-prefetch-harvest` | false | pause 后做 throwaway warm resume 采样 |
| `pause-resume-prefetch-consume` | false | 将采样 mapping 写入 pause artifact |
| `clickhouse-write-fanout` | false | 启用 ClickHouse 多写端点 fan-out |

### 2.2 Integer Flags

| Flag 名称 | 默认值 | 单位 | 说明 |
|-----------|--------|------|------|
| `collapse-envd-heap-timeout-ms` | 10000 | ms | envd heap collapse 超时 |
| `max-sandboxes-per-node` | 200 | 个 | 每节点最大 sandbox 数 |
| `gcloud-concurrent-upload-limit` | 8 | 个 | 存储上传并发限制；历史 key 名保留 gcloud 前缀 |
| `gcloud-max-tasks` | 16 | 个 | 存储上传最大任务数 |
| `clickhouse-batcher-max-batch-size` | 100 | 条 | ClickHouse batch 大小 |
| `clickhouse-batcher-max-delay` | 1000 | ms | ClickHouse batch 延迟 |
| `clickhouse-batcher-queue-size` | 1000 | 条 | ClickHouse batch 队列 |
| `best-of-k-sample-size` | 3 | 个 | Best-of-K 采样数量 |
| `best-of-k-max-overcommit` | 400 | % | 最大超卖比例 |
| `best-of-k-alpha` | 50 | % | 当前使用权重 |
| `envd-init-request-timeout-milliseconds` | 50 | ms | envd init request 超时 |
| `envd-timeout-milliseconds` | `ENVD_TIMEOUT` 或 10000 | ms | resume 等待 envd 超时 |
| `guest-sync-timeout-milliseconds` | 0 | ms | filesystem-only snapshot 强制 guest sync 超时；0 为按 RAM 推导 |
| `max-cache-writer-concurrency` | 10 | 个 | cache writer 并发数 |
| `build-cache-max-usage-percentage` | 85 | % | build cache 磁盘使用阈值 |
| `build-provision-version` | 0 | - | build provision 版本 |
| `nbd-connections-per-device` | 1 | 个 | 每个 NBD device 的连接数 |
| `memory-prefetch-max-fetch-workers` | 16 | 个 | memory prefetch fetch workers |
| `memory-prefetch-max-copy-workers` | 8 | 个 | memory prefetch copy workers |
| `pause-resume-prefetch-harvest-timeout-ms` | 15000 | ms | throwaway harvest resume 超时 |
| `tcpfirewall-max-connections-per-sandbox` | -1 | 个 | TCP firewall 每 sandbox 最大连接数；-1 不限制 |
| `sandbox-max-incoming-connections` | -1 | 个 | HTTP proxy 每 sandbox 最大入站连接数；-1 不限制 |
| `build-base-rootfs-size-limit-mb` | 25000 | MB | OCI base rootfs 大小上限 |
| `minimum-autoresume-timeout` | 300 | 秒 | 最小 autoresume timeout |
| `build-reserved-disk-space-mb` | 256 | MB | guest root 保留磁盘空间 |
| `max-starting-instances-per-node` | 3 | 个 | 每节点并发 start/resume 上限 |
| `max-concurrent-evictions` | 256 | 个 | API sandbox eviction 并发上限 |
| `max-concurrent-snapshot-upserts` | 0 | 个 | snapshot upsert 并发上限；0/负数不限制 |
| `max-concurrent-sandbox-list-queries` | 0 | 个 | sandbox list 查询并发上限；0/负数不限制 |
| `max-concurrent-snapshot-build-queries` | 0 | 个 | snapshot build 查询并发上限；0/负数不限制 |
| `min-chunker-read-size-kb` | 16 | KB | chunker 最小读批次 |
| `max-parallel-build-read-segments` | 1 | 个 | fragmented build read 并发段数；1 以下保持串行 |

### 2.3 String Flags

| Flag 名称 | 默认值 | 说明 |
|-----------|--------|------|
| `build-firecracker-version` | `DEFAULT_FIRECRACKER_VERSION` 或 `v1.14.1_431f1fc` | 构建使用的 Firecracker 版本 |
| `build-kernel-version` | `DEFAULT_KERNEL_VERSION` 或 `vmlinux-6.1.158` | 构建使用的内核版本 |
| `build-io-engine` | `Sync` | Firecracker block IO engine |
| `default-persistent-volume-type` | `""` | 默认持久卷类型 |
| `clickhouse-read-endpoint` | `""` | ClickHouse 读取端点选择；空字符串使用单一 DSN |

### 2.4 JSON Flags

| Flag 名称 | 默认值 | 说明 |
|-----------|--------|------|
| `clean-nfs-cache` | `null` | 清理 NFS cache 配置 |
| `rate-limit-config` | `null` | API route rate limit 覆盖 |
| `memfile-diff-dedup` | `{"enabled":false,...}` | memfile diff 4KiB page dedup 配置 |
| `guest-pause-reclaim` | `null` | pause 前 sync/drop_caches/compact_memory/fstrim 分步预算 |
| `free-page-hinting-config` | `null` | virtio-balloon free-page-hinting 配置 |
| `preferred-build-node` | `null` | preferred build node 信息 |
| `firecracker-versions` | `{"v1.10":"v1.10.1_30cbb07","v1.12":"v1.12.1_210cbac","v1.14":"v1.14.1_431f1fc"}` | Firecracker minor version 到构建版本映射 |
| `tracked-templates-for-metrics` | `{"base":true,"code-interpreter-v1":true,"code-interpreter-beta":true,"desktop":true}` | 指标跟踪模板集合 |
| `compress-config` | `{"compressBuilds":false,...}` | build artifact 压缩配置 |
| `tcpfirewall-egress-throttle-config` | disabled buckets | Firecracker 网卡 egress token bucket |
| `block-drive-throttle-config` | disabled buckets | Firecracker rootfs drive token bucket |

---

## 3. 当前 LaunchDarkly 行为

当前代码只内置 LaunchDarkly provider 和本地 offline store：

| 场景 | 行为 |
|------|------|
| 设置 `LAUNCH_DARKLY_API_KEY` | 使用 LaunchDarkly Server SDK 连接在线服务 |
| 不设置 `LAUNCH_DARKLY_API_KEY` | 使用代码内注册的 offline store fallback |
| CLI/测试显式调用 override | 仅影响 offline store |

因此，私有化部署如果不需要动态灰度，最小方案是 **不配置 `LAUNCH_DARKLY_API_KEY`**，直接使用 fallback。

---

## 4. 私有化替代方案

### 4.1 零改代码：使用 offline fallback

这是当前最稳妥方案：

```bash
# 不设置该变量，或显式留空
unset LAUNCH_DARKLY_API_KEY
```

优点：

- 不需要部署 LaunchDarkly 或替代服务
- 不需要修改代码
- fallback 值与 `flags.go` 保持一致

限制：

- 不能运行时灰度
- 不能按 team/template/cluster 动态覆盖

### 4.2 YAML / 文件配置

这是可选改造，不是 `2026.28` 当前能力。若要实现，建议只在 `packages/shared/pkg/featureflags` 内增加 provider 抽象，并保持现有 `BoolFlag`、`IntFlag`、`StringFlag`、`JSONFlag` 调用点不变。

配置文件应直接使用第 2 节的 flag key。例如：

```yaml
boolean_flags:
  use-memfd: true
  memfd-background-copy: true
  peer-to-peer-chunk-transfer: false
  disable-e2b-access-token-auth: false

integer_flags:
  max-sandboxes-per-node: 200
  envd-init-request-timeout-milliseconds: 50
  max-starting-instances-per-node: 3

string_flags:
  build-firecracker-version: "v1.14.1_431f1fc"
  build-kernel-version: "vmlinux-6.1.158"

json_flags:
  memfile-diff-dedup:
    enabled: false
    bestEffort: false
    directIO: false
  guest-pause-reclaim: null
```

### 4.3 Unleash / 自建服务

也是可选改造，不是当前无代码配置项。实现时要注意：

- bool flag 可以直接映射到开关。
- int/string flag 需要通过 variant payload 或自建 typed API 表达。
- JSON flag 需要保留 JSON value 语义，不能降级成字符串拼接。
- LaunchDarkly context 当前包含 team、user、cluster、template、volume、sandbox、service、compress use case 等维度；替代品需要明确支持哪些维度。

---

## 5. 推荐方案

| 场景 | 推荐 |
|------|------|
| 单节点/测试 | 不设置 `LAUNCH_DARKLY_API_KEY`，使用 fallback |
| 私有化生产且不需要动态灰度 | 不设置 `LAUNCH_DARKLY_API_KEY`，用发布流程控制配置 |
| 需要动态灰度和按上下文定向 | 保留 LaunchDarkly，或实现 YAML/Unleash provider 改造 |

---

*文档同步至上游 e2b-dev/infra 仓库 tag 2026.28*
