<!-- context-meta owner:jitawangzi reviewedAt:2026-11-24 expiresAt:2027-05 -->
# 高频开发实战配方 (Dev Recipes)

> **定位**：补齐常规编码规范之外的端到端“照着做即可编译闭环”实操配方，涵盖：**新增常规功能最小闭环**、**独立表 `DbEntity` 持久化**、**`LoginServer` HTTP 路由**、**`RedisUtil`/`LockUtil`/`CacheType`** 与 **GM Web 控制台自定义面板**。所有类名与签名均已按当前源码核实。

---

## 1. 新增常规业务功能的最小闭环 Checklist

按以下顺序推进，每步均有唯一真源，避免返工：

1. **静态配表（如需新增/改表）**：
   - 核对 `../configs/Excels/*.xlsx`、四行表头与数组分隔符（一维 `;`，二维 `;` + `|`，见 [config-rules.md](config-rules.md) 与 [doc/02_开发流程与研发规范手册.md](../../doc/02_开发流程与研发规范手册.md) 第 3 节）。
   - 走正式导表与 `game/tool/copy.bat` 同步，**严禁手改** `protocol/.../generated/` 下的 Config / Manager / Enum。
2. **协议定义与代码生成**：
   - 在 `protocol/src/main/proto/` 新增或编辑 `<Module>Msg.proto`（先全库检索确认高 8 位模块号与消息号无冲突，`Response = Request + 1`，规范见 [proto-rules.md](proto-rules.md)）。
   - 根目录执行 `.\protocol.bat` 生成 Protobuf Java 类与 `PbProtocol.java`（注意 `protocol/` 是独立 Git 仓库）。
3. **业务模块（`BasePlayerModule`）**：
   - 在 `game/src/main/java/cn/game/games/net/game/module/<领域>/` 下继承 `BasePlayerModule`（物品容器继承 `GoodsModule`）。
   - 持久字段直接作为成员保存，运行时缓存/临时对象标 `transient` 或 `@JsonIgnore`；禁止随意重命名类名/包名（`PlayerData.modules` JSON 携带完整类名）。
   - 重写 `getEventTypes()` / `handleEvent(...)` / `buildPlayerAllInfo(...)` / `onLogin()`（按需）；确保 `isComplete()` 为 `true`。
   - 涉及资源用 `PlayerHelper.isEnough` / `delResources` / `addResources`（含重复 ID 先聚合）；时间用 `DateUtil`；随机用 `Rnd`；业务报错用 `player.fail(ErrorMsgEnum.xxx)`。
4. **协议处理器（`GameBaseHandler`）**：
   - 添加 `@Component`，继承 `GameBaseHandler`（无状态单例）。
   - 实现 `getModule()`、按需覆盖 `getInitialUI()`，在 **`inititialize()`**（注意双 `ti` 拼写！）中 `putInvoker(PbProtocol.XxxRequest_..., this::method)`。
   - 在处理方法内通过 `PlayerManager.getInstance().getPlayer(client.getPlayerId())` 获取可信玩家，调用 Module，组装并 `client.sendProtocol(resp.build())`。
5. **进程内 JUnit 5 验证（必跑，不依赖裸 `mvn test`）**：
   - 在 `game/src/test/java/...` 编写测试（静态单例测试类加 `@Isolated` 并在 `@AfterEach` 还原），参考 [debugging-playbook.md](debugging-playbook.md) 第 3 节 4 个样板。
   - 常规编译与定向测试命令：
     ```powershell
     mvn -B '-DskipTests' test-compile
     pwsh -NoProfile -File ./.ai-workspace/scripts/run-java-tests.ps1 -Project game -Test <测试类名>
     ```
   - 涉及持久化变更时，必须补冷重载断言（单测用 `CborSnappyUtil.decompress(...)`，联调用 `flushAndColdReload()`）。

---

## 2. 独立表持久化（`DbEntity` + MyBatis）端到端实操指南

默认业务优先使用常规 `BasePlayerModule` 聚合 JSON 快照；仅当数据量随时间增长、需独立主键检索/离线直写或跨玩家查询（如邮件、好友、邀请、战斗记录）时，才采用独立表模式。**完整真源样板**：[Mail.java](../../game/src/main/java/cn/game/games/cache/entity/Mail.java)、[MailModule.java](../../game/src/main/java/cn/game/games/net/game/module/mail/MailModule.java)、`MailMapper.java` / `MailMapper.xml`。

### 步骤拆解

1. **DDL 与 MyBatis 资产位置**：
   - 表结构变更脚本放 `game/src/main/resources/sql/`（专用迁移放 `db/migration/`）。
   - Java 实体放 `game/src/main/java/cn/game/games/cache/entity/<Entity>.java`。
   - Mapper 接口放 `game/src/main/java/cn/game/games/net/data/mapper/<Entity>Mapper.java`，XML 放 `game/src/main/resources/mapping/<Entity>Mapper.xml`（包含默认按玩家查询方法 `selectByPlayerId`、主键 CRUD）。
