# 条件系统模式与架构指南

游戏中的条件系统（任务、成就、功能开启、活动资格）采用**多态架构**，将具体检查逻辑分散在各 `Condition` 实现类中，通过 `ClassManager` / `ConditionFactory` 分发，禁止在 `PlayerHelper` 中写 `switch-case` 硬编码。

## 1. 职责边界与三种 `countType` 模式

事件描述发生的事实；`Condition` 判断当前是否满足条件；`Quest` / `Module` 决定状态转换；协议决定可见内容。条件函数尽量无副作用，不顺手发奖、保存或开启下一阶段。

| `countType` | 含义 | 数据来源 | 实现机制与新任务开启处理 | 典型示例 |
|---|---|---|---|---|
| **0：接取后计数** | 任务/实例计数（有状态） | `Condition` 实例的 `finishCount` | 监听事件更新内存并存库；**不可**通过 `PlayerHelper.getConditionCount` 无上下文查询，也不能拿历史累计值冒充接取后次数 | “接任务后击杀 10 只怪” |
| **1：实时状态** | 当前属性检查（无状态） | 玩家当前属性（等级、物品、关卡等） | 实现 `Condition.getValue(player, config)`，由 `PlayerHelper.getConditionCount` 多态调用；晚开启时补判已有状态再监听变化 | “等级达到 50 级”“拥有 100 金币” |
| **2：累计计数** | 历史累计统计（无状态） | `CountingModule` 或专项模块 | 继承 `AbstractCumulativeCondition` 默认读 `CountingModule` 或重写 `getValue`；使用相同计数来源补判，避免重复累加历史 | “累计登录天数”“历史最高战力” |

## 2. 开发新条件标准步骤

1. **定义类型**：在 `ConditionTypeEnum`（配置枚举）中确认/新增类型，核实配置参数、目标、单位与 `countType`；生成产物与实现同步。
2. **创建实现类**：位于 `cn.game.games.net.game.module.quest.require` 包下，继承 `AbstractCondition`（Type 0/1）或 `AbstractCumulativeCondition`（Type 2），并加 `@ConditionType(type = ConditionTypeEnum.YourType)`。
3. **实现核心方法**：
   - 按需实现 `checkEventParam`（事件参数校验）与 `getEventTypes()`（监听事件）；
   - Type 1/2 实现 `getValue(Player player, ConditionConfig config)` 供 `PlayerHelper.getConditionCount(player, conditionId)` 直接查询。
4. **接入闭环**：补真实事件触发点、监听生命周期与晚开启补判（仅有判定函数不代表已接入）；状态推进与展示使用同一条件真源，但不混用“满足”“可领取”“应展示”。

### 代码示例

```java
// Type 1 实时状态示例
@ConditionType(type = ConditionTypeEnum.PlayerLevel)
public class PlayerLevelCondition extends AbstractCondition {
    @Override
    public long getValue(Player player, ConditionConfig config) {
        return player.getLevel();
    }

    @Override
    public EventTypeEnum[] getEventTypes() {
        return new EventTypeEnum[] { EventTypeEnum.LevelUp };
    }
}

// Type 2 累计计数示例（自定义模块读取）
@ConditionType(type = ConditionTypeEnum.GemWearNum)
public class GemWearNum extends AbstractCumulativeCondition {
    @Override
    public long getValue(Player player, ConditionConfig config) {
        return player.getModule(GemModule.class).getCountGTQualityWearCount(config.extParam[0], true);
    }
}
```

## 3. 核心类引用
- 接口：`cn.game.games.net.game.module.quest.Condition`
- 基类：`AbstractCondition`、`AbstractCumulativeCondition`
- 分发与入口：`ClassManager`、`ConditionFactory`、`PlayerHelper.getConditionCount`

## 4. 反例与回归

| 反例 | 修正 | 必测场景 |
|---|---|---|
| 实时金币足够后永久记完成，需求却要求领取时持有 | 由功能明确快照/实时语义，领奖时按契约复核 | 中途消耗后领取 |
| 先升级后开启任务永远不完成 | 对 `countType=1/2` 通过既有 `getValue` 补判 | 晚开启立即满足 |
| `countType=0` 用全局历史累计值初始化 | 接取时从独立状态 0 开始计数 | 接取前行为不计数 |
| 条件函数内部顺手发奖或改写状态 | 判定与推进/发放完全拆开 | 重复查询零副作用 |

优先复用已有对象与内存数据；未知/缺失配置明确报错或按既定策略降级，不用默认 `true` 掩盖问题。
