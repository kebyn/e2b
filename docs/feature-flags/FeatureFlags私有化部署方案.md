# E2B Feature Flags 完整分析与部署方案

> 本文档是 **Feature Flags 私有化部署主文档**：负责维护当前 Flag 清单、默认值、LaunchDarkly 离线行为与私有化替代方案。
>
> 本文档不维护服务启动参数全集或整体组件取舍；这些内容分别由参数文档和组件分析文档维护。
>
> 基线：上游 `e2b-dev/infra` tag `2026.30`，commit `f32ee8a2a50052f32e3632ceb451111a98dd5104`，以 `infra/packages/shared/pkg/featureflags/flags.go` 为准。
>
> 相关文档：
> - [`README.md`](../../README.md)：仓库总入口与文档导航
> - [`核心组件详解.md`](../architecture/核心组件详解.md)：Feature Flags 在整体架构里的作用
> - [`启动参数详解.md`](../reference/启动参数详解.md)：运行时环境变量（如 `LAUNCH_DARKLY_API_KEY`）

---

## 1. 阅读导航

### 如果你只想知道“不配置 LaunchDarkly 能不能跑”

可以跑。`LAUNCH_DARKLY_API_KEY` 为空时，`featureflags.NewClient()` 使用本地 offline store，并返回代码中注册的 fallback 值。

### 如果你想知道“代码里到底有哪些 Flag”

