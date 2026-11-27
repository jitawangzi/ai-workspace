<!-- context-meta owner:jitawangzi reviewedAt:2026-11-24 expiresAt:2027-05 -->
# 业务模块全景地图 (Module Map)

> **用途**：帮助首次接触本项目的开发者与 AI 快速定位 `GameServer`、`CrossServer` 与 `LoginServer` 的业务归属、核心类入口、持久化形态与跨服边界，避免盲目全仓扫描。
> **事实优先**：本表按 2026-11-24 当前工作树源码整理；新增或重构模块时同步维护本页，具体方法签名以源码为准。

---

## 1. GameServer 玩家业务模块（`game/src/main/java/cn/game/games/net/game/module/`）

默认情况下，`BasePlayerModule` 子类状态随 `PlayerData.modules` JSON 定时全量保存；`BasePlayerModule#alwaysStoreDataInStandaloneTable()` 默认实现为 `this.defaultDbMapperClass != null && this.defaultDbMapperClass.length > 0`，因此**凡重写 `defaultDbMapperClass()` 返回非空 Mapper 或显式覆写 `alwaysStoreDataInStandaloneTable()` 返回 `true` 的模块**，运行时均走独立表加载/持久化契约。当前工作树中共有 **5 个**独立表/混合模块：`battle`、`friend`、`invite`、`mail`（显式覆写两者）与 **`guild`**（覆写 `defaultDbMapperClass()` 返回 `GuildJoinMapper.class`，个人属性走聚合 JSON + `transient guildJoin` 走独立表）。

