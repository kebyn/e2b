# Daytona Kubernetes 生产部署指南

> 基于 [daytonaio/daytona](https://github.com/daytonaio/daytona) v0.157.0 源码分析  
> 官方未提供 K8s 部署文档，本方案通过逆向分析 Docker Compose 和源码构建

---

## 目录

1. [架构概览](#1-架构概览)
2. [前置要求](#2-前置要求)
3. [快速部署](#3-快速部署)
4. [分步部署](#4-分步部署)
5. [DNS 与 TLS 配置](#5-dns-与-tls-配置)
6. [扩缩容](#6-扩缩容)
7. [升级流程](#7-升级流程)
8. [运维手册](#8-运维手册)
9. [故障排查](#9-故障排查)
10. [安全加固](#10-安全加固)
11. [文件清单](#11-文件清单)

---

## 1. 架构概览

```
                        Internet
                           │
                    ┌──────┴──────┐
                    │   Ingress   │ ← *.sandbox.company.com
                    │  (Nginx)    │   api.sandbox.company.com
                    └──────┬──────┘
                           │
            ┌──────────────┼──────────────────┐
            │              │                  │
     ┌──────┴──────┐ ┌────┴─────┐  ┌────────┴────────┐
     │  API (x2)   │ │Proxy(x2) │  │ SSH Gateway(x2) │
     │ NestJS:3000 │ │ Go:4000  │  │    Go:2222      │
     │ +Dashboard  │ │          │  │                 │
     └──────┬──────┘ └────┬─────┘  └────────┬────────┘
            │              │                  │
     ┌──────┴──────────────┴──────────────────┘
     │
     ├─ PostgreSQL 17 (CloudNativePG, 3 实例, 主从)
     ├─ Redis (Bitnami, 1主2从)
     ├─ MinIO (S3 兼容对象存储)
     ├─ Keycloak (OIDC 认证)
     ├─ Docker Registry (镜像仓库)
     ├─ OTel Collector → Jaeger (链路追踪)
     │
     └─ Runner StatefulSet (N 个 Pod, 每 Pod 管理沙箱容器)
        │
        └─ 每个 Runner Pod:
           ├── daytona-runner (Go, 端口 3003)
           ├── Docker daemon (DinD 或挂载宿主机 sock)
           ├── iptables 网络隔离
           └── Sandbox 容器 (每个沙箱 = 一个 Docker 容器)
               └── Daemon (Go, 端口 2280, 嵌入 runner 镜像)
```

### 关键镜像

| 镜像 | 用途 | 端口 |
|------|------|------|
| `daytonaio/daytona-api:0.157.0` | API + Dashboard (NestJS) | 3000 |
| `daytonaio/daytona-proxy:0.157.0` | Sandbox 代理 (Go/Gin) | 4000 |
| `daytonaio/daytona-ssh-gateway:0.157.0` | SSH 接入网关 (Go) | 2222 |
| `daytonaio/daytona-runner:0.157.0` | 沙箱计算节点 (Go + DinD) | 3003 |
| `daytonaio/sandbox:0.6.0-slim` | 默认沙箱镜像 | - |

---

## 2. 前置要求

### 2.1 集群要求

| 项目 | 最低要求 | 推荐 |
|------|----------|------|
| K8s 版本 | 1.26+ | 1.29+ |
| 节点数 | 4 (1 控制 + 2 运算 + 1 数据) | 7+ |
| 总 CPU | 16 核 | 32+ 核 |
| 总内存 | 32 GB | 64+ GB |
| 存储 | 200 GB | 1 TB+ |
| Ingress Controller | Nginx | Nginx + cert-manager |
| StorageClass | 任意 | gp3/longhorn (支持 pquota 更佳) |

### 2.2 节点标签

Runner 节点需要专用标签和 Taint：

```bash
# 对每台 Runner 节点执行:
# 1. 运行准备脚本
./scripts/prepare-runner-node.sh /dev/sdX   # sdX 为 XFS 数据盘

# 2. 打标签
kubectl label node <NODE_NAME> node-role=daytona-runner

# 3. 打 Taint（可选，让 Runner 独占节点）
kubectl taint node <NODE_NAME> dedicated=daytona-runner:NoSchedule
```

### 2.3 前置安装

```bash
# CloudNativePG Operator (PostgreSQL)
kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.25/releases/cnpg-1.25.0.yaml

# Nginx Ingress Controller
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.config.proxy-body-size="100m" \
  --set controller.config.use-forwarded-headers="true" \
  --set controller.service.type=LoadBalancer

# cert-manager (TLS 证书自动管理)
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true

# Bitnami Helm repo
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

### 2.4 域名准备

在 DNS 服务商配置：

| 记录 | 类型 | 值 |
|------|------|----|
| `api.sandbox.company.com` | A/CNAME | Ingress LB IP |
| `*.proxy.sandbox.company.com` | A/CNAME | Ingress LB IP |
| `ssh.sandbox.company.com` | A/CNAME | Ingress LB IP |
| `keycloak.sandbox.company.com` | A/CNAME | Ingress LB IP |
| `jaeger.sandbox.company.com` | A/CNAME | Ingress LB IP |

---

## 3. 快速部署

```bash
# 克隆部署文件
git clone <this-repo> daytona-k8s
cd daytona-k8s

# 一键部署（交互式）
./scripts/deploy.sh deploy-all \
  --domain sandbox.company.com \
  --replicas 2 \
  --storage-class gp3

# 验证部署
./scripts/validate-deployment.sh sandbox.company.com
```

---

## 4. 分步部署

### Step 1: 创建 Namespace 和 RBAC

```bash
kubectl apply -f 00-namespace/
```

### Step 2: 生成并部署 Secrets

```bash
./scripts/generate-secrets.sh sandbox.company.com
```

这会：
- 生成所有加密密钥、Token、SSH 密钥对
- 创建 5 个 K8s Secret：`daytona-core`, `daytona-db`, `daytona-redis`, `daytona-s3`, `daytona-registry`
- 备份明文到 `01-secrets/.secrets-backup.env`（**务必安全保存**）

### Step 3: 部署 PostgreSQL

```bash
kubectl apply -f 02-infrastructure/postgres/postgres-cluster.yaml

# 等待就绪
kubectl -n daytona wait --for=condition=Ready cluster/daytona-postgres --timeout=300s

# 验证
kubectl -n daytona get cluster daytona-postgres
# NAME               AGE   INSTANCES   READY   STATUS
# daytona-postgres   30s   3           3       Cluster in healthy state
```

CloudNativePG 会自动：
- 创建 3 个 PostgreSQL 实例（1主2从）
- 使用 Secret `daytona-db` 中的凭据初始化数据库
- 配置流复制和自动故障转移

### Step 4: 部署 Redis

```bash
helm install daytona-redis bitnami/redis \
  -n daytona \
  -f 02-infrastructure/redis/redis-values.yaml

# 验证
kubectl -n daytona get pods -l app.kubernetes.io/name=redis
```

### Step 5: 部署 MinIO

```bash
kubectl apply -f 02-infrastructure/minio/minio-statefulset.yaml

# 等待就绪
kubectl -n daytona rollout status statefulset/daytona-minio --timeout=180s
```

### Step 6: 部署 Docker Registry

```bash
kubectl apply -f 02-infrastructure/registry/registry-deployment.yaml
```

### Step 7: 部署 Keycloak

```bash
# 创建 Keycloak 数据库（共享 PG 集群）
kubectl -n daytona exec -it daytona-postgres-1 -- psql -U daytona -c "CREATE DATABASE keycloak;"

helm install daytona-keycloak bitnami/keycloak \
  -n daytona \
  -f 02-infrastructure/keycloak/keycloak-values.yaml

# 部署完成后，导入 Realm 配置：
kubectl -n daytona port-forward svc/daytona-keycloak 8080:8080 &
# 打开 http://localhost:8080, 用 admin/admin 登录
# 导入 02-infrastructure/keycloak/realm-export.json (替换 ${DOMAIN} 占位符)
```

**Realm 配置要点**:
- Client ID: `daytona` (public, SPA 模式)
- Redirect URIs: `https://*.sandbox.company.com/*`, `https://api.sandbox.company.com/*`
- 启用 PKCE

### Step 8: 部署监控

```bash
kubectl apply -f 04-monitoring/otel/otel-collector.yaml
kubectl apply -f 04-monitoring/jaeger/jaeger-deployment.yaml
```

### Step 9: 部署应用服务

```bash
# API
kubectl apply -f 03-application/api/api-deployment.yaml

# 等待 API 首次就绪（包含数据库迁移，可能需要 2-5 分钟）
kubectl -n daytona rollout status deployment/daytona-api --timeout=600s

# Proxy
kubectl apply -f 03-application/proxy/proxy-deployment.yaml
kubectl -n daytona rollout status deployment/daytona-proxy --timeout=300s

# SSH Gateway
kubectl apply -f 03-application/ssh-gateway/ssh-gateway-deployment.yaml

# Runner
kubectl apply -f 03-application/runner/runner-statefulset.yaml
kubectl -n daytona rollout status statefulset/daytona-runner --timeout=600s
```

### Step 10: 部署 Ingress

```bash
# 修改域名后应用
sed 's/sandbox.company.com/YOUR_DOMAIN/g' 05-ingress/ingress.yaml | kubectl apply -f -
```

---

## 5. DNS 与 TLS 配置

### Wildcard DNS

```
*.proxy.sandbox.company.com  →  <INGRESS_LB_IP>
```

对于测试环境，可以用 nip.io:
```
*.proxy.192-168-1-100.nip.io → 192.168.1.100
```

### TLS 证书

**方案 A: Let's Encrypt (自动)**
```yaml
# 已包含在 05-ingress/ingress.yaml 中的 ClusterIssuer
# 需要 DNS01 solver 来签发通配符证书
# 替换 cert-manager ClusterIssuer 配置中的 solver
```

**方案 B: 自有证书**
```bash
kubectl -n daytona create secret tls daytona-tls \
  --cert=path/to/tls.crt \
  --key=path/to/tls.key
```

**方案 C: 自签名 (测试)**
```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=*.sandbox.company.com" \
  -addext "subjectAltName=DNS:*.sandbox.company.com,DNS:sandbox.company.com"

kubectl -n daytona create secret tls daytona-tls \
  --cert=tls.crt --key=tls.key
```

---

## 6. 扩缩容

### 增加 Runner 节点

```bash
# 方法 1: 直接扩容 StatefulSet
kubectl -n daytona scale statefulset daytona-runner --replicas=4

# 方法 2: 添加新节点后
# 1. 准备新节点
./scripts/prepare-runner-node.sh /dev/sdX
kubectl label node <NEW_NODE> node-role=daytona-runner
kubectl taint node <NEW_NODE> dedicated=daytona-runner:NoSchedule

# 2. Runner 会自动调度到新节点
```

### Runner 与 API 的连接

每个 Runner Pod 通过 StatefulSet 的 DNS 自动注册：
```
daytona-runner-0.daytona-runner.daytona.svc.cluster.local:3003
daytona-runner-1.daytona-runner.daytona.svc.cluster.local:3003
...
```

API 通过 `DEFAULT_RUNNER_DOMAIN` 和 `DEFAULT_RUNNER_API_URL` 找到默认 Runner。
新 Runner 需通过 API 手动注册或在 Dashboard 添加。

### 水平扩容

API 和 Proxy 已配置 HPA：
```bash
kubectl -n daytona get hpa
# NAME              REFERENCE                   TARGETS   MINPODS   MAXPODS
# daytona-api       Deployment/daytona-api       45%/70%   2         5
# daytona-proxy     Deployment/daytona-proxy     30%/70%   2         8
```

---

## 7. 升级流程

### 滚动升级应用

```bash
# 使用部署脚本
./scripts/deploy.sh upgrade --image-tag 0.158.0

# 或手动
kubectl -n daytona set image deployment/daytona-api \
  api=daytonaio/daytona-api:0.158.0
kubectl -n daytona rollout status deployment/daytona-api --timeout=600s

kubectl -n daytona set image deployment/daytona-proxy \
  proxy=daytonaio/daytona-proxy:0.158.0

kubectl -n daytona set image statefulset/daytona-runner \
  runner=daytonaio/daytona-runner:0.158.0
# Runner StatefulSet 支持 rollingUpdate: rollingUpdate
```

### 数据库迁移

Daytona 使用 Expand-and-Contract 模式：

```bash
# Step 1: Pre-deploy 迁移（向后兼容）
kubectl -n daytona exec deploy/daytona-api -- \
  node dist/apps/api/main.js --migration-run:pre-deploy

# Step 2: 滚动升级 API
# (deploy.sh upgrade 会自动执行 RUN_MIGRATIONS=true)

# Step 3: Post-deploy 迁移（清理旧列）
kubectl -n daytona exec deploy/daytona-api -- \
  node dist/apps/api/main.js --migration-run:post-deploy
```

### 回滚

```bash
kubectl -n daytona rollout undo deployment/daytona-api
kubectl -n daytona rollout undo deployment/daytona-proxy
kubectl -n daytona rollout undo statefulset/daytona-runner
```

---

## 8. 运维手册

### 日常操作

```bash
# 查看状态
./scripts/deploy.sh status

# 查看日志
./scripts/deploy.sh logs api
./scripts/deploy.sh logs runner
./scripts/deploy.sh logs all

# 重启 API (例如应用新环境变量)
kubectl -n daytona rollout restart deployment/daytona-api

# 查看数据库迁移状态
kubectl -n daytona exec deploy/daytona-api -- \
  node dist/apps/api/main.js --migration-run
```

### 备份

```bash
# PostgreSQL 备份 (CloudNativePG 自动备份如果配置了 barmanObjectStore)
kubectl -n daytona get backup

# 手动备份
kubectl -n daytona exec -it daytona-postgres-1 -- \
  pg_dump -U daytona daytona | gzip > daytona-db-$(date +%Y%m%d).sql.gz

# MinIO 数据备份
kubectl -n daytona exec daytona-minio-0 -- \
  mc mirror local/daytona /backup/daytona-s3/
```

### 监控查询

```bash
# Jaeger UI
kubectl -n daytona port-forward svc/daytona-jaeger-query 16686:16686
# 打开 http://localhost:16686

# OTel Prometheus 指标
kubectl -n daytona port-forward svc/daytona-otel-collector 9090:9090
# curl http://localhost:9090/metrics | grep daytona

# PostgreSQL 状态
kubectl -n daytona get cluster daytona-postgres -o yaml | yq .status

# Redis 状态
kubectl -n daytona exec -it daytona-redis-master-0 -- redis-cli INFO memory
```

### 重建某个服务

```bash
# 删除 Pod 让其自动重建
kubectl -n daytona delete pod -l app.kubernetes.io/name=daytona-api

# 强制重建（删除并等待）
kubectl -n daytona rollout restart deployment/daytona-api
```

---

## 9. 故障排查

### Sandbox 创建失败

```bash
# 1. 查看 Runner 日志
kubectl -n daytona logs daytona-runner-0 --tail=100

# 2. 检查 Runner 能否拉取镜像
kubectl -n daytona exec daytona-runner-0 -- docker pull daytonaio/sandbox:0.6.0-slim

# 3. 检查 Runner 是否注册成功
kubectl -n daytona exec deploy/daytona-api -- \
  curl -s http://localhost:3000/api/runners | jq

# 4. 检查 Docker socket 权限
kubectl -n daytona exec daytona-runner-0 -- ls -la /var/run/docker.sock
# 应为 srw-rw---- 1 root docker
```

### API 启动失败

```bash
# 1. 查看日志
kubectl -n daytona logs deploy/daytona-api --tail=50

# 2. 常见原因:
# - 数据库连接失败: 检查 daytona-db secret 和 PG 集群状态
# - Redis 连接失败: 检查 daytona-redis secret 和 Redis Pod
# - 迁移失败: 检查 PostgreSQL 日志

# 3. 跳过迁移启动 (紧急)
kubectl -n daytona set env deployment/daytona-api RUN_MIGRATIONS=false
```

### Proxy 无法路由到 Sandbox

```bash
# 1. 检查 DNS 解析
nslookup 8080-sandbox-id.proxy.sandbox.company.com

# 2. 检查 Proxy 日志
kubectl -n daytona logs deploy/daytona-proxy --tail=50

# 3. 检查 Runner 可达性
kubectl -n daytona exec deploy/daytona-proxy -- \
  wget -q -O- http://daytona-runner-0.daytona-runner:3003/health
```

### SSH 连接被拒

```bash
# 1. 检查 SSH Gateway 日志
kubectl -n daytona logs deploy/daytona-ssh-gateway --tail=50

# 2. 确保 Ingress TCP ConfigMap 生效
kubectl -n ingress-nginx get configmap tcp-services -o yaml

# 3. 测试连通性
ssh -p 2222 test-token@ssh.sandbox.company.com -v
```

### PostgreSQL 性能问题

```bash
# 查看活跃查询
kubectl -n daytona exec -it daytona-postgres-1 -- \
  psql -U daytona -c "SELECT pid, now() - pg_stat_activity.query_start AS duration, query 
  FROM pg_stat_activity WHERE state != 'idle' ORDER BY duration DESC LIMIT 10;"

# 查看连接数
kubectl -n daytona exec -it daytona-postgres-1 -- \
  psql -U daytona -c "SELECT count(*) FROM pg_stat_activity;"
```

---

## 10. 安全加固

### 部署前必做

- [ ] 替换所有默认密钥（`generate-secrets.sh` 已处理）
- [ ] 设置 `SKIP_USER_EMAIL_VERIFICATION=false`
- [ ] 启用 `DB_TLS_ENABLED=true`
- [ ] 配置 Rate Limiting（`RATE_LIMIT_*` 系列）
- [ ] 创建非默认管理员账号，禁用 Keycloak 默认 admin

### 网络策略

```yaml
# 示例: 限制 Runner 只能访问 API 和 S3
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: runner-network-policy
  namespace: daytona
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: daytona-runner
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: daytona-api
    ports:
    - port: 3000
  - to:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: daytona-minio
    ports:
    - port: 9000
  - to:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: daytona-registry
    ports:
    - port: 5000
  - to:  # 允许 DNS
    - namespaceSelector: {}
    ports:
    - port: 53
      protocol: UDP
  - to:  # 允许沙箱外网访问（按需限制）
    - ipBlock:
        cidr: 0.0.0.0/0
        except:
        - 10.0.0.0/8
        - 172.16.0.0/12
        - 192.168.0.0/16
```

### Pod Security

Runner 必须 `privileged: true`，但可以通过以下方式降低风险：
- 使用专用节点池（已通过 nodeSelector + taint 实现）
- 限制 Runner 的 Kubernetes API 权限（最小 RBAC）
- 在节点级别配置 AppArmor/SELinux
- 定期扫描 Sandbox 镜像漏洞

### Secrets 管理

生产环境建议将 Secrets 迁移到：
- HashiCorp Vault + External Secrets Operator
- AWS Secrets Manager + External Secrets Operator
- Azure Key Vault CSI Driver

---

## 11. 文件清单

```
daytona-k8s/
├── 00-namespace/
│   ├── namespace.yaml              # Namespace + ResourceQuota + LimitRange
│   └── rbac.yaml                   # ServiceAccounts + RBAC
├── 01-secrets/                     # (由 generate-secrets.sh 动态生成)
│   └── .secrets-backup.env         # 明文备份 (gitignore!)
├── 02-infrastructure/
│   ├── postgres/
│   │   ├── README.md
│   │   └── postgres-cluster.yaml   # CloudNativePG Cluster + PgBouncer
│   ├── redis/
│   │   ├── README.md
│   │   ├── redis-values.yaml       # Bitnami Redis Helm values
│   │   └── service-external.yaml
│   ├── minio/
│   │   └── minio-statefulset.yaml  # MinIO StatefulSet + Service
│   ├── keycloak/
│   │   ├── README.md
│   │   ├── keycloak-values.yaml    # Bitnami Keycloak Helm values
│   │   └── realm-export.json       # Keycloak Realm 配置模板
│   └── registry/
│       └── registry-deployment.yaml # Docker Registry + UI
├── 03-application/
│   ├── api/
│   │   └── api-deployment.yaml     # API Deployment + Service + PDB + HPA
│   ├── proxy/
│   │   └── proxy-deployment.yaml   # Proxy Deployment + Service + PDB + HPA
│   ├── ssh-gateway/
│   │   └── ssh-gateway-deployment.yaml # SSH Gateway Deployment + Service + PDB
│   └── runner/
│       └── runner-statefulset.yaml  # Runner StatefulSet + Service + PDB
├── 04-monitoring/
│   ├── otel/
│   │   └── otel-collector.yaml     # OTel Collector + ConfigMap + Service
│   └── jaeger/
│       └── jaeger-deployment.yaml  # Jaeger All-in-One + Services
├── 05-ingress/
│   └── ingress.yaml                # ClusterIssuer + Certificate + Ingress rules + TCP config
├── scripts/
│   ├── deploy.sh                   # 主部署脚本 (一键部署/状态/日志/升级/销毁)
│   ├── generate-secrets.sh         # 密钥生成脚本
│   ├── validate-deployment.sh      # 部署验证脚本
│   └── prepare-runner-node.sh      # Runner 节点准备脚本
└── README.md                       # 本文档
```

---

## 附录: 常用命令速查

```bash
# === 部署 ===
./scripts/deploy.sh deploy-all --domain example.com --storage-class gp3
./scripts/deploy.sh deploy-infra
./scripts/deploy.sh deploy-app
./scripts/deploy.sh deploy-monitor

# === 状态 ===
./scripts/deploy.sh status
./scripts/validate-deployment.sh example.com
kubectl -n daytona get pods -o wide
kubectl -n daytona get cluster

# === 日志 ===
./scripts/deploy.sh logs api
./scripts/deploy.sh logs runner
kubectl -n daytona logs -f deploy/daytona-api --tail=100

# === 扩缩容 ===
kubectl -n daytona scale statefulset daytona-runner --replicas=4
kubectl -n daytona scale deployment daytona-api --replicas=3

# === 升级 ===
./scripts/deploy.sh upgrade --image-tag 0.158.0

# === 迁移 ===
./scripts/deploy.sh migrate

# === 回滚 ===
kubectl -n daytona rollout undo deployment/daytona-api

# === 调试 ===
kubectl -n daytona exec -it daytona-runner-0 -- sh
kubectl -n daytona exec -it daytona-runner-0 -- docker ps
kubectl -n daytona exec -it daytona-postgres-1 -- psql -U daytona

# === 清理 ===
./scripts/deploy.sh destroy
```
