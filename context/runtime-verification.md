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

Start 前必须确认该 Apollo 配置指向预期测试存储：Game 启动会执行现有迁移、机器人和缓存初始化。脚本不会自动隔离共享数据库。Start 重新生成 Game/Login 身份并与 Prepare 时的独立期望逐字段比较；漂移在启动业务服务之前拒绝。启动后有界等待 Game 身份和端口进程归属，失败清理本次登记的进程。此处的就绪不等于 Login 业务或完整场景通过。

Stop 只结束本目录登记、PID/启动时间/启动标识/主类均相符的进程。重新运行需 Prepare 新快照；不要在正在核验的快照中编译。默认只启动 Game/Login；其他服务按具体场景另行准备。

## 独立期望与实际身份

期望由制品目录和配置独立采集产生 `expected-runtime.json`，不读取运行身份接口。Game 仅在显式 `game.runtimeIdentity.enabled=true` 且 `server.run.mode=test` 时启用；接口绑定 `127.0.0.1`，路径 `/runtime-identity`，默认端口 17011。生产启动不会因此自动公开接口。

| 字段 | 来源 |
|---|---|
| schemaVersion | 字符串 `1.0` |
| targetId | Game 物理进程节点名，来自实际启动参数；与逻辑区服分别核对 |
| buildId | 本次快照唯一构建标识 |
| sourceDigest | 根/六模块 POM 与 src 构建输入摘要 |
| artifactSha256 | 实际 Java 类路径顺序、路径名和文件字节摘要 |
| configSha256 | Apollo application/config/jdbc/redisson/zookeeper、所选 Spring XML 和相关启动属性摘要 |
| protocolSha256 | 实际加载 PbProtocol 所在制品摘要 |
| dataNamespace | 数据库、Redis、Zookeeper 配置的摘要标识，不保存明文凭据 |

身份接口返回启动时独立记录的 `instanceId`、实际 JVM `startedAt` 和本次 query `challenge`。每次观察重新检查磁盘与配置；Apollo 更新或摘要变化永久撤销本次严格身份，恢复原配置也不能让旧进程重新通过。严格模式拒绝 `hot.update=true`，避免内存热替换绕过磁盘摘要。该契约是受控测试环境内的关联证据，不提供远端密码学证明；源码摘要不是可复现构建证明。

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

使用 Task Run 保存实际命令、退出码和 `RUNTIME_OBSERVATION` JSON。Prepare 单独记录构建；测试使用 `scripts/check-local-runtime.ps1 -Snapshot <新快照> -LoginUrl <本机登录地址> -LogicServerId server1 -ConfirmDataScope`，它把 Start、场景、Stop 放在同一生命周期，Stop 在 finally 中。可加 `-VerifyArtifactRevocation` 验证专属快照变更和恢复后均拒绝身份；不要用 Task Run 启动服务后立即退出，否则后台进程继承的输出句柄会使证据采集失败。旧入口未配置观察时输出 `RUNTIME_UNVERIFIED`，进程成功不能宣称目标核验完成。`runtime-evidence-tests` 覆盖本机 HTTP 夹具、失败证据和真实 Java 参数编码；`runtime-identity-java` 覆盖摘要与协议身份判定，均不能替代实际联调。
