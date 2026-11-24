<!-- context-meta owner:jitawangzi reviewedAt:2026-11-21 expiresAt:2027-05 -->
# Bug 排查实战与调试手册 (Debugging Playbook)

> **适用场景**：人工或 AI（含 `.ai-sop/skills/bug-debugger/SKILL.md`）排查 Bug、核查疑似误报、定位线上/本地异常时按需加载。  
> **红线**：排查阶段先做**只读分诊与根因溯源**，确认需要修改代码或埋点后再按 [AGENTS.md](../../AGENTS.md) 启动 SOP 任务（不要提前 `Task Start`，不要只修表面现象）。

---

## 1. Phase 0 快速排雷导航与三类进程日志分布

### 1.1 先排非代码雷（配置 / 协议 / 运行目标）

| 排查项 | 本项目入口位置 | 排雷要点 |
|---|---|---|
| **静态配置数据** | 外部源：`../configs/Server/output/`<br>运行 XML：`game/src/main/resources/xml/*.xml`（`copy.bat` 同步全量至 `game`、`GlobalConst.xml` 至 `login`；仓内 `protocol`/`login` 亦存历史副本）<br>生成类：`protocol/src/main/java/cn/game/protocol/generated/{config,manager,enume,helper}/`<br>运行期查表：`ConfigQueryService`（`config.get`/`config.list`） | 先核对三处同步链路与 `-Dmetafolder`、表行 ID、数组分隔符（一维 `;`，二维 `\|` 与 `;`）、条件/权重/时间窗口；禁止手改生成类（详见 [config-rules.md](config-rules.md)）。 |
| **错误码与协议映射** | `protocol/src/main/java/cn/game/protocol/manual/ErrorMsgEnum.java`<br>`PbProtocol.java`、`BaseHandler`（`CMD_INVOKERS`） | 业务失败统一 `player.fail(ErrorMsgEnum.xxx)` 抛 `LogicException`；核对是否为预期前置拦截、`protocol.bat` 是否已重跑、`Request + 1 = Response` 配对是否正确。 |
| **运行目标与环境** | [runtime-verification.md](runtime-verification.md)、[verification-effects.md](verification-effects.md)、[doc/deployment_guide.md](../../doc/deployment_guide.md) | 常规排查不默认启服；联调先核对端口（ZK `2181`/Redis `6379`/Apollo `9888`/MySQL `3306`/Game `7011`/Login `9390`/GM 控制台 `18080`）、`hosts`（`127.0.0.1 test`）、`-Denv=dev`、`-DdefaultNetworkIp=127.0.0.1` 及 `runtimeIdentity <nonce>` 探针，防测错旧包。 |

### 1.2 三类进程真实日志路径（切勿把模拟客户端 `logs/*.log` 误当主服日志）

| 进程 | 实际日志路径 | 配置文件 | 优先排查场景 |
|---|---|---|---|
| **GameServer / CrossServer**（主服） | `${sys:SEVER_PATH}/logs/system/`：`stdout.log`、`system.log`、`net.log`、`warn.log`、`err.log`、`db.log`、`monitor.log`（按天归档在 `logs/system/<YYYY-MM-DD>/`）<br>`${sys:SEVER_PATH}/logs/game/` 与 `${sys:SEVER_PATH_CYLOG}`（业务流水：`money`/`recharge`/`shoptrade`/`activity`/`item`/`task` 等） | `game/src/main/resources/log4j2.xml`<br>`util/.../Log4j2ApolloLoader.java` | 主服启动、协议报错、NPE、SQL/Redis/RPC 异常、配置加载失败、保存/容量告警、业务扣费发奖对账 |
| **LoginServer**（登录服） | 控制台输出 + 启动目录 `init.log`（Apollo 覆盖时以远端配置为准） | `login/src/main/resources/log4j2.xml` | HTTP 登录、区服列表、账号校验与充值回调入口异常 |
| **simulationclient**（模拟客户端） | `logs/stdout.log`、`logs/err.log`、`logs/warn.log`、`logs/net.log`（按天归档在 `logs/<YYYY-MM-DD>/`） | `simulationclient/log4j2.xml` | 模拟客户端协议场景脚本执行、压测与客户端侧断言失败 |

---

## 2. 本服白盒与交互调试工具（非生产优先）

1. **GM Web 工作台（`GameServer` 内置 `vertx-web` + `gm-console/panels/`）**：
   - 默认地址：**`http://127.0.0.1:18080/gm-console`**（非生产模式自动开启；生产默认关闭，受 `gm.http.enabled/port/host/requireAuth/opsToken` 控制，详见 [doc/deployment_guide.md](../../doc/deployment_guide.md)）；
   - 自动发现全服功能模块、`proto.catalog`（协议与错误码字典）、`config.*`（配置表查询）；
   - 支持动态协议表单发包，捕获主 `Response` + 伴随 `Push`、请求级 Trace（`withTrace=true`）与前后模块字段 Diff（`withDiff=true`）；
   - 对应底层观测服务：`RequestTraceService`、`PlayerInspectService`、`ProtocolSimulationService`（`game/.../net/game/gm/`）。
