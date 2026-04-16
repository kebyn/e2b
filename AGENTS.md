# AGENTS.md - E2B Infrastructure

## 构建和测试命令

### 环境切换
```bash
make switch-env ENV=staging    # 切换环境 (prod, staging, dev)
```

### 构建
```bash
make build/api                 # 构建API
make build/orchestrator        # 构建Orchestrator
make build-and-upload          # 构建并上传所有服务
```

### 测试
```bash
# 运行所有测试
make test

# 运行单个包的测试
cd packages/api && go test -race -v ./...
cd packages/orchestrator && go test -race -v ./...

# 运行单个测试
cd packages/<package> && go test -race -v -run TestName ./path/to/package

# 集成测试
make test-integration
```

### Lint和格式化
```bash
make fmt                       # 格式化代码
make lint                      # 运行golangci-lint
```

### 代码生成
```bash
make generate                  # 生成所有代码
make generate/api              # 生成API OpenAPI代码
make generate/orchestrator     # 生成Orchestrator proto代码
make generate/db               # 生成SQLC代码
make generate-mocks            # 生成Mock代码
```

### 数据库
```bash
make migrate                   # 运行数据库迁移
cd packages/db && make create-migration NAME=migration-name
```

### 本地开发
```bash
make local-infra               # 启动本地基础设施
cd packages/api && make run-local
cd packages/api && make dev    # 使用air热重载
```

## 代码风格指南

### Go版本
- 使用 Go 1.25.4
- 项目使用 Go workspaces (go.work)

### 导入规范
使用gci格式化导入，顺序如下:
1. 标准库 (standard)
2. 第三方库 (default)
3. 项目内部包 (prefix: `github.com/e2b-dev/infra`)

```go
import (
    "context"
    "fmt"

    "github.com/gin-gonic/gin"
    "github.com/google/uuid"

    "github.com/e2b-dev/infra/packages/api/internal/api"
    "github.com/e2b-dev/infra/packages/shared/pkg/logger"
)
```

### 格式化
- 使用 `gofumpt` 格式化代码（比gofmt更严格）
- YAML/HCL 文件使用2空格缩进

### 命名约定
- 包名: 小写单词，不使用下划线
- 导出函数/类型: CamelCase
- 私有函数/类型: camelCase
- 常量: CamelCase或UPPER_CASE（用于常量组）
- 测试文件: `*_test.go`
- Mock文件: `mocks/`目录，以`mock`为前缀

### 错误处理
```go
// 使用 %w 包装错误
if err != nil {
    return fmt.Errorf("operation failed: %w", err)
}

// 使用 errors.Join 合并多个错误
return errors.Join(errs...)

// API错误使用 sendAPIStoreError
a.sendAPIStoreError(c, http.StatusBadRequest, "Error message")
```

### 日志规范
- 使用 `github.com/e2b-dev/infra/packages/shared/pkg/logger`
- 禁止直接使用 `zap.New()`, `zap.L()`, `zap.S()` 等

```go
import "github.com/e2b-dev/infra/packages/shared/pkg/logger"

logger.L().Info(ctx, "message", zap.Error(err))
logger.L().Fatal(ctx, "fatal error", zap.Error(err))
```

### 测试规范
- 使用 `testify/assert` 和 `testify/require`
- 测试运行使用 `-race` 标志检测竞态条件
- Mock使用 mockery 生成，配置在 `.mockery.yaml`
- 数据库测试使用 testcontainers-go

```go
func TestFeature(t *testing.T) {
    assert.Equal(t, expected, actual)
    require.NoError(t, err)
}
```

### 结构体初始化
- 使用 `&Type{}` 而不是 `new(Type)`
- linter禁止使用 `new` 关键字

### HTTP客户端
- 使用 `retryablehttp.NewRequestWithContext` 而不是 `retryablehttp.NewRequest`
- 始终传递 context

## Cursor规则 (.cursor/BUGBOT.md)

### PR描述
- 简要总结PR目的，不要列出所有变更文件
- 不使用列表或分区，理想情况下只有一段话
- 不使用emoji

### PR审查
审查重点:
- 潜在bug或问题
- 性能考虑
- 重要安全问题

反馈要求:
- 非常简洁，建设性
- 跳过一般性建议和变更总结
- 不做代码风格建议
- 跳过关于PR做得好的总结，只关注代码变更和潜在问题
- 不输出最终总结或最终行动项列表

## 重要开发注意事项

### Proto/gRPC
- Proto文件: `spec/process/`, `spec/filesystem/`
- 编辑proto后运行: `make generate/orchestrator` 和 `make generate/shared`

### Firecracker和VM管理
- Orchestrator需要sudo权限运行
- VM网络使用iptables和Linux netlink
- 存储使用NBD (Network Block Device)

### 环境变量
- 配置文件: `.env.{prod,staging,dev}`
- 模板: `.env.template`
- 生产环境密钥存储在GCP Secrets Manager

### 可观测性
- 所有服务导出OpenTelemetry traces/metrics/logs
- 遥测设置: `packages/shared/pkg/telemetry/`
