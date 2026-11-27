---
name: feature-test-panel-generator
description: 面向 QA 测试人员与开发复现 Bug 共用的“业务功能测试页”生成专家。按“1 玩法/子系统 = 1 独立热重载网页”粒度解耦 .proto 模块合并，结合规格文档、源码与配表生成 gm-console/panels/<panel-id>.html，保存即免重启热生效。
---

# Feature Test Panel Generator Skill（业务功能测试页生成专家）

> **真源与工程边界约定**：
> - 本 Skill 为本项目专属自建 Skill，**唯一真源位于 `.ai-workspace/skills/feature-test-panel-generator/SKILL.md`**（随 `.ai-workspace.git` 独立版本控制；严禁直接手改 `.agents/` 或 `.ai-sop/` 投影目录）。
> - **与「功能协议工作台」和「模块双轨验收」的职责边界**：
>   - **功能协议工作台（`tabWorkbench`）**：纯面向开发人员的底层 Protobuf 协议调试器（按 `.proto` `//@MessageModule` 索引）。
>   - **模块双轨验收（`module-acceptance-tester`）**：面向开发/CI 的进程内 Java 自动化契约测试与全表矩阵扫描。
>   - **业务功能测试台（本 Skill 产出：`gm-console/panels/*.html`）**：面向 **QA 测试人员日常验证** + **开发人员快速复现 Bug** 的业务可视化网页，支持一键造数、场景铺垫、业务按钮操作、实时白盒状态查看与数据重置，且自动将底层协议/GM 流水接入宿主底部「🔧 开发者诊断抽屉」。

---

## 一、 粒度原则：1 玩法 / 子系统 = 1 测试页（彻底解耦 `.proto` 合并）

项目中 `.proto` 文件大多是“1 功能 1 模块”，但并非强制 1:1：
- 例如 `Develop`（养成）可能把多个轻量养成功能合并在同一 `.proto` 模块内；
- 例如 `Activity`（活动）把全部活动协议都放在活动模块内，但每个具体活动都是一个复杂且独立的玩法。

因此**严禁机械按 `.proto` 模块 1:1 塞满一个巨无霸页面**，必须按**玩法 / 业务场景粒度**拆分独立测试页：

| 业务形态 | 推荐文件命名 | `@gm-panel.category` | `@gm-panel.modules` |
|---|---|---|---|
| 独立大模块（如商店、装备、公会） | `shop.html` / `equip.html` / `guild.html` | `核心玩法` | `["shop", "0x15"]` |
| 养成合并模块下的独立子玩法 | `develop_potential.html` / `develop_spirit.html` | `养成系统` | `["develop", "0x19"]` |
| 活动模块下的单个复杂活动玩法 | `activity_seven_days.html` / `activity_dragon_boat.html` | `运营活动` | `["activity", "0x11"]` |
| 跨多协议模块的复合链路测试页 | `cross_world_boss.html` | `跨服玩法` | `["crossworldboss", "rank"]` |
| 通用跨玩法辅助页 | `quick-test-panel.html` | `通用工具` | `[]` |

- 后端 [`GmConsolePanelLoader`](../../game/src/main/java/cn/game/games/net/game/gm/web/GmConsolePanelLoader.java) 会实时解析每个 HTML 顶部的 `<!-- @gm-panel { ... } -->` 元数据；
- 「🧪 业务测试台」门户按 `category` 分组展示玩法卡片；
- 「功能协议工作台」则按 `modules` 实现 **1 协议模块 ↔ N 业务测试页**（或 N:N）反向关联，开发在协议台点进活动/养成模块时可直接看到关联的多个玩法测试页入口。

---

## 二、 四步标准生成流程（4-Step Generation SOP）

