---

# 模拟客户端测试指南

联调结果须区分场景进程通过与实际目标已核验，使用[运行目标证据](runtime-verification.md)；保存/幂等场景复用[状态一致性验证](state-integrity-testing.md)。二者按任务范围使用，不改变默认档位。

本文档旨在指导开发者如何使用模拟客户端工程（Simulation Client）进行游戏服务器的功能测试。通过模拟客户端，我们可以启动虚拟玩家，发送指定功能的协议与服务器交互，并处理服务器的返回数据。

> **⚠️ 前置阅读**
>
> 在使用本工程前，请确保已阅读并理解 [proto-rules.md](proto-rules.md)，以掌握协议定义的基础知识。

---

## 1. 核心概念：Client 对象

`cn.game.simulation.client.Client` 是模拟客户端的关键类。
该类代表了一个虚拟玩家对象，维护着该玩家的核心游戏数据状态。通常情况下，测试人员只需了解其作用，无需修改此类代码。

### 1.1 核心字段
以下是 `Client` 类中用于支持逻辑判断和协议构造的常用字段：

| 字段名 | 类型 | 描述 |
| :--- | :--- | :--- |
| `playerAllInfo` | `PlayerAllInfo` | **玩家核心数据**。<br>对应 `PlayerMsg.proto` 中的 `PlayerAllInfo`，通常在登录后返回并自动保存。 |
| `dataMap` | `Map<String, Object>` | **通用数据容器**。<br>可自定义 Key（如协议名），用于灵活保存测试过程中的临时上下文数据。 |

### 1.2 常用方法

获取客户端玩家缓存的核心游戏数据：

```java
public PlayerAllInfo getPlayerAllInfo() {
    return playerAllInfo;
}
```

---

## 2. 功能测试开发流程

测试某个具体功能时，请遵循以下流程新建测试类。

### 2.1 新建测试类
1.  **继承父类**：新建的测试类必须继承 `ClientBaseScenarioTest`。
2.  **命名规范**：`Client[功能名]Test`（例如邮件功能：`ClientMailTest`）。
3.  **存放目录**：需与 `ClientBaseScenarioTest` 保持在同一目录。

### 2.2 代码示例
以邮件功能测试为例：

```java
public class ClientMailTest extends ClientBaseScenarioTest {

    public static void main(String[] args) {
        // 启动测试
        new ClientMailTest().start();
    }

    /**
     * 在此处实现具体的测试逻辑
     *
     * 详细规则参考父类 executeProcess() 方法注释,这里只简要说明
     *
     * 时序性：功能通常涉及多个协议，AI需根据业务逻辑编排发送顺序。
     * 示例：副本玩法需先发送“请求副本数据”，获取数据缓存后，再发送“领取奖励”。
    * 状态依赖：后一个请求的参数可能依赖前一个请求的返回数据；若前置条件不满足，先使用已约定的 fixture 准备；无法准备则明确报告阻塞，不能跳过目标请求并声称该用例通过。
    * 执行方式*：确定顺序后，按步骤逐一启动测试。
     */
    @Override
    protected void executeProcess() throws Exception {
        // 1. 发送请求
        // 2. 验证返回
        // 3. 逻辑断言
    }
}
```


### 2.3 常用 API
在 `executeProcess` 方法中，你可以使用以下父类提供的方法：

场景类统一放在 `simulationclient/src/main/java/cn/game/simulation/test/ai/`，包名 `cn.game.simulation.test.ai`，继承同包 `ClientBaseScenarioTest`。这些是带 main 入口的模拟客户端场景，不属于 Surefire 自动发现的 `src/test/java` 用例。

*   **同步发送消息**：
    `sendAndWait(Message request)` —— 发送消息并阻塞等待服务器返回,需要根据协议规则推断返回类型
*   **同步玩家数据**：
    `synchronizeDataFromServer()` —— 请求服务器刷新当前玩家的最新核心数据 (`playerAllInfo`)。
*   **GM 准备状态**：
    `sendGmCmd(String cmd)` —— 基类封装 `TestGmCmdRequest_6f000001` 并调用 `sendAndWait`；例如 `sendGmCmd("item 100001 1000")`。检查响应错误码与准备后的状态，不能只确认消息发出。

---

## 3. 编译与运行

