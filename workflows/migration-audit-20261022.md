# 迁移审查补充与事实纠正

本次依据用户转交的 Antigravity 只读报告继续完善迁移，宿主为个人 `server`，任务 `SopMigration/audit-fixes-20261022`，T2（默认）。旧 `.claude_old` 保留供比较；本轮不修改 Java 业务逻辑、协议或运行数据库。

## 审查项处理

| 报告项 | 核实与处理 |
|---|---|
| 旧 QA 项目细节遗漏 | client-test 补精确包/目录、sendGmCmd、经验升级与自定义 GM 的准备/观察/清理边界 |
| 经验 ID 100002 | 报告沿用旧 Skill 的过时值：当前 Asset.gold=100002，playerExp=100201，按源码纠正 |
| generate_excel 遗漏 | 脚本确实存在；config-rules 记录输入字段、输出位置、pandas/openpyxl 依赖及异常退出码不可靠的限制；不混同正式导表器 |
| API 导出旧目录 | export_api.bat 输出改为新 context，并给 classpath/输出参数加引号；未运行导出覆盖已有快照 |
| commit/pull 缺失 | 工作区与独立 specs 都提供入口；仅提交已暂存文件，拉取只允许干净树 fast-forward，不硬编码本机代理 |
| 新鲜度与索引 | 四份默认文档补/更新 context-meta；README 分离流程专属索引 |
| 静态导入、跨天口径 | 补新增/直接修改代码禁用 import static；核实 refreshDay/NewDay 为 00:00，保留明确使用 NewDay5 的既有功能 |
| 协议 Map 与字段表 | 补新协议结构化 repeated 消息、既有 map 兼容边界及逐字段核对表 |
| 配置路径与校验 | 补 XML 与 generated 四类目录；加载期校验、增量兼容及优先局部扩展 |
| 审计库过度摘要 | 恢复 LAZY_RESET_UNPERSISTED、LIMIT_STATE_POISONING、IN_MEMORY_TEST_MIRAGE 等代号与错误/修复形态，补并发、装配、越权、补偿、恢复和混跑检查 |
| 六个业务专题不足 | 补生命周期、接入步骤、反模式、回归与实际入口；总纲恢复索引及分层 |
| Goods 包名 | 报告中的包名不准确；使用 cn.game.games.net.game.module.award.Goods，区分配置、计算、实际发放结果和持久化契约 |
| 红点适配 | 核实 PlayerHandler/ActivityHandler 及 ActivityBase.hasRed；当前协议按请求顺序返回 repeated bool，不套用位图 |
| 测试分级与复用 | 补 Path A/B、保存闭环、降级边界和 Bug 回归复用清单 |
| Java test Profile | 增加定向 smoke 与全量入口；本机默认 Surefire 2.12.4 实测零测试，改由工作区脚本调用固定 Surefire 3.5.2 并拒绝无新报告/零执行 |
| run_client classpath | 不仅补 util，还将所有兄弟 classes 放在依赖 JAR 前；用真实同名 Java 类验证新 util 优先于旧 JAR |
| Doctor JDK 8 | 在引擎真源修复最小降级检查，已用本机 Java/javac 21 验证；不直接手改投影 |
| 共享 specs 干扰 | 保留用户确认的共享历史，文档推荐 Discover -Feature；LEGACY/PAUSED 不代表应恢复其他项目任务 |
| 诊断命令被拦截 | 引擎识别 Verify/Doctor/Status/Inputs/Preflight/Help 的受限字面命令；重放重验路径，保留客户端原生权限 |
| Verify 实际有恢复副作用 | 同时修复自动初始化/恢复路径：Verify 只检查，未决安装报错，恢复由显式 Install 处理 |
| Hook wrapper 相对路径 | 报告误判：Antigravity 从 hooks.json 所在目录启动，现有路径正确；根 ANTIGRAVITY 指令已说明 wrapper → dispatcher 链路 |
| wrapper AgentHint 缺失 | 不强行改统一入口；Claude/导入的 Cursor 依靠载荷识别，Pi 扩展显式传 PI，底座真实进程测试覆盖 |
| 宿主 .gitignore/旧删除 | 本机 .git/info/exclude 已隔离知识仓库/旧目录；生成入口和子模块是安装资产，不统一忽略；既有宿主工作树留用户整理提交 |
| ai-workspace 远端冲突 | 用户已明确 aircraft 旧知识工作区弃用，远端专供个人 server；不新建仓库、不拆分分支 |

## 规范取舍

恢复的是可执行的工程知识，不复制外部项目的业务类、持久化框架或旧 T3 门禁。常规 Module 仍遵循框架保存，不要求每个请求手动 save；条件、活动关闭态、红点与奖励以本项目源码和具体功能规则为准。旧例子中的错误、未知发布时序和部署时区不会当成已确认事实迁入。

## 验证与证据位置

引擎提交 `69181cf` 全量自动发现的 34/34 套件通过，manifest 与两个安装目标校验通过；个人项目实际 wrapper 在隔离的未登记/INACTIVE 会话中放行并执行六种诊断，权限记录未改变。这是安装进程验证，新增诊断仍与 Antigravity 客户端现场认证区分。

宿主最终记录使用 workspace-syntax（解析/Schema）、workspace-contract（链接/知识/安装）、workspace-script-tests（隔离 Git 行为/真实 Java 类加载）与 java-unit-smoke（定向 JUnit）。实际成功/失败、测试数、RecordSync 与 Complete 以 specs/features/SopMigration/tasks/audit-fixes-20261022 的机器记录及功能说明为准。全量游戏测试、模拟客户端联网、服务重启和数据库业务不属于本次验证结论。
