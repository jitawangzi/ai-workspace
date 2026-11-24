<!-- context-meta owner:jitawangzi reviewedAt:2026-11-21 expiresAt:2027-04 -->
# 项目概览 (Project Summary)

## 1. 项目背景
本项目是一个基于 **Java (JDK 21)** + **Vert.x 5** 的高性能游戏服务端，核心目标是提供**安全**、**一致**与**高效**的开发与测试体验。

完整双轨布局、五仓边界与人/AI 导航地图见 [项目根 README](../../README.md)；系统拓扑、节点生命周期与故障边界见 [doc/01_系统架构设计全景文档.md](../../doc/01_系统架构设计全景文档.md)。

## 2. 工程模块与外部依赖目录
根 `pom.xml` 声明六个 Maven 模块（Java release=21，默认 `skipTests=true`），外加控制台、文档与平级配置仓库：

- **`util/`**：通用基础工具（`DateUtil`、`Rnd`、配置加载、日志等）。
- **`protocol/`**：独立 Git 仓库，存放 Protobuf 真源（`.proto`）、协议生成类与配表生成类。
- **`core/`**：基础设施（按实体 ID 串行的虚拟线程邮箱 `IdVirtualThreadProcessor`、网络/RPC、缓存、Vert.x 集群）。
- **`game/`**：主业务服，同时包含 **GameServer** 与 **CrossServer** 入口，涵盖 `Handler`、`BasePlayerModule`、GM 平台、模块双轨验收与实体/Mapper。
- **`login/`**：登录服（HTTP 登录、账号校验、服务器列表、支付订单与运营接口）。
- **`simulationclient/`**：模拟客户端，提供协议场景测试、AI 黑盒+白盒测试 SDK 与压测工具。
- **`gm-console/` & `doc/`**：GM Web 控制台热重载面板（`panels/`）及面向研发/运维的架构、流程与本地部署文档。
- **外部平级目录**：`../configs/`（策划配表真源与导出产物）、`../dic_generate/`（配表生成器源码及《配置表AI编码规范》）。

## 3. 关键开发原则
- **线程模型**：基于 `objectId`（`playerId` / `guildId`）分配的 JDK 21 虚拟线程邮箱模型，同一玩家逻辑串行执行，无需在业务层加锁。
- **异步转同步**：严禁在业务链路中使用 `CompletableFuture` 回调链，统一使用 `AsyncUtils.await(...)` 保持线性逻辑。
- **持久化**：大多数 `BasePlayerModule` 数据由框架定时全量保存，通常无需手动 `save()`，但须确认字段进入保存链路；内存变更不等于已经持久化。独立表实体（如邮件等）通过 `DbEntity` 接口操作。
- **错误处理**：业务错误推荐使用 `player.fail(ErrorMsgEnum.xxx)` 抛出，由框架统一转换为协议错误码回包。

## 4. 常用工具 (API Whitelist)
- **时间**：必须用 `DateUtil.currentTimeMillis()`（支持非生产虚拟时钟），禁用 `System.currentTimeMillis()`。
- **随机**：必须用 `Rnd` 类（支持非生产可控随机）。
- **日志**：使用 SLF4J/Log4j2 的 `log.info/warn/error`，禁用 `System.out.println`。

## 5. 核心规范快速路由
- **流程 SOP 入口**：[AGENTS.md](../../AGENTS.md)（通用引擎在 `.ai-sop/`，投影产物禁止手改）
- **知识总索引（含 `doc/` 与排障手册）**：[context/README.md](README.md)
- **工具链、验证 Profile 与五仓归属**：[project-tooling.md](project-tooling.md)
- **编码规范与核心类入口**：[coding-style.md](coding-style.md) · [ai-coding.md](ai-coding.md)
- **协议、配表与测试**：[proto-rules.md](proto-rules.md) · [config-rules.md](config-rules.md) · [client-test.md](client-test.md)
- **本服功能规格与任务**：[specs/README.md](../specs/README.md)（`.ai-workspace/specs/features/`）

> **核对原则**：API 快照和文档示例均须以当前源码签名与运行行为为准，修改前先查证对应源码，不为迎合旧文字改动正确代码。
