# 条件系统模式

详细架构和旧项目知识保留在 [systems/condition-system.md](../systems/condition-system.md)，本页补充接入、边界与验证，避免维护两份签名真源。

## 判断、事件与推进

事件描述发生的事实；Condition 判断当前是否满足条件；Quest/Module 决定状态转换；协议决定可见内容。条件函数尽量无副作用，不顺手发奖、保存、开启下一阶段。

| countType | 数据来源 | 新任务开启时的处理 |
|---|---|---|
| 0：接取后计数 | Condition 实例 finishCount 与监听事件 | 不能拿历史累计值冒充接取后发生次数 |
| 1：实时状态 | `getValue` 读取玩家当前状态 | 开启时补判已有等级/资源等，再监听变化 |
| 2：累计数据 | CountingModule 或有明确契约的历史数据 | 使用相同计数来源补判，避免再累加一遍历史 |

直接数值查询复用 `PlayerHelper.getConditionCount(player, conditionId)`，不能把 countType=0 当作无状态查询。条件实现位于 `cn.game.games.net.game.module.quest.require`，通过 `@ConditionType` 和 `ConditionFactory` / ClassManager 的现有链路接入。

## 新条件检查步骤

- 明确用于功能开放、任务完成、活动资格还是领奖；不是所有条件都属于任务。
- 核实配置类型、参数、目标、单位和计数模式；类型枚举/配置生成结果与实现同步。
- 选择 `AbstractCondition` 或 `AbstractCumulativeCondition`，实现事件过滤和对应数值获取；先读已有同类实现。
- 补真实触发点、监听生命周期和晚开启补判；只有判定函数不代表已接入。
- 状态推进与展示使用同一条件真源，但不混用“满足”“可领取”“应展示”。

## 反例与回归

| 反例 | 修正 | 场景 |
|---|---|---|
| 实时金币足够后永久记完成，需求却要求领取时持有 | 由功能明确快照/实时语义，领奖时按契约复核 | 中途消耗后领取 |
| 先升级后开启任务永远不完成 | 对 countType=1/2 通过既有 getValue 补判 | 晚开启立即满足 |
| countType=0 用全局历史累计值初始化 | 接取时从其独立状态开始 | 接取前行为不计数 |
| 条件函数内部发奖 | 判定与推进/发放拆开 | 重复查询无副作用 |

优先用已有对象和内存数据，未知/缺失配置明确报错或按既定业务策略降级，不用默认 true 掩盖问题。
