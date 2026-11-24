# 共享项目知识索引

这里保存本 Java 游戏服务端的领域知识与工程契约。

- **项目全景与多仓边界（人 + AI 零号入口）**：[项目根 README](../../README.md) · [工作区说明](../README.md) · [功能规格索引](../specs/README.md)
- **流程与档位红线**：宿主根 [AGENTS.md](../../AGENTS.md)（通用引擎在 `.ai-sop/`；默认 T2，人工指定优先；T1/T2 无独立审核，T3 按引擎规范执行）

## 始终加载（精简核心，每次开发任务必读）

| 文档 | 内容 |
|---|---|
| [project-summary.md](project-summary.md) | 工程全景、六模块与外部目录、JDK 21、虚拟线程与保存模型 |
| [coding-style.md](coding-style.md) | Part A 可迁移经验 + Part B 本项目 API、日志、异常与持久适配 |
| [business-logic-pattern.md](business-logic-pattern.md) | 状态、周期、奖励和性能的共性设计原则 |
| [project-tooling.md](project-tooling.md) | Maven 编译、验证 Profile、多 Agent 审核约定与五仓 Git 归属 |

## 按需加载（架构、排障、编码与专项规范）

| 场景 | 文档 |
|---|---|
| **系统架构全景**（节点拓扑、登录重连、邮箱线程、RPC、存储边界） | [doc/01_系统架构设计全景文档.md](../../doc/01_系统架构设计全景文档.md) |
| **研发流程完整手册**（配表/协议/业务端到端开发示例） | [doc/02_开发流程与研发规范手册.md](../../doc/02_开发流程与研发规范手册.md) |
| **Windows 本地部署与运维**（中间件、MySQL、Apollo、服务启停） | [doc/deployment_guide.md](../../doc/deployment_guide.md) |
| **独立 Bug 排查、疑似误报分诊、日志定位与最小复现** | [debugging-playbook.md](debugging-playbook.md) |
| 实现 Handler / Module、事件、GM、物品与资源操作及核心类速查 | [ai-coding.md](ai-coding.md) |
| Protobuf 协议定义、编号规则与兼容 | [proto-rules.md](proto-rules.md) |
| 静态配表结构、生成类与校验规则 | [config-rules.md](config-rules.md) |
| 活动、任务、事件、条件、奖励、红点业务模式（含条件系统多态架构） | [business-patterns/README.md](business-patterns/README.md) |
| 模拟客户端测试、白盒 SDK 与模块双轨验收（CONTRACT + MATRIX_SCAN） | [client-test.md](client-test.md)、[module-acceptance-tester](../skills/module-acceptance-tester/SKILL.md) |
| 验证入口环境前提、副作用与清理边界 | [verification-effects.md](verification-effects.md) |
| 联调运行实例、制品快照与配置证据 | [runtime-verification.md](runtime-verification.md) |
| 保存快照、幂等、失败与恢复专项验证 | [state-integrity-testing.md](state-integrity-testing.md)、[doc/payment-process-recovery.md](../../doc/payment-process-recovery.md) |
| 实际发布、灰度、迁移或恢复演练 | [release-recovery.md](../workflows/release-recovery.md) |
| 并行开发副本与跨机器 Suspend/Resume | [parallel-development.md](../workflows/parallel-development.md) |
| 高风险逻辑检查（执行 `logic-auditor` 时） | [logic-audit-game-server.md](logic-audit-game-server.md) |
| 验证夹具、增量复审、打包核对与底层诊断细节 | [tooling-reference.md](tooling-reference.md) |

> **事实优先原则**：文档示例必须结合当前源码核对；遇到文档与现行实现冲突先查证，不能为迎合旧文字改坏正确代码。中文注释、异常日志等规范以 [coding-style.md](coding-style.md) 为准。
