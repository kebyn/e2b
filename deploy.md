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
- Do **not** start here; use [`self-host.md`](./self-host.md) or [`不修改代码完整部署指南.md`](./不修改代码完整部署指南.md)

### If you want a quick local / experimental bootstrap
- Use this file as a scratchpad sequence

### If you want a maintained local development workflow
- Use [`DEV-LOCAL.md`](./DEV-LOCAL.md)

---

## What this file is for

Use this note only when you want to:

- bootstrap a quick local / single-machine environment
- replay a previously tested operator command sequence
- adapt commands manually for debugging or experiments

It is intentionally not exhaustive, and it may lag behind the canonical docs.

---

## Example ad-hoc bootstrap sequence

```bash
modprobe nbd nbds_max=64 && sysctl -w vm.nr_hugepages=2048
apt install -y make golang unzip

cd ~/
curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz && tar -xvf google-cloud-cli-linux-x86_64.tar.gz
./google-cloud-sdk/install.sh --quiet --usage-reporting false --path-update true && . ~/.bashrc

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

git clone https://github.com/e2b-dev/infra.git
cd ~/infra/
git switch --detach 2026.10
make download-public-kernels download-public-firecrackers
make -C packages/api build && make -C packages/orchestrator build-local && make -C packages/client-proxy build && make -C packages/envd build

export POSTGRES_CONNECTION_STRING="postgresql://postgres:postgres@127.0.0.1:5432/postgres?sslmode=disable"

# Generate ClickHouse config before migrate-local
cd packages/local-dev && USERNAME=clickhouse PASSWORD=clickhouse PORT=9000 envsubst < ../clickhouse/local/config.tpl.xml > clickhouse-config-generated.xml && cd ~/infra

docker compose --file ./packages/local-dev/docker-compose.yaml up --detach
docker compose --file ./packages/local-dev/docker-compose.yaml logs -f
# Ctrl+C after logs are healthy, then continue
make -C packages/db migrate
make -C packages/local-dev seed-database
make -C packages/clickhouse migrate-local
```

---

## Maintenance note

If this file diverges from reality, prefer updating or removing commands here rather than treating it as a source of truth. The canonical docs are [`self-host.md`](./self-host.md), [`DEV-LOCAL.md`](./DEV-LOCAL.md), and [`不修改代码完整部署指南.md`](./不修改代码完整部署指南.md).
