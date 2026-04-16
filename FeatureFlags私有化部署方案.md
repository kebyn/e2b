# E2B Feature Flags 完整分析与部署方案

---

## 1. Feature Flags 完整列表

### 1.1 Boolean Flags

> **注意**: 标记为 `dev: true` 的 Flags 在 `ENVIRONMENT=dev` 或 `ENVIRONMENT=local` 时为 `true`，在 `ENVIRONMENT=prod` 时为 `false`。

| Flag 名称 | 默认值 | 说明 | 影响组件 |
|-----------|--------|------|----------|
| `sandbox-metrics-write` | **true** (固定) | 是否写入 ClickHouse 指标 | Orchestrator |
| `sandbox-metrics-read` | **true** (固定) | 是否读取 ClickHouse 指标 | API |
| `host-stats-enabled` | dev: true | 是否收集主机统计 | Orchestrator |
| `use-nfs-for-snapshots` | dev: true | 使用 NFS 存储快照 | Orchestrator |
| `use-nfs-for-templates` | dev: true | 使用 NFS 存储模板 | Orchestrator |
| `write-to-cache-on-writes` | false | 写入时同时写入缓存 | Orchestrator |
| `use-nfs-for-building-templates` | dev: true | 构建模板时使用 NFS | Orchestrator |
| `best-of-k-can-fit` | true | BestOfK 算法是否检查资源可用性 | API |
| `best-of-k-too-many-starting` | false | 是否限制并发启动数 | API |
| `edge-provided-sandbox-metrics` | false | 使用 Edge 提供的指标 | API |
| `create-storage-cache-spans` | dev: true | 创建存储缓存追踪 span | Orchestrator |
| `sandbox-auto-resume` | dev: true | Sandbox 自动恢复 | API/Orchestrator |
| `peer-to-peer-chunk-transfer` | false | 启用 P2P 块传输 | Orchestrator |
| `peer-to-peer-async-checkpoint` | false | 异步 checkpoint 上传 | Orchestrator |
| `can-use-persistent-volumes` | dev: true | 是否允许持久卷 | API |
| `execution-metrics-on-webhooks` | false | Webhook 包含执行指标 | Orchestrator |
| `sandbox-label-based-scheduling` | false | 基于标签的调度 | API |
| `sandbox-placement-optimistic-resource-accounting` | false | 乐观资源计算 | API |

### 1.2 Integer Flags

| Flag 名称 | 默认值 | 单位 | 说明 | 影响组件 |
|-----------|--------|------|------|----------|
| `max-sandboxes-per-node` | 200 | 个 | 每节点最大 Sandbox 数 | Orchestrator |
| `gcloud-concurrent-upload-limit` | 8 | 个 | GCS 并发上传数 | Orchestrator |
| `gcloud-max-tasks` | 16 | 个 | GCS 最大任务数 | Orchestrator |
| `clickhouse-batcher-max-batch-size` | 100 | 条 | ClickHouse 批处理大小 | API |
| `clickhouse-batcher-max-delay` | 1000 | ms | ClickHouse 批处理延迟 | API |
| `clickhouse-batcher-queue-size` | 1000 | 条 | ClickHouse 队列大小 | API |
| `best-of-k-sample-size` | 3 | 个 | BestOfK 采样数 (K) | API |
| `best-of-k-max-overcommit` | 400 | % | 最大超卖比例 (R=4) | API |
| `best-of-k-alpha` | 50 | % | 当前使用权重 (Alpha=0.5) | API |
| `envd-init-request-timeout-milliseconds` | **50** | ms | envd 初始化超时 | Orchestrator |
| `host-stats-sampling-interval` | 5000 | ms | 主机统计采样间隔 | Orchestrator |
| `max-cache-writer-concurrency` | 10 | 个 | 缓存写入并发数 | Orchestrator |
| `build-cache-max-usage-percentage` | 85 | % | 缓存磁盘最大使用率 | Orchestrator |
| `build-provision-version` | 0 | - | 构建配置版本 | Orchestrator |
| `nbd-connections-per-device` | **1** | 个 | NBD 设备连接数 | Orchestrator |
| `memory-prefetch-max-fetch-workers` | 16 | 个 | 内存预取最大抓取 worker | Orchestrator |
| `memory-prefetch-max-copy-workers` | 8 | 个 | 内存预取最大复制 worker | Orchestrator |
| `tcpfirewall-max-connections-per-sandbox` | -1 | 个 | TCP 防火墙每 Sandbox 连接数 (-1=无限制) | Orchestrator |
| `sandbox-max-incoming-connections` | -1 | 个 | HTTP 代理最大连接数 (-1=无限制) | API |
| `build-base-rootfs-size-limit-mb` | 25000 | MB | 基础 rootfs 大小限制 | Orchestrator |
| `minimum-autoresume-timeout` | 300 | s | 最小自动恢复超时 | API |
| `max-concurrent-snapshot-upserts` | 0 | 个 | 并发 snapshot upsert 数 (0=无限制) | API |
| `max-concurrent-sandbox-list-queries` | 0 | 个 | 并发 sandbox 列表查询数 (0=无限制) | API |
| `max-concurrent-snapshot-build-queries` | 0 | 个 | 并发 snapshot build 查询数 (0=无限制) | API |

