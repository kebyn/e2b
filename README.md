# E2B Infra 私有化部署文档

本仓库是 `e2b-dev/infra` 的中文私有化部署文档壳。根目录只保留仓库入口、元文件、上游子模块和少量增强部署资产；中文部署分析、运行手册和参考文档统一维护在 `docs/` 子目录。上游工程源码、IaC、CI、OpenAPI、脚本、测试和英文开发文档都以 `infra/` Git submodule 为准。

当前事实基线固定为上游正式标签 `2026.28`，提交 `fda7bef1095afb909197e272c0a8a123797f0bfb`。中文文档中的当前行为均应能由该子模块中的源码、英文文档、环境模板、部署定义或 migration 验证；上游滚动分支不作为当前文档依据。

## 初始化

克隆后先拉取子模块：

```bash
git submodule update --init --recursive
```

需要执行上游工程命令时进入子模块：

```bash
cd infra
```

也可以在根目录显式引用子模块路径，例如：

```bash
make -C infra/packages/db migrate
```

## 仓库边界

根目录保留：

- `README.md`、`AGENTS.md`、`LICENSE`、`.gitmodules`
- `docs/` 中文文档目录
- `ansible/`、`daytona-k8s/` 等本地增强部署资产目录
- `infra/` 子模块指针

上游工程内容直接从 `infra/` 引用：

- 源码和二进制构建：`infra/packages/`
- Terraform、Nomad job 和云资源定义：`infra/iac/`
- OpenAPI 规范：`infra/spec/`
- GitHub Actions 和代码质量配置：`infra/.github/`
- 脚本、测试、Grafana、fixtures：`infra/scripts/`、`infra/tests/`、`infra/grafana/`、`infra/fixtures/`
- 英文开发文档：`infra/self-host.md`、`infra/DEV-LOCAL.md`、`infra/DEV.md`、`infra/CONTRIBUTING.md`、`infra/CLAUDE.md`

不要把子模块中的英文文档复制到根仓库。更新上游版本时，应先移动 `infra/` gitlink，再按固定提交审计中文文档，保证源码和文档使用同一事实基线。

## 阅读导航

### 上游官方文档

- 官方 Terraform 云部署路径：[`infra/self-host.md`](./infra/self-host.md)
- 本地开发环境：[`infra/DEV-LOCAL.md`](./infra/DEV-LOCAL.md)
- 上游开发说明：[`infra/DEV.md`](./infra/DEV.md)
- 贡献说明：[`infra/CONTRIBUTING.md`](./infra/CONTRIBUTING.md)

### 私有化部署

- 不修改代码完整私有化部署：[`docs/deployment/不修改代码完整部署指南.md`](./docs/deployment/不修改代码完整部署指南.md#阅读导航)
- 不修改代码高可用部署：[`docs/deployment/不修改代码高可用部署方案.md`](./docs/deployment/不修改代码高可用部署方案.md#5-高可用验证)
- Kubernetes 私有化部署：[`docs/deployment/K8s私有化部署指南.md`](./docs/deployment/K8s私有化部署指南.md#阅读导航)
- Ansible 部署：[`docs/deployment/Ansible部署指南.md`](./docs/deployment/Ansible部署指南.md)

### 参考与架构

- 启动参数和环境变量：[`docs/reference/启动参数详解.md`](./docs/reference/启动参数详解.md#阅读导航)
- 核心组件职责：[`docs/architecture/核心组件详解.md`](./docs/architecture/核心组件详解.md#阅读导航)
- 私有化组件取舍：[`docs/architecture/私有化部署组件分析.md`](./docs/architecture/私有化部署组件分析.md#阅读导航)
- Feature Flags / LaunchDarkly 私有化：[`docs/feature-flags/FeatureFlags私有化部署方案.md`](./docs/feature-flags/FeatureFlags私有化部署方案.md#1-阅读导航)

### 上游同步与 Daytona

- 上游 `2026.17` 到 `2026.28` 同步影响：[`docs/upstream/上游同步说明-2026.17-to-2026.28.md`](./docs/upstream/上游同步说明-2026.17-to-2026.28.md)
- AI Agent Sandbox 产品对比：[`docs/daytona/sandbox-detailed-comparison.md`](./docs/daytona/sandbox-detailed-comparison.md)
- Daytona Kubernetes 部署：[`docs/daytona/k8s-production-deployment.md`](./docs/daytona/k8s-production-deployment.md)

## 路径约定

根目录文档中出现的上游源码路径均以 `infra/` 开头。示例：

- `infra/packages/api/internal/cfg/model.go`
- `infra/iac/provider-gcp/`
- `infra/spec/openapi.yml`
- `infra/.github/workflows/pr-tests.yml`

如果某条命令必须在 Go module、Terraform module 或上游脚本所在目录执行，文档会显式写出 `cd infra` 或使用 `make -C infra/...`。
