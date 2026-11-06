# 联调的运行目标证据

本规则只用于联调/发布结论；不改变 T1/T2/T3、RecordSync 或 Complete 的机器条件。纯进程内测试继续使用现有 Profile。

## 执行入口

`run_client.ps1` 保留原参数；未配置运行观察时输出 `RUNTIME_UNVERIFIED`，成功只表示场景进程退出成功。需要运行身份核对时同时传 `-ExpectedRuntime <发布清单JSON>` 和 `-RuntimeIdentityUri <实际身份接口URL>`；发布验证可加 `-RequireRuntimeIdentity`，缺配置会在启动测试前失败。

期望清单必须从待发布制品/配置生成，至少包括这些字段（示意字段，不能照抄为实际证据）：

| 字段 | 来源 |
|---|---|
| schemaVersion | 字符串 `1.0` |
| targetId | 测试玩家实际目标区服，与场景配置 `game.server.id` 核对 |
| buildId | 构建系统产生的版本标识 |
| sourceDigest | 构建输入 SHA-256，64 位小写十六进制 |
| artifactSha256 | 实际运行制品集合的 SHA-256 |
| configSha256 | 生效配置集合摘要，不能只取代码仓默认配置 |
| protocolSha256 | 实际生效协议版本摘要 |
| dataNamespace | 隔离测试数据范围标识，不含凭据 |

身份接口是部署环境的只读适配契约，当前仓库未提供可直接使用的生产接口地址，也未新增游戏公网协议。接口需从实际运行进程的启动制品和生效配置返回以上字段，并附 `instanceId`、ISO 8601 `startedAt`，原样返回请求 query 的 `challenge`。不能通过读取调用者的期望清单生成“实际”结果。实例后面的负载均衡不能随机返回不同节点；多节点测试须按节点取证。

采集器在测试前后发出不同 challenge，拒绝重定向、身份不匹配、前后版本变化和实例重启。接口应由部署方在内网/已授权访问边界提供，远程传输使用受信 HTTPS；此工具不提供身份签名认证。URI 不允许凭据/query/fragment，输出只保留契约字段。连接失败或缺字段不标记通过。

## 场景与观察的关联

观测接口与模拟客户端是两条连接。工具输出 `OBSERVED_MATCH` 仅证明接口报告与期望一致，`scenarioRouting=REQUIRES_SCENARIO_TARGET_EVIDENCE` 明示尚未自动证明场景落到该节点。场景日志还须保留所连网关、目标区服和由服务端返回的实际实例标识；有代理、跨服转发时追踪实际处理实例。单独读取 `ServerTestContext.serverId` 只证明客户端配置，不证明实际路由。

目前缺少实际部署的身份接口和场景侧处理实例回传，完整目标关联仍需宿主接入后验证；不得把本次采集器的回归测试或配置字段存在，报告为完整游戏联调通过。旧入口保持可用，但不补造这些证据。

使用现有 Task Run 保存命令、退出码和 `RUNTIME_OBSERVATION` JSON；不复制成功摘要来覆盖失败批次。期望清单变更须按现有规则留痕。参数示例：

```powershell
& ./run_client.ps1 -TestClass '<实际完整类名>' -ExpectedRuntime '<实际发布清单路径>' -RuntimeIdentityUri '<实际只读身份接口>' -RequireRuntimeIdentity
```

占位符必须替换为真实值；此示例不代表接口已部署。采集器行为回归使用 Profile `runtime-evidence-tests`，仅使用本机 HTTP 夹具。