### 1.3 String Flags

| Flag 名称 | 默认值 | 说明 | 影响组件 |
|-----------|--------|------|----------|
| `build-firecracker-version` | **v1.12.1_210cbac** | 构建使用的 Firecracker 版本 | Orchestrator |
| `build-io-engine` | Sync | IO 引擎 (Sync/Async) | Orchestrator |
| `default-persistent-volume-type` | "" | 默认持久卷类型 | API |

### 1.4 JSON Flags

| Flag 名称 | 默认值 | 说明 | 影响组件 |
|-----------|--------|------|----------|
| `clean-nfs-cache` | null | 清理 NFS 缓存命令 | Orchestrator |
| `rate-limit-config` | null | 按团队的速率限制配置 | API |
| `preferred-build-node` | null | 优先构建节点 | API |
| `firecracker-versions` | {"v1.10":"v1.10.1_30cbb07","v1.12":"v1.12.1_210cbac"} | Firecracker 版本映射 | Orchestrator |
| `tracked-templates-for-metrics` | {"base":true,"code-interpreter-v1":true,...} | 指标跟踪的模板列表 | Orchestrator |
| `chunker-config` | {"useStreaming":false,"minReadBatchSizeKB":16} | 分块器配置 | Orchestrator |
| `tcpfirewall-egress-throttle-config` | {"ops":{"bucketSize":-1},"bandwidth":{"bucketSize":-1}} | 出口流量限制 | Orchestrator |
| `block-drive-throttle-config` | {"ops":{"bucketSize":-1},"bandwidth":{"bucketSize":-1}} | 磁盘限速 | Orchestrator |

---

## 2. YAML 配置方案

### 2.1 配置文件格式

