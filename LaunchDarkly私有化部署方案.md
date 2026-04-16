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
- YAML 配置方案
- Unleash 方案
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
// packages/shared/pkg/featureflags/client.go
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

### 场景 A：不需要动态灰度 / 不想改代码

直接不设置：

```bash
# 留空或不设置即可
# export LAUNCH_DARKLY_API_KEY=
```

然后查看：
- [`FeatureFlags私有化部署方案.md` 的 6. 推荐方案](./FeatureFlags私有化部署方案.md#6-推荐方案)
- [`FeatureFlags私有化部署方案.md` 的 2. Feature Flags 完整列表](./FeatureFlags私有化部署方案.md#2-feature-flags-完整列表)

适用场景：
- 单节点部署
- 测试环境
- 生产环境但接受“固定默认值”

### 场景 B：不使用 LaunchDarkly，但仍想管理 Flag

优先看主文档中的替代方案：
- [`FeatureFlags私有化部署方案.md` 的 3. YAML 配置方案](./FeatureFlags私有化部署方案.md#3-yaml-配置方案)
- [`FeatureFlags私有化部署方案.md` 的 4. Unleash 配置方案](./FeatureFlags私有化部署方案.md#4-unleash-配置方案)

建议：
- **不需要灰度**：用 YAML
- **需要灰度 / UI / 动态下发**：用 Unleash

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
- YAML / Unleash 方案细节
- 代码改造接口与 Provider 设计

### [`核心组件详解.md`](./核心组件详解.md) 负责
- Feature Flags 在系统架构中的作用
- 为什么按 team / template / sandbox 维度控制有意义

### [`启动参数详解.md`](./启动参数详解.md) 负责
- `LAUNCH_DARKLY_API_KEY` 等运行时环境变量的使用位置

---

## 5. 私有化部署建议

### 最小成本

不配置 `LAUNCH_DARKLY_API_KEY`，直接使用离线默认值。

### 需要配置化管理

改用 YAML 配置，避免继续维护 LaunchDarkly 依赖。

### 需要灰度 / UI / 多环境管理

改用 Unleash；具体落地方式见：

- [`FeatureFlags私有化部署方案.md` 的 4. Unleash 配置方案](./FeatureFlags私有化部署方案.md#4-unleash-配置方案)

---

## 6. 快速决策

| 需求 | 建议方案 | 继续阅读 |
|------|----------|----------|
| 只想跑起来 | LaunchDarkly 离线模式 | [`FeatureFlags私有化部署方案.md` 第 6 节](./FeatureFlags私有化部署方案.md#6-推荐方案) |
| 想用文件管理配置 | YAML | [`FeatureFlags私有化部署方案.md` 第 3 节](./FeatureFlags私有化部署方案.md#3-yaml-配置方案) |
| 想要灰度发布和 UI | Unleash | [`FeatureFlags私有化部署方案.md` 第 4 节](./FeatureFlags私有化部署方案.md#4-unleash-配置方案) |

---

## 7. 一句话总结

**LaunchDarkly 在私有化部署里不是必须组件。** 当前代码已经支持“未配置 API Key 时回退到离线默认值”，所以大多数私有化场景应把 [`FeatureFlags私有化部署方案.md`](./FeatureFlags私有化部署方案.md) 作为主文档，按是否需要灰度能力来选择“离线默认值 / YAML / Unleash”。