### 3.1 按范围编译与启动
常规验证先用 project-tooling.md 的 Maven 编译与定向测试。只有本次需要完整协议联调且已确认环境、进程归属和账号时，才启动/重启服务；不要把启动完整环境作为每次任务的默认步骤。
以下入口默认只准备独立制品快照；实际启动使用 `-Action Start -Snapshot <目录> -ConfirmDataScope`，先确认该快照的测试存储范围。身份与逻辑区服核对见 [运行目标证据](runtime-verification.md)：

```powershell
pwsh -NoProfile -File ./run_server.ps1
```

### 3.2 运行测试

使用 PowerShell 脚本执行测试：

```powershell
pwsh -NoProfile -File ./run_client.ps1 -TestClass <完整类名>
```

### 3.3 结果检查与排错

执行脚本后，请根据控制台输出判断结果：

*   ✅ **SCENARIO_PROCESS_PASS**
    *   **含义**：脚本执行成功；仍须核对目标断言确实执行、无跳过。该提示不等于 SOP 任务 Complete 或完整业务验收。

*   ❌ **COMPILATION FAILED**
    *   **行动**：阅读上方 Maven 错误日志，修复 Java 语法错误后重试。

*   ❌ **TEST FAILED**
    *   **行动**：阅读控制台打印的 Java 运行时日志，根据错误类型分析：
        *   **Timeout (超时)**：检查服务器是否正在运行，或代码逻辑是否被某些操作阻塞。
        *   **Assertion Error (断言错误)**：检查模拟数据（如道具数量、前置条件）是否与服务器逻辑预期不符。

> **失败续做**：保留失败日志，定位根因后复用同一验证批次复测；不靠无关成功覆盖失败。恢复与证据规则遵循根 AGENTS.md。

---

## 4. 其他注意事项

1.  **请求机制**：
    客户端是同步阻塞模型。每次只能向服务器发送一个请求，在该请求收到回应（或超时）之前，不会发送新的请求。

2.  **账号管理**：
    *   **默认行为**：每次测试默认使用一个新的随机账号注册,服务器默认会给账号添加足够的资源，开启所有功能等，方便测试。
    *   **固定账号**：如果需要保持使用同一个账号进行连续测试，请修改 `env.properties` 文件：

    ```properties
    # env.properties
    # 设置用户名时使用固定账号，不设置则每次重新注册
    user.name=19952
    ```
## 5. GM 指令辅助测试

在测试过程中，经常需要快速设置玩家状态（如发道具、跳关卡、跨天）。可以通过发送 GM 指令协议来实现。

### 5.1 协议说明

*   **协议号**: `TestGmCmdRequest_6f000001` (PbProtocol.TestGmCmdRequest_6f000001)
*   **参数**: `cmd` (字符串)

### 5.2 使用示例

继承基类时优先 `sendGmCmd("item " + Asset.playerExp.ID + " 10000")` 准备经验，`Asset` 为 `cn.game.protocol.generated.enume.Asset`。当前 `playerExp.ID=100201`；旧 Skill 的 `100002` 现为金币，不能照抄。资源增加经 `CurrencyModule` / `PlayerHelper` 的等级处理链产生升级，仍应断言最终等级及开放状态。下例保留手动协议写法供理解底层行为。

```java
// 发送 GM 指令：增加 1000 个 100001 号道具
TestGmCmdRequest_6f000001 gmReq = TestGmCmdRequest_6f000001.newBuilder()
    .setCmd("item 100001 1000")
    .build();
sendAndWait(gmReq);

// 发送 GM 指令：模拟跨天
TestGmCmdRequest_6f000001 newDayReq = TestGmCmdRequest_6f000001.newBuilder()
    .setCmd("newday")
    .build();
sendAndWait(newDayReq);
```

### 5.3 常用指令速查

| 指令 | 参数示例 | 描述 |
| :--- | :--- | :--- |
| `item` | `item 100001 100` / `item 200001 10` | 增加资源或道具（遵循 6 位分段规则：`100001`=元宝、`100002`=金币、`200001`=道具） |
| `hero` | `hero 331001 1` | 增加英雄（如 `331001`=孙悟空，具体 ID 查 `Hero.xml`） |
| `zxgk` | `zxgk 1005` | 设置主线关卡进度到 1005 |
| `newday` | `newday` | 触发玩家个人跨天逻辑 |
| `time` / `time.offset` | `time.offset offset="+1d"` | 虚拟时钟时间偏移（`+1d`=1 天、`-2h`=2 小时；详见 [ai-coding.md](ai-coding.md) 第 12 节） |

### 5.4 item 指令特殊用法 (批量添加)

