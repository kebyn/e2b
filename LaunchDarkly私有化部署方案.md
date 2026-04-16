# LaunchDarkly 私有化部署替代方案

---

## 当前代码分析

E2B 使用 LaunchDarkly Server SDK (`go-server-sdk/v7`)，代码特点：

```go
// packages/shared/pkg/featureflags/client.go

func NewClient() (*Client, error) {
    if launchDarklyApiKey == "" {
        // 离线模式：使用代码中的默认值
        return NewClientWithDatasource(launchDarklyOfflineStore)
    }
    // 在线模式：连接 LaunchDarkly 云服务
    ldClient, err := ldclient.MakeClient(launchDarklyApiKey, waitForInit)
    return &Client{ld: ldClient}, nil
}
```

**关键特性：**
- 未配置 `LAUNCH_DARKLY_API_KEY` 时自动使用默认值（离线模式）
- 所有 Flag 都有 fallback 默认值
- 支持按 team/template/sandbox 维度的目标控制

---

## 方案对比

| 方案 | 修改代码 | 成本 | 灰度发布 | UI 管理 | 推荐度 |
|------|----------|------|----------|---------|--------|
| 方案 A: 默认值 | ❌ 无 | 零 | ❌ 不支持 | ❌ 无 | ⭐⭐⭐⭐⭐ |
| 方案 B: YAML 配置 | ✅ 小 | 零 | ❌ 不支持 | ❌ 无 | ⭐⭐⭐⭐ |
| 方案 C: Unleash | ✅ 中 | 低 | ✅ 支持 | ✅ 有 | ⭐⭐⭐⭐ |
| 方案 D: Flagsmith | ✅ 中 | 低 | ✅ 支持 | ✅ 有 | ⭐⭐⭐⭐ |
| 方案 E: Flipt | ✅ 中 | 低 | ✅ 支持 | ✅ 有 | ⭐⭐⭐ |
| 方案 F: etcd/Consul | ✅ 大 | 中 | ❌ 不支持 | ❌ 无 | ⭐⭐ |
| 方案 G: 自研 | ✅ 大 | 高 | 自定义 | 自定义 | ⭐⭐ |

---

## 方案 A: 使用默认值（推荐，无需修改代码）

### 优点
- 零成本
- 代码已内置支持
- 无需额外组件

### 缺点
- 无法动态调整参数
- 无法按 team/template 灰度控制

### 实现

```bash
# 不设置 LAUNCH_DARKLY_API_KEY 即可
# 所有 Flag 使用代码中的 fallback 值

# 环境变量
# LAUNCH_DARKLY_API_KEY=  # 留空或不设置
```

### 默认值列表

> **注意**: 以下默认值来自代码 `packages/shared/pkg/featureflags/flags.go`，与 ENVIRONMENT 相关的 Flags（标记为 `dev: true`）在 `ENVIRONMENT=dev` 或 `ENVIRONMENT=local` 时为 `true`，在 `ENVIRONMENT=prod` 时为 `false`。

```yaml
# Boolean Flags (固定值)
sandbox-metrics-write: true              # 固定 true
sandbox-metrics-read: true               # 固定 true
write-to-cache-on-writes: false
peer-to-peer-chunk-transfer: false
peer-to-peer-async-checkpoint: false
best-of-k-can-fit: true
best-of-k-too-many-starting: false
edge-provided-sandbox-metrics: false
execution-metrics-on-webhooks: false
sandbox-label-based-scheduling: false
sandbox-placement-optimistic-resource-accounting: false

# Boolean Flags (与 ENVIRONMENT 相关)
host-stats-enabled: dev: true            # ENVIRONMENT=dev/local 时 true
use-nfs-for-snapshots: dev: true
use-nfs-for-templates: dev: true
use-nfs-for-building-templates: dev: true
create-storage-cache-spans: dev: true
sandbox-auto-resume: dev: true
can-use-persistent-volumes: dev: true

# Integer Flags
max-sandboxes-per-node: 200
gcloud-concurrent-upload-limit: 8
gcloud-max-tasks: 16
clickhouse-batcher-max-batch-size: 100
clickhouse-batcher-max-delay: 1000       # 毫秒
clickhouse-batcher-queue-size: 1000
best-of-k-sample-size: 3
best-of-k-max-overcommit: 400            # 百分比 (R=4)
best-of-k-alpha: 50                      # 百分比 (Alpha=0.5)
envd-init-request-timeout-milliseconds: 50  # 毫秒 (不是 500!)
host-stats-sampling-interval: 5000       # 毫秒
max-cache-writer-concurrency: 10
build-cache-max-usage-percentage: 85
build-provision-version: 0
nbd-connections-per-device: 1            # 注意：是 1，不是 4!
memory-prefetch-max-fetch-workers: 16
memory-prefetch-max-copy-workers: 8
tcpfirewall-max-connections-per-sandbox: -1  # -1 表示无限制
sandbox-max-incoming-connections: -1
build-base-rootfs-size-limit-mb: 25000
minimum-autoresume-timeout: 300          # 秒
max-concurrent-snapshot-upserts: 0       # 0 表示无限制
max-concurrent-sandbox-list-queries: 0
max-concurrent-snapshot-build-queries: 0

# String Flags
build-firecracker-version: "v1.12.1_210cbac"  # 注意：版本号后缀!
build-io-engine: "Sync"
default-persistent-volume-type: ""

# Firecracker 版本映射 (JSON)
firecracker-versions:
  v1.10: "v1.10.1_30cbb07"
  v1.12: "v1.12.1_210cbac"
```

