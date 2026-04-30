# E2B Kubernetes 私有化部署完整指南

---

## 目录

1. [架构概述](#1-架构概述)
2. [前置条件](#2-前置条件)
3. [代码改造方案](#3-代码改造方案)
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
│  │  │  (Sentinel)  │  │   (HA)       │  │  (可选)      │              │   │
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
| Redis | StatefulSet | 3 | Sentinel 或 Cluster 模式 |
| PostgreSQL | StatefulSet | 3 | 主从复制 + 连接池 |
| ClickHouse | StatefulSet | 1+ | 可选，用于指标存储 |

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

## 3. 代码改造方案

### 3.1 新增 K8s 服务发现

创建文件：`packages/api/internal/clusters/discovery/kubernetes.go`

```go
package discovery

import (
    "context"
    "fmt"

    "github.com/google/uuid"
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "k8s.io/client-go/kubernetes"
    "k8s.io/client-go/rest"

    "github.com/e2b-dev/infra/packages/shared/pkg/consts"
)

type K8sServiceDiscovery struct {
    clientset *kubernetes.Clientset
    clusterID uuid.UUID
    namespace string
    labelSelector string
}

func NewK8sServiceDiscovery(clusterID uuid.UUID, namespace string) (*K8sServiceDiscovery, error) {
    config, err := rest.InClusterConfig()
    if err != nil {
        return nil, fmt.Errorf("failed to get in-cluster config: %w", err)
    }

    clientset, err := kubernetes.NewForConfig(config)
    if err != nil {
        return nil, fmt.Errorf("failed to create k8s client: %w", err)
    }

    return &K8sServiceDiscovery{
        clientset:     clientset,
        clusterID:     clusterID,
        namespace:     namespace,
        labelSelector: "app=e2b-orchestrator",
    }, nil
}

func (sd *K8sServiceDiscovery) Query(ctx context.Context) ([]Item, error) {
    pods, err := sd.clientset.CoreV1().Pods(sd.namespace).List(ctx, metav1.ListOptions{
        LabelSelector: sd.labelSelector,
        FieldSelector: "status.phase=Running",
    })
    if err != nil {
        return nil, fmt.Errorf("failed to list orchestrator pods: %w", err)
    }

    result := make([]Item, 0, len(pods.Items))
    for _, pod := range pods.Items {
        if pod.Status.PodIP == "" {
            continue
        }

        result = append(result, Item{
            UniqueIdentifier:     string(pod.UID),
            NodeID:               pod.Spec.NodeName,
            InstanceID:           pod.Name,
            LocalIPAddress:       pod.Status.PodIP,
            LocalInstanceApiPort: consts.OrchestratorAPIPort,
        })
    }

    return result, nil
}
```

### 3.2 修改配置模型

修改文件：`packages/api/internal/cfg/model.go`

```go
// 新增服务发现配置
type ServiceDiscoveryConfig struct {
    // k8s, static, redis, nomad
    Provider string `env:"SERVICE_DISCOVERY_PROVIDER" envDefault:"k8s"`
    
    // K8s 配置
    K8sNamespace string `env:"K8S_NAMESPACE" envDefault:"e2b"`
    
    // 静态配置文件路径
    StaticConfigPath string `env:"STATIC_CONFIG_PATH"`
}

type Config struct {
    // ... 现有字段 ...
    
    ServiceDiscovery ServiceDiscoveryConfig
}
```

### 3.3 修改 Orchestrator 启动逻辑

修改文件：`packages/api/internal/orchestrator/orchestrator.go`

```go
func New(...) (*Orchestrator, error) {
    // ... 现有代码 ...

    // 修改节点发现逻辑
    var nodeDiscovery Discovery
    switch config.ServiceDiscovery.Provider {
    case "k8s":
        nodeDiscovery, err = discovery.NewK8sServiceDiscovery(
            consts.LocalClusterID,
            config.ServiceDiscovery.K8sNamespace,
        )
    case "static":
        nodeDiscovery, err = discovery.NewStaticDiscovery(
            config.ServiceDiscovery.StaticConfigPath,
        )
    case "redis":
        nodeDiscovery, err = discovery.NewRedisDiscovery(redisClient)
    default:
        // 原有 Nomad 逻辑
        nodeDiscovery = discovery.NewLocalDiscovery(...)
    }

    // ... 后续代码 ...
}
```

### 3.4 修改 Consul 依赖

修改文件：`packages/orchestrator/internal/sandbox/network/storage.go`

```go
type StorageType string

const (
    StorageTypeLocal StorageType = "local"
    StorageTypeRedis StorageType = "redis"
    StorageTypeConsul StorageType = "consul"  // 保留向后兼容
)

func newStorage(ctx context.Context, nodeID string, config Config) (Storage, error) {
    storageType := GetEnv("IP_SLOT_STORAGE", "local")
    
    switch StorageType(storageType) {
    case StorageTypeRedis:
        redisURL := GetEnv("REDIS_URL", "")
        if redisURL == "" {
            return nil, fmt.Errorf("REDIS_URL is required for redis storage")
        }
        return NewStorageRedis(redisURL, nodeID, config)
    case StorageTypeLocal:
        return NewStorageLocal(ctx, config)
    default:
        // 原有 Consul 逻辑（向后兼容）
        return NewStorageKV(nodeID, config)
    }
}
```

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
  SERVICE_DISCOVERY_PROVIDER: "k8s"
  K8S_NAMESPACE: "e2b"
  IP_SLOT_STORAGE: "local"
  SANDBOX_STORAGE_BACKEND: "redis"
  
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
  
  # Redis
  REDIS_URL: "redis:6379"
  
  # 认证（可选）
  SUPABASE_JWT_SECRETS: ""
  ADMIN_TOKEN: "your-admin-token"
  
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
        - name: API_GRPC_ADDRESS
          value: "e2b-api:5009"
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

### 4.7 Redis (Sentinel 模式)

```yaml
# redis-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  namespace: e2b
spec:
  serviceName: redis
  replicas: 3
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
  name: redis
  namespace: e2b
spec:
  selector:
    app: redis
  ports:
  - port: 6379
    targetPort: 6379
  clusterIP: None
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
REDIS_URL=redis:6379

# 模板存储
TEMPLATE_BUCKET_NAME=e2b-templates
BUILD_CACHE_BUCKET_NAME=e2b-build-cache
STORAGE_PROVIDER=GCPBucket  # 或 AWSBucket

# === K8s 特定配置 ===

# 服务发现
SERVICE_DISCOVERY_PROVIDER=k8s
K8S_NAMESPACE=e2b

# IP 槽位存储（避免使用 Consul）
IP_SLOT_STORAGE=local

# Sandbox 存储后端
SANDBOX_STORAGE_BACKEND=redis

# === 可选配置 ===

# 认证
SUPABASE_JWT_SECRETS=xxx
ADMIN_TOKEN=xxx

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
  --from-literal=REDIS_URL="redis:6379" \
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

*文档同步至上游 e2b-dev/infra 仓库 upstream/main (2026.17+13)*