### Step 1：三源业务梳理（Spec + 源码 + 配表）
在动手写 HTML 前，先完整核实目标玩法的真实规则，严禁凭空猜测字段名或协议号：
1. **读业务规格（如有）**：检索 `.ai-workspace/specs/features/<FeatureName>/01_server_rules.md` 与 `06_design_contract.md`，提炼测试人员关心的核心流程、限购/次数/冷却门槛、跨天/跨周重置规则与异常拦截场景（`BR-*` / `EX-*`）。
2. **读真实服务端源码**：
   - `*Msg.proto`：确认所有相关 `Request` / `Response` / `Push` 的精确消息名与字段名（使用 `camelCase` 或 `.proto` 定义名）；
   - `*Handler.java`：确认每个协议的前置校验（`isFuncOpen`、`Condition`、资源扣除 `delResources`/`player.pay`、预期 `ErrorMsgEnum`）；
   - `*Module.java`：确认状态字段结构（供 `gm.inspect` 白盒渲染）以及 `gm.resetModule` 需要重置的模块类名清单（如 `ShopModule`、`MonthCardModule`、`CurrencyModule`）；
   - `game/.../gm/command/*Gm.java`：确认现成可用的 `@GmAction` 指令（如 `item.item`、`item.itemdel`、`player.init`、`player.super`、`player.newday`、`battle.zxgk` 等）。
3. **读关联配表结构**：查看 `protocol/src/main/java/cn/game/protocol/generated/config/*Config.java` 与 `Asset.java`，确认精确表名与字段名（如 `Shop`、`ShopItem`、`PurchaseParameter`、`Asset.Vouchers = 100008`）。

### Step 2：设计 QA + Dev 双用页面结构
每个业务功能测试页必须采用统一的“四段式”结构，既让测试人员无需懂协议号就能上手，又让开发能直接用来复现 Bug：
1. **顶部反馈条**：用自然中文展示最近一次操作的业务结果（成功奖励摘要 / 失败错误码与中文释义）。
2. **场景准备、造数与数据重置区**：
   - **快捷造数**：一键补齐该玩法高频货币/门票/材料/代金券（RMB 直购优先补 `Asset.Vouchers = 100008`），支持自定义资源 ID + 数量发放与扣除；
   - **重置与跨周期**：一键重置本玩法关联的 `BasePlayerModule`（以及清空货币用于测不足拦截）、触发个人跨天 `player.newday` 或推进虚拟时钟 `time.offset`；
   - **白盒状态看板**：用 KPI 卡片直观展示玩家当前关键数值/次数/激活状态，并附一个 `<details>` 折叠区展示原始 `gm.inspect` JSON 供开发核查字段。
3. **分业务子页签（动态配表驱动，禁止硬编码死配置行）**：
   - 通过 `window.GmConsole.queryConfigList(tableName)` 动态拉取真实配置表数据渲染下拉框或表格；
   - 每行操作提供「业务执行按钮」+「一键补齐本条所需消耗」+（按需）「境界/限购边界触发按钮」；
   - 页面按钮全部使用策划/QA 业务术语，不要只写冷冰冰的协议名。
4. **一键边界与 Bug 复现脚本区（推荐）**：
   - 将该玩法最易出 Bug 的 3~4 条高频场景（如：余额不足拦截、重复请求幂等防刷、上限拦截 + 跨天恢复、快照保存与回滚对比）封装为“▶ 运行此场景”按钮；
   - 每一步都走 `window.GmConsole.invokeProto(...)`，自动进入宿主底部「🔧 开发者诊断抽屉」，开发展开即可看原始 Request/Response/Push/Trace/Diff 并复制 cURL！

### Step 3：严格遵守页面实现与主题规范
1. **文件命名**：放在 `gm-console/panels/<panel-id>.html`，文件名**必须严格匹配 `^[a-zA-Z0-9_-]+\.html$`**（不支持子目录或中文文件名）。
2. **顶部声明式元数据块**（必填，放在文件最开头前 8KB 内）：
   ```html
   <!-- @gm-panel
   {
     "id": "example_feature",
     "title": "玩法中文测试台名称",
     "category": "核心玩法",
     "audience": ["QA", "DEV"],
     "modules": ["example", "0x15"],
     "tags": ["标签1", "标签2"],
     "order": 50,
     "summary": "一句话说明此测试页覆盖哪些业务流程、造数、重置与复现能力。"
   }
   -->
   ```