```yaml
# /etc/e2b/feature-flags.yaml

# ============================================================
# E2B Feature Flags 配置
# ============================================================

# Boolean Flags
boolean_flags:
  sandbox-metrics-write: true
  sandbox-metrics-read: true
  host-stats-enabled: true
  use-nfs-for-snapshots: false
  use-nfs-for-templates: false
  write-to-cache-on-writes: false
  use-nfs-for-building-templates: false
  best-of-k-can-fit: true
  best-of-k-too-many-starting: false
  edge-provided-sandbox-metrics: false
  create-storage-cache-spans: false
  sandbox-auto-resume: true
  sandbox-catalog-local-cache: true
  peer-to-peer-chunk-transfer: false
  peer-to-peer-async-checkpoint: false
  can-use-persistent-volumes: true
  execution-metrics-on-webhooks: false
  sandbox-label-based-scheduling: false

# Integer Flags
integer_flags:
  max-sandboxes-per-node: 200
  gcloud-concurrent-upload-limit: 8
  gcloud-max-tasks: 16
  clickhouse-batcher-max-batch-size: 100
  clickhouse-batcher-max-delay: 1000
  clickhouse-batcher-queue-size: 1000
  best-of-k-sample-size: 3
  best-of-k-max-overcommit: 400
  best-of-k-alpha: 50
  envd-init-request-timeout-milliseconds: 50
  host-stats-sampling-interval: 5000
  max-cache-writer-concurrency: 10
  build-cache-max-usage-percentage: 85
  build-provision-version: 0
  nbd-connections-per-device: 1            # 注意：默认值是 1
  memory-prefetch-max-fetch-workers: 16
  memory-prefetch-max-copy-workers: 8
  tcpfirewall-max-connections-per-sandbox: -1
  sandbox-max-incoming-connections: -1
  build-base-rootfs-size-limit-mb: 25000
  max-concurrent-snapshot-upserts: 0
  max-concurrent-sandbox-list-queries: 0
  max-concurrent-snapshot-build-queries: 0

# String Flags
string_flags:
  build-firecracker-version: "v1.12.1_210cbac"  # 注意：版本号后缀
  build-io-engine: "Sync"
  default-persistent-volume-type: ""

# JSON Flags
json_flags:
  firecracker-versions:
    v1.10: "v1.10.1_30cbb07"
    v1.12: "v1.12.1_210cbac"
  
  tracked-templates-for-metrics:
    base: true
    code-interpreter-v1: true
    code-interpreter-beta: true
    desktop: true
  
  chunker-config:
    useStreaming: false
    minReadBatchSizeKB: 16
  
  tcpfirewall-egress-throttle-config:
    ops:
      bucketSize: -1
      oneTimeBurst: 0
      refillTimeMs: 1000
    bandwidth:
      bucketSize: -1
      oneTimeBurst: 0
      refillTimeMs: 1000

# ============================================================
# 按维度覆盖 (可选)
# ============================================================
overrides:
  # 按团队覆盖
  team:
    "team-uuid-1":
      max-sandboxes-per-node: 500
      sandbox-auto-resume: true
    "team-uuid-2":
      max-sandboxes-per-node: 100
  
  # 按模板覆盖
  template:
    "template-uuid-1":
      sandbox-metrics-write: true
      host-stats-sampling-interval: 1000
  
  # 按集群覆盖
  cluster:
    "cluster-uuid-1":
      nbd-connections-per-device: 8
      memory-prefetch-max-fetch-workers: 32
```

### 2.2 配置加载代码

```go
// packages/shared/pkg/featureflags/yaml_provider.go

package featureflags

import (
    "context"
    "os"
    "sync"
    
    "gopkg.in/yaml.v3"
    "github.com/launchdarkly/go-sdk-common/v3/ldcontext"
    "github.com/launchdarkly/go-sdk-common/v3/ldvalue"
)

type YAMLFlagsConfig struct {
    BooleanFlags map[string]bool                   `yaml:"boolean_flags"`
    IntegerFlags map[string]int                    `yaml:"integer_flags"`
    StringFlags  map[string]string                 `yaml:"string_flags"`
    JSONFlags    map[string]map[string]interface{}  `yaml:"json_flags"`
    Overrides    OverridesConfig                    `yaml:"overrides"`
}

type OverridesConfig struct {
    Team     map[string]map[string]interface{} `yaml:"team"`
    Template map[string]map[string]interface{} `yaml:"template"`
    Cluster  map[string]map[string]interface{} `yaml:"cluster"`
}

type YAMLProvider struct {
    config YAMLFlagsConfig
    mu     sync.RWMutex
}

func NewYAMLProvider(path string) (*YAMLProvider, error) {
    data, err := os.ReadFile(path)
    if err != nil {
        return nil, err
    }
    
    var config YAMLFlagsConfig
    if err := yaml.Unmarshal(data, &config); err != nil {
        return nil, err
    }
    
    return &YAMLProvider{config: config}, nil
}

func (p *YAMLProvider) GetBool(key string, fallback bool) bool {
    p.mu.RLock()
    defer p.mu.RUnlock()
    
    if val, ok := p.config.BooleanFlags[key]; ok {
        return val
    }
    return fallback
}

func (p *YAMLProvider) GetInt(key string, fallback int) int {
    p.mu.RLock()
    defer p.mu.RUnlock()
    
    if val, ok := p.config.IntegerFlags[key]; ok {
        return val
    }
    return fallback
}

func (p *YAMLProvider) GetString(key string, fallback string) string {
    p.mu.RLock()
    defer p.mu.RUnlock()
    
    if val, ok := p.config.StringFlags[key]; ok {
        return val
    }
    return fallback
}

func (p *YAMLProvider) GetJSON(key string, fallback ldvalue.Value) ldvalue.Value {
    p.mu.RLock()
    defer p.mu.RUnlock()
    
    if val, ok := p.config.JSONFlags[key]; ok {
        return ldvalue.FromJSONMarshal(val)
    }
    return fallback
}

// Reload 重新加载配置文件
func (p *YAMLProvider) Reload(path string) error {
    data, err := os.ReadFile(path)
    if err != nil {
        return err
    }
    
    var config YAMLFlagsConfig
    if err := yaml.Unmarshal(data, &config); err != nil {
        return err
    }
    
    p.mu.Lock()
    p.config = config
    p.mu.Unlock()
    
    return nil
}
```

