# 状态一致性与恢复验证

按变更范围复用现有用例，不把下表作为每次修改的全量必跑清单。相关入口：Profile `state-integrity`，通过已有 Java 运行器执行 game 模块中四组测试，并逐方法核对 `test-suites/state-integrity.json`，缺失、跳过、失败均不能由其他成功补足。

| 风险 | 现有载体（`game/src/test/java/cn/game/games/net/game/helper/`） | 证明范围 |
|---|---|---|
| 保存快照被后续修改污染 | PlayerSaveSnapshotTest | 真实序列化及映射参数、内存替身 DAO |
| 同玩家保存时序/失败 | PlayerSaveOrderingTest | 保存协调器的进程内顺序与完成信号 |
| 超时未知、迟到提交、重试和写保护 | PlayerSaveRiskTest | 可控时钟、邮箱、保存结果；不模拟真实断电 |
| 支付重复通知和不一致凭据 | PaymentIdempotencyTest | 幂等状态与证明字段、旧数据兼容 |

目标清单逐项列出方法名；调整测试方法时同步实际载体及预期，不通过删除缺失目标消除失败。该 Profile 不访问真实数据库，不代表玩家协议/真实集群或断电恢复验收。

## 数据库与崩溃窗口

真实数据库覆盖已有 `PlayerSaveDatabaseIT`；必须先核对该类实际环境条件、隔离库、唯一测试数据与精确清理，它会写测试记录。不得默认连接现有业务库，也不得把环境导致的跳过记为通过。

| 场景 | 验收与证据 |
|---|---|
| 保存完成后重载 | 等待本代真实提交完成，丢弃内存对象，由新连接/新对象冷读资源、领取位和操作标识 |
| 已提交但回包丢失 | 重复同一业务操作，不重复扣费/发奖，返回契约一致 |
| 已回成功但尚未保存时崩溃 | 在隔离进程中固定该窗口后终止，再从实际存储恢复；先记录该操作的持久化承诺，不假定定时保存等于零丢失 |
| 扣费/发奖/标记部分成功 | 枚举每一副作用后的失败点，验证回滚或持久化补偿；未知结果先核实，不能盲目重发 |
| 业务日切换、重登、跨节点 | 未先查询直接写；周期口径一致；恢复后不能重新领取 |
| 新旧版本混跑 | 新读旧、旧读新、旧写新、降级后继续写均保留必要状态 |

准备/操作/断言/清理分开：夹具只准备前置状态，操作调用正式入口；预期来自业务规则，不能把实现输出复制为预期。保存完成冷读不能代替保存前崩溃测试。恢复演练须记录终止点、持久化前后值、重试次数和清理结果，不能用进程内异常替代断电结论。

尚未确认的资产操作成功承诺、可接受丢失窗口和补偿规则标为 UNKNOWN。这是相关场景的未验证范围，不自动升级任务档位；发布若依赖该保证，应先补齐依据。

## 普通充值跨进程验收

`scripts/run-payment-process-tests.ps1` 执行 `PaymentProcessRecoveryIT` 六个精确方法：正式充值发奖、双 JVM 事件总线通信、真实请求超时、重复请求，以及占位后/保存前/commit 前/commit 后的强制退出和新进程恢复。新目标进程自身的玩家字段与独立数据库冷读同时核对；详细契约见宿主 [普通充值恢复验收](../../doc/payment-process-recovery.md)。

占位后未完成的订单恢复为待核对并阻止自动重发，不能把这一保护行为标记为“自动补偿成功”。本组采用专用业务启动器，前任死亡后才启动继任，不证明 Redis 路由权或并存节点写入安全；也不替代完整 Game/Login 或支付平台验收。新增业务按其实际链路补对应资产和副作用断言，不能照抄本组钻石预期。

## 轻量业务预期与反证试用

相关T2修改先在现有任务说明中引用业务依据，列出入口/前置条件、应变化的状态和副作用、不应变化的旧行为、失败/重复/旧数据结果。此为已有验收点的写法，不要求新表单或批准。未知承诺不能从当前实现反推。

首次试用为生产ServerHandler.ship的在线FirstCharge热凭证分支，复用PaymentIdempotencyTest的5个方法。断言包含提交前凭证不可用、同单不重复执行奖励/Charge/保存、身份或购买参数不匹配不能复用凭证。奖励和存储为替身，durableStore=null；不等于普通Recharge的真实钻石、持久claim/receipt或支付平台验收。

按需反证在独立源码副本中分别去掉proofAwaitingCommit保护和凭证全字段匹配，原版/恢复版全部通过、两种变异成功编译后在预期assertFalse失败才计为检测成功。直接凭证断言与正式ship副作用断言分开说明；不推断所有错单入口都经过本次变异。试用材料见specs的ServerArchitectureAndAgentReadiness/tasks/behavior-contract-test-sensitivity；不会将变异提交到业务源码。

后续优先复用state-integrity或run-java-tests及精确方法清单；合成测试组合入口复用已有受控子进程和报告检查，不能为消除身份冲突放宽生产权限。已有独立审核先读规则与测试，再读实现总结；没有要求审核的T2不因此新增审核环节。

## 正式反证与同分支校准入口

可复用入口已迁到 [run-payment-sensitivity.ps1](../scripts/run-payment-sensitivity.ps1)，判定在 [payment-trial-result.ps1](../scripts/payment-trial-result.ps1)，回归在 [payment-sensitivity.tests.ps1](../scripts/payment-sensitivity.tests.ps1)。两份历史任务 evidence 保留原脚本和原观察，不再作为执行入口。新入口不依赖历史任务、旧绝对路径或已有报告；每次创建独立源码副本，材料目录必须不存在。

```powershell
# 从宿主根执行；替换为当前实际任务 ID，材料放在任务 evidence 下。
& ./.ai-workspace/scripts/run-payment-sensitivity.ps1 -Workspace . -OutputPath './.ai-workspace/specs/features/ServerArchitectureAndAgentReadiness/tasks/TaskId/evidence/payment-trial'
```

任务内通过现有 Task Run 记录上面命令，外层总预算覆盖四个阶段；每阶段仍为1800秒。原版/恢复版退出0、变异版恰好1，且必须完成进程收尾、退出已知、无输出/清理诊断，再检查五个精确方法和两处目标断言。124/125、其他非零码或清理未知，即使报告匹配也不得计为命中。原始日志、JUnit、终态和源码摘要保留；最终恢复副本并核对源树与副本摘要，失败也写恢复结果。临时源码副本不是干净 Git 检出，不证明交付完整性。

`first-charge-calibration` 运行 `FirstChargeCalibrationTest` 三个精确方法：同一在线 FirstCharge/热 PayItem/PaymentCompletion/ServerHandler.ship 分支，分别使用计数替身与未重写 buy 的正式 FirstChargeActivity。共同核对提交前无响应/凭证、提交后成功、重复不再执行业务/Charge、配置缺失异常和保存未写入拒绝。正式 buy 只解锁付费项及同组免费项，钻石不变；另核对真实保存装配的活动快照，不能把旧 awards 计数解释为真实发奖。

配置、前置活动装配和事务 writer 仍为隔离夹具；快照解码不是数据库冷读。本组不覆盖 ActivityHandler 下单前资格验证、领取接口 reward、完整 Game/Login、真实支付平台或崩溃恢复。已有 Recharge IT 与本组 FirstCharge 不互相替代。状态序列测试留到下次相关修改，本轮不新增框架或门禁。