2. **实体实现 `DbEntity` 接口（注意是 `implements`，不是 `extends`）**：
   ```java
   public class SampleRecord implements Serializable, DbEntity {
       private static final long serialVersionUID = 1L;
       private long id;
       private long playerId;
       // ... 表字段与 getter/setter

       /** 返回主键（联合主键返回对应数组/对象，匹配 Mapper deleteByPrimaryKey 参数）。 */
       @Override
       public Object primaryKey() {
           return id;
       }

       /** 若类名与 Mapper 命名非默认映射，显式返回 Mapper Class；默认可由 DAO 按约定推导。 */
       @Override
       public Class<?> getMapperClass() {
           return SampleRecordMapper.class;
       }

       /** 可选：写入前在玩家线程把内存结构序列化到表字段，避免在 Worker 线程读并发集合。 */
       @Override
       public void beforeSave() {
           // this.payloadJson = JsonUtil.toJsonString(this.cachedPayload);
       }
   }
   ```
3. **Module 声明独立表加载与排除 JSON 序列化**：
   ```java
   public class SampleStandaloneModule extends BasePlayerModule {

       /** 独立表数据必须加 @JsonIgnore（或 transient），防止重复写入 PlayerData.modules JSON！ */
       @JsonIgnore
       private Map<Long, SampleRecord> records = new ConcurrentHashMap<>();

       /** 声明走独立表持久化契约。 */
       @Override
       public boolean alwaysStoreDataInStandaloneTable() {
           return true;
       }

       /** 声明登录/加载时要查询的 Mapper 列表（默认调用 selectByPlayerId）。 */
       @Override
       public Class<?>[] defaultDbMapperClass() {
           return new Class<?>[] { SampleRecordMapper.class };
       }

       /** 消费框架按 defaultDbMapperClass() 顺序返回的查询结果。 */
       @Override
       @SuppressWarnings("unchecked")
       protected void initFromDb(ListIterator<?> iterator) {
           List<SampleRecord> list = (List<SampleRecord>) iterator.next();
           for (SampleRecord item : list) {
               this.records.put(item.getId(), item);
           }
       }

       /** 写入须显式调用 DbEntity 的 insert/update/delete（返回 Vert.x Future）。 */
       public Future<Object> addRecord(SampleRecord record) {
           this.records.put(record.getId(), record);
           return record.insert();
       }
   }
   ```
4. **关键避坑点**：
   - `alwaysStoreDataInStandaloneTable()=true` **不会自动忽略字段序列化**，独立表集合必须手动加 `@JsonIgnore`（或 `transient`），否则会双写进 `PlayerData.modules`！
   - 若某字段（如 `MailModule.globalMailId` 标量游标）仍希望留在玩家聚合 JSON 中，不要标 `@JsonIgnore`，但要明确区分两套保存时机。
   - `record.insert()` / `update()` / `delete()` 返回异步 `io.vertx.core.Future`，关键资产/前置依赖必须 `AsyncUtils.await(...)` 或纳入返回 Future 链，不能假设调用完就已落库；多条 `DAO.executeDbTaskList(...)` 顺序执行但**不自动开启统一数据库事务**。

---

## 3. `LoginServer` HTTP 路由与 MyBatis 开发速查

`LoginServer` 使用 Vert.x Web + Spring 自动装配路由，**不要在 `RestServer.regRouter(...)` 里手工取消注释硬编码**，应遵循注解发现机制：

1. **路由入口机制**：
   - [VertxRouterConfig.java](../../login/src/main/java/cn/game/login/net/clientpacket/vertx/VertxRouterConfig.java) 自动注入所有 Spring `BaseVertxHandler` Bean，并已前置挂载全局中间件：`requestId` 日志、`SecurityHandler`（拦路径穿越与非法字符）、1 MiB `BodyHandler`、CORS 与统一 `failureHandler`。
   - 新增 HTTP 接口：在 `cn.game.login.net.clientpacket.vertx`（或其子包）新建类，标注 `@VertxRoute` 并实现 `BaseVertxHandler`：
     ```java
     @VertxRoute(value = "/gm/example_action", method = "POST")
     public class ExampleHttpReq implements BaseVertxHandler {
         @Autowired
         private UserMapper userMapper;

         @Override
         public void handle(RoutingContext ctx) {
             // 读取 JSON 请求体或表单/查询参数
             JsonObject body = ctx.body().asJsonObject();
             // ... 鉴权、参数校验与业务处理
             ctx.response()
                 .putHeader("Content-Type", "application/json; charset=utf-8")
                 .end(new JsonObject().put("code", 0).encode());
         }
     }
     ```