### 2.3 环境变量

```bash
# 启用 YAML 配置
export FEATURE_FLAGS_PROVIDER=yaml
export FEATURE_FLAGS_CONFIG=/etc/e2b/feature-flags.yaml
```

---

## 3. Unleash 配置方案

### 3.1 Docker Compose 部署

```yaml
# docker-compose.unleash.yml

version: '3.8'

services:
  unleash:
    image: unleashorg/unleash-server:latest
    container_name: unleash
    ports:
      - "4242:4242"
    environment:
      DATABASE_URL: postgres://unleash:${UNLEASH_DB_PASSWORD}@postgres:5432/unleash
      DATABASE_SSL: "false"
      LOG_LEVEL: info
    depends_on:
      postgres:
        condition: service_healthy
    restart: unless-stopped

  postgres:
    image: postgres:17-alpine
    container_name: unleash-db
    environment:
      POSTGRES_USER: unleash
      POSTGRES_PASSWORD: ${UNLEASH_DB_PASSWORD}
      POSTGRES_DB: unleash
    volumes:
      - unleash_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U unleash"]
      interval: 5s
      timeout: 5s
      retries: 5
    restart: unless-stopped

volumes:
  unleash_data:
```

```bash
# .env 文件
UNLEASH_DB_PASSWORD=your-secure-password
```

```bash
# 启动
docker-compose -f docker-compose.unleash.yml up -d

# 访问 UI
# http://localhost:4242
# 默认账号: admin / unleash4all
```

### 3.2 Unleash Flags 配置