`item` 指令支持通过设置数量为 `0` 来实现**按类型批量添加**所有物品。

*   **格式**: `item [ID或类型ID] 0`
*   **规则**:
    *   当 `count` 为 0 时，第一个参数既可以是具体的 ItemId，也可以是 `GoodsTypeEnum` 的类型 ID (1=资源, 2=道具, 3=英雄...)。
    *   系统会自动遍历该类型下的所有配置表，并添加对应物品。
    *   **数量规则**:
        *   资源类 (Type 1): 每种 +1,000,000
        *   道具类 (Type 2): 每种 +80,000
        *   英雄 (Type 3): 每种 +1
        *   其他实体类: 通常 +1 或 +10

*   **示例**:
    *   `item 1 0` -> 添加所有类型的资源 (金币、钻石、经验等) 各 100万。
    *   `item 2 0` -> 添加游戏内所有道具 各 8万个。
    *   `item 100001 0` -> 100001 是资源类型，效果同 `item 1 0`。

---

## 6. 对抗性测试要求
- **边界值**: 必须测试字符串为空、最大长度、特殊字符。
- **重复请求**: 测试连续发送两次相同请求（幂等性）。

### 自定义 GM 的边界

现有 GM 无法精确构造状态时，可在当前任务范围内在 `cn.game.games.net.game.gm.command` 下新增或扩展带 `@Component` + `@GmGroup` / `@GmAction` / `@GmParam` 注解的 GM 分组类，由 `GmDispatcher` 自动扫描注册并纳入 `GmSecurityTier` 安全分级（详见 [ai-coding.md](ai-coding.md) 第 12 节；旧式 `AbstractGm` + `GmRegistry`/`GmCommand` 仅作历史兼容基类与参数辅助保留，不再用于手工注册新指令）。自定义 GM 仅用于 Arrange / Observe / Cleanup，不代替被测正式入口，不绕过资格或直接执行目标奖励逻辑。检查环境/权限、影响账号、可重复执行与清理方式；新增服务端代码按正常编译和部署流程生效，不为测试方便修改公共持久化模型。

## 7. 从实践迁移的测试闭环

- 先复用现有测试计划、模拟客户端场景与通用 GM 原语。GM 仅用于准备、观察、清理；目标行为由正式 Protobuf 请求或正式业务入口触发。
- 断言至少覆盖响应、服务端状态、副作用和相关回归。`println`、服务启动成功、无异常退出均不能替代业务断言；用例失败必须产生非零退出码。
- 跨天、限购、懒重置、发奖、扣费应覆盖“未打开查询页直接写请求”、连续重复请求、失败后重试及重登。
- 对保存行为的验证：触发正式操作 → 等待或通过测试设施确认本项目保存完成 → 从持久化介质重载为新对象 → 断言真实字段。`synchronizeDataFromServer()` 只是协议刷新，不保证从数据库冷读。常规 Module 的定时保存与独立表显式保存分别验证，不为测试便利改框架保存策略。
- 保存 expected、actual、失败步骤、账号/轮次和必要日志；失败即停止依赖后续步骤，清理本用例资源。时间控制恢复原值，共享环境串行执行会相互污染的用例。
- 使用当前配置解析链确认 XML 的实际目录/版本；可控夹具写清用途与来源，不伪称真实配表验证。不要修改生产配置做测试。
- 涉及外部埋点时检查字段名、触发时机、失败/回滚不发及重试不重复。
- 修改 Java 后按本项目实际进程部署并重启受影响实例；复制 class 到运行目录不证明已加载。只操作已确认的工作区、实例、PID，不按 java 进程名全局清理。
- 纯逻辑测试、模拟客户端联调、持久化冷重载覆盖不同层次；交付列明实际执行范围。T1/T2 不自动增加独立审核或完整环境启动要求。

## 8. 验证路径分级

