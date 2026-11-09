# 联调的运行目标证据

本规则用于联调结论，不改变 T1/T2/T3 或 Complete 条件。纯进程内测试继续使用现有 Profile。

## 本机运行入口

`run_server.ps1` 默认执行 `Prepare`：先核对源码，完整构建六模块，再复制不可原地重建的制品快照到 `.ai-workspace/.runtime/local-runtime/<runId>`。默认 Apollo 为回环地址 `http://127.0.0.1:9888`、集群 `SYQ`，与现有独立启动脚本一致。仅准备不会启动业务服务、清理日志或结束其他进程。

```powershell
./run_server.ps1 -Action Prepare -ApolloUri 'http://127.0.0.1:9888' -ApolloCluster SYQ
./run_server.ps1 -Action Start -Snapshot '<上一步输出目录>' -ConfirmDataScope
./run_server.ps1 -Action Status -Snapshot '<同一目录>'
./run_server.ps1 -Action Stop -Snapshot '<同一目录>'
```

Start 前必须确认该 Apollo 配置指向预期测试存储：Game 启动会执行现有迁移、机器人和缓存初始化。脚本不会自动隔离共享数据库。Start 外部预检仅作提前诊断。Game/Login 实际 JVM 都在日志配置、业务 Config、Redis、ZK、Spring/JDBC 初始化之前执行共同屏障：固定 Apollo properties/XML 与已声明业务键的系统/环境回退值，再计算实际身份并与各自 Prepare 独立期望完整比较；缺少期望、解析失败或漂移直接退出。业务后续全部通过 Apollo SPI 读取同一份内存配置；远端更新不改变存储目标，仅永久撤销身份。未声明的 namespace、文件及格式拒绝读取；Spring XML 的 import、location/locations 属性及同名 Bean property（含 placeholder、override、util:properties）与 DTD 拒绝使用，避免固定正文后再加载未核验配置。启动后有界等待 Game 身份和端口进程归属，失败清理本次登记的进程。此处的就绪不等于 Login 业务或完整场景通过。

Start/Stop/Status 从检查前到操作结束持有同一快照跨进程排他锁；竞争立即报告 `LOCAL_RUNTIME_BUSY`。登记同目录临时写入并原子替换，失败保持旧 JSON；部分启动失败逐条清理全部已启动进程，清理异常不跳过后续进程。锁文件保留，仅释放句柄。完整验收入口只在自己成功启动后清理，对短暂锁忙有界重试，不能误停另一调用的服务。`processes.json` 存在时不可重复启动。

Stop 只结束本目录登记、PID/启动时间/启动标识/主类均相符的进程。重新运行需 Prepare 新快照；不要在正在核验的快照中编译。默认只启动 Game/Login；其他服务按具体场景另行准备。

## 独立期望与实际身份

期望由制品目录和配置独立采集产生 `expected-runtime.json`，不读取运行身份接口。清单入口按 `app.id` 复用 Game/Login 的命令行节点解析，在读取 Apollo 前设置对应的 `game.server.id` / `login.server.id`；配置中的默认节点名可以与实际启动节点不同，不能通过抄取身份接口的摘要修正期望。Game 仅在显式 `game.runtimeIdentity.enabled=true` 且 `server.run.mode=test` 时启用；接口绑定 `127.0.0.1`，路径 `/runtime-identity`，默认端口 17011。生产启动不会因此自动公开接口。

| 字段 | 来源 |
|---|---|
| schemaVersion | 字符串 `1.0` |
| targetId | Game 物理进程节点名，来自实际启动参数；与逻辑区服分别核对 |
| buildId | 本次快照唯一构建标识 |
| sourceDigest | 根/六模块 POM 与 src 构建输入摘要 |
| artifactSha256 | 实际 Java 类路径顺序、路径名和文件字节摘要 |
| configSha256 | 固定的 Apollo application/config/jdbc/redisson/zookeeper/log4j2、所选 Spring 与日志 XML、已声明业务键的系统/环境有效回退和相关启动属性摘要 |
| protocolSha256 | 实际加载 PbProtocol 所在制品摘要 |
| dataNamespace | 数据库、Redis、Zookeeper 配置的摘要标识，不保存明文凭据 |

