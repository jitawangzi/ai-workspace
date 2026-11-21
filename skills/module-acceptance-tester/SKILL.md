---
name: module-acceptance-tester
description: 模块级双轨自动化验收与多态配表矩阵扫描测试专家。在功能模块开发完成后按需独立调用，结合 .ai-workspace/specs/features/ 设计文档与源码/配表，为模块编写进程内功能契约验收（CONTRACT）与多态分支×全量配表矩阵扫描（MATRIX_SCAN）套件，并挂载至 GM Web 工作台。
---

# Module Acceptance Tester Skill（模块级双轨验收与多态配表全集扫描专家）

> **真源与工程边界约定**：
> - 本 Skill 为本项目专属自建 Skill，**唯一真源位于 `.ai-workspace/skills/module-acceptance-tester/SKILL.md`**（随 `.ai-workspace.git` 独立版本控制，由 AI SOP 安装器投影至 `.agents/skills/`，严禁直接手改 `.agents/` 或 `.ai-sop/` 投影目录）。
> - **独立于日常开发主流程**：本 Skill 不绑定在日常功能开发主流程中，避免拉长常规开发周期；在整个功能模块开发完毕、或需要对存量模块补充全面验收时，由开发者**手动按需唤醒**。
> - **任务登记规则**：唤醒本 Skill 新增或修改验收套件代码时，遵循项目根目录 `AGENTS.md` 任务管理规范（未显式指定档位时默认登记 **T2** 任务，执行编译与对应套件 JUnit 验证后 `RecordSync` 并 `Task Complete`）。

---

## 一、 角色设定与核心目标

你是本项目的**模块级双轨自动化验收架构师（Module Acceptance Architect）**。
传统的开发自测往往只抽取 1 条最简单的数据跑通主流程，存在两大盲区：
1. **多态业务策略分支漏测（代码维度）**：同一协议入口背后通过 `switch(type)`、枚举分发（如 `ItemUse`）或 `GoodsModule` 子类走向多套截然不同的处理逻辑，仅测一种类型会导致其余多态分支覆盖率为 0%；
2. **正式配表全集运行时盲区（数据维度）**：静态配表检查器无法发现运行时动态公式计算、跨表深层引用、阶梯消耗或特殊参数组合引发的 `NullPointerException`、`IllegalArgumentException` 或奖励漏发（如商店前 10 个商品配置正确，第 85 个商品配置错误导致线上购买崩溃）。

你的职责是为目标模块编写实现 `ModuleAcceptanceSuite` 接口的进程内双轨验收套件（位于 `game/src/main/java/cn/game/games/net/game/gm/acceptance/suites/`），使其同时可在 **GM Web 控制台工作台（`/gm-console`）** 一键点击执行，也可在 **JUnit** 中自动化回归。

---

## 二、 核心方法论：Spec 设计文档 + 源码 + 配表“双源交叉比对”与三级冲突裁决

### 1. 严禁“仅看代码写测试”的同义反复陷阱（Anti-Tautology Rule）
如果只看现有 Java 代码来写断言，一旦开发人员漏写了某条业务校验（如需求规定“每日限购 3 次”或“跨天自动重置”，但代码漏写了），顺着代码写出的测试就会把错误行为当成预期放过。

因此，在编写任何验收用例前，**必须执行双源交叉采集**：
- **第一源（业务意图真源 Why & Should-Be）**：检索 `.ai-workspace/specs/features/` 下与目标模块相关的所有功能规格目录（包括模块主目录及历史增量修改目录），读取：
  - `01_server_rules.md`（提取 `BR-*` 业务规则、`EX-*` 异常拦截、`AC-*` 验收标准）；
  - `06_design_contract.md` / `04_change_impact.json`（提取 `DC-*` 状态流转与持久化契约、`INV-*` 行为不变量、跨周期懒重置与写入口自愈要求）；
  - `05_test_plan.md`（参考已规划的边界场景与测试点）。
- **第二源（物理实现真源 As-Is）**：读取当前工作区的 `.proto` 协议文件、`*Handler.java`、`*Module.java` 以及 `protocol/.../config/*Config.java`、`*Manager.java` 与 `game/src/main/resources/xml/*.xml`。

### 2. 文档与代码不匹配（Spec-Code Drift）时的三级裁决铁律

当对比发现 `.ai-workspace/specs/features/` 下的文档与当前 Java 源码不一致时，**严禁盲目顺从代码或盲目写无法编译的旧符号**，必须按以下三级规则裁决：