---

## 方案 B: YAML 配置文件（小改动）

### 优点
- 简单直观
- 可以通过配置文件修改参数
- 支持版本控制

### 缺点
- 需要重启服务生效
- 无灰度发布能力
- 需要修改代码

### 实现

#### 1. 创建配置文件

```yaml
# /etc/e2b/feature-flags.yaml
flags:
  # 布尔 Flag
  sandbox-metrics-write: true
  host-stats-enabled: true
  peer-to-peer-chunk-transfer: false
  
  # 整数 Flag
  max-sandboxes-per-node: 100
  nbd-connections-per-device: 8
  build-cache-max-usage-percentage: 80
  
  # 字符串 Flag
  build-io-engine: "Async"

# 按维度覆盖 (可选)
overrides:
  team:
    "team-uuid-1":
      max-sandboxes-per-node: 500
  template:
    "template-uuid-1":
      sandbox-metrics-write: true
```

#### 2. 新增配置加载代码

```go
// packages/shared/pkg/featureflags/config.go

package featureflags

import (
    "os"
    "gopkg.in/yaml.v3"
)

type FlagsConfig struct {
    Flags     map[string]interface{} `yaml:"flags"`
    Overrides OverridesConfig        `yaml:"overrides"`
}

type OverridesConfig struct {
    Team     map[string]map[string]interface{} `yaml:"team"`
    Template map[string]map[string]interface{} `yaml:"template"`
}

func LoadFlagsFromConfig(path string) (*FlagsConfig, error) {
    data, err := os.ReadFile(path)
    if err != nil {
        return nil, err
    }
    
    var config FlagsConfig
    if err := yaml.Unmarshal(data, &config); err != nil {
        return nil, err
    }
    
    return &config, nil
}
```

#### 3. 修改 client.go

```go
// 修改 NewClient 函数
func NewClient() (*Client, error) {
    configPath := os.Getenv("FEATURE_FLAGS_CONFIG")
    
    // 优先级: 环境变量配置文件 > LaunchDarkly > 默认值
    if configPath != "" {
        return NewClientWithConfig(configPath)
    }
    
    if launchDarklyApiKey == "" {
        return NewClientWithDatasource(launchDarklyOfflineStore)
    }
    
    ldClient, err := ldclient.MakeClient(launchDarklyApiKey, waitForInit)
    if err != nil {
        return nil, err
    }
    return &Client{ld: ldClient}, nil
}
```

#### 4. 环境变量

```bash
export FEATURE_FLAGS_CONFIG="/etc/e2b/feature-flags.yaml"
```

---

## 方案 C: Unleash（推荐开源方案）

### 优点
- 开源免费
- 功能完整（灰度发布、A/B 测试）
- 有 Web UI
- 支持 Go SDK
- API 兼容性好

### 缺点
- 需要部署额外服务
- 需要修改代码

### 部署

```bash
# Docker Compose 部署
cat > docker-compose.unleash.yml << 'EOF'
version: '3.8'

services:
  unleash:
    image: unleashorg/unleash-server:latest
    ports:
      - "4242:4242"
    environment:
      DATABASE_URL: postgres://unleash:password@postgres:5432/unleash
      DATABASE_SSL: "false"
    depends_on:
      - postgres

  postgres:
    image: postgres:17-alpine
    environment:
      POSTGRES_USER: unleash
      POSTGRES_PASSWORD: password
      POSTGRES_DB: unleash
    volumes:
      - unleash_data:/var/lib/postgresql/data

volumes:
  unleash_data:
EOF

docker-compose -f docker-compose.unleash.yml up -d
```

### 使用方式

```go
// packages/shared/pkg/featureflags/unleash.go

package featureflags

import (
    "context"
    "github.com/Unleash/unleash-client-go/v4"
)

type UnleashClient struct {
    client *unleash.Client
}

func NewUnleashClient(appName, url, token string) (*UnleashClient, error) {
    client, err := unleash.NewClient(unleash.Config{
        AppName:    appName,
        Url:        url,  // http://unleash:4242/api
        CustomHeaders: map[string]string{
            "Authorization": token,
        },
    })
    if err != nil {
        return nil, err
    }
    
    return &UnleashClient{client: client}, nil
}

func (c *UnleashClient) BoolFlag(ctx context.Context, flag string, fallback bool) bool {
    return c.client.IsEnabled(flag, unleash.WithFallback(fallback))
}
```

