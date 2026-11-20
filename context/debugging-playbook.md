<!-- context-meta owner:jitawangzi reviewedAt:2026-11-19 expiresAt:2027-05 -->
# Bug 排查实战手册 (Debugging Playbook)

> 本文件专为 `.ai-sop/skills/bug-debugger/SKILL.md` 提供精炼的宿主排雷导航与最小复现入口，**仅在排查 Bug / 核查疑似误报时按需加载**。详细长文档按表内指针按需查阅，不重复全文。

## 1. Phase 0 快速排雷导航（先排非代码雷）

| 排查项 | 本项目入口位置 | 排雷要点 |
|---|---|---|
| **静态配置数据** | 运行 XML：`game/src/main/resources/xml/*.xml`<br>生成类：`protocol/src/main/java/cn/game/protocol/generated/{config,manager,enume,helper}/`<br>运行期查表：`ConfigQueryService` | 先核对表行 ID、数组格式（`\|` 与 `;`）、条件/权重/时间窗口与实际生效版本；禁止手改生成类（详见 [config-rules.md](config-rules.md)）。 |
| **错误码与失败口径** | `protocol/src/main/java/cn/game/protocol/manual/ErrorMsgEnum.java` | 业务失败统一 `player.fail(ErrorMsgEnum.xxx)` 抛 `LogicException`；核对是否为预期前置条件拦截。 |
| **系统与业务日志** | 配置：`game/src/main/resources/log4j2.xml`<br>系统/报错：`logs/system/`（`stdout`/`Warn`/`Error`/`Net`/`Db`）<br>业务流水：`logs/game/`（`money`/`recharge`/`shoptrade`/`activity`/`item`/`task` 等） | 查报错堆栈看 `Error`/`Warn`；查扣费/发奖/活动链路对账看对应业务流水日志。 |
| **测试期白盒观测** | `RequestTraceService`、`PlayerInspectService`、`ProtocolSimulationService`（`game/.../net/game/gm/`） | 非生产环境可录制请求 Trace、资源净变化与模块字段自省。 |
| **运行目标与环境** | [runtime-verification.md](runtime-verification.md)、[verification-effects.md](verification-effects.md) | 常规排查不默认启服；联调前先核对实例进程、制品快照与配置版本，避免测错旧包。 |

## 2. 最小复现路径分级（按成本由低到高）

### Level 1（首选）：进程内 JUnit 5 + 轻量夹具（秒级，不启服）

- **执行命令（关键坑）**：根 `pom.xml` 默认 `<skipTests>true</skipTests>`，且本机 Maven 默认 Surefire 2.12.4 **不跑 JUnit 5**，切勿直接运行裸 `mvn test`。统一使用：
  ```powershell
  pwsh -NoProfile -File ./.ai-workspace/scripts/run-java-tests.ps1 -Project game -Test <测试类名>
  ```
  （正式修复在 SOP 任务内通过 `Task Run` 留证，Profile 见 [project-tooling.md](project-tooling.md)。）
- **Mock 基础设施现状**：依赖 JUnit 5 (`5.11.3`) + `awaitility`，**未引入 Mockito**。遇到静态单例（`ServerContext`、`PlayerManager`、`*Manager.instance()`）时，测试类必须标 `@Isolated`，用轻量手写替身或反射注入，并在 `@AfterEach`/`@AfterAll`/`AutoCloseable.close()` 中**还原原引用**。
- **可直接照抄的 4 个标杆样板**：
  1. **单模块内存状态/重置**：`game/src/test/java/cn/game/games/net/game/module/PlayerModuleResetTest.java`（`ClassManager.getInstance().init()` + `new Player(PlayerData)` + `player.initModule(...)` + `RunMode.DEV`）
  2. **真实协议编解码 + 邮箱 + Handler 闭环（无 DB）**：`game/src/test/java/cn/game/games/net/game/module/mail/MailFilterTest.java` 与 `MailFilterFixture.java`
  3. **合成配置表 + 快照冷重载验证**：`game/src/test/java/cn/game/games/net/game/helper/FirstChargeCalibrationTest.java`（动态 DOM 构造 `*Config` 注入 `*Manager.instance()` + `CborSnappyUtil.decompress` 验落盘新对象）
  4. **虚拟线程捕获 / Trace / 虚拟时钟与可控随机**：`ProtocolSimulationServiceTest.java`（`VirtualGameClient`）、`RequestTraceServiceTest.java`、`util/.../DateUtilVirtualClockTest.java`、`util/.../RndControlledRandomTest.java`

### Level 2：模拟客户端黑盒 + 白盒一体化测试（需完整协议/模块联动或真实落库时）

- 继承 `ClientBaseScenarioTest`（`simulationclient/src/main/java/cn/game/simulation/test/ai/`），执行 `./run_client.ps1 -TestClass <完整类名>`；完整 API 见 [client-test.md](client-test.md) 第 10 节。
- 优先复用 `WhiteBoxTestKit`：`resetModules` / `saveSnapshot` / `setVirtualTimeOffset` / `seedRng` / `sendAndTrace`（自动附服务端错误与资源流水净额）/ `inspectModuleField` / `flushAndColdReload()`。

### Level 3：真实 DB / 进程恢复测试（仅涉真实 MySQL/ZK/强杀恢复）

- 参考 `*DatabaseIT.java` 与 [state-integrity-testing.md](state-integrity-testing.md)，不作为常规业务 Bug 的默认入口。

## 3. 本项目高频“修表面漏根因”陷阱

完整已知缺陷模式库见 [logic-audit-game-server.md](logic-audit-game-server.md)，排查时重点防以下 4 类误修：

1. **虚拟线程 + 异步窗口重入**：同 `playerId` 在邮箱内串行，但跨越 `AsyncUtils.await(...)`、跨玩家或跨节点回调时状态可能已变；禁止只在下游加去重标记，必须追查资格校验与状态占用的原子顺序。
2. **周期重置污染与遗漏**：检查 `LIMIT_STATE_POISONING`（先覆盖日期再递增次数）与 `LAZY_RESET_UNPERSISTED`（只在查询入口 reset，玩家未打开界面直接发写请求就出错）；时间一律走 `DateUtil`（禁用 `System`）并核对 `00:00` vs `05:00` 跨天口径。
3. **内存幻觉（`IN_MEMORY_TEST_MIRAGE`）**：常规 `BasePlayerModule` 走定时全量快照，独立表（如邮件）走 `DbEntity` 显式写入；`synchronizeDataFromServer()` 只是协议刷新，验证落库类 Bug 必须走保存完成 → 新对象冷重载（单测看 `CborSnappyUtil.decompress`，联调看 `flushAndColdReload()`）。
4. **源头写入 vs 存量脏存档**：修完写入源头后，单独评估线上老玩家已有脏数据在加载/重登重建（`initFromDb` / 模块生命周期）时是否需要显式兼容兜底，不混为一谈。

## 4. B 类（难复现）《精准取证清单》索取项参考

当 Bug 归类为 B 类（`L3 推理待证`）时，向提单人/运维索取证据尽量精确到以下维度：
- **定位标识**：`playerId`、`serverId`、触发时间窗口（精确到分钟）、客户端报错码（对照 `ErrorMsgEnum`）与触发协议名/按钮操作顺序。
- **日志片段**：对应时段的 `logs/system/{Error,Warn,stdout}` 及受影响业务流水（如 `logs/game/{money,recharge,activity,item,task}`）。
- **数据与版本快照**：对应配置 XML 版本/行内容，及受影响玩家相关模块/独立表（如 `t_player` 模块快照或 `mail` 等表）的关键字段值。