| 冲突等级 | 场景界定 | 强制裁决动作 |
|---|---|---|
| **裁决 A：疑似代码漏实现 / 违背业务规则**<br>(`SPEC_CODE_MISMATCH`) | 规格文档明确要求了某项业务校验、限购/冷却阈值、扣费/发奖公式或跨天自愈逻辑（`BR-*`/`EX-*`/`INV-*`），但当前源码漏写、写反或绕过了校验 | **坚持按规格文档的正确业务预期编写断言！**<br>1. 让该条 `CONTRACT` 或 `MATRIX_SCAN` 用例在运行时真实暴露 `SUT_FAILURE` 或 `ASSERTION_FAILED`；<br>2. 在用例标题或失败消息中显式标注：`[SPEC_CODE_MISMATCH: 依据 <Feature>/01_server_rules.md#BR-xx，规格要求...但代码实际...]`；<br>3. 严禁为了凑“100% 绿灯”而删改断言迁就 Bug。 |
| **裁决 B：技术符号演进 / 历史文档滞后**<br>(`DOC_DRIFT_WARNING`) | 代码后续经过合法重构或 T1/T2 调整，导致类名、方法签名、协议字段名、枚举名或配表字段名演进，且当前源码与 `.proto`/XML 配表完全自洽 | **物理调用服从当前编译态代码，同步输出文档漂移告警！**<br>1. 协议构造、类引用与配表字段读取使用当前源码真实签名，确保测试套件 100% 可编译、可发包；<br>2. 在套件类头 JavaDoc 及执行汇报中输出 `[DOC_DRIFT_WARNING]` 清单，列明滞后的文档路径、条款号与当前代码真实签名。 |
| **裁决 C：无规格文档的存量老模块**<br>(`LEGACY_CODE_INFERRED`) | `.ai-workspace/specs/features/` 下不存在该模块的任何历史规格文档 | **基于源码 + 配表 + 通用业务规范逆向推导！**<br>参照 `.ai-workspace/context/business-logic-pattern.md`（通用五步状态矩阵、周期重置、资源守恒）与 `.ai-workspace/context/ai-coding.md` 推导完整契约用例与配表扫描矩阵，不因缺少历史文档而阻塞。 |

---

## 三、 四步标准作业流程（4-Step Generation SOP）

### Step 1：四维上下文盘点与覆盖建模（Discovery & Modeling）

对目标模块执行以下盘点，并在脑中（或任务说明中）建立三维覆盖表：
1. **检索规格文档**：在 `.ai-workspace/specs/features/` 下查找匹配模块名/关键字的目录，提取核心 `BR-*`、`EX-*`、`INV-*` 并与源码比对。
2. **盘点协议入口（`*Msg.proto` & `*Handler.java`）**：
   - 确认 `//@MessageModule` 十六进制模块号（如 `0x0b` 道具、`0x15` 商店）；
   - 列出 `inititialize()` 中注册的全部 `putInvoker(PbProtocol.XxxRequest, this::xxx)` 协议入口；
   - 梳理每个入口的前置校验链（功能开启 `player.isFuncOpen`、`Condition` 条件检查、次数/限购上限、CD 冷却、资源消耗 `PlayerHelper.delResources` 或 `player.pay`）。
3. **盘点多态分发分支（Polymorphic Branches）**：
   - 找出模块内所有的 `switch-case`、枚举策略分发（如 `ItemUse.valueOf(item.ItemType)`）、`GoodsModule` 子类分发、或按配置表 `Type` 字段走不同逻辑的代码分支；
   - 将每个分支定义为稳定的字符串键（如 `"ITEM_USE_TYPE_4_HeroChoose"`、`"SHOP_TYPE_2_Heishi"`），填入套件的 `getDeclaredBranches()`。
4. **盘点关联配置表（`*Config.java` & `*Manager.java`）**：
   - 找出模块读取的所有 `XxxManager.instance().list()` 配置表，填入 `getRelatedTables()`；
   - 明确每张表的：**主键 ID**、**分类/多态字段**、**前置条件字段（如 `UnlockCondition`/`BuyCondition`）**、**消耗字段（如 `PurchaseParameter`/`cost`/`Decompose`）** 与 **产出奖励字段（如 `Item`/`Reward`/`Para`）**。

---

### Step 2：编写轨道一「🧪 功能链路契约验收（`CONTRACT`）」

在套件的 `runContractCases(AcceptanceContext ctx)` 中，首先调用 `InProcessAcceptanceKit.ensureHandlerRegistered(MODULE_ID, XxxHandler::new)` 确保模块协议处理器已注册，然后通过 `ctx.executeContractCase(caseId, title, () -> { ... })` 针对核心业务规则与状态机边界编写契约用例：