### 环境变量

```bash
export UNLEASH_URL="http://unleash:4242/api"
export UNLEASH_TOKEN="default:development.unleash-insecure-api-token"
```

### Flag 迁移

```bash
# 在 Unleash UI 中创建 Flag
# 访问 http://unleash:4242 (默认账号: admin / unleash4all)

# 创建 Feature Toggle
- sandbox-metrics-write (boolean)
- max-sandboxes-per-node (number via variant)
- build-io-engine (string via variant)
```

---

## 方案 D: Flagsmith

### 优点
- 功能完整
- UI 友好
- 支持远程配置
- 有 SaaS 和自托管选项

### 缺点
- 需要部署额外服务
- 需要修改代码

### 部署

```bash
# Docker Compose 部署
cat > docker-compose.flagsmith.yml << 'EOF'
version: '3.8'

services:
  flagsmith:
    image: flagsmith/flagsmith:latest
    ports:
      - "8000:8000"
    environment:
      DATABASE_URL: postgresql://flagsmith:password@postgres:5432/flagsmith
    depends_on:
      - postgres

  postgres:
    image: postgres:17-alpine
    environment:
      POSTGRES_USER: flagsmith
      POSTGRES_PASSWORD: password
      POSTGRES_DB: flagsmith
    volumes:
      - flagsmith_data:/var/lib/postgresql/data

volumes:
  flagsmith_data:
EOF

docker-compose -f docker-compose.flagsmith.yml up -d
```

### 使用方式

```go
import (
    "github.com/flagsmith/flagsmith-go-client/v3"
)

client := flagsmith.NewClient(
    "your-server-side-environment-key",
    flagsmith.WithBaseURL("http://flagsmith:8000/api/v1/"),
)

// 获取 Feature Flag
enabled, _ := client.FeatureEnabled("sandbox-metrics-write")

// 获取 Remote Config
value, _ := client.GetFeatureValue("max-sandboxes-per-node")
```

---

## 方案 E: Flipt

### 优点
- 轻量级
- 支持 gRPC
- Git 友好（配置可版本控制）

### 缺点
- 功能相对简单
- 社区较小

### 部署

```bash
docker run -d \
  --name flipt \
  -p 8080:8080 \
  -p 9090:9090 \
  -v /var/lib/flipt:/var/lib/flipt \
  flipt/flipt:latest
```

### 配置示例

```yaml
# features.yml
version: "1.0"
flags:
  - key: sandbox-metrics-write
    name: Sandbox Metrics Write
    type: BOOLEAN_FLAG_TYPE
    enabled: true
    variants:
      - key: "true"
        name: "Enabled"
      - key: "false"
        name: "Disabled"
    rules:
      - segment: team-premium
        distributions:
          - variant: "true"
            rollout: 100

  - key: max-sandboxes-per-node
    name: Max Sandboxes Per Node
    type: VARIANT_FLAG_TYPE
    variants:
      - key: "100"
        name: "100"
      - key: "200"
        name: "200"
      - key: "500"
        name: "500"
    default_variant: "200"
```

---

## 推荐方案

### 最小成本（推荐）

```bash
# 使用默认值，无需任何修改
# 不设置 LAUNCH_DARKLY_API_KEY
```

### 低成本（需要小改动）

```bash
# 方案 B: YAML 配置文件
# 修改约 50 行代码
export FEATURE_FLAGS_CONFIG="/etc/e2b/feature-flags.yaml"
```

### 功能完整（需要中等改动）

```bash
# 方案 C: Unleash（推荐）
# 开源、功能完整、有 UI
export UNLEASH_URL="http://unleash:4242/api"
export UNLEASH_TOKEN="your-token"
```

---

## 代码修改量对比

| 方案 | 新增文件 | 修改文件 | 代码行数 |
|------|----------|----------|----------|
| A: 默认值 | 0 | 0 | 0 |
| B: YAML | 1 | 1 | ~100 |
| C: Unleash | 1 | 1 | ~200 |
| D: Flagsmith | 1 | 1 | ~200 |
| E: Flipt | 1 | 1 | ~250 |

---

## 私有化部署建议

### 1. 单节点/测试环境
使用**方案 A（默认值）**，零成本

### 2. 生产环境（不需要灰度）
使用**方案 B（YAML 配置）**，通过配置文件管理

### 3. 生产环境（需要灰度）
使用**方案 C（Unleash）**，功能完整且免费

### 部署 Unleash 到 Ansible

```yaml
# ansible/roles/unleash/tasks/main.yml
- name: 部署 Unleash
  docker_compose:
    project_src: /opt/unleash
    files:
      - docker-compose.yml
    state: present
```
