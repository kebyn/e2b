# E2B Grafana 配置

## 目录结构

```
grafana/
├── dashboards/
│   ├── e2b-overview.json      # 平台概览 Dashboard
│   └── e2b-services.json      # 服务健康 Dashboard
├── alerts/
│   └── e2b-alerts.yml         # Prometheus 告警规则
├── datasources/
│   └── datasources.yml        # 数据源配置
└── README.md                  # 本文档
```

## 部署方式

### 方式 1: Docker Compose

```yaml
# docker-compose.grafana.yml
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - ./grafana/alerts:/etc/prometheus/alerts
      - prometheus_data:/prometheus

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - ./grafana/dashboards:/etc/grafana/provisioning/dashboards
      - ./grafana/datasources:/etc/grafana/provisioning/datasources
      - grafana_data:/var/lib/grafana

  loki:
    image: grafana/loki:latest
    ports:
      - "3100:3100"
    volumes:
      - loki_data:/loki

  clickhouse:
    image: clickhouse/clickhouse-server:25-alpine
    ports:
      - "8123:8123"
      - "9000:9000"
    volumes:
      - clickhouse_data:/var/lib/clickhouse

volumes:
  prometheus_data:
  grafana_data:
  loki_data:
  clickhouse_data:
```

### 方式 2: Helm (Kubernetes)

```bash
# 添加 Helm 仓库
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# 部署 Prometheus + Grafana
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword=your-password

# 导入 Dashboard
kubectl create configmap e2b-dashboards \
  --from-file=grafana/dashboards/ \
  -n monitoring

# 应用告警规则
kubectl apply -f grafana/alerts/e2b-alerts.yml
```

### 方式 3: Ansible

已集成在 `ansible/roles/` 中（如需部署）。

## Dashboard 说明

### E2B Overview

核心监控面板，包含：

| 面板 | 说明 |
|------|------|
| 运行中 Sandbox | 实时 Sandbox 数量 |
| API 请求/秒 | API 请求速率 |
| 错误率 | 5xx 错误率 |
| P99 延迟 | API P99 响应时间 |
| Nomad 节点数 | 集群节点数量 |
| 数据库连接 | PostgreSQL 活跃连接 |
| API 请求速率 | 按方法和状态码分组 |
| API 延迟分布 | P50/P95/P99 延迟曲线 |
| API 端点错误率 | 按端点分组的错误率 |
| Sandbox 创建/销毁速率 | 生命周期事件 |
| Sandbox 生命周期 | 运行时长分布 |
| Sandbox 按团队分布 | 团队使用情况 |
| Sandbox 按模板分布 | 模板使用趋势 |
| Sandbox 创建延迟 | 创建耗时分布 |
| CPU/内存/磁盘使用率 | 系统资源 |
| 网络/磁盘 I/O | I/O 吞吐量 |
| PostgreSQL 连接/查询/复制延迟 | 数据库指标 |
| Redis 内存/命中率/连接数 | 缓存指标 |
| Nomad 任务状态/CPU/内存分配 | 编排器指标 |

### E2B Services

服务健康监控面板，包含：

| 面板 | 说明 |
|------|------|
| 服务状态 | 各服务 UP/DOWN 状态 |
| 服务运行时间 | 各实例运行时长 |
| 服务进程资源 | CPU/内存/Goroutines |
| gRPC 指标 | 请求速率/延迟/错误率 |

## 告警规则

| 告警 | 阈值 | 严重级别 |
|------|------|----------|
| E2BServiceDown | up == 0 持续 1m | critical |
| E2BAPIHighErrorRate | 5xx > 5% | critical |
| E2BAPIHighLatency | P99 > 2s | warning |
| E2BSandboxLimitReached | > 150 | warning |
| PostgreSQLConnectionLimit | > 80% | warning |
| PostgreSQLReplicationLag | > 5s | critical |
| RedisMemoryHigh | > 80% | warning |
| RedisLowHitRate | < 80% | warning |
| NomadJobFailed | > 0 | warning |
| HighCPUUsage | > 80% | warning |
| HighMemoryUsage | > 85% | warning |
| DiskSpaceLow | < 15% | critical |

## Prometheus 配置示例

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "alerts/*.yml"

scrape_configs:
  - job_name: 'e2b-api'
    static_configs:
      - targets: ['api-1:6060', 'api-2:6060', 'api-3:6060']

  - job_name: 'e2b-orchestrator'
    static_configs:
      - targets: ['compute-1:6060', 'compute-2:6060', 'compute-3:6060']

  - job_name: 'e2b-client-proxy'
    static_configs:
      - targets: ['proxy-1:6060', 'proxy-2:6060']

  - job_name: 'e2b-postgresql'
    static_configs:
      - targets: ['pg-exporter:9187']

  - job_name: 'e2b-redis'
    static_configs:
      - targets: ['redis-exporter:9121']

  - job_name: 'nomad'
    static_configs:
      - targets: ['nomad-1:4646', 'nomad-2:4646', 'nomad-3:4646']

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
```

## 访问

- Grafana: http://localhost:3000
- 默认账号: admin / admin
- Prometheus: http://localhost:9090
