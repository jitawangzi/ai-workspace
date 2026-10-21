# 奖励与资源模式

## 三层结构与实际入口

| 层 | 本项目载体 / 入口 | 责任 |
|---|---|---|
| 配置描述 | `int[]` / `int[][]`、`RandomGivenConfig` | ID、数量、掉落规则；按字段契约解释数组，不能凭维度猜格式 |
| 业务计算 | `cn.game.games.net.game.module.award.Goods`；`PlayerHelper.randomReward(int)` | 产生 `List<Goods>` 计算结果，保留资源 ID 与数量，不等于已入背包 |
| 发放与协议 | `PlayerHelper.addResources` / `addGoods` / `addReward`；`List<RewardInfo>` | 更新真实资源并返回实际发放增量，业务响应显式填充 |

`Goods` 实际包名是 `cn.game.games.net.game.module.award`。它承载 id/count，不是其他项目的带类型字典模型；资源类型由本项目配置与公共入口解释。持久化奖励（如邮件）遵循当前实体及序列化契约，不能凭“三层”口诀强制所有持久实体换一种类型，也不把协议 Builder/临时回包对象保存为真源。

## 标准发放流程

1. 校验可信玩家、活动/任务归属、周期、资格、领取状态；复用老类型的完整校验链。
2. 解析配置与计算掉落，确认 ID 存在、数量合法、容量/溢出及重复领取策略；随机结果需要重试稳定时保存本次结算依据，不能失败后反复重抽获利。
3. 核实全部成本后按匹配重载扣除，调用 `PlayerHelper` 发放，使用有业务语义的 `OpType`；不直接改 CurrencyModule 字段来绕过事件和通知。
4. 领取位、奖励结果及成本形成一致状态，明确任何一步失败的回滚/补偿与幂等键；单玩家串行不意味着外部邮件/数据库操作天然原子。
5. 确认进入 Module 或独立表的实际保存链路。常规 Module 定时保存，不照搬别的项目“每次发奖都手动 save”。
6. 按协议将实际 `RewardInfo` 加入 Response；`notify` 只控制既有通知职责，不能代替响应填充。

## 调用示例与边界

下例为已完成前置校验后的局部示意；`player`、奖励配置 ID、操作枚举和响应 Builder 均来自具体业务，不是完整领奖事务。

```java
// 计算掉落与实际发放分别处理，响应保留实际资源增量。
List<Goods> goods = PlayerHelper.randomReward(randomRewardId);
List<RewardInfo> rewards = PlayerHelper.addResources(player, goods, opType);
respBuilder.addAllRewards(rewards);
```

纯奖励预览不能调用 `addResources`；动态属性、实际实例 ID 和合并后的数量以发放结果为准。普通静态预览按协议返回配置 ID/描述；持久化待领取内容要保存足以重现本次结算的数据，不保存可能随配置变化而改变含义的临时推断。

## 常见反模式

| 错误 | 后果 | 正确做法 |
|---|---|---|
| 调用 randomReward 后直接回包 | 显示发奖但背包没变化 | 通过公共发放入口得到实际 RewardInfo |
| notify=true 后不填 Response | 通知与业务回包职责混淆 | 按协议显式 addAllRewards |
| 多次逐项扣费，最后一项才发现不足 | 部分成功、玩家损失 | 预检查整体成本并采用已验证的批量语义 |
| 缺失配置 ID 时默认发普通货币 | 类型丢失且掩盖坏配置 | 加载期校验，运行时按业务失败策略处理并记录 |
| 只验证响应列表长度 | 未发现保存遗漏或重复发放 | 断言资源增减、领取位、失败重试与冷重载 |

## 回归清单

覆盖多个资源类型、零/负/超限数量、非法 ID、资源不足、容量/溢出、重复请求、超时重试、通知与响应一致、保存完成后重登。随机奖励应有可复现断言和总量/范围约束；不能通过多次尝试直到成功掩盖概率错误。
