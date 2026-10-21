# 个人项目 SOP 迁移记录

迁移日期：2026-10-21。源项目知识为 `.claude_old/context/`；跨项目经验来自 aircraft 工作区提交 `f07ffb3`。本次保留旧目录原件，不复制旧 Skills、旧 MCP 绝对路径、会话或批准状态。

## 旧知识去向

| 旧 context | 新 context | 处理 |
|---|---|---|
| project-summary.md | [项目概览](../context/project-summary.md) | 保留，修正缺失的旧 SOP 链接，补新布局和事实边界 |
| coding-style.md | [编码规范 Part B](../context/coding-style.md) | 保留异常/API/资源/JavaDoc，澄清 notify 与响应填充职责 |
| ai-coding.md | [完整开发知识](../context/ai-coding.md) | 保留架构、线程、事件、GM、物品、条件；修复未闭合代码块，区分内存变更和完成保存 |
| api-whitelist.md | [API 快照](../context/api-whitelist.md) | 保留全部签名，去失效绝对路径，标明需核对当前源码 |
| client-test.md | [模拟客户端测试](../context/client-test.md) | 保留客户端 API/GM，修复协议链接；取消“跳过目标请求也算通过”的旧表述 |
| config-rules.md | [配置指南](../context/config-rules.md) | 保留生成链与表规范，补真实来源/隔离测试约束 |
| proto-rules.md | [协议规范](../context/proto-rules.md) | 保留 Protobuf 编号、生成和同步方式，补兼容与接收方视角 |
| systems/condition-system.md | [条件系统](../context/systems/condition-system.md) | 完整保留，business-patterns 只建立索引，不维护重复正文 |

旧 Dragon `SERVER_RULES.md` 按原文件保存到新 specs，对其未确认设计不作业务推断，也不生成批准状态。

## aircraft 经验的取舍

| 参考资产 | 迁入内容 | 适配边界 |
|---|---|---|
| coding-style Part A | 增量修改、禁止顺手整顿/改基础设施、旧校验链、中文注释、设计意图与方法契约、异常至少 warn/堆栈 | 持久化改为验证宿主保存闭环，不要求所有 Module 手动 save；去专有 API 示例 |
| coding-style Part B | 对象复用、Fast-Fail、错误语义、旧数据迁移、混跑写回、接收方展示兼容、埋点字段复用 | 用个人项目 ErrorMsgEnum/Module/DbEntity；不迁 Mongo DAO、字段缩写、SVN、Gradle、默认时区与发布顺序假设 |
| business-logic-pattern 与六个专题 | 条件/状态/展示分离、写入口防御重置、活动收尾、任务晚开启补判、事件、红点、资源闭环 | 适配 Handler/Module/PlayerHelper/Condition，不迁参考项目具体业务类与奖励类型 |
| proto-rules | 业务结果优先、静态 ID、字段稳定、兼容窗口、按接收方过滤 | 保留本项目 Protobuf 与资源通知契约，不照搬 JSON 命名或资源同步策略 |
| client-test | 正式入口 Act、GM fixture、冷重载、真实配置来源、断言分层、失败证据、进程归属 | 使用模拟客户端；定时保存完成后再冷重载，不移植 JSP/Tomcat 工具 |
| logic-audit-game-server | 重入、越权、部分成功、周期污染、保存假象、恢复幂等、兼容覆盖、日志追溯 | 检查清单不自动给 T1/T2 增加独立审核或新门禁 |
| project-tooling / workflows | 仓库归属、真实验证记录、同步与运行隔离 | Maven + Git，schemas/scripts/workflows 目录保留，但不复制不适用的运行脚本 |

## 已核对与待核实

本次查证根 POM 的六模块、JDK 21、默认 skipTests=true，以及 IdVirtualThreadProcessor、BasePlayerModule、PlayerHelper、ClientBaseScenarioTest、run_client.ps1、protocol.bat 的对应职责。其他 API 快照与旧业务知识保留，使用前须查对应源码，不能宣称逐个方法均已验证。

尚未确定个人项目的发布顺序、客户端回退能力、各活动时区和完整联调环境；这些约束在相关功能任务中核实，未写入参考项目的假设。本次不启动游戏服务、修改数据库或验证 Dragon 业务。

宿主原有工作树包含 PlayerManager.java 修改、旧 `.claude` 删除及若干未跟踪文件；迁移前保存了本机哈希清单，收尾核对既有文件和 `.claude_old` 原件。aircraft 只读，未修改其仓库配置或内容。

引擎接入遇到默认分支 dev 无法登记的问题，已在 `13601f6` 修复为识别 Git 的真实 origin/HEAD，继续计算 merge-base 并保留基线防收窄校验；未把宿主改名为 main。补齐临时 SVN 工具后，全量自动发现的 33 套测试全部通过。

项目输入策略额外纳入工作区文档、配置与脚本，使其实际内容绑定验证证据；保留默认业务输入，不通过排除源码或执行豁免完成迁移。Start 因当时打开中的 Word 文档锁未能采集起点，按引擎规则保留 UNAVAILABLE；用户保存关闭后继续正常 T2 验证，不补造起点。另核实 `logs/` 是 GameSSLogger、LoggerManager 与 Log4j2 的运行输出，且已被宿主 Git 忽略；项目策略排除此目录，避免持续写入的无 `.log` 后缀埋点日志被误当构建输入。

最终版本、验证结果和仓库提交以工作区 README 与本任务记录为准。