看 [2. Feature Flags 完整列表](#2-feature-flags-完整列表)。该清单按 `flags.go` 的 `NewBoolFlag`、`NewIntFlag`、`NewStringFlag`、`NewJSONFlag` 生成。

当前清单共 113 项（51 Boolean + 39 Integer + 11 String + 12 JSON），可在仓库根目录复核：

```bash
rg -U -o 'New(Bool|Int|String|JSON)Flag\(\s*"' \
  infra/packages/shared/pkg/featureflags/flags.go | wc -l
```

### 如果你想接入 YAML / Unleash / 自建配置

当前 `2026.30` 代码没有 `FEATURE_FLAGS_PROVIDER=yaml` 或 `FEATURE_FLAGS_PROVIDER=unleash` 这类 provider 选择环境变量。YAML/Unleash 是可选改造方案，不是现有无代码改动能力。

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
| `orch-accepts-combined-host` | false | 是否让 Orchestrator 直接接受 `sandbox.<DOMAIN_NAME>` + `E2b-Sandbox-Id`/`E2b-Sandbox-Port` 组合；关闭时 Client Proxy 会把共享 Host 改写为 `{port}-{sandboxID}.<DOMAIN_NAME>` 以兼容下游。它不是 Header 寻址总开关 |
| `storage-soft-delete-check` | false | 读取 storage-index soft-delete tombstone |
| `storage-soft-delete-enforce` | false | soft-deleted 对象读取失败关闭 |
| `use-memfd` | true | Firecracker guest memory 使用 memfd |
| `memfd-background-copy` | true | memfd snapshot cache 后台复制 |
| `memfd-dedup-inflight-serve` | false | memfd dedup 期间直接服务 in-flight 页面（`2026.30` 新增） |
| `peer-to-peer-chunk-transfer` | false | 启用 P2P chunk routing |
| `peer-to-peer-async-checkpoint` | false | checkpoint 异步上传 |
| `can-use-persistent-volumes` | dev: true | 是否允许持久卷 |
| `sandbox-label-based-scheduling` | false | Sandbox 基于标签调度 |
| `free-page-reporting` | false | Firecracker free page reporting |
| `freeze-user-cgroup` | dev: true | pause 前 freeze 用户 cgroup |
| `freeze-guest-hierarchy` | false | pause 前 freeze 整个 guest cgroup 层级（`2026.30` 新增） |
| `collapse-envd-heap` | false | pause 前让 envd 折叠匿名堆页 |
| `volume-fallback-to-unmatched-nodes` | true | volume 调度允许回退到未匹配节点 |
| `sandbox-volume-label-based-scheduling` | false | 按 volume 类型标签过滤节点 |
| `network-transform-rules` | dev: true | 允许网络规则 transform |
| `byop-proxy-enabled` | dev: true | 启用 BYOP egress proxy 配置 |
| `enable-sandbox-iam-tokens` | dev: true | 为 sandbox 签发 IAM token（`2026.30` 新增） |
| `customer-secrets` | false | 客户侧 secret 管理路由（`/secrets`）的 feature gate（`2026.30` 新增） |
| `disable-legacy-team-mutations` | false | 禁用旧版 team 直改路径（project projection 迁移期开关，`2026.30` 新增） |
| `v4-header-for-uncompressed` | false | 未压缩上传使用 V4 header |
| `header-v5-write` | false | pause 写 V5 header |
| `resume-origin-node-remap` | false | resume 超时后重映射 origin node |
| `expiration-index-healer` | true | Redis 过期索引 healer |
| `nbd-async-write-zeroes` | false | NBD WRITE_ZEROES/TRIM 异步处理 |
| `pause-resume-prefetch-harvest` | false | pause 后做 throwaway warm resume 采样 |
| `pause-resume-prefetch-consume` | false | 将采样 mapping 写入 pause artifact |
| `clickhouse-write-fanout` | false | 启用 ClickHouse 多写端点 fan-out |
| `logs-read-config` | `LOGS_READ_CONFIG` 环境变量或 false | sandbox/构建日志读取后端切换（无 LaunchDarkly 部署经 `LOGS_READ_CONFIG` 覆盖，`2026.30` 新增） |
| `fsfreeze-via-exec` | false | 用 `fsfreeze -f /` 命令冻结 guest rootfs（`2026.30` 新增） |
| `fs-only-resume-api` | false | resume/connect 接受 `memory:false`（仅文件系统恢复，`2026.30` 新增） |
| `preboot-fs-recovery` | false | 冷启动前运行受限文件系统恢复（`2026.30` 新增） |
| `use-sync-wp` | false | Firecracker snapshot 加载启用 use_sync_wp（同步写保护，`2026.30` 新增） |
| `in-place-checkpoint` | false | Checkpoint 原地 pause/snapshot/resume（`2026.30` 新增） |
| `defer-memory-export` | false | 原地 checkpoint 延迟导出 guest 内存（`2026.30` 新增） |
| `sync-wp-tracker-dirty` | false | 从同步 WP fault 推导 pause 时脏页集（UFFD 脏跟踪，`2026.30` 新增） |
| `defer-rootfs-export` | false | 延迟 rootfs diff seal（reflink，`2026.30` 新增） |
| `build-ensure-free-disk-space` | false | build 步骤后、finalize 前扩容 rootfs（`2026.30` 新增） |
| `build-ext4-dir-index` | false | 保留 mkfs.ext4 的 htree 目录索引（`2026.30` 新增） |
| `build-envd-memory-protection` | false | 构建 sandbox 中 envd 内存保护（`2026.30` 新增） |
| `pause-refusal-restore` | false | 可重试 pause 拒绝后的恢复（记录保留、路由重注册，`2026.30` 新增） |
| `orchestrator-routing-publish` | false | Orchestrator 在 MarkRunning 时写 `sandbox:routing:{id}` 路由记录（`2026.30` 新增） |
| `orchestrator-routing-prioritized` | false | Client Proxy 优先读 Orchestrator 路由记录解析节点（`2026.30` 新增） |
| `envd-binary-cache` | dev: true（可用 `ENVD_BINARY_CACHE` 覆盖） | envd 升级路径使用节点本地二进制缓存（`2026.30` 新增） |
| `workspacesEnabled` | false | workspace 能力开关。注意该 key 是历史遗留的 camelCase，不是 kebab-case（`2026.30` 新增可观测） |

> `2026.28` 存在的 `disable-e2b-access-token-provisioning`、`disable-e2b-access-token-auth` 和 `sandbox-placement-optimistic-resource-accounting` 已在 `2026.30` 移除：用户级 `sk_e2b_` access token 被整体删除，不再有对应的开关。

与用户请求路径直接相关的三个 Flag 需要区分：

- `orch-accepts-combined-host` 只控制 Client Proxy 到 Orchestrator 的共享 Host 兼容改写；Header 寻址本身无需启用它。
- `network-transform-rules` 控制 API 是否接受 Sandbox 网络域名 Header transform，生产 fallback 为 `false`。
- `byop-proxy-enabled` 控制 API 是否接受 `network.egressProxy` SOCKS5 配置，生产 fallback 为 `false`。

完整请求字段和限制见 [`2026.30用户可见功能.md`](../reference/2026.30用户可见功能.md#3-sandbox-网络-transform-与-socks5-出口)。`sandbox-auto-resume` 已从 `2026.28` 删除；流量触发恢复由 Sandbox 的 `autoResume` API 配置和 Client Proxy API gRPC 通道决定，不应创建同名自定义 Flag。

### 2.2 Integer Flags

| Flag 名称 | 默认值 | 单位 | 说明 |
|-----------|--------|------|------|
| `collapse-envd-heap-timeout-ms` | 10000 | ms | envd heap collapse 超时 |
| `freeze-user-cgroup-timeout-ms` | 2000 | ms | pause 前 freeze 用户 cgroup 的超时（`2026.30` 新增） |
| `freeze-guest-hierarchy-max-cgroups` | 512 | 个 | 单次 guest cgroup 层级 sweep 上限（`2026.30` 新增） |
| `max-sandboxes-per-node` | 200 | 个 | 每节点最大 sandbox 数 |
| `gcloud-concurrent-upload-limit` | 8 | 个 | 存储上传并发限制；历史 key 名保留 gcloud 前缀 |
| `gcloud-max-tasks` | 16 | 个 | 存储上传最大任务数 |
| `clickhouse-batcher-max-batch-size` | 1000 | 条 | ClickHouse batch 大小 |
| `clickhouse-batcher-max-delay` | 1000 | ms | ClickHouse batch 延迟 |
| `clickhouse-batcher-queue-size` | 1000 | 条 | ClickHouse batch 队列 |
| `best-of-k-sample-size` | 3 | 个 | Best-of-K 采样数量 |
| `best-of-k-max-overcommit` | 400 | % | 最大超卖比例 |
| `best-of-k-alpha` | 50 | % | 当前使用权重 |
| `envd-init-request-timeout-milliseconds` | 50 | ms | envd init request 超时 |
| `envd-timeout-milliseconds` | `ENVD_TIMEOUT` 或 10000 | ms | resume 等待 envd 超时 |
| `guest-sync-timeout-milliseconds` | 0 | ms | filesystem-only snapshot 强制 guest sync 超时；0 为按 RAM 推导 |
| `max-network-rule-domains` | 10 | 个 | 网络规则允许的最大域名数（`2026.30` 新增） |
| `max-cache-writer-concurrency` | 10 | 个 | cache writer 并发数 |
| `build-cache-max-usage-percentage` | 85 | % | build cache 磁盘使用阈值 |
| `build-provision-version` | 0 | - | build provision 版本 |
| `nbd-connections-per-device` | 1 | 个 | 每个 NBD device 的连接数 |
| `memory-prefetch-max-fetch-workers` | 16 | 个 | memory prefetch fetch workers |
| `memory-prefetch-max-copy-workers` | 8 | 个 | memory prefetch copy workers |
| `memory-prefetch-coalesce-max-mb` | 0 | MB | 连续 prefetch 块合并上限；0 不合并（`2026.30` 新增） |
| `resume-last-cycle-prefetch-max-mib` | -1 | MiB | 单次恢复的 last-cycle diff 预取上限；-1 不限制（`2026.30` 新增） |
| `pause-resume-prefetch-harvest-timeout-ms` | 15000 | ms | throwaway harvest resume 超时 |
| `tcpfirewall-max-connections-per-sandbox` | -1 | 个 | TCP firewall 每 sandbox 最大连接数；-1 不限制 |
| `sandbox-max-incoming-connections` | -1 | 个 | HTTP proxy 每 sandbox 最大入站连接数；-1 不限制 |
| `build-base-rootfs-size-limit-mb` | 25000 | MB | OCI base rootfs 大小上限 |
| `minimum-autoresume-timeout` | 300 | 秒 | 最小 autoresume timeout |
| `build-reserved-disk-space-mb` | 256 | MB | guest root 保留磁盘空间 |
| `max-starting-instances-per-node` | 3 | 个 | 每节点并发 start/resume 上限 |
| `max-concurrent-evictions` | 256 | 个 | API sandbox eviction 并发上限 |
| `auto-pause-overstay-budget-milliseconds` | 120000 | ms | evictor 对内存超时 sandbox 的重试预算（`2026.30` 新增） |
| `max-concurrent-snapshot-upserts` | 0 | 个 | snapshot upsert 并发上限；0/负数不限制 |
| `max-concurrent-sandbox-list-queries` | 0 | 个 | sandbox list 查询并发上限；0/负数不限制 |
| `max-concurrent-snapshot-build-queries` | 0 | 个 | snapshot build 查询并发上限；0/负数不限制 |
| `min-chunker-read-size-kb` | 16 | KB | chunker 最小读批次 |
| `max-parallel-build-read-segments` | 1 | 个 | fragmented build read 并发段数；1 以下保持串行 |
| `pause-admission-grace-milliseconds` | -1 | ms | pause/checkpoint 准入预检宽限；负数禁用预检（`2026.30` 新增） |

### 2.3 String Flags

| Flag 名称 | 默认值 | 说明 |
|-----------|--------|------|
| `build-firecracker-version` | `DEFAULT_FIRECRACKER_VERSION` 或 `v1.14-0.2.0` | 构建使用的 Firecracker 版本；新模板构建使用 `v1.14-0` release 线 |
| `build-kernel-version` | `DEFAULT_KERNEL_VERSION` 或 `vmlinux-6.1.158` | 构建使用的内核版本 |
| `build-envd-version` | `DEFAULT_ENVD_VERSION` 或 `promoted` | 构建烧入的 envd 版本；`promoted` 选用节点本地已提升的二进制（`HOST_ENVD_PATH`），无 LaunchDarkly 的部署不受影响（`2026.30` 新增） |
| `build-io-engine` | `Sync` | Firecracker block IO engine |
| `build-kernel-cmdline-args` | `""` | 构建内核 cmdline 追加参数（`2026.30` 新增） |
| `envd-upgrade-target` | `ENVD_UPGRADE_TARGET` 或 `off` | resume 时 envd live 升级目标版本；`off` 关闭（`2026.30` 新增） |
| `envd-offline-upgrade-target` | `ENVD_OFFLINE_UPGRADE_TARGET` 或 `off` | filesystem-only 快照冷启动 resume 时离线改写 rootfs 内 envd 二进制（`2026.30` 新增） |
| `fs-only-resume-cpu-model` | `""` | 限制 filesystem-only 快照只能在报告该 CPU 型号的节点上 resume（`2026.30` 新增） |
| `resume-prefetch-source` | `init` | resume 预取来源 trace 选择（`2026.30` 新增） |
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
| `firecracker-versions` | `{"v1.10":"v1.10.1_30cbb07","v1.12":"v1.12.1_210cbac","v1.14":"v1.14.1_431f1fc","v1.14-0":"v1.14-0.2.0"}` | Firecracker minor version 到构建版本映射；key 必须等于 value 的 LD key（不变量） |
| `tracked-templates-for-metrics` | `{"base":true,"code-interpreter-v1":true,"code-interpreter-beta":true,"desktop":true}` | 指标跟踪模板集合 |
| `compress-config` | `{"compressBuilds":false,...}` | build artifact 压缩配置 |
| `tcpfirewall-egress-throttle-config` | disabled buckets | Firecracker 网卡 egress token bucket |
| `block-drive-throttle-config` | disabled buckets | Firecracker rootfs drive token bucket |
| `logs-write-config` | `null` | 日志写入后端配置（`2026.30` 新增，配合 `logs-read-config` 支持日志存储迁移） |

---

## 3. 当前 LaunchDarkly 行为

当前代码只内置 LaunchDarkly provider 和本地 offline store。核心入口是 `infra/packages/shared/pkg/featureflags/client.go`：

```go
func NewClient() (*Client, error) {
    if launchDarklyApiKey == "" {
        return NewClientWithDatasource(launchDarklyOfflineStore)
    }

    ldClient, err := ldclient.MakeClient(launchDarklyApiKey, waitForInit)
    return &Client{ld: ldClient}, nil
}
```

运行时行为如下：

| 场景 | 行为 |
|------|------|
| 设置 `LAUNCH_DARKLY_API_KEY` | 使用 LaunchDarkly Server SDK 连接在线服务 |
| 不设置 `LAUNCH_DARKLY_API_KEY` | 使用代码内注册的 offline store fallback |
| CLI/测试显式调用 override | 仅影响 offline store |

因此，私有化部署如果不需要动态灰度，最小方案是 **不配置 `LAUNCH_DARKLY_API_KEY`**，直接使用 fallback。LaunchDarkly 不是必需组件；它只在需要运行时灰度、按 team/template/cluster/sandbox 等上下文定向覆盖 flag 时才有保留价值。

| 场景 | 当前能力 / 建议 | 继续阅读 |
|------|------------------|----------|
| 不需要动态灰度，只想无代码跑起来 | 不设置 `LAUNCH_DARKLY_API_KEY`，使用代码内 fallback 默认值 | [4.1 零改代码：使用 offline fallback](#41-零改代码使用-offline-fallback) |
| 想确认每个 Flag 的默认值 | 以 `infra/packages/shared/pkg/featureflags/flags.go` 为准 | [2. Feature Flags 完整列表](#2-feature-flags-完整列表) |
| 想用 YAML / Unleash / 自建服务管理 Flag | 这是可选代码改造，不是 `2026.30` 现有无代码能力 | [4. 私有化替代方案](#4-私有化替代方案) |
| 只查 `LAUNCH_DARKLY_API_KEY` 配置 | 看运行时配置参考 | [`启动参数详解.md`](../reference/启动参数详解.md#阅读导航) |

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

这是可选改造，不是 `2026.30` 当前能力。若要实现，建议只在 `infra/packages/shared/pkg/featureflags` 内增加 provider 抽象，并保持现有 `BoolFlag`、`IntFlag`、`StringFlag`、`JSONFlag` 调用点不变。

配置文件应直接使用第 2 节的 flag key。例如：

```yaml
boolean_flags:
  use-memfd: true
  memfd-background-copy: true
  peer-to-peer-chunk-transfer: false
  logs-read-config: true

integer_flags:
  max-sandboxes-per-node: 200
  envd-init-request-timeout-milliseconds: 50
  max-starting-instances-per-node: 3

string_flags:
  build-firecracker-version: "v1.14-0.2.0"
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
- LaunchDarkly context 当前包含 team、user、cluster、deployment、instance-group、template、volume、sandbox、service、tier、compress use case 等维度；替代品需要明确支持哪些维度。
- `2026.30` 新增的 envd 升级（`envd-upgrade-target` / `envd-offline-upgrade-target`）和日志路由（`logs-read-config` / `logs-write-config`）在 flags 包内有专门 resolver，替代实现需保持等价语义。

---

## 5. 推荐方案

| 场景 | 推荐 |
|------|------|
| 单节点/测试 | 不设置 `LAUNCH_DARKLY_API_KEY`，使用 fallback |
| 私有化生产且不需要动态灰度 | 不设置 `LAUNCH_DARKLY_API_KEY`，用发布流程控制配置 |
| 需要动态灰度和按上下文定向 | 保留 LaunchDarkly，或实现 YAML/Unleash provider 改造 |

---

*文档同步至上游 e2b-dev/infra 仓库 tag 2026.30*
