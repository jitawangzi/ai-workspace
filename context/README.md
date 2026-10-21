# 共享项目知识

这里保存个人 Java 游戏服务端的项目知识。流程入口是项目根 `AGENTS.md`，通用引擎位于 `.ai-sop/`；默认 T2，人工指定优先。T1/T2 不要求独立审核；T3 按引擎规范执行。

## 始终加载

| 文档 | 内容 |
|---|---|
| [project-summary.md](project-summary.md) | 六模块结构、JDK 21、线程与保存模型 |
| [coding-style.md](coding-style.md) | Part A 可迁移经验 + Part B 本项目 API 和适配 |
| [business-logic-pattern.md](business-logic-pattern.md) | 状态、周期、奖励和性能的共性原则 |
| [project-tooling.md](project-tooling.md) | Maven、验证 Profile、Git 仓库归属 |

## 按需加载

| 场景 | 文档 |
|---|---|
| 实现 Handler / Module、事件、GM 或资源操作 | [ai-coding.md](ai-coding.md)、[api-whitelist.md](api-whitelist.md) |
| Protobuf 定义及兼容 | [proto-rules.md](proto-rules.md) |
| 表结构、生成类、配置来源 | [config-rules.md](config-rules.md) |
| 测试与模拟客户端 | [client-test.md](client-test.md) |
| 高风险逻辑检查；已要求 logic-auditor 时 | [logic-audit-game-server.md](logic-audit-game-server.md) |
| 活动、任务、事件、条件、奖励、红点 | [business-patterns/README.md](business-patterns/README.md) |

### 流程专属索引

| 场景 | 文档 |
|---|---|
| 流程产物与旧规格接入 | [ai-automation-workflow.md](ai-automation-workflow.md) |
| 迁移审查问题、纠正与验证边界 | [审查补充记录](../workflows/migration-audit-20261022.md) |

旧 context 全部保留其知识去向，原件仍在 `.claude_old/context/`。迁移映射与未核实事项见 [迁移记录](../workflows/migration-20261021.md)。API 快照与旧示例必须结合当前源码使用；冲突先查证，不能为迎合旧文字改坏现行实现。中文注释、异常日志等新增规范以 coding-style 为准。