3. **三套主题全兼容（暗色 / 晴日浅灰 / 暖纸护眼）**：
   - **严禁硬编码深色或浅色背景 hex**（如 `#0f172a`、`#1e293b`、`#ffffff` 背景），统一使用宿主注入的语义 CSS 变量：
     `var(--card-bg)`、`var(--surface-subtle)`、`var(--border-color)`、`var(--row-border)`、`var(--text-main)`、`var(--text-muted)`、`var(--primary)`、`var(--primary-contrast)`、`var(--accent-text)`、`var(--success)`、`var(--success-text)`、`var(--acceptance-bg)`、`var(--danger)`、`var(--danger-text)`、`var(--danger-soft-bg)`、`var(--danger-border)`、`var(--warning-soft-bg)`、`var(--warning-text)`、`var(--warning-border)`、`var(--info-soft-bg)`、`var(--info-border)`、`var(--code-bg)`、`var(--code-text)`。
   - 复用宿主按钮类：`.btn`、`.btn-secondary`、`.btn-danger`。
4. **脚本隔离与生命周期清理**：
   - 将所有 JS 包裹在 IIFE `(function () { 'use strict'; ... })();` 中，只暴露单一命名空间（如 `window.XxxQaPanel`），避免不同测试页切换时全局变量冲突；
   - 订阅玩家切换事件 `const unsub = window.GmConsole.onPlayerChange(...)`，并在 `window.__gmPanelCleanup` 中取消订阅/清理定时器，确保热重载与切页零泄漏；
   - 所有动态拼接到 HTML 的服务端文本必须经 `window.GmConsole.escapeHtml(...)` 转义。
5. **只读自省防误伤**：
   - 调用 `GmConsole.inspectPlayer([...])` 时确保模块类名真实存在，或准备回退调用，避免单个可选模块名不匹配导致整页空白。

### Step 4：生成后自检闭环
1. **JS 语法校验**：用 Node `vm.Script` 对新生成 HTML 中的全部 `<script>` 块做语法解析校验（零语法错误）。
2. **硬编码深色检查**：确认文件中没有硬编码深色背景（`#0f172a` / `#1e293b` / `#0b1120`）。
3. **元数据与热重载校验**：确认 `@gm-panel` JSON 合法、文件名符合 `^[a-zA-Z0-9_-]+\.html$`；非生产环境运行 `GameServer` 时，在「🧪 业务测试台」点「♻️ 刷新目录」即可免重启看到新卡片并进入验证。

---

## 三、 `window.GmConsole` SDK v2 速查表

所有业务测试页统一调用 `window.GmConsole`（自动携带当前选中玩家、Token 鉴权头、镜像真端开关，并自动写入底部「🔧 开发者诊断抽屉」）：

