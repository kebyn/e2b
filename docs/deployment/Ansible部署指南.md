# E2B Ansible 部署指南

> 上游事实基线：`e2b-dev/infra` tag `2026.28`，commit `fda7bef1095afb909197e272c0a8a123797f0bfb`。`ansible/` 是本仓库增强资产，不属于上游子模块；其模板已按该提交的运行时契约核对。

## 目录结构

```
ansible/
├── inventories/
│   └── production/
│       ├── hosts.ini              # 主机清单
│       └── group_vars/
│           └── all.yml            # 全局变量
├── playbooks/
│   ├── deploy.yml                 # 主部署 Playbook
│   ├── verify.yml                 # 健康检查
│   └── cleanup.yml                # 清理
└── roles/
    ├── postgresql/                # PostgreSQL (必需)
    ├── redis/                     # Redis (必需)
    ├── nomad/                     # Nomad (必需)
    ├── api/                       # API 服务 (必需)
    ├── client-proxy/              # Client Proxy (必需)
    ├── orchestrator/              # Orchestrator (必需)
    ├── template-manager/          # Template Manager (可选)
    ├── dashboard-api/             # Dashboard API (可选)
    ├── dashboard/                 # Dashboard Frontend (可选、本地固定版本)
    └── nginx/                     # Nginx 负载均衡
```

## 前置条件

1. **控制节点**: 安装 `ansible-core` 2.15+（Redis 仓库任务使用 `deb822_repository`）
2. **目标节点**: Ubuntu 22.04+, SSH 免密登录
3. **二进制文件**: `infra/packages/*/bin/` 目录下已有编译好的二进制
4. **DNS**: 标准客户端在 `E2B_DOMAIN=<domain>` 下访问 `{port}-{sandboxID}.<domain>`；但当前 Ansible Nginx 模板的 Sandbox `server_name` 只有 `*.sandbox.<domain>`，默认资产并不承接这个标准 Host。可工作的外部入口必须同时接收 `{port}-{sandboxID}.<domain>` 和 `sandbox.<domain>`，保留原始 Host 以及 `E2b-Sandbox-Id`、`E2b-Sandbox-Port`，再转发到 Client Proxy；启用 Dashboard 时另需配置 `dashboard.<domain>` 与 `dashboard-api.<domain>`

Nomad Client 必须分成两个节点池。Orchestrator 使用 `default`，Template Manager 使用 `build`；两者的 gRPC 固定端口都是 `5008`，不能调度到同一主机。示例 inventory 已通过 `orchestrator`、`template_manager` 两个子组建立该隔离。

## 快速开始

以下命令默认从仓库根目录执行；运行 `ansible-playbook` 前进入 `ansible/` 资产目录。

### 1. 修改配置

```bash
# 编辑主机清单
vim ansible/inventories/production/hosts.ini

# 编辑全局变量
vim ansible/inventories/production/group_vars/all.yml
```

至少需要完成以下配置：

```yaml
postgres_password: "使用生产密码"
admin_token: "使用生产随机值"
sandbox_access_token_hash_seed: "使用独立的生产随机值"
volume_token_signing_key: "ECDSA:base64-private-key"

# 当前上游 Redis 客户端没有密码字段，只接受 host:port。
# 内置 Redis 必须保持空密码，并通过私网、防火墙或安全组限制访问。
redis_requirepass: ""
redis_url: "redis-vip.example.com:6379"

# 首次部署可留空，由 playbook bootstrap 并保存到 Nomad 主服务器；
# 已有集群也可以直接填写现有管理 Token。
nomad_token: ""
nomad_acl_token_file: /etc/nomad.d/e2b-management.token

# 直接使用内置 HTTP Nginx 时保持 http；由外部 LB/Ingress 终止 TLS 时改为 https。
public_url_scheme: http
```

首次 ACL bootstrap 得到的 Token 会以 root-only `0600` 权限保存在首台 Nomad Server。后续完整部署、按 tag 部署和验证 playbook 都会复用它；如果集群已初始化但该文件丢失，必须恢复文件或填写 `nomad_token`，playbook 不会尝试二次 bootstrap。

