# AI Agent Sandbox 产品详细能力对比分析

## 规范

> **使用中文，先写规范再进行修改。**

- 本文档以 E2B 为基准，对各 Sandbox 产品进行全方位能力拆解
- 每个产品从 8 个维度详细分析：沙箱生命周期、代码执行、文件系统、网络与浏览器、开发工具、安全隔离、弹性扩展、生态集成
- 对比维度粒度细化到 API 级别

---

## 目录

1. [E2B（基准）详细能力分析](#1-e2b基准详细能力分析)
2. [Daytona 详细能力分析](#2-daytona-详细能力分析)
3. [OpenSandbox 详细能力分析](#3-opensandbox-详细能力分析)
4. [agent-infra/sandbox 详细能力分析](#4-agent-infrasandbox-详细能力分析)
5. [阿里云 Agent Sandbox 详细能力分析](#5-阿里云-agent-sandbox-详细能力分析)
6. [腾讯云 Agent Runtime 详细能力分析](#6-腾讯云-agent-runtime-详细能力分析)
7. [全维度能力对比矩阵](#7-全维度能力对比矩阵)
8. [API 能力逐项对比](#8-api-能力逐项对比)

---

## 1. E2B（基准）详细能力分析

### 1.1 沙箱生命周期管理

| 能力 | 详情 |
|------|------|
| **创建** | `Sandbox.create()` 支持指定 `timeout`（秒/毫秒）、`metadata`（自定义键值对） |
| **超时管理** | `setTimeout()` / `set_timeout()` 运行时动态调整超时 |
| **暂停/恢复** | 支持 `pause()` / `resume()`，暂停后状态持久化，可无限期保留 |
| **销毁** | `kill()` 立即销毁 |
| **信息查询** | `getInfo()` / `get_info()` 返回 sandboxId、templateId、metadata、startedAt、endAt |
| **最大运行时长** | Pro: 24小时，Base: 1小时（通过 pause/resume 可突破） |

### 1.2 代码执行

| 能力 | 详情 |
|------|------|
| **命令执行** | `sandbox.commands.run(cmd)` 返回 stdout/stderr/exitCode |
| **代码解释器** | `sandbox.runCode(code)` 支持 Python/JavaScript 等多语言 |
| **流式输出** | 支持 `on_stdout` / `on_stderr` 回调 |
| **超时控制** | 命令和代码执行均可指定 timeout |

### 1.3 文件系统

| 能力 | 详情 |
|------|------|
| **读取文件** | `sandbox.files.read()` |
| **写入文件** | `sandbox.files.write()` |
| **列出目录** | `sandbox.files.list()` |
| **上传文件** | 支持上传本地文件到沙箱 |
| **下载文件** | 支持从沙箱下载文件到本地 |

### 1.4 网络与浏览器

| 能力 | 详情 |
|------|------|
| **浏览器** | ❌ 不支持 |
| **VNC** | ❌ 不支持 |
| **端口暴露** | 通过 Desktop SDK 可选支持 |

### 1.5 开发工具

| 能力 | 详情 |
|------|------|
| **Git** | ❌ 无内置 Git API |
| **LSP** | ❌ 不支持 |
| **PTY** | ❌ 不支持 |
| **Jupyter** | 通过 Code Interpreter SDK 支持 |

### 1.6 安全隔离

| 能力 | 详情 |
|------|------|
| **隔离级别** | 容器级隔离 |
| **网络隔离** | 基础网络隔离 |
| **存储隔离** | 沙箱内独立文件系统 |

### 1.7 弹性扩展

| 能力 | 详情 |
|------|------|
| **创建速度** | 标准（秒级） |
| **并发能力** | 通过 API Key 配额限制 |
| **资源规格** | 固定规格，不可自定义 CPU/内存 |

### 1.8 生态集成

| 能力 | 详情 |
|------|------|
| **SDK** | Python, JavaScript/TypeScript |
| **自托管** | ✅ Terraform 部署（AWS/GCP/Azure） |
| **模板** | 支持自定义 Docker 模板 |
| **CI/CD** | GitHub Actions 集成 |
| **LLM 集成** | 官方 Cookbook 支持 OpenAI、Anthropic、LangChain 等 |

---

## 2. Daytona 详细能力分析

### 2.1 沙箱生命周期管理

| 能力 | 详情 |
|------|------|
| **创建** | `daytona.create()` 支持 `language`、`name`、`labels`、`resources`、`volumes` |
| **启动/停止** | `start()` / `stop()` 完整状态转换（Running → Stopped → Archived） |
| **归档** | `archive()` 文件系统移至对象存储，降低成本 |
| **恢复** | `recover()` 从错误状态恢复 |
| **删除** | `delete()` |
| **自动管理** | `autoStopInterval`（默认15分钟）、`autoArchiveInterval`（默认7天）、`autoDeleteInterval` |
| **无限运行** | `autoStopInterval=0` 禁用自动停止 |
| **临时沙箱** | `ephemeral=True` 停止后自动删除 |
| **动态调整资源** | `resize()` 运行中可增加 CPU/内存，停止后可调整磁盘 |

### 2.2 代码执行

| 能力 | 详情 |
|------|------|
| **代码运行** | `sandbox.process.codeRun(code)` 支持 Python/TypeScript/JavaScript |
| **命令执行** | `sandbox.process.executeCommand(cmd)` |
| **PTY 终端** | ✅ 伪终端支持，可运行交互式命令 |
| **日志流** | ✅ 实时日志流 |
| **语言指定** | 创建时通过 `language` 参数指定运行时 |

### 2.3 文件系统

| 能力 | 详情 |
|------|------|
| **列出文件** | `fs.listFiles(path)` 返回名称、是否目录、大小、修改时间 |
| **文件信息** | `fs.getFileDetails(path)` 返回权限、所有者、组、模式 |
| **创建目录** | `fs.createFolder(path, mode)` |
| **上传文件** | `fs.uploadFile()` / `fs.uploadFiles()` 支持批量 |
| **下载文件** | `fs.downloadFile()` / `fs.downloadFiles()` 支持批量 |
| **删除文件** | `fs.deleteFile(path)` 支持递归删除 |
| **文件权限** | `fs.setFilePermissions(path, {mode, owner, group})` |
| **查找文本** | `fs.findFiles(path, pattern)` 递归搜索文件内容 |
| **替换文本** | `fs.replaceInFiles(files, pattern, newValue)` 批量替换 |
| **移动/重命名** | `fs.moveFiles(source, destination)` |

### 2.4 Git 操作（独有）

| 能力 | 详情 |
|------|------|
| **克隆仓库** | `git.clone(url, path)` 支持认证、指定分支 |
| **仓库状态** | `git.status(path)` 当前分支、ahead/behind、文件状态 |
| **分支管理** | `git.createBranch()` / `git.checkoutBranch()` / `git.deleteBranch()` / `git.branches()` |
| **暂存** | `git.add(path, files)` |
| **提交** | `git.commit(path, message, author, email)` 支持 `allowEmpty` |
| **推送** | `git.push(path)` 支持认证 |
| **拉取** | `git.pull(path)` 支持认证 |

### 2.5 LSP 支持（独有）

| 能力 | 详情 |
|------|------|
| **创建 LSP 服务器** | `createLspServer(languageId, pathToProject)` |
| **支持语言** | Python, TypeScript |
| **代码补全** | `lsp.completions(path, position)` |
| **文件通知** | `lsp.didOpen()` / `lsp.didClose()` |
| **文档符号** | `lsp.documentSymbols(path)` |
| **沙箱符号** | `lsp.sandboxSymbols(query)` 全局搜索 |

### 2.6 网络与浏览器

| 能力 | 详情 |
|------|------|
| **VNC** | ✅ 支持 VNC 远程桌面 |
| **SSH** | ✅ SSH 访问 |
| **Web Terminal** | ✅ 浏览器内终端 |
| **预览** | ✅ HTTP 预览 URL |
| **自定义代理** | ✅ 自定义预览代理 |
| **网络限制** | ✅ 防火墙规则，可阻止出站流量 |
| **VPN** | ✅ VPN 连接 |
| **Computer Use** | ✅ 屏幕录制 |

### 2.7 安全与审计

| 能力 | 详情 |
|------|------|
| **审计日志** | ✅ 完整审计日志 |
| **安全报告** | ✅ 安全展示 |
| **网络隔离** | ✅ 每个沙箱独立网络栈 |

### 2.8 弹性与部署

| 能力 | 详情 |
|------|------|
| **创建速度** | 亚 90ms |
| **资源规格** | 默认 1 vCPU / 1GB RAM / 3GB Disk，最大 4 vCPU / 8GB RAM / 10GB Disk |
| **地区** | 多地区部署 |
| **快照** | OCI 镜像快照，支持自定义/公共/私有镜像 |
| **卷** | ✅ 持久化卷 |
| **声明式构建** | ✅ 声明式构建器 |
| **自托管** | ✅ 开源部署 + 客户管理计算 |
| **MCP** | ✅ MCP Server 集成 |

### 2.9 SDK 与工具

| 能力 | 详情 |
|------|------|
| **SDK** | Python, TypeScript, Ruby, Go（最广） |
| **CLI** | ✅ 完整命令行工具 |
| **API** | ✅ REST API |
| **Webhooks** | ✅ Webhook 通知 |
| **Playground** | ✅ 在线 Playground |
| **OpenTelemetry** | ✅ 实验性支持 |

---

## 3. OpenSandbox 详细能力分析

### 3.1 沙箱生命周期管理

| 能力 | 详情 |
|------|------|
| **创建** | `Sandbox.create(image, entrypoint, env, timeout)` |
| **销毁** | `sandbox.kill()` |
| **超时管理** | 通过 `timeout` 参数（timedelta）控制 |
| **上下文管理** | `async with sandbox` 自动清理 |
| **协议** | 标准化的沙箱生命周期 API 规范（OpenAPI spec） |

### 3.2 代码执行

| 能力 | 详情 |
|------|------|
| **命令执行** | `sandbox.commands.run(cmd)` |
| **代码解释器** | `CodeInterpreter.create(sandbox)` + `interpreter.codes.run(code, language)` |
| **多语言** | Python, JavaScript, 更多语言支持 |
| **流式输出** | 支持 stdout/stderr 流 |

### 3.3 文件系统

| 能力 | 详情 |
|------|------|
| **读取文件** | `sandbox.files.read_file(path)` |
| **写入文件** | `sandbox.files.write_files([WriteEntry])` 支持批量，可指定 mode |
| **列出目录** | 支持目录浏览 |

### 3.4 运行时与隔离

| 能力 | 详情 |
|------|------|
| **Docker** | ✅ 本地 Docker 运行时 |
| **Kubernetes** | ✅ 高性能 K8s 运行时（原生调度） |
| **安全容器** | ✅ gVisor / Kata Containers / Firecracker microVM |
| **网络策略** | ✅ Ingress Gateway（多路由策略）+ Egress 控制 |

### 3.5 生态集成

| 能力 | 详情 |
|------|------|
| **SDK** | Python, JavaScript/TypeScript, Java/Kotlin, C#/.NET, Go(Roadmap)（最多） |
| **沙箱协议** | 标准化生命周期和执行 API |
| **CNCF** | ✅ CNCF Landscape 成员 |
| **Agent 集成** | Claude Code, Gemini CLI, Codex, LangGraph, Google ADK |
| **浏览器** | ✅ Chrome + VNC + Playwright |
| **桌面** | ✅ VNC 桌面环境 |
| **VS Code** | ✅ code-server |
| **RL 训练** | ✅ 强化学习训练示例 |
| **持久卷** | ✅ PVC / OSSFS（Roadmap） |

### 3.6 项目成熟度

| 指标 | 详情 |
|------|------|
| **Commits** | 880 |
| **Contributors** | 47 |
| **Stars** | 9.4k |
| **Releases** | 71 |
| **活跃度** | 活跃（2026.03 最新发布） |

---

## 4. agent-infra/sandbox 详细能力分析

### 4.1 沙箱生命周期管理

| 能力 | 详情 |
|------|------|
| **启动** | `docker run` 单命令启动 |
| **访问** | HTTP API + SDK |
| **上下文** | `client.sandbox.get_context()` 获取环境信息 |

### 4.2 代码执行

| 能力 | 详情 |
|------|------|
| **Shell 执行** | `client.shell.exec_command(cmd)` |
| **Jupyter** | `client.jupyter.execute_code(code)` Python 代码执行 |
| **Node.js** | `client.nodejs.execute_nodejs_code(code)` |
| **安全沙箱** | 隔离的 Python/Node.js 执行环境 |

### 4.3 文件系统

| 能力 | 详情 |
|------|------|
| **读取文件** | `client.file.read_file(path)` |
| **写入文件** | `client.file.write_file(path, content)` |
| **列出目录** | `client.file.list_files(path)` |
| **搜索** | `client.file.search()` |
| **替换** | `client.file.replace()` |

### 4.4 浏览器能力（独有亮点）

| 能力 | 详情 |
|------|------|
| **VNC** | ✅ 可视化浏览器远程桌面 |
| **CDP** | ✅ Chrome DevTools Protocol 编程控制 |
| **截图** | `client.browser.screenshot()` |
| **导航** | MCP `navigate` 工具 |
| **点击/输入/滚动** | MCP `click` / `type` / `scroll` 工具 |
| **Playwright** | ✅ 直接 CDP 连接 |

### 4.5 开发工具

| 能力 | 详情 |
|------|------|
| **VSCode Server** | ✅ 浏览器内完整 IDE |
| **Jupyter** | ✅ 内置 Jupyter Notebook |
| **终端** | ✅ WebSocket 终端 |
| **端口转发** | ✅ 智能预览代理 |
| **MCP 服务器** | ✅ 预配置 4 个 MCP 服务器（browser/file/shell/markitdown） |

### 4.6 架构特点

| 能力 | 详情 |
|------|------|
| **设计理念** | All-in-One 单容器 |
| **文件系统** | 统一共享文件系统 |
| **部署** | Docker / Docker Compose / Kubernetes |
| **中国镜像** | ✅ 字节跳动镜像（enterprise-public-cn-beijing.cr.volces.com） |
| **JWT** | ✅ JWT 认证支持 |
| **DNS** | ✅ DNS-over-HTTPS |

### 4.7 SDK

| 能力 | 详情 |
|------|------|
| **Python** | `pip install agent-sandbox` |
| **TypeScript** | `npm install @agent-infra/sandbox` |
| **Go** | `go get github.com/agent-infra/sandbox-sdk-go` |

---

## 5. 阿里云 Agent Sandbox 详细能力分析

### 5.1 沙箱生命周期管理

| 能力 | 详情 |
|------|------|
| **创建** | E2B 兼容 SDK 或 Sandbox CR 声明式管理 |
| **休眠** | 内存状态保持，1s~15s 唤醒 |
| **Checkpoint** | 内存状态 Checkpoint / Restore |
| **克隆** | 状态克隆，支持分支并行探索 |

### 5.2 弹性能力（独有亮点）

| 能力 | 详情 |
|------|------|
| **创建速度** | 百毫秒级（Warm Pool 预热） |
| **大规模并发** | 15K Sandbox/分钟 |
| **镜像加速** | 镜像缓存，拉取耗时缩短 90% |
| **预调度** | 基于负载特征的预调度优化 |

### 5.3 安全隔离

| 能力 | 详情 |
|------|------|
| **隔离级别** | MicroVM 级别（最强） |
| **计算隔离** | 独立 MicroVM |
| **网络隔离** | 端到端网络隔离 |
| **存储隔离** | 端到端存储隔离 |
| **审计** | 沙箱级日志与监控 |

### 5.4 生态集成

| 能力 | 详情 |
|------|------|
| **E2B 兼容** | ✅ 完全兼容 E2B SDK |
| **K8s 原生** | ✅ 深度融合 Kubernetes |
| **AgentScope** | ✅ 阿里自研 Agent 框架 |
| **Sandbox CR** | ✅ 自定义资源对象声明式管理 |
| **存储/网络/监控** | ✅ 兼容现有 K8s 生态 |

### 5.5 应用场景

| 场景 | 详情 |
|------|------|
| **AgentRL** | 强化学习训练、轨迹采样、环境交互、多路径探索 |
| **AgentServing** | 深度研究、工具调用、多轮会话 |
| **OpenClaw** | 个人助理/数字员工搭建 |

### 5.6 当前状态

| 指标 | 详情 |
|------|------|
| **状态** | 邀测 |
| **服务形态** | 阿里云 ACS 服务 |
| **开源** | ❌ 闭源 |

---

## 6. 腾讯云 Agent Runtime 详细能力分析

### 6.1 接入方式

| 能力 | 详情 |
|------|------|
| **SDK** | 直接使用 `e2b-code-interpreter` |
| **域名替换** | `E2B_DOMAIN=ap-guangzhou.tencentags.com` |
| **API Key** | 腾讯云控制台创建的 API Key |
| **代码改动** | 最小化，仅替换环境变量 |

### 6.2 沙箱工具

| 能力 | 详情 |
|------|------|
| **模板管理** | 腾讯云控制台创建沙箱工具 |
| **超时** | `timeout` 参数控制，默认 10 分钟 |
| **代码执行** | `sandbox.run_code()` 流式输出 |

### 6.3 优势

| 优势 | 详情 |
|------|------|
| **迁移成本** | 极低（仅替换域名+Key） |
| **国内可用** | 腾讯云基础设施 |
| **生态复用** | 完全复用 E2B 生态代码 |

### 6.4 局限

| 局限 | 详情 |
|------|------|
| **自主性** | 无自主 SDK，完全依赖 E2B |
| **差异化** | 无显著功能差异 |
| **开源** | ❌ 闭源 |
| **可移植性** | 仅腾讯云可用 |

---

## 7. 全维度能力对比矩阵

### 7.1 沙箱生命周期

| 能力 | E2B | Daytona | OpenSandbox | agent-infra | 阿里云 | 腾讯云 |
|------|-----|---------|-------------|-------------|--------|--------|
| **创建** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **销毁** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **超时管理** | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| **暂停/恢复** | ✅ | ❌ | ❌ | ❌ | ✅(休眠唤醒) | ❌ |
| **停止/启动** | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ |
| **归档** | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **动态调整资源** | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **Checkpoint** | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **状态克隆** | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **临时沙箱** | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **自动生命周期** | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |

### 7.2 代码执行

| 能力 | E2B | Daytona | OpenSandbox | agent-infra | 阿里云 | 腾讯云 |
|------|-----|---------|-------------|-------------|--------|--------|
| **命令执行** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **代码执行** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **多语言运行时** | 多 | 3种 | 多 | 2种 | 多 | 多 |
| **PTY 终端** | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **日志流** | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |

### 7.3 文件系统

| 能力 | E2B | Daytona | OpenSandbox | agent-infra | 阿里云 | 腾讯云 |
|------|-----|---------|-------------|-------------|--------|--------|
| **读取** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **写入** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **列出** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **批量上传** | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| **批量下载** | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ |
| **删除** | ❌ | ✅ | ❌ | ❌ | ✅ | ✅ |
| **权限管理** | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **查找文本** | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ |
| **替换文本** | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ |
| **移动/重命名** | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |

### 7.4 Git 操作

| 能力 | E2B | Daytona | OpenSandbox | agent-infra | 阿里云 | 腾讯云 |
|------|-----|---------|-------------|-------------|--------|--------|
| **克隆** | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **状态** | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **分支管理** | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **暂存/提交** | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **推送/拉取** | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |

### 7.5 LSP 支持

| 能力 | E2B | Daytona | OpenSandbox | agent-infra | 阿里云 | 腾讯云 |
|------|-----|---------|-------------|-------------|--------|--------|
| **LSP 服务器** | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **代码补全** | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **文档符号** | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **全局符号搜索** | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |

### 7.6 浏览器与桌面

| 能力 | E2B | Daytona | OpenSandbox | agent-infra | 阿里云 | 腾讯云 |
|------|-----|---------|-------------|-------------|--------|--------|
| **VNC** | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **CDP** | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ |
| **浏览器截图** | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ |
| **Playwright** | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ |
| **桌面环境** | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **SSH** | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **Web Terminal** | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ |

### 7.7 开发工具

| 能力 | E2B | Daytona | OpenSandbox | agent-infra | 阿里云 | 腾讯云 |
|------|-----|---------|-------------|-------------|--------|--------|
| **VSCode** | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ |
| **Jupyter** | 通过CI | ❌ | ✅ | ✅ | ❌ | ❌ |
| **MCP** | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ |
| **预览代理** | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ |

### 7.8 安全隔离

| 能力 | E2B | Daytona | OpenSandbox | agent-infra | 阿里云 | 腾讯云 |
|------|-----|---------|-------------|-------------|--------|--------|
| **隔离级别** | 容器 | 容器 | 多选 | 容器 | MicroVM | 未公开 |
| **gVisor** | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| **Kata** | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| **Firecracker** | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| **网络防火墙** | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ |
| **审计日志** | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ |

### 7.9 弹性与部署

| 能力 | E2B | Daytona | OpenSandbox | agent-infra | 阿里云 | 腾讯云 |
|------|-----|---------|-------------|-------------|--------|--------|
| **创建速度** | 秒级 | 90ms | 秒级 | 秒级 | 百毫秒 | 秒级 |
| **大规模并发** | 有限 | 有限 | K8s调度 | 单容器 | 15K/分钟 | 有限 |
| **多地区** | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ |
| **自定义资源** | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ |
| **K8s 原生** | ❌ | ❌ | ✅ | 可部署 | ✅ | ❌ |
| **Docker** | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ |
| **自托管** | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |

---

## 8. API 能力逐项对比

### 8.1 沙箱管理 API

| API | E2B | Daytona | OpenSandbox | agent-infra |
|-----|-----|---------|-------------|-------------|
| `create` | ✅ | ✅ | ✅ | ✅ |
| `delete/kill` | ✅ | ✅ | ✅ | ❌ |
| `start` | ❌ | ✅ | ❌ | ❌ |
| `stop` | ❌ | ✅ | ❌ | ❌ |
| `pause` | ✅ | ❌ | ❌ | ❌ |
| `resume` | ✅ | ❌ | ❌ | ❌ |
| `archive` | ❌ | ✅ | ❌ | ❌ |
| `recover` | ❌ | ✅ | ❌ | ❌ |
| `resize` | ❌ | ✅ | ❌ | ❌ |
| `list` | ❌ | ✅ | ❌ | ❌ |
| `getInfo` | ✅ | ✅ | ✅ | ✅ |
| `setTimeout` | ✅ | ❌ | ❌ | ❌ |
| `snapshot` | ❌ | ✅ | ❌ | ❌ |

### 8.2 文件操作 API

| API | E2B | Daytona | OpenSandbox | agent-infra |
|-----|-----|---------|-------------|-------------|
| `read` | ✅ | ✅ | ✅ | ✅ |
| `write` | ✅ | ✅ | ✅ | ✅ |
| `list` | ✅ | ✅ | ✅ | ✅ |
| `upload` | ✅ | ✅ | ✅ | ❌ |
| `download` | ✅ | ✅ | ❌ | ❌ |
| `delete` | ❌ | ✅ | ❌ | ❌ |
| `createFolder` | ❌ | ✅ | ❌ | ❌ |
| `getInfo` | ❌ | ✅ | ❌ | ❌ |
| `setPermissions` | ❌ | ✅ | ✅ | ❌ |
| `find` | ❌ | ✅ | ❌ | ✅ |
| `replace` | ❌ | ✅ | ❌ | ✅ |
| `move` | ❌ | ✅ | ❌ | ❌ |

### 8.3 Git 操作 API

| API | E2B | Daytona | OpenSandbox | agent-infra |
|-----|-----|---------|-------------|-------------|
| `clone` | ❌ | ✅ | ❌ | ❌ |
| `status` | ❌ | ✅ | ❌ | ❌ |
| `branches` | ❌ | ✅ | ❌ | ❌ |
| `createBranch` | ❌ | ✅ | ❌ | ❌ |
| `checkout` | ❌ | ✅ | ❌ | ❌ |
| `deleteBranch` | ❌ | ✅ | ❌ | ❌ |
| `add` | ❌ | ✅ | ❌ | ❌ |
| `commit` | ❌ | ✅ | ❌ | ❌ |
| `push` | ❌ | ✅ | ❌ | ❌ |
| `pull` | ❌ | ✅ | ❌ | ❌ |

### 8.4 浏览器 API

| API | E2B | Daytona | OpenSandbox | agent-infra |
|-----|-----|---------|-------------|-------------|
| `screenshot` | ❌ | ❌ | ✅ | ✅ |
| `navigate` | ❌ | ❌ | ✅ | ✅ |
| `click` | ❌ | ❌ | ✅ | ✅ |
| `type` | ❌ | ❌ | ✅ | ✅ |
| `scroll` | ❌ | ❌ | ✅ | ✅ |
| `getInfo` | ❌ | ❌ | ✅ | ✅ |

---

## 总结

### 能力排名（按维度）

**沙箱生命周期管理**：Daytona > 阿里云 > E2B > OpenSandbox > agent-infra > 腾讯云

**代码执行**：Daytona ≈ OpenSandbox > E2B > agent-infra > 阿里云 > 腾讯云

**文件系统**：Daytona > OpenSandbox > E2B > agent-infra > 阿里云 > 腾讯云

**Git 操作**：Daytona（独有）>>> 其他

**LSP 支持**：Daytona（独有）>>> 其他

**浏览器/桌面**：agent-infra ≈ OpenSandbox > 阿里云 > Daytona > E2B = 腾讯云

**安全隔离**：阿里云 > OpenSandbox > Daytona > E2B ≈ agent-infra > 腾讯云

**弹性扩展**：阿里云 > Daytona > OpenSandbox > E2B > agent-infra > 腾讯云

**SDK 语言覆盖**：OpenSandbox > Daytona > agent-infra > E2B > 阿里云 ≈ 腾讯云

### 关键差异化能力

| 产品 | 独有/领先能力 |
|------|-------------|
| **E2B** | 暂停/恢复、成熟的 LLM 生态集成 |
| **Daytona** | Git API、LSP、PTY、完整生命周期管理（start/stop/archive/recover/resize）、90ms 创建 |
| **OpenSandbox** | 5 种 SDK、沙箱协议标准化、gVisor/Kata/Firecracker 安全容器、CNCF |
| **agent-infra** | All-in-One 单容器、预配置 MCP 服务器、VNC+CDP 浏览器、零配置 |
| **阿里云** | MicroVM 隔离、15K/分钟弹性、休眠唤醒、Checkpoint、Warm Pool |
| **腾讯云** | E2B 完全兼容、极简迁移 |