| 方法 | 说明 | 典型示例 |
|---|---|---|
| `getSelectedPlayerId()` / `requirePlayerId()` | 获取当前选中的调试 `playerId`（`requirePlayerId` 未选时自动弹测试登录框） | `const pid = GmConsole.requirePlayerId();` |
| `onPlayerChange(cb)` | 监听玩家切换/快照回滚事件，返回取消订阅函数 | `const unsub = GmConsole.onPlayerChange(() => refresh());` |
| `invokeProto(msgIdOrName, payload, opts)` | 走真实玩家虚拟线程发 Protobuf 协议，返回 `{ok, response, errorCode, errorName, errorDesc, pushes, trace, diff}` | `await GmConsole.invokeProto('ShopItemBuyRequest_15000003', { shopId: 1, itemId: 101, count: 1 })` |
| `executeAction(action, args, playerId)` | 执行已注册 `@GmAction`（不传 `playerId` 默认取当前选中玩家） | `await GmConsole.executeAction('player.init', {})` |
| `inspectPlayer(modules, playerId)` | 白盒只读自省指定模块内存状态 | `await GmConsole.inspectPlayer(['ShopModule', 'CurrencyModule'])` |
| `resetModules(modules, playerId)` | 反射重置指定模块状态（传 `'all'` 重置全部） | `await GmConsole.resetModules('ShopModule,MonthCardModule')` |
| `addResource(id, count)` / `delResource(id, count)` / `setResource(id, count)` | 给当前玩家发放 / 扣除 / 精确设置道具或货币数量（代金券 ID=`100008`） | `await GmConsole.setResource(100001, 99)` |
| `setPlayerLevel(lv, {nearLevelUp, exp})` / `setVipLevel(vip, {nearLevelUp, exp})` | 设置玩家等级 / VIP 等级，支持 `nearLevelUp: true` 将当前经验设为最大经验 - 1（差 1 点即升级） | `await GmConsole.setPlayerLevel(20, { nearLevelUp: true })` |
| `openAllFunc()` / `setMainStage(idOrIndex)` | 一键解锁全部 `InitialUI` 功能 / 设置主线通关进度（`battle.zxgk`） | `await GmConsole.openAllFunc()` / `await GmConsole.setMainStage(15)` |
| `saveSnapshot(name)` / `restoreSnapshot(name)` / `flushAndColdReload()` | 保存 / 回滚玩家内存快照 / 强制落盘冷重载 | `await GmConsole.saveSnapshot('before_bug')` |
| `toggleQuickGmDrawer(true)` | 呼出控制台右侧全局「⚡ 快捷 GM 抽屉」（各玩法页无需重复堆叠通用调等级/跳关/超级号控件） | `GmConsole.toggleQuickGmDrawer(true)` |
| `queryConfigList(table, {filter, page, pageSize})` | 分页/条件查询静态配置表 | `await GmConsole.queryConfigList('ShopItem', { pageSize: 200 })` |
| `queryConfigGet(table, {id, key})` | 按 ID 或键查询单条配置（`GlobalConst` 用 `key`） | `await GmConsole.queryConfigGet('Shop', { id: 1 })` |
| `getGoodsCatalog(typeId, keyword)` | 查询全物品大类（`typeId=0`）或指定大类下全部配表条目（`typeId=1/2/3/7/15/...`，含 `canSet`/`canDel` 能力标识），用于 2 级联动选品 | `await GmConsole.getGoodsCatalog(2, '碎片')` |
| `offsetTime(expr, opts)` / `newDay()` | 推进全局虚拟时钟 / 触发当前玩家个人跨天 | `await GmConsole.offsetTime('+1d')` / `await GmConsole.newDay()` |
| `seedRng(seed)` / `resetRng()` | 固定 / 恢复服务端随机数种子（复现概率类 Bug） | `await GmConsole.seedRng(12345)` |
| `openModuleWorkbench(moduleIdOrKey)` | 跳转至开发向协议工作台对应模块 | `GmConsole.openModuleWorkbench('0x15')` |
| `toggleDiagnosticsDrawer(true)` | 展开底部开发者诊断抽屉 | `GmConsole.toggleDiagnosticsDrawer(true)` |
| `toast(msg, level)` / `escapeHtml(str)` | 右下角轻提示（`'ok'|'warn'|'error'|'info'`）与 HTML 转义 | `GmConsole.toast('操作成功', 'ok')` |

---

## 四、 黄金标杆参考

生成任何新玩法测试页前，优先参考首个完整标杆实现：
- **[gm-console/panels/shop.html](../../gm-console/panels/shop.html)**：完整示范了 `@gm-panel` 元数据、三套主题适配、顶部造数/重置/跨天与白盒 KPI 看板、多业务子页签动态读表、RMB 代金券自动补齐、以及 QA/Dev 共用的一键边界复现脚本。