| 子包 | 游戏领域 / 职责 | 核心 Module / Service | 核心 Handler | 存储形态与特殊依赖 |
|---|---|---|---|---|
| `account` | 账号运行时数据结构 | `Account`（无 PlayerModule） | — | 内存辅助对象 |
| `activity` | 个人与全服/跨服活动体系（开关、周期、领奖、红点） | `ActivityModule`、`PlayerActivityManager`、`GlobalActivityManager` | `ActivityHandler` | 聚合快照；跨服活动经 `ServerHelper.getCrossActivityProxy` 调 `CrossServer` |
| `award` | 掉落计算与奖励值对象 | `Goods`、`RewardHelper`、`UnionApply` | — | **禁止业务直调 `RewardHelper` 发奖**，统一经 `PlayerHelper.addResources` |
| `backpack` | 通用背包容器基类 | `BackpackModule`、`AbstractBackpackGoodsModule` | — | 聚合快照 |
| `battle` | 主线/西游/合成/爬塔/灵山/失落真经/梦魇/大王来巡山等战斗与关卡 | `BattleModule` | `BattleHandler`、`HCBattleHandler`、`XiYouBattleHandler`、`IBattleHandler` | **独立表**（`alwaysStoreDataInStandaloneTable()=true`） |
| `chat` | 聊天频道与发言 | `ChatModule` | `ChatHandler` | 聚合快照 |
| `currency` | 数值资源（货币/经验/体力）与体力恢复 | `CurrencyModule`、`MoneyRecoverModule` | — | 聚合快照；对应 `Asset` 枚举与 `GoodsType=1` |
| `develop` | **养成大类总包**（属性汇总、防线皮肤、装备/合并装备、宝石、英雄/合成英雄/皮肤、仙友、时装、宠物、神通、龙/剑等） | `AttrModule`、`DevelopModule`、`HeroModule`、`HCHeroModule`、`HeroSkinModule`、`EquipModule`、`MergeEquipModule`、`GemModule`、`PetModule`、`FairyFriendModule`、`SecretscriptModule`、`DefenceSkinModule`、`FashionModule`、`HCCommonModule`、`DragonModule`、`DragonSkillModule`、`SwordModule` | `DevelopHandler`、`HeroHandler`、`HCHeroHandler`、`EquipHandler`、`MergeEquipHandler`、`GemHandler`、`PetHandler`、`FairyFriendHandler`、`SecretscriptHandler`、`HCCommonHandler`、`DragonHandler` | 聚合快照；实体类多继承 `GoodsModule`（注意 `Equipment(7)`/`Dragon(11)`/`DragonSkill(12)`/`Sword(36)` 在 `GoodsTypeEnum.java` 注释中标明暂未启用；各模块本身均继承 `BasePlayerModule#isComplete()` 默认 `true`，改前须结合枚举与实际调用点核对） |
| `draw` | 抽卡 / 英雄招募（含请神） | `DrawModule` | `DrawHandler` | 聚合快照；依赖 `Rnd` 可控随机 |
| `friend` | 好友列表、申请、黑名单、送礼 | `FriendModule` | `FriendHandler` | **独立表**（`alwaysStoreDataInStandaloneTable()=true`） |
| `func` | 功能开启（`InitialUI`）与开关判断 | `FuncModule` | — | 聚合快照；`GameBaseHandler#getInitialUI()` 自动校验 |
| `ginseng` | 人参果树养成与专属商店 | `GinsengTreeModule` | `GinsengTreeHandler` | 聚合快照 |
| `guarantee` | 抽卡/玩法保底计数 | `GuaranteeModule` | — | 聚合快照 |
| `guild` | 玩家侧公会（仙会）代理与个人数据 | `GuildModule` | `GuildHandler` | **混合模式（独立表 + 聚合快照）**：覆写 `defaultDbMapperClass()` 返回 `GuildJoinMapper.class`（运行时 `alwaysStoreDataInStandaloneTable()=true`，`transient guildJoin` 走独立表加载），个人申请/退会等基础字段走聚合 JSON；公会主体在 **`CrossServer`**，须经 `ServerHelper.getGuildProxy(guildId)` 调用 |
| `invite` | 好友邀请码与邀请奖励 | `InviteModule` | `InviteHandler` | **独立表**（`alwaysStoreDataInStandaloneTable()=true`） |
| `item` | 堆叠/非堆叠/唯一/限时道具基类与背包 | `ItemModule`、`ExpireItemModule`、`AbstractItem*Module` | `ItemHandler` | 聚合快照；对应 `GoodsType=2` |
| `mail` | 玩家邮件、公告邮件、全服邮件拉取、筛选分页 | `MailModule` | `MailHandler` | **独立表**（`alwaysStoreDataInStandaloneTable()=true`，`Mail` 实体 + `MailMapper`，字段标 `@JsonIgnore`） |
| `match` | 游戏服侧匹配辅助 | `MatchManager`、`MatchRoom` | — | 内存辅助；跨服匹配对应 `cross/match/` |
| `player` | 玩家根业务模块、累计统计、通用变量、外观（头像/头像框/称号/聊天框/形象）、积分奖励、热支付订单 | `PlayerModule`、`CountingModule`、`VarModule`、`FigureModule`、`HeadBoxModule`、`HeadPortraitModule`、`TitleModule`、`ChatBoxModule`、`PointRewardModule` | `PlayerHandler`（位于 `net/game/handler/`） | 聚合快照；`PlayerModule` 承载热支付订单 `payItems`（遵循支付持久化与去重红线） |
| `pvp` | 离线 PVP / 大道争锋 / 擂台战斗 | `OfflineBattleModule` | `OfflineBattleHandler` | 聚合快照；战报可关联 Redis `PVEVP_RECORD_ID` |
| `quest` | 日常/周常/主线/成就/活动任务与多态条件系统（`quest/require/`） | `QuestModule`、`QuestHelper`、`ConditionFactory` | `QuestHandler` | 聚合快照；条件实现在 `quest/require/`，带 `@ConditionType` |
| `rank` | 排行榜查询、领奖与分数上报 | `RankModule`、`RankService` | `RankHandler` | 聚合快照 + Redis `SET_RANK` |
| `recharge` | 支付订单项、完成凭证、异步回包与离线发货策略 | `PayItem`、`PayType`、`PaymentCompletion`、`PaymentReply` | `ServerHandler.ship`（发货入口） | 高危红线区域；关联 `PaymentOrderPublisher` / `PaymentDedupStore` |
| `shop` | 通用商店、首充、月卡、限时礼包、战令/直购礼包 | `ShopModule`、`FirstChargeModule`、`MonthCardModule`、`LimitedTimeGiftModule`、`XianShiLiBaoModule` | `ShopHandler` | 聚合快照；直购走 `PaymentOrderPublisher` 与代金券抵扣 |
| `story` | 剧情推进与对话节点 | `StoryModule` | `StoryHandler` | 聚合快照 |
| `union` | 历史联盟服务封装（旧接口） | `UnionService`、`UnionGameService` | — | **注意区分**：当前正式公会（仙会）在 `module/guild/` + `cross/guild/`，切勿与 `union/` 混淆 |
| `vip` | VIP 等级、特权与 VIP 礼包 | `VipModule` | `VipHandler` | 聚合快照 |

### 配套基础设施目录（`game/src/main/java/cn/game/games/net/game/`）
- `handler/`：`GameBaseHandler`、`PlayerHandler`（登录/重连/心跳/红点）、`ServerHandler`（跨服发货/系统内部消息）
- `helper/`：`PlayerHelper`（资源/条件/发包/保存）、`ServerHelper`（跨服 RPC 代理）、`PlayerSaveCoordinator` / `PlayerWriteGuard`（保存保序与写保护）、`TestHelper`
- `gm/`：注解 GM 内核（`GmDispatcher`、`GmSecurityPolicy`、`OpsRepairService`、`command/*`）、白盒观测（`RequestTraceService`、`PlayerInspectService`、`PlayerSnapshotService`、`VirtualClockService`、`proto/*`）、GM Web 控制台（`web/GmWebConsoleServer`、`web/FeatureWorkbenchService`）、模块双轨验收（`acceptance/*`）

