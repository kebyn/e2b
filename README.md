![E2B Infra Preview Light](/readme-assets/infra-light.png#gh-light-mode-only)
![E2B Infra Preview Dark](/readme-assets/infra-dark.png#gh-dark-mode-only)

# E2B Infrastructure

[E2B](https://e2b.dev) is an open-source infrastructure for AI code interpreting. In our main repository [e2b-dev/e2b](https://github.com/e2b-dev/E2B) we are giving you SDKs and CLI to customize and manage environments and run your AI agents in the cloud.

This repository contains the infrastructure that powers the E2B platform.

## Reading guide

Start here depending on what you need:

- **Self-host E2B on a cloud provider** → [`self-host.md`](./self-host.md)
- **Run an ad-hoc local / experimental bootstrap** → [`deploy.md`](./deploy.md)
- **Understand the main infrastructure components** → [`核心组件详解.md`](./核心组件详解.md)
- **Decide which components are required in private deployments** → [`私有化部署组件分析.md`](./私有化部署组件分析.md)
- **Look up runtime configuration and environment variables** → [`启动参数详解.md`](./启动参数详解.md)
- **See feature flags and private alternatives** → [`FeatureFlags私有化部署方案.md`](./FeatureFlags私有化部署方案.md)
- **Follow the no-code production deployment path** → [`不修改代码完整部署指南.md`](./不修改代码完整部署指南.md)
- **Do HA validation and failover drills** → [`不修改代码高可用部署方案.md`](./不修改代码高可用部署方案.md)

## Repository scope

This repo is the infrastructure layer for E2B, including:

- Terraform / cloud provisioning
- Nomad-based workload orchestration
- API, Client Proxy, Orchestrator, Template Manager
- storage, observability, and deployment tooling

## Self-hosting

Read the [self-hosting guide](./self-host.md) to learn how to set up the infrastructure on your own. The infrastructure is deployed using Terraform.

Supported cloud providers:
- 🟢 GCP
- 🟢 AWS (Beta)
- [ ] Azure
- [ ] General linux machine