当前 Ansible Nginx 模板的 Sandbox `server_name` 只有 `*.sandbox.<domain>`。这既不会匹配 `sandbox.<domain>` 本身，也不会匹配标准客户端生成的 `{port}-{sandboxID}.<domain>`；因此现有资产不能直接承接标准 Host 寻址，也不只是缺少 `sandbox.<domain>` 这个共享入口。要提供可工作的外部入口，需由外部 LB/Nginx 同时接收 `{port}-{sandboxID}.<domain>` 和 `sandbox.<domain>`，保留原始 Host 与两个 routing Header，并将两类请求转发到 Client Proxy。这里记录的是资产边界，本次上游文档同步不修改 Ansible 模板。

`STORAGE_PROVIDER=Local` 只在单节点或共享文件系统上成立。多个 Orchestrator 或启用独立 Template Manager 时，应先把 `local_template_storage_base_path` 和 `local_build_cache_storage_base_path` 以 NFS 等方式挂载到所有相关节点的相同路径，再设置：

```yaml
local_storage_shared: true
```

未确认共享挂载时部署会提前失败，防止构建产物只落在某一台构建节点上。也可以改用 `GCPBucket` 或 `AWSBucket`。

PostgreSQL 17 由 playbook 配置官方 PGDG 仓库安装。`postgres_migration_enabled` 默认为 `true`，首台主库会使用与当前上游 `go.mod` 匹配的 Goose 执行 `infra/packages/db/migrations/`；只有在外部流程已经负责 migration 时才应关闭它。

### 2. 验证连接

```bash
cd ansible
ansible all -i inventories/production/hosts.ini -m ping
```

### 3. 部署

```bash
# 完整部署
ansible-playbook -i inventories/production/hosts.ini playbooks/deploy.yml

# 分步部署
ansible-playbook -i inventories/production/hosts.ini playbooks/deploy.yml --tags postgresql
ansible-playbook -i inventories/production/hosts.ini playbooks/deploy.yml --tags redis
ansible-playbook -i inventories/production/hosts.ini playbooks/deploy.yml --tags nomad
ansible-playbook -i inventories/production/hosts.ini playbooks/deploy.yml --tags api
ansible-playbook -i inventories/production/hosts.ini playbooks/deploy.yml --tags client-proxy
ansible-playbook -i inventories/production/hosts.ini playbooks/deploy.yml --tags orchestrator
ansible-playbook -i inventories/production/hosts.ini playbooks/deploy.yml --tags template-manager
ansible-playbook -i inventories/production/hosts.ini playbooks/deploy.yml --tags nginx
```

### 4. 验证部署

```bash
ansible-playbook -i inventories/production/hosts.ini playbooks/verify.yml
```

## 组件说明

| 组件 | Tag | 必需 | 说明 |
|------|-----|------|------|
| PostgreSQL | `postgresql` | ✅ | 流复制，不含自动选主 |
| Redis | `redis` | ✅ | 主从 + Sentinel；应用仍需稳定主端点 |
| Nomad | `nomad` | ✅ | 服务器+客户端 |
| API | `api` | ✅ | HTTP/gRPC 接口 |
| Client Proxy | `client-proxy` | ✅ | 流量代理 |
| Orchestrator | `orchestrator` | ✅ | Sandbox 管理 |
| Template Manager | `template-manager` | ⚠️ | 模板构建 |
| Dashboard API | `dashboard-api` | ⚠️ | Web 管理后端 |
| Dashboard | `dashboard` | ⚠️ | Web 管理前端 |
| Nginx | `nginx` | ✅ | 负载均衡 |

PostgreSQL role 不安装 Patroni、repmgr 等自动故障切换组件，默认连接串仍指向 inventory 中标记为 primary 的固定主机。Redis role 会安装 Sentinel，但 Nginx role 不为 Redis 提供 HAProxy/VIP，E2B 进程也不会查询 Sentinel。仅运行这些 role 不等于获得数据层自动 HA；生产环境必须另行提供稳定写端点和切换流程，并把 `postgres_connection_string`、`redis_url` 指向这些端点。

## 可选组件

在 `group_vars/all.yml` 中配置:

```yaml
# 启用 Dashboard API（需要先配置 Auth Provider/Ory）
dashboard_enabled: true
dashboard_install_method: source
dashboard_session_secret: "至少 32 字符的随机值"
auth_provider_config: '{"jwt":[{"issuer":{"url":"https://auth.example.com","audiences":["e2b-dashboard"],"audienceMatchPolicy":"MatchAny"},"cacheDuration":"30m"}]}'
ory_sdk_url: "https://ory.example.com"
ory_project_api_token: "your-ory-project-token"
ory_issuer_url: "https://auth.example.com"
dashboard_ory_oauth2_client_id: "dashboard-web-client"
dashboard_ory_oauth2_client_secret: "your-oauth-client-secret"
dashboard_ory_oauth2_cli_client_id: "e2b-cli-public-client"
dashboard_ory_oauth2_audience: "https://api.e2b.example.com"

# 启用 Template Manager
template_manager_enabled: true
template_manager_count: 1

# 私有化默认从 build 节点的 Docker daemon 读取构建镜像
artifacts_registry_provider: Local
local_artifacts_replicated: false

# 启用 ClickHouse
clickhouse_enabled: true

# 启用 Loki
loki_enabled: true
```

`clickhouse_enabled` 和 `loki_enabled` 只让服务模板引用 inventory 中 `[clickhouse]`、`[loki]` 组的外部地址。当前资产没有 ClickHouse 或 Loki 安装 role，也不会初始化它们；启用开关前必须自行部署这些服务。远端 ClickHouse 应使用实际连接串运行 migration，不能使用硬编码 `localhost:9000/default` 的 `migrate-local`：

```bash
GOOSE_DRIVER=clickhouse \
GOOSE_DBSTRING="$CLICKHOUSE_CONNECTION_STRING" \
go -C infra/packages/clickhouse tool goose \
  -table "_migrations" -dir migrations up
```

当前 Dashboard role 只实现 `source` 安装方式；配置其他值会在部署前失败。启用 Dashboard 时，Nginx 会分别暴露 `dashboard_domain` 和 `dashboard_api_domain`；Client Proxy 调用 API 的 internal gRPC 则通过 `api_domain:5009` 转发。请确保负载均衡节点的网络策略允许客户端代理访问 TCP `5009`。

Dashboard 的固定上游提交使用 Next.js 16 完整构建，构建节点至少需要 6 GiB 内存；role 会在下载依赖前校验该条件。Bun 版本按上游 `packageManager` 固定为 1.2.0，Dashboard commit 与 Bun 下载均固定，避免 `main` 分支漂移导致重复部署得到不同产物。

`artifacts_registry_provider: Local` 会在 Template Manager 节点安装并启动 Docker，且构建镜像必须已存在被调度节点的 Docker daemon 中，因此默认只运行一个实例。只有已把镜像同步到所有 build 节点时，才能提高 `template_manager_count` 并设置 `local_artifacts_replicated: true`。使用 GCP Artifact Registry 或 ECR 时，将 provider 改为 `GCP_ARTIFACTS` 或 `AWS_ECR`，并配置对应的云凭据和仓库参数。

PostgreSQL 副本默认只在尚未成为 standby 时执行 `pg_basebackup`。需要有意重建副本时临时设置 `postgres_replica_rebuild: true`，完成后立即恢复为 `false`。

playbook 会在 NBD 模块加载前写入 `nbds_max=256`并校验当前值。如果旧节点已以较小的上限加载了 NBD，部署会停止并要求在无运行 sandbox 时重载模块，或重启该节点。

## 本地回归检查

提交部署配置前可运行：

```bash
python3 -m unittest -v ansible.tests.test_private_deploy_templates
```

该测试会检查所有 playbook 语法、运行时模板、Nomad 节点池和服务注册、ACL Token 使用、产物目录、内部 gRPC 路由及 systemd 资源单位。

## 清理

```bash
ansible-playbook -i inventories/production/hosts.ini playbooks/cleanup.yml
```

**警告**: 清理会停止部署服务并删除 `e2b_base_dir` 下的运行时、模板和构建缓存。PostgreSQL、Redis 与 Nomad 的独立数据目录不会被删除。

---

*文档同步至上游 e2b-dev/infra 仓库 tag 2026.28，commit fda7bef1095afb909197e272c0a8a123797f0bfb*