身份接口返回启动时独立记录的 `instanceId`、实际 JVM `startedAt` 和本次 query `challenge`。每次观察重新检查磁盘与配置；Apollo 更新或摘要变化永久撤销本次严格身份，恢复原配置也不能让旧进程重新通过。严格模式拒绝 `hot.update=true`，避免内存类热替换绕过磁盘摘要。XML 热加载仍保留，但真实 CREATE/MODIFY 分派在任何解析前递增资源版本，OVERFLOW 同样递增；身份采集首尾核对启动资源版本，解析失败或恢复原文件都不能恢复身份。普通启动继续原行为。该契约是受控测试环境内的关联证据，不提供远端密码学证明；源码摘要不是可复现构建证明。

## 场景与观察的关联

```powershell
./run_client.ps1 -TestClass cn.game.simulation.test.ai.ClientRuntimeIdentityTest `
  -RuntimeSnapshot '<快照目录>' -ExpectedRuntime '<快照目录>/expected-runtime.json' `
  -RuntimeIdentityUri 'http://127.0.0.1:17011/runtime-identity' -RequireRuntimeIdentity `
  -GameId game_test -LogicServerId server1 -LoginUrl 'http://127.0.0.1:9390' -TestAccount '<本次独立测试账号>'
```

占位符须替换为真实值。`RuntimeSnapshot` 使用快照类路径并跳过编译；一般入口仍支持原有即时编译。严格身份参数必须成对，且必须指定预期逻辑区服。账号、登录地址和物理节点可显式覆盖，不修改共享 `env.properties`。

`ClientBaseScenarioTest` 在真实登录完成后，通过当前玩家连接发送既有测试 GM 协议的 `runtimeIdentity <challenge>`；服务校验在线玩家及当前连接，返回同一 Game 进程身份、玩家 ID、实际逻辑区服。场景前后使用不同挑战，并核对独立期望、HTTP 实例、玩家及指定逻辑区服。`ClientRuntimeIdentityTest` 实际执行心跳请求；不发奖励或修改存量玩家。

HTTP 前后观察只证明接口的身份稳定。只有场景前后探针也匹配时，`scenarioRouting=AUTHENTICATED_GAME_NODE_PROBES_MATCH` 才成立；它证明两个探针在同一认证节点处理，不证明场景中每一个跨服业务请求均由该节点执行。跨服业务仍须提供对应处理链证据。场景失败时仍尝试后探针，保留原异常及次要观察异常；失败或未完成报告只保留白名单字段，HTTP 后观察失败也不会丢失已收到的场景证据。

严格身份采集与协议探针单独使用 30 秒有界等待，普通业务协议保持原 5 秒时限。

使用 Task Run 保存实际命令、退出码和 `RUNTIME_OBSERVATION` JSON。Prepare 单独记录构建；测试使用 `scripts/check-local-runtime.ps1 -Snapshot <新快照> -LoginUrl <本机登录地址> -LogicServerId server1 -ConfirmDataScope`，它把 Start、场景、Stop 放在同一生命周期，Stop 在 finally 中。可加 `-VerifyArtifactRevocation` 验证专属快照变更和恢复后均拒绝身份；或使用新快照加 `-VerifyXmlRevocation`，追加合法 XML 注释并等待真实加载成功，恢复字节后才执行首次探针，必须拒绝。两种撤销分别使用新快照。不要用 Task Run 启动服务后立即退出，否则后台进程继承的输出句柄会使证据采集失败。旧入口未配置观察时输出 `RUNTIME_UNVERIFIED`，进程成功不能宣称目标核验完成。`runtime-evidence-tests` 覆盖本机 HTTP 夹具、失败证据和真实 Java 参数编码；`runtime-identity-java` 覆盖摘要与协议身份判定，均不能替代实际联调。


## 边界回归

启动前先原子保存 `launch-intent.json` 并刷新到磁盘，保存失败则不创建业务进程。登记失败或控制进程在记录 PID 前退出时，新的 Stop/Status 执行者读取同一快照意图，按完整 launchId 和主类参数发现候选，再核对 PID、启动时间和当前命令行；相似前缀标识不能匹配。清理逐个处理，有界等待原 Process 对象退出，失败保留意图和既有登记供再次 Stop。重复 Stop 应成功，不能将已退出进程当清理失败；保留意图的快照禁止重新 Start，应另行 Prepare。

`runtime-concurrency-tests` 增补“登记失败→未登记进程清理失败→原执行者退出→新执行者 Stop”和“业务进程创建后、返回 PID 前控制器退出”，并核对再次 Stop 与其他启动标识的进程不受影响。控制器是真实独立 pwsh，业务进程由持久状态夹具替代，不连接数据库；本测试不宣称完成真实 Game/Login 故障注入。

发现 java.exe 候选但命令行为空或空白时，无法排除它是尚未登记的本轮进程。Stop/Status 在候选仍存活或存活查询失败时报告 `LOCAL_RUNTIME_STOP_INCOMPLETE` / `CANDIDATE_IDENTITY_UNKNOWN`；明确不存在的候选不阻塞。查询进程被拒绝同样不能算退出。未知身份不会授权终止，其他可核验的本轮进程仍继续处理，启动意图及既有登记保留；恢复读取权限后用同一快照再次 Stop。不可读候选也可能属于其他任务，因此此时宁可报告发现不完整，不能仅凭 java.exe 名称停止。回归覆盖空/空白、查询拒绝、枚举后消失、只有旧登记记录、新执行者重试及未知外部进程不被误杀；这些为受控夹具，未模拟真实操作系统权限切换。

"runtime-identity-java" 包含独立 JVM 的真实 Apollo SPI、普通模式兼容和 XML 修改→加载→恢复→首次检查；"runtime-concurrency-tests" 用独立 pwsh 进程及受控业务夹具覆盖排他锁、失败调用清理归属、原子写失败和锁持有者退出。"scripts/runtime-startup-boundary.tests.ps1 -Snapshot <新快照>" 实际运行两个业务入口，将独立期望生成后的有效存储配置覆盖到本机陷阱端口，核对拒绝原因与零连接，并验证缺失/损坏期望；它不修改共享 Apollo。单测/陷阱测试与完整真实场景分别记录，不能相互替代。

严格配置支持当前启动链使用的标准 XML 配置入口：全部 springArgs 文件均验证（包括名为 log4j2.xml 的文件）；带命名空间的 location/locations 及引用写法也拒绝。直接声明的 PropertiesLoaderSupport / YamlProcessor 属性加载器及子类、无法解析的 Bean 类型、factory-method/factory-bean 间接创建方式在严格模式下不支持。此规则不等于审计任意自定义 Bean 或扫描后 Java 代码。

系统/环境中已有 Apollo 枚举键的覆盖自动固定。仅存在于系统/环境中的业务键须在独立期望与真实启动两端一致声明 JVM 参数 runtime.config.overrideKeys（逗号分隔）；声明和值均计入身份。通过 Apollo Config API 请求未声明但存在于环境的键会直接拒绝（含类型读取），不悄悄忽略覆盖。Spring Environment 和默认系统 Bean 只暴露已声明的固定映射，未声明键按缺失处理。终端或执行器每次改变的无关环境标识不再参与业务身份。

严格 Spring 上下文使用同一份已核验的系统/环境映射（含默认 systemProperties/systemEnvironment Bean），并拒绝无 location 的额外 placeholder/override 配置器及 SpEL。XML 解码时和最终值解析时均检查，防止占位符展开后拼成动态表达式。普通启动仍使用原上下文。

## 真实进程权限恢复验收

`pwsh -NoProfile -File ./.ai-workspace/scripts/runtime-permission.tests.ps1` 使用 Windows、PowerShell 7 和可用的 java/javac。只编译和启动独立 classpath 中的休眠 Java 夹具，不调用 Prepare/Start、不读取 Apollo、不连接业务存储。分别验证仅启动意图、仅登记文件两种恢复入口；第三个不同 launchId 的进程检查误杀边界。

监督者先持有专用进程句柄并保存原 DACL，再只拒绝该进程的查询/终止权限；新观察者必须实际得到访问拒绝。调用真实 Status/Stop 检查未知身份不误报成功、其他可确认进程继续清理、记录字节保留；恢复 DACL 后用新执行者 Stop，并重复调用。全部专用进程在 finally 中恢复/清理，现场日志和状态文件保留在本次 `.runtime/local-runtime/acl_*` 目录；Java 夹具有五分钟自退出上限。

2026-11-08 两种入口真实验收均通过，新观察者得到查询错误5且命令行不可读，恢复后可完成清理。此结论只覆盖本机Windows和专用Java夹具，不代表所有Windows版本/WMI提供器或业务Game/Login故障场景。现有null/空白及查询失败模拟回归继续保留，不由这次成功替代。
