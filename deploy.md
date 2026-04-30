# Deploy Notes (local / ad-hoc)

> This file is **an ad-hoc operator note**, not the canonical deployment guide.
>
> Related docs:
> - [`README.md`](./README.md): repo entrypoint
> - [`self-host.md`](./self-host.md): official cloud self-hosting flow
> - [`不修改代码完整部署指南.md`](./不修改代码完整部署指南.md): manual production deployment path
> - [`DEV-LOCAL.md`](./DEV-LOCAL.md): local development setup

---

## Reading guide

### If you want the supported production path
- Do **not** start here; use [`self-host.md`](./self-host.md#reading-guide) or [`不修改代码完整部署指南.md`](./不修改代码完整部署指南.md#阅读导航)

### If you want a quick local / experimental bootstrap
- Use this file as a scratchpad sequence

### If you want a maintained local development workflow
- Use [`DEV-LOCAL.md`](./DEV-LOCAL.md#system-prep)

---

## What this file is for

Use this note only when you want to:

- bootstrap a quick local / single-machine environment
- replay a previously tested operator command sequence
- adapt commands manually for debugging or experiments

It is intentionally not exhaustive, and it may lag behind the canonical docs.

---

## Data Layer Quick Start (Docker)

以下命令用于快速启动本地测试环境的数据层组件。适用于单节点快速测试场景。

### PostgreSQL

```bash
docker run -d --name postgres \
  -e POSTGRES_USER=e2b \
  -e POSTGRES_PASSWORD=password \
  -e POSTGRES_DB=e2b \
  -p 5432:5432 \
  -v postgres-data:/var/lib/postgresql/data \
  postgres:17-alpine

# 验证
docker exec postgres pg_isready -U e2b

# 连接串格式 (用于后续迁移和 API 启动)
# postgresql://e2b:password@127.0.0.1:5432/e2b?sslmode=disable
```

> **注意**: 此 Quick Start 创建的用户/数据库与下方迁移命令使用相同的连接串。如果使用其他 PostgreSQL 实例，请确保连接串中的用户名、密码、数据库一致。

### Redis

```bash
docker run -d --name redis \
  -p 6379:6379 \
  -v redis-data:/data \
  redis:7-alpine redis-server --appendonly yes --maxmemory 1gb

# 验证
docker exec redis redis-cli ping
```

### ClickHouse

```bash
docker run -d --name clickhouse \
  -p 8123:8123 -p 9000:9000 \
  -v clickhouse-data:/var/lib/clickhouse \
  --ulimit nofile=262144:262144 \
  clickhouse/clickhouse-server:25-alpine

# 验证
docker exec clickhouse clickhouse-client --query "SELECT version()"
```

### Loki

```bash
docker run -d --name loki \
  -p 3100:3100 \
  -v loki-data:/loki \
  grafana/loki:3.3.2 -config.file=/etc/loki/local-config.yaml

# 验证
docker exec loki wget -q --spider http://localhost:3100/ready && echo "OK"
```

> **完整部署方案**: 参见 [`不修改代码完整部署指南.md - 数据层`](./不修改代码完整部署指南.md#1-数据层)，包含原生部署、高可用配置、集群模式等详细方案。

---

## Example ad-hoc bootstrap sequence

> **注意**: 此序列使用 infra 仓库的 `packages/local-dev/docker-compose.yaml`，该文件启动以下服务：
> - PostgreSQL (端口 5432)
> - Redis (端口 6379)
> - ClickHouse (端口 9000/8123)
>
> **版本说明**: `git switch --detach 2026.10` 指定 E2B 版本，根据需要更新。

```bash
# === 系统准备 ===
modprobe nbd nbds_max=64 && sysctl -w vm.nr_hugepages=2048
apt install -y make golang unzip

# === GCloud CLI（可选，用于 GCP 部署）===
cd ~/
curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz && tar -xvf google-cloud-cli-linux-x86_64.tar.gz
./google-cloud-sdk/install.sh --quiet --usage-reporting false --path-update true && . ~/.bashrc

# === Nomad 安装 ===
cd ~/
wget https://releases.hashicorp.com/nomad/1.11.3/nomad_1.11.3_linux_amd64.zip
unzip nomad_1.11.3_linux_amd64.zip
rm -f LICENSE.txt nomad_1.11.3_linux_amd64.zip
mv nomad /usr/local/bin/
mkdir /data/nomad -pv
cat > /etc/systemd/system/nomad.service <<EOF
[Unit]
Description=nomad
Wants=network-online.target
After=network-online.target

[Service]
WorkingDirectory=/data/nomad
ExecStart=nomad agent -dev   -bind 0.0.0.0   -network-interface='{{ GetDefaultInterfaces | attr "name" }}'
Restart=always
RestartSec=10
CPUQuota=100%

[Install]
WantedBy=multi-user.target
EOF
systemctl enable --now nomad
systemctl status nomad

# === 获取 E2B 代码 ===
git clone https://github.com/e2b-dev/infra.git
cd ~/infra/
git switch --detach 2026.10  # 根据需要选择版本

# === 下载 Firecracker 组件 ===
make download-public-kernels download-public-firecrackers

# === 编译服务 ===
make -C packages/api build && make -C packages/orchestrator build-local && make -C packages/client-proxy build && make -C packages/envd build

# === 启动数据层 ===
# 使用 docker-compose 启动 PostgreSQL + Redis + ClickHouse
export POSTGRES_CONNECTION_STRING="postgresql://e2b:password@127.0.0.1:5432/e2b?sslmode=disable"
export REDIS_URL="redis://127.0.0.1:6379"
export LOKI_URL="http://127.0.0.1:3100"  # 如果使用单独启动的 Loki
export CLICKHOUSE_CONNECTION_STRING="clickhouse://clickhouse:clickhouse@127.0.0.1:9000/default"  # ClickHouse 迁移必需

# Generate ClickHouse config before migrate-local
cd packages/local-dev && USERNAME=clickhouse PASSWORD=clickhouse PORT=9000 envsubst < ../clickhouse/local/config.tpl.xml > clickhouse-config-generated.xml && cd ~/infra

docker compose --file ./packages/local-dev/docker-compose.yaml up --detach
docker compose --file ./packages/local-dev/docker-compose.yaml logs -f
# Ctrl+C after logs are healthy, then continue

# === 数据库迁移 ===
# 注意: 迁移命令依赖上方已设置的环境变量
make -C packages/db migrate
make -C packages/local-dev seed-database
make -C packages/clickhouse migrate-local
```

> **数据层替代方案**: 如果没有 infra 仓库的 docker-compose.yaml，可使用上文 [Data Layer Quick Start](#data-layer-quick-start-docker) 的单容器命令。

---

## Environment Variables (Quick Reference)

以下环境变量用于本地开发/测试环境的快速配置。

```bash
# === 必需变量 ===
export POSTGRES_CONNECTION_STRING="postgresql://e2b:password@127.0.0.1:5432/e2b?sslmode=disable"
export REDIS_URL="redis://127.0.0.1:6379"
export LOKI_URL="http://127.0.0.1:3100"

# === Volume Token（API 启动必需）===
export VOLUME_TOKEN_ISSUER="local.e2b.dev"
export VOLUME_TOKEN_SIGNING_METHOD="ES256"
export VOLUME_TOKEN_SIGNING_KEY="ECDSA:$(openssl ecparam -name prime256v1 -genkey -noout | base64 -w0)"
export VOLUME_TOKEN_SIGNING_KEY_NAME="local-dev"

# === 可选变量 ===
# 注意: CLICKHOUSE_CONNECTION_STRING 在迁移时需要设置，但在生产运行时可选（有 NoopClient 降级）
export CLICKHOUSE_CONNECTION_STRING="clickhouse://clickhouse:clickhouse@127.0.0.1:9000/default"
export ENVIRONMENT="local"
export NODE_ID="local-$(hostname)"

# === Nomad 配置（本地开发可省略）===
export NOMAD_ADDRESS="http://127.0.0.1:4646"
```

> **完整参数说明**: 参见 [`启动参数详解.md`](./启动参数详解.md)，包含所有服务的详细环境变量说明。

---

## Maintenance note

If this file diverges from reality, prefer updating or removing commands here rather than treating it as a source of truth. The canonical docs are [`self-host.md`](./self-host.md), [`DEV-LOCAL.md`](./DEV-LOCAL.md), and [`不修改代码完整部署指南.md`](./不修改代码完整部署指南.md).