1. **必须覆盖的契约切面**：
   - **正向主链路（Happy Path）**：调用 `SandboxResetter.resetModules(player, ...)` 重置模块 $\to$ 准备精确资源与前置状态 $\to$ 调用静态方法 `InProcessAcceptanceKit.invokeProto(player.getPlayerId(), PbProtocol.XxxRequest, payloadMap)` 发送正式请求 $\to$ 断言 `InProcessAcceptanceKit.assertProtocolSuccess(res)`（内含 `errorCode == 0` 与 `trace.errorEvents` 为空校验）、资源扣除与奖励发放流水净额匹配（`InProcessAcceptanceKit.assertResourceDelta(res, configId, expectedSignedDelta)` 或 `assertAnyRewardGranted(res)`）、模块内存状态变更正确（`InProcessAcceptanceKit.inspectModuleField(player, moduleName, dotPath)`）。
   - **资源/条件不足拦截（Negative Guard）**：在清零货币或未达标状态下发包 $\to$ 调用 `InProcessAcceptanceKit.assertErrorCode(res, ErrorMsgEnum.xxx.getId())` 断言返回预期非零错误码（如 `resource_not_enough` 或 `condition_check_error`）且状态未被脏改。
   - **限购/冷却/上限拦截（Limit Guard）**：连续购买或操作直至达到配表上限（如 `ShopItemQuota`），再发第 $N+1$ 次请求 $\to$ 断言返回上限错误码（如 `shop_item_buy_count_max` / `times_limit`）。
   - **跨周期重置自愈（Cross-Day / Reset）**：在达到每日上限后，触发跨天刷新（如 `player.getShopModule().onDayReset()` 或 `PlayerHelper.refreshDay`）$\to$ 验证计数归零并可再次成功执行。
   - **幂等与防重入（Idempotency）**：对一次性购买/领取协议（如月卡、章节礼包、基金通行证购买、已领奖励）重复发送相同请求 $\to$ 断言第二次请求被 `repeat_request` / `month_card_repeated` / `shop_gift_repeated` 拦截。
2. **禁止项**：
   - 在验证“余额不足/条件不满足/达到上限”的反例契约用例中，**严禁调用破障器自动补钱或开启条件豁免**！
   - 切勿对第一次正向前置操作使用 `if (code == 0)` 包裹第二次重复拦截断言（防止因前置缺钱失败而静默跳过断言造成假阳性）。

---

### Step 3：编写轨道二「📊 多态策略 × 配表全集矩阵扫描（`MATRIX_SCAN`）」

在套件的 `runMatrixScan(AcceptanceContext ctx)` 中，遍历目标模块关联配表的 **100% 正式配置行**（`ctx.executeMatrixRow` 内部已自动封装 `shouldRunCase(caseId)` 单条过滤、`maxMatrixRows` 行数上限与 `ctx.isCircuitBroken()` 连续 3 次夹具失败熔断器，外层循环只需检查 `if (ctx.isCircuitBroken()) break;`）：