```bash
#!/bin/bash
# create-flags.sh - 批量创建 Unleash Feature Flags

UNLEASH_URL="http://localhost:4242"
API_TOKEN="default:development.unleash-insecure-api-token"

# 创建项目
curl -X POST "${UNLEASH_URL}/api/admin/projects" \
  -H "Authorization: ${API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "e2b",
    "name": "E2B Platform"
  }'

# ============================================================
# Boolean Flags
# ============================================================

boolean_flags=(
  "sandbox-metrics-write:Sandbox Metrics Write"
  "sandbox-metrics-read:Sandbox Metrics Read"
  "host-stats-enabled:Host Stats Enabled"
  "use-nfs-for-snapshots:Use NFS for Snapshots"
  "use-nfs-for-templates:Use NFS for Templates"
  "write-to-cache-on-writes:Write to Cache on Writes"
  "use-nfs-for-building-templates:Use NFS for Building Templates"
  "best-of-k-can-fit:Best of K Can Fit"
  "best-of-k-too-many-starting:Best of K Too Many Starting"
  "edge-provided-sandbox-metrics:Edge Provided Sandbox Metrics"
  "create-storage-cache-spans:Create Storage Cache Spans"
  "sandbox-auto-resume:Sandbox Auto Resume"
  "sandbox-catalog-local-cache:Sandbox Catalog Local Cache"
  "peer-to-peer-chunk-transfer:Peer to Peer Chunk Transfer"
  "peer-to-peer-async-checkpoint:Peer to Peer Async Checkpoint"
  "can-use-persistent-volumes:Can Use Persistent Volumes"
  "execution-metrics-on-webhooks:Execution Metrics on Webhooks"
  "sandbox-label-based-scheduling:Sandbox Label Based Scheduling"
)

for item in "${boolean_flags[@]}"; do
  IFS=':' read -r key description <<< "$item"
  
  curl -X POST "${UNLEASH_URL}/api/admin/features" \
    -H "Authorization: ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${key}\",
      \"description\": \"${description}\",
      \"type\": \"release\",
      \"project\": \"e2b\",
      \"stale\": false,
      \"impressionData\": false
    }"
  
  echo "Created: ${key}"
done

# ============================================================
# Integer Flags (使用 Variant)
# ============================================================

integer_flags=(
  "max-sandboxes-per-node:200"
  "gcloud-concurrent-upload-limit:8"
  "gcloud-max-tasks:16"
  "clickhouse-batcher-max-batch-size:100"
  "clickhouse-batcher-max-delay:1000"
  "clickhouse-batcher-queue-size:1000"
  "best-of-k-sample-size:3"
  "best-of-k-max-overcommit:400"
  "best-of-k-alpha:50"
  "envd-init-request-timeout-milliseconds:50"    # 注意：是 50，不是 500
  "host-stats-sampling-interval:5000"
  "max-cache-writer-concurrency:10"
  "build-cache-max-usage-percentage:85"
  "build-provision-version:0"
  "nbd-connections-per-device:1"                  # 注意：是 1，不是 4
  "memory-prefetch-max-fetch-workers:16"
  "memory-prefetch-max-copy-workers:8"
  "tcpfirewall-max-connections-per-sandbox:-1"
  "sandbox-max-incoming-connections:-1"
  "build-base-rootfs-size-limit-mb:25000"
  "max-concurrent-snapshot-upserts:0"
  "max-concurrent-sandbox-list-queries:0"
  "max-concurrent-snapshot-build-queries:0"
)

for item in "${integer_flags[@]}"; do
  IFS=':' read -r key default <<< "$item"
  
  curl -X POST "${UNLEASH_URL}/api/admin/features" \
    -H "Authorization: ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${key}\",
      \"description\": \"Integer flag with default: ${default}\",
      \"type\": \"release\",
      \"project\": \"e2b\",
      \"stale\": false,
      \"impressionData\": false
    }"
  
  # 添加 Variant
  curl -X POST "${UNLEASH_URL}/api/admin/features/${key}/variants" \
    -H "Authorization: ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${key}-variant\",
      \"weight\": 1000,
      \"weightType\": \"fix\",
      \"stickiness\": \"default\",
      \"payload\": {
        \"type\": \"string\",
        \"value\": \"${default}\"
      }
    }"
  
  echo "Created: ${key} (default: ${default})"
done

# ============================================================
# String Flags
# ============================================================

string_flags=(
  "build-firecracker-version:v1.12.1_210cbac"  # 注意：版本号后缀
  "build-io-engine:Sync"
  "default-persistent-volume-type:"
)

for item in "${string_flags[@]}"; do
  IFS=':' read -r key default <<< "$item"
  
  curl -X POST "${UNLEASH_URL}/api/admin/features" \
    -H "Authorization: ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${key}\",
      \"description\": \"String flag with default: ${default}\",
      \"type\": \"release\",
      \"project\": \"e2b\",
      \"stale\": false,
      \"impressionData\": false
    }"
  
  # 添加 Variant
  curl -X POST "${UNLEASH_URL}/api/admin/features/${key}/variants" \
    -H "Authorization: ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${key}-variant\",
      \"weight\": 1000,
      \"weightType\": \"fix\",
      \"stickiness\": \"default\",
      \"payload\": {
        \"type\": \"string\",
        \"value\": \"${default}\"
      }
    }"
  
  echo "Created: ${key} (default: ${default})"
done

echo "All flags created successfully!"
```

