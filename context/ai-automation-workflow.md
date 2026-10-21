# 项目交付适配索引

本文件只定位项目知识与产物，不复制旧 SOP 的编排规则。任务入口统一为根 `AGENTS.md` 和 `ai-sop.ps1 Task`。默认 T2，人工档位优先；T3 才加载 `.ai-sop/workflows/agent-t3.md` 与 `.ai-sop/workflows/superpowers-adapter.md`。

| 工作 | 项目知识 |
|---|---|
| 架构与业务实现 | project-summary、coding-style、business-logic-pattern、ai-coding |
| 协议与配表 | proto-rules、config-rules |
| 测试验证 | client-test、project-tooling、verification-commands |
| 按需逻辑审查 | logic-audit-game-server、对应 business-patterns 专题 |

功能资料位于 `.ai-workspace/specs/features/<FeatureName>/`。新流程使用 `01_server_rules.md`、`06_design_contract.md`、`05_test_plan.md`、机器生成的覆盖/状态文件及 `tasks/`。只创建本档实际需要的产物，T2 不为形式补完整 T3 模板。

通用 Schema 真源在 `.ai-sop/schemas/`，本工作区 `schemas/` 仅存项目自有扩展。批准、状态、任务、会话与证据必须由引擎写入，不能手写成功状态。旧规格中的 FINALIZED、已确认或已完成文字不自动变成新机器批准。

旧 Dragon `SERVER_RULES.md` 作为历史需求保留；若开展该功能，先核对业务事实与当前实现，再按实际档位整理当前契约。迁移本身不宣称 Dragon 已实现或验收。