1. **单条配表三段式回调微环标准模板**：
   每一行配表记录必须通过 `ctx.executeMatrixRow(caseId, configTable, configId, branchKey, arrangeAndPreCheck, sutAct, sutVerify)` 在独立沙盒微环内执行：
   - **回调 1 `arrangeAndPreCheck`（阶段 1 造数破障 + 阶段 2 前置自检，`Runnable`）**：
     - 调用 `SandboxResetter.resetModules(player, "item", "currency", ...)` 重置被测模块与关联资源模块（支持传不带 `Module` 后缀的短名称或类简单名），确保当前行与第 1 行处于完全一致的初始环境；
     - 调用 `ConditionSatisfier.satisfyConditions(player, config.UnlockCondition, config.BuyCondition)`（支持传入 `int[]...` 或 `int...` 条件 ID，内部自动拉满等级/VIP/关卡、开启条件豁免并在遇到公会条件时自动设置虚拟 `guildId`）；
     - 若业务要求目标条目先存在于玩家模块容器中（如商店购买要求 `ShopModule` 持有该 `ShopItem`，道具使用/分解要求背包持有该 `Item`），显式注入目标实例并清零已购买/已使用计数；
     - 调用 `CostProvisioner` 静态方法自动补齐本行配置所需的普通资源或 **`Asset.Vouchers`（代金券，ID=`100023`）**：
       - 商店购买参数（`[costType, itemId, count]`）：`CostProvisioner.provisionShopPayment(player, config.PurchaseParameter, 1)`；
       - 二维资源数组（`int[][]`）：`CostProvisioner.provisionArrayCost(player, config.Cost, 1)`；
       - 一维资源数组（`[id, count]`）：`CostProvisioner.provisionFlatCost(player, config.Cost, 1)`；
       - 宝箱抽卡防免费券污染：`CostProvisioner.clearCompetingFreeTicketIfNecessary(player, shopBoxConfig, costType)`；
     - **前置自检**：校验所需前置道具/状态已在沙盒玩家身上就绪；若未就绪则抛出 `new AcceptanceFixtureException("...", false)`（引擎自动归因为 `FIXTURE_DEFECT` 或 `PROVISION_FAILED`，连续 3 次触发熔断，绝不混淆为业务 Bug）。
   - **回调 2 `sutAct`（阶段 3 正式协议发包，`Supplier<Map<String, Object>>`）**：
     - 调用并返回 `InProcessAcceptanceKit.invokeProto(player.getPlayerId(), PbProtocol.XxxRequest, payloadMap)`，走真实 `Dispatcher` + `Handler` 执行，全程捕获 Response、Push、Trace `resourceEvents`/`errorEvents` 与模块 `Diff`。
   - **回调 3 `sutVerify`（阶段 4 语义守恒断言，`Consumer<Map<String, Object>>`）**：
     - 调用 `InProcessAcceptanceKit.assertProtocolSuccess(result)` 校验响应 `errorCode == 0` 且 `trace.errorEvents` 为空；
     - 校验资源消耗与产出流水净额或模块业务状态跟配表字段一致（如分解道具获得的资源 ID 与数量等于 `item.Decompose[0]` / `item.Decompose[1]` 时调用 `InProcessAcceptanceKit.assertResourceDelta(result, item.Decompose[0], item.Decompose[1])`；若不一致则抛出 `AssertionError`，引擎自动归因为 `ASSERTION_FAILED`）。
   - **阶段 5 `TEARDOWN`（引擎自动强制复位）**：
     - 由 `AcceptanceContext` 的 `finally` 块自动执行 `SandboxExecutionGuard.enableConditionBypass(playerId, false)`、`ConditionSatisfier.setSandboxGuildContext(player, 0L)` 与 `Rnd.resetControlledRandom()`，防止跨用例状态泄漏。

2. **多态分支命中登记**：
   - 每行配表执行时必须传入其所属的 `branchKey`（必须与 `getDeclaredBranches()` 中声明的分支键一致）；
   - 引擎自动汇总每个 `branchKey` 的扫描行数与通过率，对命中数为 `0` 的声明分支自动生成 `UNCOVERED_BRANCH:<branchKey>` 告警。

---

### Step 4：注册、编译与自检验证闭环（Verification）

1. **在验收引擎中注册套件**：
   - 新套件实现 `ModuleAcceptanceSuite` 接口，放置在 `game/src/main/java/cn/game/games/net/game/gm/acceptance/suites/` 目录；
   - 在 `ModuleAcceptanceEngine` 私有构造器（`game/src/main/java/cn/game/games/net/game/gm/acceptance/ModuleAcceptanceEngine.java`）中调用 `registerSuite(new XxxModuleAcceptanceSuite())` 完成内置注册（使 GM 网页工作台与离线 JUnit 均可直接发现并调用）。
2. **编写/更新 JUnit 自动化测试**：
   - 在 `game/src/test/java/cn/game/games/net/game/gm/acceptance/ModuleAcceptancePlatformTest.java`（或对应模块验收测试类）中补充对该 `moduleId` 的 `CONTRACT`、`MATRIX_SCAN` 与单条 `caseId` 重试断言；
   - 通过 `Task Run -Profile compile`、`compile-tests` 与 `module-acceptance-platform`（或定向 Java 测试命令）验证套件零夹具故障（`provisionFailures == 0 && fixtureDefects == 0`），并能完整输出 `ModuleAcceptanceReport`。
3. **向用户输出结构化验收总结**：
   - 汇总：① 关联规格文档核对结论（含 `[SPEC_CODE_MISMATCH]` 与 `[DOC_DRIFT_WARNING]` 清单）；② 轨道一契约用例覆盖列表；③ 轨道二配表扫描总行数、多态分支覆盖率及实测发现的真实配表/代码缺陷明细。

---

## 四、 黄金参考范本与标准套件代码骨架