### 3.3 Unleash 客户端代码

```go
// packages/shared/pkg/featureflags/unleash_provider.go

package featureflags

import (
    "context"
    "strconv"
    
    unleash "github.com/Unleash/unleash-client-go/v4"
    "github.com/launchdarkly/go-sdk-common/v3/ldvalue"
)

type UnleashProvider struct {
    client *unleash.Client
}

func NewUnleashProvider(appName, url, token string) (*UnleashProvider, error) {
    client, err := unleash.NewClient(unleash.Config{
        AppName: appName,
        Url:     url,
        CustomHeaders: map[string]string{
            "Authorization": token,
        },
        RefreshInterval: 15, // 15 秒刷新一次
    })
    if err != nil {
        return nil, err
    }
    
    return &UnleashProvider{client: client}, nil
}

func (p *UnleashProvider) GetBool(key string, fallback bool) bool {
    return p.client.IsEnabled(key, unleash.WithFallback(fallback))
}

func (p *UnleashProvider) GetInt(key string, fallback int) int {
    variant := p.client.GetVariant(key, unleash.WithVariantFallback(&unleash.Variant{
        Payload: unleash.Payload{
            Type:  "string",
            Value: strconv.Itoa(fallback),
        },
    }))
    
    if variant.Payload.Type == "string" {
        val, err := strconv.Atoi(variant.Payload.Value)
        if err == nil {
            return val
        }
    }
    
    return fallback
}

func (p *UnleashProvider) GetString(key string, fallback string) string {
    variant := p.client.GetVariant(key, unleash.WithVariantFallback(&unleash.Variant{
        Payload: unleash.Payload{
            Type:  "string",
            Value: fallback,
        },
    }))
    
    if variant.Payload.Type == "string" {
        return variant.Payload.Value
    }
    
    return fallback
}

func (p *UnleashProvider) GetJSON(key string, fallback ldvalue.Value) ldvalue.Value {
    variant := p.client.GetVariant(key, unleash.WithVariantFallback(&unleash.Variant{
        Payload: unleash.Payload{
            Type:  "json",
            Value: fallback.JSONString(),
        },
    }))
    
    if variant.Payload.Type == "json" {
        return ldvalue.Parse(variant.Payload.Value)
    }
    
    return fallback
}

func (p *UnleashProvider) Close() error {
    p.client.Close()
    return nil
}
```

### 3.4 Unleash 按团队/模板灰度

```bash
# 创建团队 Context
curl -X POST "${UNLEASH_URL}/api/admin/context" \
  -H "Authorization: ${API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "team",
    "description": "Team context for targeting",
    "legalValues": ["team-uuid-1", "team-uuid-2"],
    "stickiness": true
  }'

# 创建模板 Context
curl -X POST "${UNLEASH_URL}/api/admin/context" \
  -H "Authorization: ${API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "template",
    "description": "Template context for targeting",
    "legalValues": ["template-uuid-1", "template-uuid-2"],
    "stickiness": true
  }'

# 为特定团队启用 Flag
curl -X POST "${UNLEASH_URL}/api/admin/features/max-sandboxes-per-node/environments/default/strategies" \
  -H "Authorization: ${API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "flexibleRollout",
    "constraints": [
      {
        "contextName": "team",
        "operator": "IN",
        "values": ["team-uuid-1", "team-uuid-2"]
      }
    ],
    "parameters": {
      "rollout": "100",
      "stickiness": "default",
      "groupId": "max-sandboxes-per-node"
    },
    "variants": [
      {
        "name": "high-limit",
        "weight": 1000,
        "weightType": "fix",
        "payload": {
          "type": "string",
          "value": "500"
        }
      }
    ]
  }'
```