2. **重要注意**：
   - `VertxRouterConfig.registerAnnotationRoute` 当前通过 `router.route(route.value()).handler(handler)` 挂载，未在路由层按 `method` 硬过滤；如接口仅限 `POST`，应在 `handle` 内显式校验 `ctx.request().method()`。
   - 同步与异步异常都必须确保结束 `ctx.response()`（或交给 `ctx.fail(err)`），避免 HTTP 连接挂死。
   - `LoginServer` 数据库位于独立 `login` 库（Mapper 接口在 `login/.../mapper/`，XML 在 `login/src/main/resources/mapping/`），**切勿复用 `GameServer` 的数据源或实体**。
   - 与 `GameServer` 通信走 `LoginServerImpl` / `RemoteLoginServerInterface` Vert.x EventBus RPC。

---

## 4. `RedisUtil`、`LockUtil` 与 `CacheType` 常用范式

1. **Key 命名必须统一收敛在 `CacheType`**：
   - 定义位置：[CacheType.java](../../core/src/main/java/cn/game/core/cache/CacheType.java)。
   - 用法：`CacheType.CROSS_ACTIVITY_ACTIVE_UID.key(configId, scopeKey)`，内部自动拼为 `ENUM_NAME_arg1_arg2`；新增全局 Redis Key 或分布式锁 Key 先在 `CacheType` 登记并写清注释，严禁业务代码中散落魔法字符串。
2. **读取/写入与虚拟线程 `await`**：
   - `RedisUtil`（[RedisUtil.java](../../util/src/main/java/cn/game/util/RedisUtil.java)）封装了 Redisson 常用操作，高级结构可通过 `RedisUtil.getRedis()` 获取 `RedissonClient`。
   - 在玩家/实体虚拟线程中等待 `RFuture` 时，**先用 `AsyncUtils.toVertxFuture(rf)` 再 `AsyncUtils.await(...)`**，不要直接把 `RFuture` 传给 `AsyncUtils.await`。
3. **分布式锁（`LockUtil`）**：
   - 定义位置：[LockUtil.java](../../util/src/main/java/cn/game/util/LockUtil.java)（默认 `waitTime=5s`、`leaseTime=30s`）。
   - 同步虚拟线程内短临界区：
     ```java
     String lockKey = CacheType.CROSS_ACTIVITY_CREATE_LOCK.key(configId, scopeKey);
     RLock lock = LockUtil.tryLockSync(lockKey);
     if (lock == null) {
         // 获取锁失败：按业务约定返回重试或失败，严禁假装成功继续写
         return;
     }
     try {
         // 临界区逻辑（禁止在持锁期间做无界慢 IO）
     } finally {
         LockUtil.unlock(lock);
     }
     ```
   - 仅需租约互斥（不需显式 unlock、靠 TTL 自动释放）可用 `LockUtil.acquire(key, leaseTime, unit)` / `acquireAsync(...)`。
   - **分布式对象路由**：玩家（`PLAYER`）、公会（`GUILD`）、跨服活动（`CROSS_ACTIVITY`）的物理节点路由由 `IdCache`（[IdCache.java](../../core/src/main/java/cn/game/core/cache/id/IdCache.java)）管理，不要绕过 `IdCache` 手拼路由 Key。

---

## 5. GM Web 控制台与 `gm-console/panels/` 热重载面板指南

1. **启动与访问**：
   - 非生产模式（`-Dserver.run.mode=test` / `dev`）启动 `GameServer` 时，[GmWebConsoleServer](../../game/src/main/java/cn/game/games/net/game/gm/web/GmWebConsoleServer.java) 自动挂载。
   - 默认地址：**`http://127.0.0.1:18080/gm-console`**（配置键 `gm.http.enabled` / `gm.http.port` / `gm.http.host` / `gm.http.requireAuth` / `gm.http.opsToken` 及对应 `GM_HTTP_*` 环境变量，端口 `17011` 保留给 `/runtime-identity`，禁止冲突）。
   - 生产模式默认关闭且强制 Fail-Closed；仅在显式配置开启与 Token 鉴权后才暴露 `OPS_SAFE` / `OPS_REPAIR` 能力。
2. **编写热重载自定义面板**：
   - 存放目录：`server/gm-console/panels/*.html`（参考样例 [quick-test-panel.html](../../gm-console/panels/quick-test-panel.html)）。
   - [GmConsolePanelLoader](../../game/src/main/java/cn/game/games/net/game/gm/web/GmConsolePanelLoader.java) 动态读取该目录，修改 HTML 后刷新网页即可生效，无需重启 `GameServer`。
   - 面板内直接调用控制台注入的 `window.GmConsole.executeAction("<gmActionId>", { ...params })` 执行已注册的 `@GmAction` 指令（返回统一 JSON 结果），严禁在面板中绕过鉴权直接拼装未授权后台接口。
