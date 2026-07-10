# LaunchDarkly 私有化部署说明（索引版）

> 本文档是 **LaunchDarkly 专题索引文档**：回答“当前代码如何接入 LaunchDarkly、离线模式如何工作、私有化时为什么通常不需要保留它”。
>
> 相关文档：
> - [`README.md`](./README.md)：仓库总入口与文档导航
> - [`FeatureFlags私有化部署方案.md`](./FeatureFlags私有化部署方案.md)：Feature Flags 主文档，含完整默认值与替代方案
> - [`核心组件详解.md`](./核心组件详解.md)：Feature Flags 在整体架构中的作用
> - [`启动参数详解.md`](./启动参数详解.md)：`LAUNCH_DARKLY_API_KEY` 等运行时配置

---

## 阅读导航

### 如果你只想知道“不配 LaunchDarkly 能不能跑”
- 看 [**2. 当前代码中的 LaunchDarkly 行为**](#2-当前代码中的-launchdarkly-行为)

### 如果你想要完整 Feature Flags 替代方案
- 看 [`FeatureFlags私有化部署方案.md`](./FeatureFlags私有化部署方案.md#1-阅读导航)

### 如果你只是查环境变量
- 看 [`启动参数详解.md`](./启动参数详解.md#阅读导航)

---

## 1. 本文档的定位

[`FeatureFlags私有化部署方案.md`](./FeatureFlags私有化部署方案.md) 已经覆盖了：
- 完整 Feature Flags 清单与默认值
- YAML 配置可选改造方案
- Unleash 可选改造方案
- 多 Provider 改造思路
- 部署建议与推荐路线

因此，本文档只保留 **LaunchDarkly 专属信息**：
1. 当前代码怎样接入 LaunchDarkly
2. 不配置 `LAUNCH_DARKLY_API_KEY` 时会发生什么
3. 私有化场景下为什么通常不必继续使用 LaunchDarkly
4. 应该跳转到哪份主文档继续看

---

## 2. 当前代码中的 LaunchDarkly 行为

E2B 当前使用 LaunchDarkly Server SDK（`go-server-sdk/v7`）。核心行为如下：

```go
// infra/packages/shared/pkg/featureflags/client.go
func NewClient() (*Client, error) {
    if launchDarklyApiKey == "" {
        return NewClientWithDatasource(launchDarklyOfflineStore)
    }

    ldClient, err := ldclient.MakeClient(launchDarklyApiKey, waitForInit)
    return &Client{ld: ldClient}, nil
}
```

### 结论

- 配置了 `LAUNCH_DARKLY_API_KEY`：连接 LaunchDarkly 在线服务
- 未配置 `LAUNCH_DARKLY_API_KEY`：进入 **离线模式**
- 离线模式下，所有 Flag 使用代码里定义的 fallback 默认值

这意味着：

> **私有化部署如果不想引入 LaunchDarkly，本身就可以直接跑。**

---

## 3. 私有化场景下的推荐阅读路径

| 场景 | 当前能力 / 建议 | 继续阅读 |
|------|------------------|----------|
| 不需要动态灰度，只想无代码跑起来 | 不设置 `LAUNCH_DARKLY_API_KEY`，使用代码内 fallback 默认值 | [`FeatureFlags私有化部署方案.md`](./FeatureFlags私有化部署方案.md#1-阅读导航) |
| 想确认每个 Flag 的默认值 | 以 `infra/packages/shared/pkg/featureflags/flags.go` 为准 | [`FeatureFlags私有化部署方案.md` 的完整列表](./FeatureFlags私有化部署方案.md#2-feature-flags-完整列表) |
| 想用 YAML / Unleash / 自建服务管理 Flag | 这是可选代码改造，不是 `2026.28` 现有无代码能力 | [`FeatureFlags私有化部署方案.md` 的私有化替代方案](./FeatureFlags私有化部署方案.md#4-私有化替代方案) |
| 只查 `LAUNCH_DARKLY_API_KEY` 配置 | 看运行时配置参考 | [`启动参数详解.md`](./启动参数详解.md#阅读导航) |

最小私有化部署可以直接不设置：

```bash
# 留空或不设置即可
# export LAUNCH_DARKLY_API_KEY=
```

---

## 4. 与其他文档的关系

为了减少重复，相关内容统一拆分如下：

### 这份文档负责
- LaunchDarkly 在线 / 离线模式说明
- 私有化时为什么可以不继续用 LaunchDarkly
- 把读者引导到主文档

### [`FeatureFlags私有化部署方案.md`](./FeatureFlags私有化部署方案.md) 负责
- 完整 Flag 清单
- 精确默认值
- YAML / Unleash 可选改造方案
- 代码改造接口与 Provider 设计

### [`核心组件详解.md`](./核心组件详解.md) 负责
- Feature Flags 在系统架构中的作用
- 为什么按 team / template / sandbox 维度控制有意义

### [`启动参数详解.md`](./启动参数详解.md) 负责
- `LAUNCH_DARKLY_API_KEY` 等运行时环境变量的使用位置

---

## 5. 一句话总结

**LaunchDarkly 在私有化部署里不是必须组件。** 当前代码已经支持“未配置 API Key 时回退到离线默认值”。大多数私有化场景应把 [`FeatureFlags私有化部署方案.md`](./FeatureFlags私有化部署方案.md) 作为主文档；如果要 YAML / Unleash / 自建服务，需要按该文档实现 provider 改造。