| 路径 | 适用范围 | 必须观察 | 不能证明 |
|---|---|---|---|
| Path A：进程内 / 模块级 JUnit | 纯计算、条件判定、状态转换、可隔离的模块行为 | 输入边界、失败分支、真实业务入口的断言与测试计数 | 网络协议、实际数据库、运行中服务已加载新代码 |
| Path B：模拟客户端协议测试 | Handler、鉴权、协议顺序、模块与资源通知联动 | 正式 Protobuf 请求、错误码、回包/推送、状态与副作用 | 仅刷新协议缓存不能证明冷重载持久化 |
| 模块双轨验收与多态配表全集扫描 | 模块级全协议契约验收 (`CONTRACT`) + 多态策略分支 × 全量正式配表遍历扫雷 (`MATRIX_SCAN`) | 进程内沙盒玩家、虚拟存盘确认、三维副作用静默、分支命中覆盖率与资源守恒断言 | 跨进程真实 TCP 握手与外部 MySQL/Redis 物理写入 |
| 保存闭环补充 | 重置、扣费、领奖、迁移等依赖保存的修改 | 保存完成后从持久化介质重建新对象，验证字段和幂等性 | 读取同一 Player/Module 内存对象不能作为落库证据 |
| 环境受限降级 | 完整环境未就绪时先做 Path A | 明确已执行的断言、未覆盖入口及限制 | 不将 A 改称 B；按需求目标补必要验证或记录真实待办 |

## 9. Bug 修复测试复用清单

| 检查 | 做法与通过依据 |
|---|---|
| 既有用例 | 检索同功能规格、JUnit 与模拟客户端场景；优先在旧用例补断言，避免重建平行框架 |
| 修复前失败 | 尽可能用同一入口复现原错误，记录 expected/actual；无法重现说明缺失条件，不伪造 RED |
| 状态准备 | 复用基类、现有 GM 和配置解析链；GM 只负责准备，正式请求负责 Act |
| 关键回归 | 未先查询直接写、边界时间、重复请求、失败重试、跨账号归属、已有类型不退化 |
| 保存与展示 | 回包、通知、资源增减、领取位一致；保存类缺陷补新对象重载，红点验证亮起和消除 |
| 隔离与恢复 | 独立账号/轮次、可复现随机与时间源，结束恢复偏移；不得误停其他 Java 进程 |
| 证据收尾 | 同一 Kind/Batch 复测；保留失败尝试，验证真实测试数和退出码，记录未执行范围 |


---

## 10. AI 黑盒 + 白盒一体化测试标准流程（批次 A~D 平台能力）

在 GmAndTestPlatform（批次 A~D）测试平台能力支撑下，模拟客户端测试由纯黑盒发包升级为**黑盒发包 + 白盒自省 + 服务端 Trace 录制 + 冷重载落库**一体化测试闭环。

### 10.1 五步一体化测试闭环标准
1. **Arrange（环境准备与快照基线）**：
   - 模块数据初始化：使用 `resetModules("ModuleA", "ModuleB")` 重置指定模块（或空参重置全部模块）至初始状态。
   - 环境快照留底：调用 `whiteBox.saveSnapshot("snapshot_name")` 保存测试前快照基线，支持用例中途或异常时精确回滚。
   - 确定性控制：如需时间或随机数干预，调用 `setVirtualTimeOffset` / `setVirtualTime` 或 `seedRng` / `sequenceRng` 消除偶现不确定性。
2. **Act & Trace（黑盒发包与白盒追踪联合录制）**：
   - 使用 `sendAndTrace(request)` 代替普通 `sendAndWait`，在底层自动开启服务端 Trace 录制、发送业务协议、并在最外层 `finally` 自动拉取流水事件并关闭 Trace。
   - 若业务抛出异常，底层自动将服务端 Trace 捕获的错误事件通过 `addSuppressed` 附加到业务异常中（EX-14, DR-11），避免关键服务端上下文丢失。
3. **Assert（双重视角联合断言）**：
   - 协议返回断言：校验 `TracedResponse.getResponse()` 消息体、状态字段与错误码。
   - 服务端错误断言：调用 `traced.assertNoServerErrors()` 确认服务端业务链路无未捕获异常或逻辑报警。
   - 资源流水净额断言：调用 `traced.assertResourceDelta(configId, expectedDelta, opType)` 精确比对资源变化量与操作类型。
   - 流水事件断言：调用 `traced.assertHasResourceEvent(configId, isAdd)` 校验增减事件。
4. **Introspect（深入内存校验白盒状态）**：
   - 内存点分路径自省：使用 `inspectModuleField("ModuleName", "path.to.field")` 读取服务端最新内存状态，避免单纯依赖下发协议。
   - 跨类型等价断言：调用 `assertModuleFieldEquals("ModuleName", "path.to.field", expectedValue)`，自动处理 Number 跨类型比对。
