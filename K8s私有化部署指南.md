# E2B Kubernetes 私有化部署完整指南

> 本文档是 **Kubernetes 私有化部署专线文档**：负责说明如何用 `2026.28` 已内置的 Kubernetes service discovery 部署 E2B，不维护通用裸机 / Docker / Nomad 部署步骤。
>
> 相关文档：
> - [`README.md`](./README.md)：仓库总入口与文档导航
> - [`不修改代码完整部署指南.md`](./不修改代码完整部署指南.md)：零 Terraform / 零 IaC 的通用生产部署主文档
> - [`不修改代码高可用部署方案.md`](./不修改代码高可用部署方案.md)：高可用验证、故障恢复和监控补强
> - [`启动参数详解.md`](./启动参数详解.md)：`SERVICE_DISCOVERY_PROVIDER`、`K8S_*`、`REDIS_*` 等运行时配置
> - [`私有化部署组件分析.md`](./私有化部署组件分析.md)：组件取舍、替代和降级策略

---

## 阅读导航

### 如果你要在 Kubernetes 上部署
- 直接按本文档顺序执行

### 如果你只是确认 K8s 是否还需要改代码
- 看 [3. 2026.28 内置 K8s 支持](#3-202628-内置-k8s-支持)

### 如果你在查环境变量或组件取舍
- 变量看 [`启动参数详解.md`](./启动参数详解.md#阅读导航)，组件取舍看 [`私有化部署组件分析.md`](./私有化部署组件分析.md#阅读导航)

---

## 目录

1. [架构概述](#1-架构概述)
2. [前置条件](#2-前置条件)
3. [2026.28 内置 K8s 支持](#3-202628-内置-k8s-支持)
4. [K8s 部署清单](#4-k8s-部署清单)
5. [配置管理](#5-配置管理)
6. [网络与存储](#6-网络与存储)
7. [监控与日志](#7-监控与日志)
8. [高可用配置](#8-高可用配置)

---

## 1. 架构概述

### 1.1 组件关系图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Kubernetes Cluster                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         Ingress Layer                                │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                  │   │
│  │  │   Nginx     │  │   Nginx     │  │   Nginx     │                  │   │
│  │  │  Ingress    │  │  Ingress    │  │  Ingress    │  (3 replicas)    │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                     │                                       │
│  ┌──────────────────────────────────┴──────────────────────────────────┐   │
│  │                        Application Layer                             │   │
│  │                                                                      │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │   │
│  │  │     API      │  │     API      │  │     API      │              │   │
│  │  │  (Replica 1) │  │  (Replica 2) │  │  (Replica 3) │              │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘              │   │
│  │                                                                      │   │
│  │  ┌──────────────┐  ┌──────────────┐                                │   │
│  │  │ Client Proxy │  │ Client Proxy │  (2+ replicas)                 │   │
│  │  └──────────────┘  └──────────────┘                                │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                     │                                       │
│  ┌──────────────────────────────────┴──────────────────────────────────┐   │
│  │                       Orchestrator Layer                             │   │
│  │                                                                      │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │   │
│  │  │   Orch-1     │  │   Orch-2     │  │   Orch-N     │              │   │
│  │  │ (DaemonSet)  │  │ (DaemonSet)  │  │ (DaemonSet)  │              │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                     │                                       │
│  ┌──────────────────────────────────┴──────────────────────────────────┐   │
│  │                         Data Layer                                   │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │   │
│  │  │   Redis      │  │  PostgreSQL  │  │  ClickHouse  │  (可选)       │   │
│  │  │(VIP/Cluster) │  │   (HA)       │  │  (可选)      │              │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 组件角色

| 组件 | K8s 部署方式 | 副本数 | 说明 |
|------|-------------|--------|------|
| API | Deployment | 3 | 无状态，水平扩展 |
| Client Proxy | Deployment | 2+ | 无状态，水平扩展 |
| Orchestrator | DaemonSet | = 节点数 | 每个节点一个，管理 sandbox |
| Redis | StatefulSet / 外部托管服务 | 1 主 + 副本 + LB，或 Cluster | 应用只连接 `REDIS_URL` 单端点或 `REDIS_CLUSTER_URL` 集群端点，不直连 Sentinel |
| PostgreSQL | StatefulSet | 3 | 主从复制 + 连接池 |
| ClickHouse | StatefulSet | 1+ | 可选，用于指标存储 |

> **K8s Node Pool 等价方案**
> - Nomad `node_pool` 在 K8s 中对应 `nodeSelector` 或 `nodeAffinity`
> - Orchestrator 使用 DaemonSet，天然每个节点运行一个（无需 nodeSelector）
> - 如需添加 Template Manager：
>   - 使用 Deployment + `nodeSelector: pool: build`
>   - 或通过 `nodeAffinity` 限制到特定节点池
>   - 需修改 `GRPC_PORT` 为 `5009` 避免与 Orchestrator 端口冲突（DaemonSet 已占用 5008）

---

## 2. 前置条件

### 2.1 K8s 集群要求

```yaml
# 最小配置
节点数: 3 (高可用)
每节点:
  CPU: 8 核
  内存: 32GB
  存储: 200GB SSD

# 网络要求
- 支持 CNI (Calico/Cilium 推荐)
- 支持 LoadBalancer 或 NodePort
- Pod 网络 CIDR 不与宿主机冲突
```

### 2.2 特权要求

Orchestrator 需要以下特权（用于管理 sandbox）：

```yaml
# 需要启用的内核模块
- nbd (Network Block Device)
- tun/tap
- iptables

# 需要的能力
- SYS_ADMIN
- NET_ADMIN

# 需要的设备访问
- /dev/net/tun
- /dev/nbd*
```

### 2.3 存储要求

```yaml
# StorageClass
- fast-ssd: 用于数据库和缓存
- shared-nfs: 用于模板和快照存储（可选）

# 持久卷
- PostgreSQL: 100GB per replica
- Redis: 20GB per replica
- ClickHouse: 500GB (可选)
- 模板存储: 500GB+ (NFS 或对象存储)
```

---

## 3. 2026.28 内置 K8s 支持

`2026.28` 已经内置 Kubernetes 服务发现，不需要再新增 discovery 代码或修改 API 启动逻辑。当前代码中的入口如下：

| 能力 | 当前代码 |
|------|----------|
| Orchestrator Pod 发现 | `infra/packages/api/internal/orchestrator/discovery/kubernetes.go` |
| Template Manager Pod 发现 | `infra/packages/api/internal/clusters/discovery/kubernetes.go` |
| Provider 选择 | `infra/packages/api/internal/handlers/store.go` |
| 配置模型 | `infra/packages/api/internal/cfg/model.go` |

### 3.1 API 服务发现配置

```bash
SERVICE_DISCOVERY_PROVIDER=kubernetes
K8S_NAMESPACE=e2b
K8S_ORCHESTRATOR_POD_LABEL_SELECTOR=app.kubernetes.io/name=orchestrator
K8S_TEMPLATE_MANAGER_POD_LABEL_SELECTOR=app.kubernetes.io/name=template-manager
```

`SERVICE_DISCOVERY_PROVIDER` 的有效值是：

| 值 | 说明 |
|----|------|
| `nomad` | 默认值，查询 Nomad API |
| `kubernetes` | 查询当前 Pod ServiceAccount 可访问的 K8s API |
| `local` | 使用 `LOCAL_ORCHESTRATOR_ADDRESS` 指向单个 Orchestrator，主要用于本地开发 |

### 3.2 K8s RBAC 要求

API Pod 需要能 list/watch Pod，至少应授予当前 namespace 内 `pods` 的 `get`、`list`、`watch` 权限。服务发现会过滤未 ready、无 IP 的 Pod，并使用 Orchestrator Pod 的 host IP / Template Manager Pod 的 pod IP 建立连接。

### 3.3 不再需要的旧改造

早期文档建议新增 `K8sServiceDiscovery`、`ServiceDiscoveryConfig` 或 `IP_SLOT_STORAGE`。这些不再适用于 `2026.28`：

- 不要把 provider 值写成旧简称 `k8s`，当前枚举值是 `kubernetes`。
- 不要新增旧式静态配置文件变量作为官方路径，当前本地静态模式使用 `LOCAL_ORCHESTRATOR_ADDRESS`。
- Orchestrator IP slot 仍由现有网络配置控制；本文部署清单可使用 `USE_LOCAL_NAMESPACE_STORAGE=true` 做单节点/每节点独立分配，但这不是 API 服务发现配置。

---

## 4. K8s 部署清单

### 4.1 Namespace

```yaml
# namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: e2b
  labels:
    app.kubernetes.io/part-of: e2b
```

### 4.2 ConfigMap

```yaml
# configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: e2b-config
  namespace: e2b
data:
  ENVIRONMENT: "prod"
  SERVICE_DISCOVERY_PROVIDER: "kubernetes"
  K8S_NAMESPACE: "e2b"
  K8S_ORCHESTRATOR_POD_LABEL_SELECTOR: "app.kubernetes.io/name=orchestrator"
  K8S_TEMPLATE_MANAGER_POD_LABEL_SELECTOR: "app.kubernetes.io/name=template-manager"
  USE_LOCAL_NAMESPACE_STORAGE: "true"

  # 默认端口
  GRPC_PORT: "5008"
  PROXY_PORT: "3002"
  HEALTH_PORT: "3003"

  # Nomad 配置（可选，保留向后兼容）
  NOMAD_ADDRESS: ""

  # ClickHouse（可选）
  CLICKHOUSE_CONNECTION_STRING: ""
```

### 4.3 Secrets

```yaml
# secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: e2b-secrets
  namespace: e2b
type: Opaque
stringData:
  # 数据库
  POSTGRES_CONNECTION_STRING: "postgresql://e2b:password@postgres:5432/e2b?sslmode=disable"

  # Redis：应用连接稳定主端点；Cluster 模式改用 REDIS_CLUSTER_URL
  REDIS_URL: "redis-primary:6379"
  # REDIS_CLUSTER_URL: "redis-node-1:6379,redis-node-2:6379,redis-node-3:6379"

  # 认证 provider（可选）
  AUTH_PROVIDER_CONFIG: '{"jwt":[]}'
  ADMIN_TOKEN: "your-admin-token"
  ORY_SDK_URL: "https://your-ory.example.com"
  ORY_PROJECT_API_TOKEN: "your-ory-project-token"
  ORY_ISSUER_URL: "https://your-ory.example.com"

  # Volume Token
  VOLUME_TOKEN_ISSUER: "e2b.your-domain.com"
  VOLUME_TOKEN_SIGNING_METHOD: "ES256"
  VOLUME_TOKEN_SIGNING_KEY: "ECDSA:base64-encoded-private-key"
  VOLUME_TOKEN_SIGNING_KEY_NAME: "prod-2024-01"

  # 模板存储（GCP 或 AWS）
  TEMPLATE_BUCKET_NAME: "e2b-templates"
  BUILD_CACHE_BUCKET_NAME: "e2b-build-cache"
  GOOGLE_SERVICE_ACCOUNT_BASE64: ""

  # Loki（可选）
  LOKI_URL: "http://loki:3100"
```

### 4.4 API Deployment

```yaml
# api-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: e2b-api
  namespace: e2b
  labels:
    app: e2b-api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: e2b-api
  template:
    metadata:
      labels:
        app: e2b-api
    spec:
      serviceAccountName: e2b-api
      containers:
      - name: api
        image: e2b/api:latest
        args: ["--port", "3000"]
        ports:
        - name: http
          containerPort: 3000
        - name: grpc
          containerPort: 5009
        - name: pprof
          containerPort: 6060
        envFrom:
        - configMapRef:
            name: e2b-config
        env:
        - name: NODE_ID
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POSTGRES_CONNECTION_STRING
          valueFrom:
            secretKeyRef:
              name: e2b-secrets
              key: POSTGRES_CONNECTION_STRING
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: e2b-secrets
              key: REDIS_URL
        - name: ADMIN_TOKEN
          valueFrom:
            secretKeyRef:
              name: e2b-secrets
              key: ADMIN_TOKEN
        - name: VOLUME_TOKEN_ISSUER
          valueFrom:
            secretKeyRef:
              name: e2b-secrets
              key: VOLUME_TOKEN_ISSUER
        - name: VOLUME_TOKEN_SIGNING_METHOD
          valueFrom:
            secretKeyRef:
              name: e2b-secrets
              key: VOLUME_TOKEN_SIGNING_METHOD
        - name: VOLUME_TOKEN_SIGNING_KEY
          valueFrom:
            secretKeyRef:
              name: e2b-secrets
              key: VOLUME_TOKEN_SIGNING_KEY
        - name: VOLUME_TOKEN_SIGNING_KEY_NAME
          valueFrom:
            secretKeyRef:
              name: e2b-secrets
              key: VOLUME_TOKEN_SIGNING_KEY_NAME
        resources:
          requests:
            cpu: "500m"
            memory: "512Mi"
          limits:
            cpu: "2"
            memory: "2Gi"
        livenessProbe:
          httpGet:
            path: /health
            port: http
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: http
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: e2b-api
  namespace: e2b
spec:
  selector:
    app: e2b-api
  ports:
  - name: http
    port: 80
    targetPort: http
  - name: grpc
    port: 5009
    targetPort: grpc
  type: ClusterIP
```

### 4.5 Client Proxy Deployment

```yaml
# client-proxy-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: e2b-client-proxy
  namespace: e2b
  labels:
    app: e2b-client-proxy
spec:
  replicas: 2
  selector:
    matchLabels:
      app: e2b-client-proxy
  template:
    metadata:
      labels:
        app: e2b-client-proxy
    spec:
      containers:
      - name: client-proxy
        image: e2b/client-proxy:latest
        ports:
        - name: proxy
          containerPort: 3002
        - name: health
          containerPort: 3003
        envFrom:
        - configMapRef:
            name: e2b-config
        env:
        - name: NODE_ID
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: e2b-secrets
              key: REDIS_URL
        - name: API_INTERNAL_GRPC_ADDRESS
          value: "e2b-api:5009"
        - name: API_EDGE_GRPC_ADDRESS
          value: "e2b-api:5109"
        resources:
          requests:
            cpu: "250m"
            memory: "256Mi"
          limits:
            cpu: "1"
            memory: "1Gi"
        livenessProbe:
          httpGet:
            path: /
            port: health
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: health
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: e2b-client-proxy
  namespace: e2b
spec:
  selector:
    app: e2b-client-proxy
  ports:
  - name: proxy
    port: 3002
    targetPort: proxy
  type: ClusterIP
```

### 4.6 Orchestrator DaemonSet

```yaml
# orchestrator-daemonset.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: e2b-orchestrator
  namespace: e2b
  labels:
    app: e2b-orchestrator
spec:
  selector:
    matchLabels:
      app: e2b-orchestrator
  template:
    metadata:
      labels:
        app: e2b-orchestrator
    spec:
      hostNetwork: true
      hostPID: true
      dnsPolicy: ClusterFirstWithHostNet
      serviceAccountName: e2b-orchestrator
      tolerations:
      - operator: Exists
      nodeSelector:
        e2b-orchestrator: "true"
      initContainers:
      - name: setup-modules
        image: busybox
        command:
        - sh
        - -c
        - |
          modprobe nbd nbds_max=256
          modprobe tun
          echo 1 > /proc/sys/vm/unprivileged_userfaultfd
          sysctl -w vm.nr_hugepages=2048
        securityContext:
          privileged: true
      containers:
      - name: orchestrator
        image: e2b/orchestrator:latest
        ports:
        - name: grpc
          containerPort: 5008
          hostPort: 5008
        - name: proxy
          containerPort: 5007
          hostPort: 5007
        envFrom:
        - configMapRef:
            name: e2b-config
        env:
        - name: NODE_ID
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: NODE_IP
          valueFrom:
            fieldRef:
              fieldPath: status.hostIP
        - name: TEMPLATE_BUCKET_NAME
          valueFrom:
            secretKeyRef:
              name: e2b-secrets
              key: TEMPLATE_BUCKET_NAME
        - name: BUILD_CACHE_BUCKET_NAME
          valueFrom:
            secretKeyRef:
              name: e2b-secrets
              key: BUILD_CACHE_BUCKET_NAME
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: e2b-secrets
              key: REDIS_URL
        - name: ORCHESTRATOR_BASE_PATH
          value: "/var/lib/e2b/orchestrator"
        - name: SANDBOX_DIR
          value: "/var/lib/e2b/fc-vm"
        - name: HOST_KERNELS_DIR
          value: "/var/lib/e2b/fc-kernels"
        - name: FIRECRACKER_VERSIONS_DIR
          value: "/var/lib/e2b/fc-versions"
        - name: HOST_ENVD_PATH
          value: "/var/lib/e2b/fc-envd/envd"
        securityContext:
          privileged: true
        volumeMounts:
        - name: e2b-data
          mountPath: /var/lib/e2b
        - name: dev
          mountPath: /dev
        - name: hugepages
          mountPath: /dev/hugepages
        - name: modules
          mountPath: /lib/modules
          readOnly: true
        resources:
          requests:
            cpu: "1"
            memory: "2Gi"
          limits:
            cpu: "4"
            memory: "8Gi"
      volumes:
      - name: e2b-data
        hostPath:
          path: /var/lib/e2b
          type: DirectoryOrCreate
      - name: dev
        hostPath:
          path: /dev
      - name: hugepages
        hostPath:
          path: /dev/hugepages
      - name: modules
        hostPath:
          path: /lib/modules
```

### 4.7 Redis 接入（单端点或 Cluster）

`2026.28` 的应用侧 Redis 客户端只支持两类连接：

- `REDIS_URL=host:port`：单 Redis 端点。生产环境可在 Redis 主从前放 HAProxy/VIP/云 LB，让应用始终连接当前主节点。
- `REDIS_CLUSTER_URL=host1:port,host2:port`：Redis Cluster 端点列表。

不要把 Sentinel 的 `26379` 端口配置给应用。Sentinel 可以作为 Redis 主从选主和运维查询机制，但应用前面仍需要单一 `host:port` 入口。下面的清单是最小 StatefulSet 示例；生产高可用建议使用 Redis Operator、云托管 Redis，或 Redis 主从 + HAProxy/VIP。

```yaml
# redis-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  namespace: e2b
spec:
  serviceName: redis-headless
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
          name: redis
        command: ["redis-server", "--appendonly", "yes", "--maxmemory", "2gb"]
        volumeMounts:
        - name: data
          mountPath: /data
        resources:
          requests:
            cpu: "500m"
            memory: "2Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: fast-ssd
      resources:
        requests:
          storage: 20Gi
---
apiVersion: v1
kind: Service
metadata:
  name: redis-headless
  namespace: e2b
spec:
  selector:
    app: redis
  ports:
  - port: 6379
    targetPort: 6379
  clusterIP: None
---
apiVersion: v1
kind: Service
metadata:
  name: redis-primary
  namespace: e2b
spec:
  selector:
    app: redis
  ports:
  - port: 6379
    targetPort: 6379
```

### 4.8 PostgreSQL (主从复制)

```yaml
# postgres-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: e2b
spec:
  serviceName: postgres
  replicas: 3
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:17-alpine
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_USER
          value: "e2b"
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: password
        - name: POSTGRES_DB
          value: "e2b"
        - name: PGDATA
          value: "/var/lib/postgresql/data/pgdata"
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: fast-ssd
      resources:
        requests:
          storage: 100Gi
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: e2b
spec:
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
  clusterIP: None
```

### 4.9 Ingress

```yaml
# ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: e2b-ingress
  namespace: e2b
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - api.e2b.your-domain.com
    - sandbox.e2b.your-domain.com
    secretName: e2b-tls
  rules:
  - host: api.e2b.your-domain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: e2b-api
            port:
              number: 80
  - host: "*.sandbox.e2b.your-domain.com"
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: e2b-client-proxy
            port:
              number: 3002
```

### 4.10 ServiceAccount & RBAC

```yaml
# rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: e2b-api
  namespace: e2b
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: e2b-orchestrator
  namespace: e2b
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: e2b-orchestrator
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: e2b-orchestrator
subjects:
- kind: ServiceAccount
  name: e2b-orchestrator
  namespace: e2b
roleRef:
  kind: ClusterRole
  name: e2b-orchestrator
  apiGroup: rbac.authorization.k8s.io
```

---

## 5. 配置管理

### 5.1 环境变量汇总

```bash
# === 必需配置 ===

# 数据库
POSTGRES_CONNECTION_STRING=postgresql://e2b:password@postgres:5432/e2b

# Redis
# 单端点模式：指向 Redis 主节点前面的 Service / HAProxy / VIP
REDIS_URL=redis-primary:6379
# 或 Cluster 模式：逗号分隔多个节点
# REDIS_CLUSTER_URL=redis-node-1:6379,redis-node-2:6379,redis-node-3:6379

# 模板存储
TEMPLATE_BUCKET_NAME=e2b-templates
BUILD_CACHE_BUCKET_NAME=e2b-build-cache
STORAGE_PROVIDER=GCPBucket  # 或 AWSBucket

# === K8s 特定配置 ===

# 服务发现
SERVICE_DISCOVERY_PROVIDER=kubernetes
K8S_NAMESPACE=e2b
K8S_ORCHESTRATOR_POD_LABEL_SELECTOR=app.kubernetes.io/name=orchestrator
K8S_TEMPLATE_MANAGER_POD_LABEL_SELECTOR=app.kubernetes.io/name=template-manager

# IP 槽位存储（避免使用 Consul）
USE_LOCAL_NAMESPACE_STORAGE=true

# === 可选配置 ===

# 认证 provider
AUTH_PROVIDER_CONFIG='{"jwt":[]}'
ADMIN_TOKEN=xxx
ORY_SDK_URL=https://your-ory.example.com
ORY_PROJECT_API_TOKEN=xxx
ORY_ISSUER_URL=https://your-ory.example.com

# Volume Token
VOLUME_TOKEN_ISSUER=e2b.your-domain.com
VOLUME_TOKEN_SIGNING_METHOD=ES256
VOLUME_TOKEN_SIGNING_KEY=ECDSA:base64-key
VOLUME_TOKEN_SIGNING_KEY_NAME=prod-2024

# 监控
CLICKHOUSE_CONNECTION_STRING=clickhouse://...
LOKI_URL=http://loki:3100
```

### 5.2 Secret 管理建议

```bash
# 使用 kubectl 创建 secret
kubectl create secret generic e2b-secrets \
  --namespace e2b \
  --from-literal=POSTGRES_CONNECTION_STRING="postgresql://..." \
  --from-literal=REDIS_URL="redis-primary:6379" \
  --from-literal=ADMIN_TOKEN="$(openssl rand -hex 32)"

# 或使用 Sealed Secrets / External Secrets Operator
```

---

## 6. 网络与存储

### 6.1 网络策略

```yaml
# network-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: e2b-network-policy
  namespace: e2b
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - port: 3000
    - port: 3002
  - from:
    - podSelector: {}
  egress:
  - to:
    - podSelector: {}
  - to:
    - namespaceSelector: {}
    ports:
    - port: 53
      protocol: UDP
    - port: 53
      protocol: TCP
  - to:
    ports:
    - port: 443
    - port: 80
```

### 6.2 模板存储选项

```yaml
# 选项 1: 使用 NFS (推荐用于私有化)
apiVersion: v1
kind: PersistentVolume
metadata:
  name: e2b-templates
spec:
  capacity:
    storage: 500Gi
  accessModes:
  - ReadWriteMany
  nfs:
    server: nfs-server.example.com
    path: /exports/e2b-templates

---
# 选项 2: 使用 MinIO (S3 兼容对象存储)
# 配置 STORAGE_PROVIDER=Local 和 LOCAL_TEMPLATE_STORAGE_BASE_PATH
```

---

## 7. 监控与日志

### 7.1 可选组件部署

```yaml
# clickhouse-statefulset.yaml (可选)
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: clickhouse
  namespace: e2b
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: clickhouse
        image: clickhouse/clickhouse-server:25-alpine
        ports:
        - containerPort: 8123
        - containerPort: 9000
        volumeMounts:
        - name: data
          mountPath: /var/lib/clickhouse
```

### 7.2 Grafana + Loki (可选)

```bash
# 使用 Helm 部署
helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki -n e2b
helm install grafana grafana/grafana -n e2b
```

---

## 8. 高可用配置

### 8.1 Pod 反亲和性

```yaml
# 在 Deployment spec.template.spec 中添加
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values:
            - e2b-api
        topologyKey: kubernetes.io/hostname
```

### 8.2 HPA 自动扩缩容

```yaml
# api-hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: e2b-api-hpa
  namespace: e2b
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: e2b-api
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

### 8.3 PDB (Pod Disruption Budget)

```yaml
# pdb.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: e2b-api-pdb
  namespace: e2b
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: e2b-api
```

---

## 部署步骤

```bash
# 1. 创建 namespace
kubectl apply -f namespace.yaml

# 2. 创建 RBAC
kubectl apply -f rbac.yaml

# 3. 创建 ConfigMap 和 Secret
kubectl apply -f configmap.yaml
kubectl create secret generic e2b-secrets --namespace e2b \
  --from-literal=POSTGRES_CONNECTION_STRING="..." \
  --from-literal=REDIS_URL="..." \
  --from-literal=ADMIN_TOKEN="..."

# 4. 部署数据层
kubectl apply -f redis-statefulset.yaml
kubectl apply -f postgres-statefulset.yaml

# 5. 等待数据库就绪
kubectl wait --for=condition=ready pod -l app=redis -n e2b --timeout=120s
kubectl wait --for=condition=ready pod -l app=postgres -n e2b --timeout=120s

# 6. 运行数据库迁移
kubectl run migration --rm -it --namespace e2b \
  --image=e2b/api:latest \
  --env="POSTGRES_CONNECTION_STRING=..." \
  -- ./migrate

# 7. 部署应用层
kubectl apply -f api-deployment.yaml
kubectl apply -f client-proxy-deployment.yaml
kubectl apply -f orchestrator-daemonset.yaml

# 8. 部署 Ingress
kubectl apply -f ingress.yaml

# 9. 验证部署
kubectl get pods -n e2b
kubectl logs -f deployment/e2b-api -n e2b
```

---

*文档同步至上游 e2b-dev/infra 仓库 tag 2026.28*
