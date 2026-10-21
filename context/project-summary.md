# 项目概览 (Project Summary)

## 1. 项目背景
本项目是一个基于 Java (JDK 21) 的高性能游戏服务端。核心目标是提供**安全**、**一致**与**高效**的开发体验。

## 2. 核心目录结构
- **`game/`**: 主游戏服（包含 `Handler` 协议入口、`Module` 业务逻辑、配置管理）。
- **`protocol/`**: 存放 Protobuf 定义与生成产物。
- **`core/` & `util/`**: 通用基础能力 (`AsyncUtils`, `DateUtil`, `Rnd`)。
- **`simulationclient/`**: 模拟客户端，用于功能测试和压测。

## 3. 关键开发原则
- **线程模型**: 基于 `objectId` (playerId) 分配的 JDK21 虚拟线程模型。同一玩家的逻辑串行执行，无需锁。
- **异步转同步**: 严禁使用 `CompletableFuture` 回调链，必须使用 `AsyncUtils.await(...)` 将异步转同步，以保持代码线性逻辑。
- **持久化**: 大多数 Module 数据由框架定时全量保存，通常无需手动 `save()`，但须确认数据确实进入保存链路；内存变更不等于已经持久化。特殊情况（如邮件）使用 `DbEntity` 接口手动操作。
- **错误处理**: 业务逻辑错误推荐使用 `player.fail(ErrorMsgEnum.xxx)` 抛出异常，由框架统一处理。

## 4. 常用工具 (API Whitelist)
- **时间**: 必须用 `DateUtil.currentTimeMillis()`，禁用 `System`。
- **随机**: 必须用 `Rnd` 类。
- **日志**: 使用 `log.info/error`，禁用 `System.out.println`。

## 5. 详细规范文档 (Detailed Rules)
> 详情请参阅以下文档：
- **开发流程 SOP**: [SOP](../../.ai-sop/SUPERPOWERS_MANUAL.md)
- **AI 编码上下文规范**: [Coding Rules](ai-coding.md)
- **通讯协议规范**: [Protocol Rules](proto-rules.md)
- **静态配置数据规范**: [Config Rules](config-rules.md)
- **测试指南**: [Test Rules](client-test.md)
- **API 白名单**: [API Whitelist](api-whitelist.md)

## 6. 新 SOP 布局与事实边界

- 通用引擎：项目根 `.ai-sop/`，安装器生成根 `AGENTS.md`、`ai-sop.ps1` 与各工具入口。
- 项目知识：`.ai-workspace/context/`；功能规格：`.ai-workspace/specs/features/`。
- 构建与仓库归属见 [project-tooling.md](project-tooling.md)，默认加载索引见 [README.md](README.md)。
- `login/` 提供登录入口；`pom.xml` 声明 util、protocol、core、game、login、simulationclient 六模块，编译 release=21。
- 本次核对了 `IdVirtualThreadProcessor`、`BasePlayerModule`、`PlayerHelper` 与模拟客户端测试基类；其他旧知识保留作为项目资产，具体修改前仍核对对应源码。API 快照不是当前签名的保证。
- `.claude_old/` 原样保留为历史审查来源，不再作为活跃流程入口；旧 Skills、旧 MCP 绝对路径及旧批准状态不迁入新引擎。