5. **Cold Reload & Verify（强制落盘与冷重载验证持久化）**：
   - 强制落盘并重启加载：调用 `flushAndColdReload()`，触发服务端强制写库并将实体冷读重构（校验 `reloadedFromDb == true` 且实体哈希发生变化），同时刷新客户端本地缓存。
   - 二次状态断言：重载后再次调用 `assertModuleFieldEquals(...)` 验证数据真正落盘无丢失。
   - 环境复位：测试收尾调用 `whiteBox.restoreSnapshot(...)` 恢复快照，基类 `ClientBaseScenarioTest` 最外层 `finally` 自动执行 `whiteBox.cleanupAll()` 最佳努力复位时钟与随机源。

### 10.2 WhiteBoxTestKit API 速查表
| 分类 | 方法签名 | 说明 |
|---|---|---|
| **状态准备 (Arrange)** | `resetModules(String... modules)` / `resetModules(List<String>)` | 重置指定或全部模块 |
| | `saveSnapshot(String snapshotName)` | 保存快照 |
| | `restoreSnapshot(String snapshotName)` | 恢复快照并刷新客户端缓存 |
| | `listSnapshots()` / `deleteSnapshots()` | 快照查询与清理 |
| | `setVirtualTimeOffset(offset, allowBackward, kick)` | 调整虚拟时钟偏移量 |
| | `setVirtualTime(targetTime, allowBackward, kick)` | 设定虚拟时钟绝对时间 |
| | `resetVirtualTime(allowBackward, kick)` | 复位虚拟时钟 |
| | `seedRng(seed)` / `sequenceRng(intList, doubleList)` | 设置确定性随机种子/预设序列 |
| | `resetRng()` | 复位可控随机数生成器 |
| **执行与追踪 (Act & Trace)** | `sendAndTrace(Message request)` | 发送协议并录制白盒 Trace |
| | `traceExecution(Supplier<T> action)` | 块级白盒 Trace 录制 |
| **复合断言 (TracedResponse)** | `assertNoServerErrors()` | 断言服务端无报错事件 (EX-14) |
| | `assertResourceDelta(configId, delta, [opType])` | 断言资源带符号变化净额 |
| | `assertHasResourceEvent(configId, isAdd)` | 断言存在指定增减资源流水 |
| **自省与落盘 (Introspect & Reload)** | `inspectModule(moduleName)` | 自省模块数据结构 (EX-15) |
| | `inspectModuleField(moduleName, dotPath)` | 点分路径深入自省字段值 (EX-15) |
| | `assertModuleFieldEquals(moduleName, dotPath, expected)` | 断言点分路径字段等价 (EX-15) |
| | `flushAndColdReload()` | 强制落盘并冷重载，刷新本地缓存 (EX-15) |
| **退出清理 (Cleanup)** | `cleanupAll()` | 自动最佳努力复位 Trace、时钟与随机源 (DR-12) |

---

## 11. 进程内模块双轨验收与多态配表全集扫描（ModuleAcceptancePlatform 与 SOP 分工）

针对“多态业务策略分支漏测”与“正式配表全集运行时动态流转盲区”，项目内置了进程内模块双轨验收引擎（`cn.game.games.net.game.gm.acceptance.ModuleAcceptanceEngine`），并配有项目级自建 Skill [module-acceptance-tester](../skills/module-acceptance-tester/SKILL.md)。

### 11.1 标准 SOP 开发流程与独立 Skill 的职责分工

为避免拉长日常开发周期，两套机制按“日常增量门禁”与“模块全面验收”严格解耦：

