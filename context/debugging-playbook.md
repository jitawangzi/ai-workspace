<!-- context-meta owner:jitawangzi reviewedAt:2026-11-21 expiresAt:2027-04 -->
# 游戏服务端排障与调试手册 (Debugging Playbook)

> **适用场景**：人工或 AI 排查 Bug、核查疑似误报、定位线上/本地异常。  
> **红线**：排查阶段先做**只读分诊与根因溯源**，确认需要修改代码或埋点后再按 [AGENTS.md](../../AGENTS.md) 启动 SOP 任务（不要提前 `Task Start`，不要只修表面现象）。

---

## 1. 第一现场：日志目录与常见观测点

实时运行日志默认输出在宿主根 `logs/` 及进程目录（已 Git 忽略，不纳入 SOP 输入指纹）。**排查服务端 Bug 时务必先分清进程，切勿把模拟客户端的 `logs/*.log` 误当成主服日志**：

| 进程 | 实际日志路径 | 配置文件 | 优先排查场景 |
|---|---|---|---|
| **GameServer / CrossServer**（主服） | `${sys:SEVER_PATH}/logs/system/`：`stdout.log`、`system.log`、`net.log`、`warn.log`、`err.log`、`db.log`、`monitor.log`（按天归档在 `logs/system/<YYYY-MM-DD>/`）<br>`${sys:SEVER_PATH}/logs/game/` 与 `${sys:SEVER_PATH_CYLOG}`（业务/渠道统计流水，如 `login`/`recharge`/`money`/`item` 等） | `game/src/main/resources/log4j2.xml`<br>`util/.../Log4j2ApolloLoader.java` | 主服启动、协议报错、NPE、SQL/Redis/RPC 异常、配置加载失败、保存/容量告警、业务流水核对 |
| **LoginServer**（登录服） | 控制台输出 + 启动目录 `init.log`（受 Apollo 动态配置覆盖时按远端配置为准） | `login/src/main/resources/log4j2.xml` | HTTP 登录、区服列表、账号校验与充值回调入口异常 |
| **simulationclient**（模拟客户端） | `logs/stdout.log`、`logs/err.log`、`logs/warn.log`、`logs/net.log`（按天归档在 `logs/<YYYY-MM-DD>/`） | `simulationclient/log4j2.xml` | 模拟客户端协议场景脚本执行、压测与客户端侧断言失败 |

> 启动期日志级别、Apollo 动态覆盖及各服务端口见 [doc/deployment_guide.md](../../doc/deployment_guide.md)。

---

## 2. 本服白盒与交互调试工具（非生产环境优先使用）

当前工程已内置完整的 GM 与协议白盒调试底座，排查功能 Bug 时**优先用真实运行时观测，不要靠猜**：

1. **GM Web 工作台（`GameServer` 内置 `vertx-web` + `gm-console/panels/`）**：
   - 自动发现全服功能模块、Proto 协议目录（`proto.catalog`）、错误码字典（`ErrorMsgEnum`）与配置表查询（`config.tables` / `config.list` / `config.get`）。
   - 支持**动态协议表单发包**、捕获主 `Response` + 伴随 `Push`、查看单次请求耗时/异常/资源流水（`withTrace=true`）以及执行前后模块状态差异（`withDiff=true`）。
   - 磁盘热重载面板位于 `gm-console/panels/`（示例：`quick-test-panel.html`）。
2. **结构化测试协议 `0x6f` 与核心白盒指令**：
   - `gm.inspect`：只读抓取在线玩家指定模块真实内存状态（`OPS_SAFE`，在目标玩家虚拟线程内采集）。
   - `gm.trace.*`：录制非生产业务请求 Trace、资源流水与 ERROR 日志。
   - `time.*`：非生产跨平台虚拟时钟（`DateUtil` / 跨天 / 跨周 / 跨月结算测试），排查周期重置类 Bug 必用。
   - `gm.snapshot.*` / `gm.flushAndColdReload`：非生产玩家快照与强制落盘冷重载，用于复现“内存态正常、重登后丢失”类持久化 Bug。
   - `gm.rng.*`（`gm.rng.seed` / `gm.rng.sequence` / `gm.rng.status` / `gm.rng.reset`）：非生产可控随机，用于复现概率掉落/抽卡类 Bug。
   - *安全边界*：生产模式（`RunMode.PRODUCTION`）硬禁用 `DEV_TEST_ONLY` 与 `0x6f`，只读排查仅限 `OPS_SAFE`。