2. **结构化测试协议 `0x6f` 与核心白盒指令**（`GmDispatcher` 同时接受规范全名 `player.gm.*`/`player.time.*` 与无冲突短名 `gm.*`/`time.*`）：
   - `gm.inspect`：只读抓取在线玩家指定模块真实内存状态（`OPS_SAFE`，在目标玩家虚拟线程内采集）；
   - `gm.trace.*`：录制非生产业务请求 Trace、资源流水净变化与 ERROR 日志；
   - `time.*`：非生产跨平台虚拟时钟（`DateUtil` / 跨天 / 跨周 / 跨月结算测试）；
   - `gm.snapshot.*` / `gm.flushAndColdReload`：非生产玩家快照与强制落盘冷重载（复现“内存正常、重登丢失”类持久化 Bug）；
   - `gm.rng.*`（`gm.rng.seed` / `gm.rng.sequence` / `gm.rng.status` / `gm.rng.reset`）：非生产可控随机（复现概率掉落/抽卡类 Bug）；
   - *安全边界*：生产模式（`RunMode.PRODUCTION`）硬禁用 `DEV_TEST_ONLY` 与 `0x6f`，只读排查仅限 `OPS_SAFE`。
3. **模块双轨验收**：模块级契约与全量配表矩阵扫描可调用 `module-acceptance-tester` Skill 或运行 Profile `module-acceptance-platform`。

---

## 3. 最小复现路径分级（按成本由低到高）

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

- 继承 `ClientBaseScenarioTest`（`simulationclient/src/main/java/cn/game/simulation/test/ai/`），执行 `./run_client.ps1 -TestClass <完整类名>`；完整 API 见 [client-test.md](client-test.md)。
- 优先复用 `WhiteBoxTestKit`：`resetModules` / `saveSnapshot` / `setVirtualTimeOffset` / `seedRng` / `sendAndTrace`（自动附服务端错误与资源流水净额）/ `inspectModuleField` / `flushAndColdReload()`。

### Level 3：真实 DB / 进程恢复测试（仅涉真实 MySQL / ZK / 强杀恢复）

- 参考 `*DatabaseIT.java`、[state-integrity-testing.md](state-integrity-testing.md) 与 [doc/payment-process-recovery.md](../../doc/payment-process-recovery.md)，不作为常规业务 Bug 的默认入口。

---

## 4. 本项目高频“修表面漏根因”陷阱与高危红线

完整已知缺陷模式库见 [logic-audit-game-server.md](logic-audit-game-server.md)，排查与修复时重点防以下 5 类误区：

1. **虚拟线程 + 异步窗口重入**：同 `playerId` 在邮箱（`IdVirtualThreadProcessor`）内串行，但跨越 `AsyncUtils.await(...)`、误用 `CompletableFuture` 回调链、跨玩家或跨节点回调时状态可能已变；禁止只在下游加去重标记，必须追查资格校验与状态占用的原子顺序。
2. **周期重置污染与遗漏**：检查 `LIMIT_STATE_POISONING`（先覆盖日期再递增次数）与 `LAZY_RESET_UNPERSISTED`（只在查询入口 reset，玩家未打开界面直接发写请求就出错）；时间一律走 `DateUtil`（禁用 `System`）并核对 `00:00` vs `05:00` 跨天口径。
3. **内存幻觉（`IN_MEMORY_TEST_MIRAGE`）**：常规 `BasePlayerModule` 走定时全量快照，独立表（如邮件）走 `DbEntity` 显式写入；`synchronizeDataFromServer()` 只是协议刷新，验证落库类 Bug 必须走保存完成 → 新对象冷重载（单测看 `CborSnappyUtil.decompress`，联调看 `flushAndColdReload()`）。
4. **源头写入 vs 存量脏存档**：修完写入源头后，单独评估线上老玩家已有脏数据在加载/重登重建（`initFromDb` / 模块生命周期）时是否需要显式兼容兜底；登录链路同时注意区分物理节点 ID、逻辑区服 ID（`VirtualServerRegistry`）、账号 UID 与 `playerId`（见 [doc/01_系统架构设计全景文档.md](../../doc/01_系统架构设计全景文档.md) 第 1.3 节）。
5. **充值/订单异常（高危红线）**：严禁擅自删除热订单、重放发货或解除 `PAYMENT_FROZEN` / `UNKNOWN` 隔离。使用只读离线核对工具 `payment-evidence.ps1` / `payment-cleanup-preflight.ps1` 并对照 [doc/payment-process-recovery.md](../../doc/payment-process-recovery.md) 与 [doc/01_系统架构设计全景文档.md](../../doc/01_系统架构设计全景文档.md) 支付章节处置。

---

## 5. B 类（难复现）《精准取证清单》索取项参考

当 Bug 归类为 B 类（`L3 推理待证`）时，向提单人/运维索取证据尽量精确到以下维度：
- **定位标识**：`playerId`、`serverId`（区分物理节点 ID 与逻辑区服 ID）、触发时间窗口（精确到分钟）、客户端报错码（对照 `ErrorMsgEnum`）与触发协议名/按钮操作顺序。
- **日志片段**：对应时段的 `logs/system/{err,warn,stdout,net}.log`（及 `LoginServer` `init.log`）和受影响业务流水（如 `logs/game/{money,recharge,activity,item,task}`）。
- **数据与版本快照**：对应配置 XML 版本/行内容，及受影响玩家相关模块/独立表（如 `t_player_data` 模块快照或 `mail` 等表）的关键字段值。