### 3.5 环境变量

```bash
# Unleash 配置
export FEATURE_FLAGS_PROVIDER=unleash
export UNLEASH_URL=http://unleash:4242/api
export UNLEASH_TOKEN=default:development.unleash-insecure-api-token
export UNLEASH_APP_NAME=e2b-api
```

---

## 4. 修改代码支持多 Provider

### 4.1 Provider 接口

```go
// packages/shared/pkg/featureflags/provider.go

package featureflags

import "github.com/launchdarkly/go-sdk-common/v3/ldvalue"

// Provider 定义 Feature Flag 提供者接口
type Provider interface {
    GetBool(key string, fallback bool) bool
    GetInt(key string, fallback int) int
    GetString(key string, fallback string) string
    GetJSON(key string, fallback ldvalue.Value) ldvalue.Value
    Close() error
}
```

### 4.2 修改 Client

```go
// packages/shared/pkg/featureflags/client.go (修改后)

package featureflags

import (
    "context"
    "os"
    
    ldclient "github.com/launchdarkly/go-server-sdk/v7"
    "github.com/launchdarkly/go-sdk-common/v3/ldcontext"
)

type Client struct {
    provider       Provider
    ld             *ldclient.LDClient
    deploymentName string
    serviceName    string
}

func NewClient() (*Client, error) {
    provider := os.Getenv("FEATURE_FLAGS_PROVIDER")
    
    switch provider {
    case "yaml":
        configPath := os.Getenv("FEATURE_FLAGS_CONFIG")
        yamlProvider, err := NewYAMLProvider(configPath)
        if err != nil {
            return nil, err
        }
        return &Client{provider: yamlProvider}, nil
        
    case "unleash":
        url := os.Getenv("UNLEASH_URL")
        token := os.Getenv("UNLEASH_TOKEN")
        appName := os.Getenv("UNLEASH_APP_NAME")
        unleashProvider, err := NewUnleashProvider(appName, url, token)
        if err != nil {
            return nil, err
        }
        return &Client{provider: unleashProvider}, nil
        
    default:
        // LaunchDarkly (默认)
        if launchDarklyApiKey == "" {
            return NewClientWithDatasource(launchDarklyOfflineStore)
        }
        ldClient, err := ldclient.MakeClient(launchDarklyApiKey, waitForInit)
        if err != nil {
            return nil, err
        }
        return &Client{ld: ldClient}, nil
    }
}
```

---

## 5. 部署对比

| 特性 | YAML 配置 | Unleash | LaunchDarkly |
|------|-----------|---------|--------------|
| 部署成本 | 零 | 中 | 高 (企业版) |
| 动态更新 | 需重启 | 自动 | 自动 |
| 灰度发布 | ❌ | ✅ | ✅ |
| 按团队/模板 | ❌ | ✅ | ✅ |
| Web UI | ❌ | ✅ | ✅ |
| API | ❌ | ✅ | ✅ |
| 多环境支持 | ❌ | ✅ | ✅ |
| 审计日志 | ❌ | ✅ | ✅ |
| 代码改动 | ~100行 | ~200行 | 0 |

---

## 6. 推荐方案

### 6.1 单节点/测试
使用 **YAML 配置**，零成本部署

### 6.2 生产环境（不需要灰度）
使用 **YAML 配置**，通过 Git 管理版本

### 6.3 生产环境（需要灰度）
使用 **Unleash**，支持团队/模板级别的灰度发布

### 部署命令

```bash
# YAML 方案
export FEATURE_FLAGS_PROVIDER=yaml
export FEATURE_FLAGS_CONFIG=/etc/e2b/feature-flags.yaml

# Unleash 方案
docker-compose -f docker-compose.unleash.yml up -d
./create-flags.sh
export FEATURE_FLAGS_PROVIDER=unleash
export UNLEASH_URL=http://unleash:4242/api
export UNLEASH_TOKEN=your-token
```