| 维度 | 标准 SOP 开发流程（T2 / T3）生成 | 独立 Skill (`module-acceptance-tester`) 按需生成 |
|---|---|---|
| **触发时机** | 日常新增/修改业务代码、修 Bug 时同步编写并作为 `Task Complete` 门禁 | 整个业务模块开发定型后、策划大批量配表后或提测封版前，由开发者**手动按需唤醒**（默认登记 T2 任务） |
| **代码位置** | `game/src/test/java/.../*Test.java`（Path A JUnit）或 `simulationclient/.../Client*Test.java`（Path B 模拟客户端） | `game/src/main/java/cn/game/games/net/game/gm/acceptance/suites/*ModuleAcceptanceSuite.java`（注册至 `ModuleAcceptanceEngine`） |
| **覆盖重点** | 1. 底层机制与白盒技术契约（存盘协调、并发、冷读反序列化表征）；<br>2. 本次改动点的 1~3 个典型样本 TDD 正反向断言；<br>3. 特定 Bug 的 `RED -> Fix -> GREEN` 回归用例。<br>*(不在日常增量任务中强制要求写全表扫描)* | 1. **轨道一 (`CONTRACT`)**：结合 `.ai-workspace/specs/features/` 设计文档与源码，覆盖该模块名下全部 Request 协议的正向主链路、条件/余额/限购拦截、跨天重置与幂等防重；<br>2. **轨道二 (`MATRIX_SCAN`)**：穷举该模块所有多态分发分支 × 关联配表的 **100% 正式数据行**（自动造数、破障、代金券同步抵扣、校验无报错且产出守恒）。 |
| **执行入口** | Maven Surefire (`run-java-tests.ps1`) / `run_client.ps1` | 1. **真实服务器集群联调验收（首选正式环境）**：`pwsh -NoProfile -File ./.ai-workspace/scripts/run-live-module-acceptance.ps1 -ModuleId <0x..> -Mode ALL -AutoStartServers`（按需或全量拉起 `LoginServer` + `GameServer` + `CrossServer`，强制 `requireLiveCluster=true` 走真实跨服 RPC 与 `ActorMailbox` 虚拟线程）；<br>2. **GM 网页工作台可视化点按**：`/gm-console` 模块详情页顶部集群拓扑状态徽章及「🧪 功能契约验收」「📊 多态全量配表扫描」「🚀 一键全量验收」与失败项「🔄 单条重试」；<br>3. **JUnit 桥接回归**：通过 `Task Run -Profile module-acceptance-platform` 离线回归。 |

### 11.2 沙盒安全隔离与核心组件速查

| 组件类名 | 核心职责 |
|---|---|
| `ModuleAcceptanceSuite` | 模块双轨验收套件接口；通过 `getRequiredServerTypes()` 声明模块依赖的真实服务器拓扑（如本服模块 `List.of(ServerType.Game)`、跨服公会模块 `List.of(ServerType.Game, ServerType.Cross)`） |
| `ModuleAcceptanceEngine` | 套件注册中心与双轨调度器；提供 `inspectClusterTopology` 校验 `ActiveServerListManager` 在线节点，支持 `requireLiveCluster=true` 强制真实集群验收；生产模式（`PRODUCTION`）下在引擎入口与 HTTP 路由层执行双重硬阻断 |
| `SandboxExecutionGuard` | 维护专用沙盒玩家 ID 段（`PlayerSaveCoordinator.SANDBOX_PLAYER_ID_MIN = 900_000_000_000L`，默认分配 `900_000_000_000L + Math.max(1L, (long) moduleId)`）、真实集群跨服路由注册（在 Redis 注册沙盒玩家 `IdCache` 所在 `GameServer` 路由与 `SimplePlayer` 快照，支持 `GameServer <-> CrossServer` 双向 RPC）、跨服沙盒实体 `DAO` 写库精准静默（识别沙盒 `PlayerData`/`GuildJoin`/`GuildData`）、`PushService` 与 `RankService` 静默，以及 `PlayerSaveCoordinator` 沙盒虚拟存盘确认 |
| `AcceptanceContext` | 驱动 `executeContractCase` 与三段式回调 `executeMatrixRow`，执行四态故障归因（`PASSED` / `PROVISION_FAILED` / `FIXTURE_DEFECT` / `SUT_FAILURE` / `ASSERTION_FAILED`）、连续 3 次夹具失败熔断、多态分支 `UNCOVERED_BRANCH` 告警与集群节点缺失 `CLUSTER_TOPOLOGY_MISSING` 告警 |
| `InProcessAcceptanceKit` | 进程内静态工具包：`ensureHandlerRegistered`、`invokeProto`（在真实 `GameServer` 中自动将沙盒静默上下文传播至玩家 `ActorMailbox` 虚拟线程）、`gm`、`inspectModuleField`、`assertProtocolSuccess`、`assertErrorCode`、`assertResourceDelta` |
| `SandboxResetter` | 调用 `resetModules(player, "item", "shop", "currency", ...)` 原地毫秒级重置模块状态、清理虚拟公会上下文并复位可控随机源 |
| `ConditionSatisfier` | 调用 `satisfyConditions(player, ...)` 自动拉满等级/VIP/关卡、开启沙盒条件豁免并在涉及公会条件时注入临时虚拟 `guildId` |
| `CostProvisioner` | 调用 `provisionShopPayment` / `provisionCostArray` / `provisionCostMatrix` 自动补齐消耗资源，将 RMB 直购自动映射为注入 `Asset.Vouchers`（代金券 ID=`100008`）触发同步抵扣 |
