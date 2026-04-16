# E2B Ansible 部署指南

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
    └── nginx/                     # Nginx 负载均衡
```

## 前置条件

1. **控制节点**: 安装 Ansible 2.9+
2. **目标节点**: Ubuntu 22.04+, SSH 免密登录
3. **二进制文件**: `packages/*/bin/` 目录下已有编译好的二进制

## 快速开始

### 1. 修改配置

```bash
# 编辑主机清单
vim ansible/inventories/production/hosts.ini

# 编辑全局变量
vim ansible/inventories/production/group_vars/all.yml
```

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
| PostgreSQL | `postgresql` | ✅ | 主从复制 |
| Redis | `redis` | ✅ | Sentinel 模式 |
| Nomad | `nomad` | ✅ | 服务器+客户端 |
| API | `api` | ✅ | HTTP/gRPC 接口 |
| Client Proxy | `client-proxy` | ✅ | 流量代理 |
| Orchestrator | `orchestrator` | ✅ | Sandbox 管理 |
| Template Manager | `template-manager` | ⚠️ | 模板构建 |
| Dashboard API | `dashboard-api` | ⚠️ | Web 管理后端 |
| Dashboard | `dashboard` | ⚠️ | Web 管理前端 |
| Nginx | `nginx` | ✅ | 负载均衡 |

## 可选组件

在 `group_vars/all.yml` 中配置:

```yaml
# 启用 Dashboard (需要先配置 Supabase)
dashboard_enabled: true
supabase_url: "https://your-project.supabase.co"
supabase_anon_key: "your-anon-key"

# 启用 Template Manager
template_manager_enabled: true

# 启用 ClickHouse
clickhouse_enabled: true

# 启用 Loki
loki_enabled: true
```

## 清理

```bash
ansible-playbook -i inventories/production/hosts.ini playbooks/cleanup.yml
```

**警告**: 清理会停止所有服务并删除数据。