3. **模拟客户端 & 模块双轨验收**：
   - 协议级复现脚本：`run_client.ps1 -TestClass <完整类名>`，规则见 [client-test.md](client-test.md)。
   - 模块级批量契约与全量配表矩阵扫描：调用 `module-acceptance-tester` Skill 或运行 Profile `module-acceptance-platform`。
   - 联调运行实例身份核对（防连错进程/旧代码）：见 [runtime-verification.md](runtime-verification.md)（探针 `runtimeIdentity <nonce>`）。

---

## 3. 四类高频问题快速分诊路径

### 3.1 服务启动失败 / 中间件连不上
1. 先核对本地端口监听（见 [doc/deployment_guide.md](../../doc/deployment_guide.md) 第六节）：ZK `2181`、Redis `6379`、Apollo `9888`（`http://localhost:9888/health`）、ZKUI `9990`、MySQL `3306`、Game `7011`、Login `9390`。
2. 检查 Windows `hosts` 是否配置 `127.0.0.1 test`；JVM 参数是否误用了 `-Denv=local`（应为 `-Denv=dev` + `-Ddev_meta=http://test:9888`）。
3. 多网卡（VPN/VMware）导致 Vert.x 集群绑定异常时，确认已传 `-DdefaultNetworkIp=127.0.0.1`。

### 3.2 登录异常 / 协议收不到或回包错误码异常
1. 区分**物理节点 ID**（`ServerContext.getServerId()`）、**逻辑区服 ID**（`VirtualServerRegistry`，ZK 路径 `/server/login/game/virtual-servers`）、**账号 UID** 与 **`playerId`**，不要混用（详见 [doc/01_系统架构设计全景文档.md](../../doc/01_系统架构设计全景文档.md) 第 1.3 节）。
2. 检查 `protocol/` 独立仓库与 `PbProtocol.java` 是否已重新运行 `protocol.bat` 生成；确认 `Request + 1 = Response` 配对与 `BaseHandler` 注册（`CMD_INVOKERS`）。
3. 查看业务错误码：用 `proto.catalog` 或直接查 `protocol/.../ErrorMsgEnum.java`，定位对应 `player.fail(ErrorMsgEnum.xxx)` 抛出点。

### 3.3 配表不生效 / 数值不对 / NPE
1. 核对三处同步链路：外部真源 `../configs/Server/output/` → `protocol/src/main/java/cn/game/protocol/generated/{config,enume,helper,manager}/` → XML 同步至 `protocol/`、`game/`、`login/` 的 `src/main/resources/xml/`。
2. 核对 JVM 参数 `-Dmetafolder=D:\work-all\game\configs\Server` 与配表规则 [config-rules.md](config-rules.md)、`../dic_generate/配置表AI编码规范.md`。
3. 在线直接调用 `config.get` / `config.list` 验证进程实际加载的配表内容，区分“表没导进去”和“代码读错字段”。

### 3.4 玩家状态丢失 / 并发脏数据 / 充值与保存异常
1. **先查线程归属**：确认是否越过玩家邮箱（`IdVirtualThreadProcessor`）直接改了玩家状态，或误用 `CompletableFuture` 回调链（未用 `AsyncUtils.await(...)`）导致切出玩家串行队列。
2. **先查保存链路**：确认新增字段是否挂入 `BasePlayerModule` 序列化集合或独立 `DbEntity`；用 `gm.flushAndColdReload` 或定向测试 Profile `state-integrity` 验证冷重载一致性（参考 [state-integrity-testing.md](state-integrity-testing.md)）。
3. **充值/订单异常（高危红线）**：严禁擅自删除热订单、重放发货或解除 `PAYMENT_FROZEN` / `UNKNOWN` 隔离。使用只读离线核对工具 `payment-evidence.ps1` / `payment-cleanup-preflight.ps1` 并对照 [doc/payment-process-recovery.md](../../doc/payment-process-recovery.md) 与 [doc/01_系统架构设计全景文档.md](../../doc/01_系统架构设计全景文档.md) 支付章节处置。

---

## 4. 根因溯源四步法（防“只修表面”）

1. **定性分流**：先判定是 **A 可稳定复现代码缺陷**、**B 并发/环境/状态依赖难复现问题**，还是 **C 非代码误报**（配表未同步、进程跑的是旧制品、测试数据前置不满足）。
2. **反向溯源**：从报错日志/错误码一路追到真实状态写入点与事件源头，核对 `coding-style.md`、`business-logic-pattern.md` 及对应 `business-patterns/` 专题。
3. **先证后改**：修复前先构造最小可复现单测或模拟客户端场景（RED），修改后再跑 `compile` + 定向回归（GREEN）。
4. **验证事实**：绝不以 `mvn compile`（默认 `skipTests=true`）或旧日志当成已验证；按 [project-tooling.md](project-tooling.md) 用 `Task Run` 留存真实测试证据。