编写新模块验收套件前，优先参考已落地的两个标杆套件：
- 道具模块标杆：`game/src/main/java/cn/game/games/net/game/gm/acceptance/suites/ItemModuleAcceptanceSuite.java`
- 商店模块标杆：`game/src/main/java/cn/game/games/net/game/gm/acceptance/suites/ShopModuleAcceptanceSuite.java`

标准套件代码骨架如下：

```java
package cn.game.games.net.game.gm.acceptance.suites;

import java.util.Collection;
import java.util.List;
import java.util.Map;

import cn.game.games.cache.entity.Player;
import cn.game.games.net.game.gm.acceptance.*;
import cn.game.games.net.game.helper.PlayerHelper;
import cn.game.games.net.game.module.item.ItemHandler;
import cn.game.protocol.generated.config.ItemConfig;
import cn.game.protocol.generated.enume.ItemUse;
import cn.game.protocol.generated.manager.ItemManager;
import cn.game.protocol.manual.ErrorMsgEnum;
import cn.game.protocol.manual.OpType;
import cn.game.protocol.protobuf.PbProtocol;

/**
 * 示例模块双轨自动化验收套件
 */
public class ExampleModuleAcceptanceSuite implements ModuleAcceptanceSuite {

    private static final int MODULE_ID = 0x0b; // 对应 //@MessageModule 十六进制模块号

    @Override
    public int getModuleId() {
        return MODULE_ID;
    }

    @Override
    public String getModuleKey() {
        return "item";
    }

    @Override
    public String getTitle() {
        return "道具使用与分解验收";
    }

    @Override
    public List<String> getDeclaredBranches() {
        return List.of("ITEM_USE_TYPE_4_HeroChoose", "ITEM_SELL_DECOMPOSE");
    }

    @Override
    public List<String> getRelatedTables() {
        return List.of("ItemConfig");
    }

    @Override
    public void runContractCases(AcceptanceContext ctx) throws Exception {
        InProcessAcceptanceKit.ensureHandlerRegistered(MODULE_ID, ItemHandler::new);
        Player player = ctx.getSandboxPlayer();

        // 轨道一：功能链路契约与异常边界验收
        ctx.executeContractCase("CONTRACT:item_sell_not_enough", "未拥有道具出售应返回资源不足拦截", () -> {
            SandboxResetter.resetModules(player, "item", "currency");
            Map<String, Object> req = Map.of("id", List.of(200001), "count", List.of(1));
            Map<String, Object> res = InProcessAcceptanceKit.invokeProto(
                    player.getPlayerId(), PbProtocol.ItemSellRequest_0b000007, req);
            InProcessAcceptanceKit.assertErrorCode(res, ErrorMsgEnum.resource_not_enough.getId());
        });
    }

    @Override
    public void runMatrixScan(AcceptanceContext ctx) throws Exception {
        InProcessAcceptanceKit.ensureHandlerRegistered(MODULE_ID, ItemHandler::new);
        Player player = ctx.getSandboxPlayer();
        if (ItemManager.instance() == null) {
            return;
        }

        // 轨道二：多态策略 × 正式配表全量遍历扫描
        Collection<ItemConfig> allItems = ItemManager.instance().list();
        for (ItemConfig item : allItems) {
            if (ctx.isCircuitBroken()) {
                break;
            }
            if (item.Decompose != null && item.Decompose.length >= 2 && item.Decompose[0] > 0 && item.Decompose[1] > 0) {
                String branchKey = "ITEM_SELL_DECOMPOSE";
                String caseId = "MATRIX_ITEM_SELL_" + item.ID;
                ctx.executeMatrixRow(caseId, "ItemConfig", item.ID, branchKey,
                        () -> {
                            SandboxResetter.resetModules(player, "item", "currency");
                            PlayerHelper.addResources(player, item.ID, 1, OpType.GM, false);
                            if (!PlayerHelper.isEnough(player, item.ID, 1)) {
                                throw new AcceptanceFixtureException("造数后道具数量仍未满足", false);
                            }
                        },
                        () -> {
                            Map<String, Object> req = Map.of("id", List.of(item.ID), "count", List.of(1));
                            return InProcessAcceptanceKit.invokeProto(
                                    player.getPlayerId(), PbProtocol.ItemSellRequest_0b000007, req);
                        },
                        result -> {
                            InProcessAcceptanceKit.assertProtocolSuccess(result);
                            if (item.Decompose[0] != item.ID) {
                                InProcessAcceptanceKit.assertResourceDelta(
                                        result, item.Decompose[0], (long) item.Decompose[1]);
                            }
                        }
                );
            }
        }
    }
}
```