---

## 2. CrossServer 跨服子系统（`game/src/main/java/cn/game/games/net/cross/`）

`CrossServer` 与 `GameServer` 同处 `game/` Maven 模块，但以独立进程（`-Dapp.id=cross`，主类 `cn.game.games.net.cross.CrossServer`）运行。共享对象按 `DistributedObjectType`（`GUILD`、`CROSS_ACTIVITY`）在 Redis `IdCache` 路由，并在所属 `CrossServer` 邮箱内按对象 ID 串行处理。

| 子包 | 职责 | 核心类 | GameServer 调用入口 |
|---|---|---|---|
| `activity` | **跨服活动体系**：跨服活动生命周期、目录寻址、存储 SPI、玩家参与与动作执行 | `CrossActivityService`、`CrossActivityServiceImpl`、`CrossActivityServiceInterface`、`CrossGlobalActivityManager`、`CrossActivityBase`、`RedisCrossActivityDirectory`、`CrossActivityStore` / `DefaultCrossActivityStore` | `ServerHelper.getCrossActivityProxy(activityUid)`（点对点，无路由快失败）<br>`ServerHelper.getCrossActivityBalanceProxy()`（负载均衡创活） |
| `guild` | **公会（仙会）权威服务**：创建、审批、捐献、砍价、成员权限、日志与快照 | `GuildService`、`GuildServiceInterface`、`GuildManager`、`Guild`、`GuildCrossHandler`、`GuildHelper` | `ServerHelper.getGuildProxy(guildId)`<br>`ServerHelper.getAllServerInterface(ServerType.Cross, GuildServiceInterface.class)` |
| `data` | 跨服启动与节点离开时的游标分页装载器 | `CrossServerDataLoader`、`GuildDataLoader`、`CrossActivityDataLoader` | 仅 CrossServer Leader/节点内部调度 |
| `match` | 跨服匹配房间与队列管理 | `MatchManager`、`MatchRoom` | CrossServer 内部匹配逻辑 |
| `remote` | 跨服通用远程接口实现 | `CrossServerInterface`、`CrossServerImpl` | Vert.x EventBus RPC |

---

## 3. LoginServer 登录与支付网关（`login/src/main/java/cn/game/login/`）

`LoginServer`（`-Dapp.id=login`，主类 `cn.game.login.LoginServer`）提供外部 HTTP 接口（默认端口 `9390`）与内部 Vert.x RPC（`LoginServerImpl` / `LoginServerInterface`），不持有完整在线 `Player` 对象。

| 包 / 目录 | 职责 | 核心类 |
|---|---|---|
| `LoginServer` / `RestServer` | 节点启动入口与 Vert.x HTTP 监听（读取 Apollo `vertx.http.port`） | `LoginServer`、`RestServer`、`CenterServer` |
| `net/clientpacket/vertx/` | **HTTP 路由主链**：注解式路由自动注册、全局安全过滤/CORS/Body 限制/请求日志 | `@VertxRoute`、`BaseVertxHandler`、`VertxRouterConfig`、`VertxRegisterReq`、`VertxThirdPartyConfirmReq`、`VertxServerListReq`、`VertxLogicServerListReq` |
| `net/clientpacket/vertx/wechat/` | 微信 / 畅游 / iOS 支付创单、验单与发货推送回调 | `ChangYouShipPush`、`WechatShipPush`、`PayCallbackSuccessReq`、`IOSPayOrderProcessor`、`AndroidWechatPayOrderProcessor`、`PaymentOrderState` |
| `net/clientpacket/vertx/gm/` | 登录服运营 GM 接口（订单查询/补单、公告、IP 白名单、操作日志） | `GmSelectOrderReq`、`GmPayOrderSuccessReq`、`GmAddNoticeReq`、`GmAddIpWhitelistReq` |
| `net/clientpacket/vertx/sojump/` | 问卷星外部回调 | `SojumpCallbackReq` |
| `cache/entity/` & `mapper/` | MyBatis 持久实体与 Mapper（XML 在 `login/src/main/resources/mapping/`） | `User`、`UserServer`、`PayOrder`、`Notice`、`IpWhitelist`、`GmOpt` |
| `net/remote/` | 供 `GameServer` 调用的内部 RPC 实现（Session 换 UID、创单等） | `LoginServerImpl`、`LoginServerInterface` |
