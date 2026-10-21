# 游戏条件系统说明 (Game Condition System)

## 1. 概述 (Overview)

游戏中的条件系统主要用于任务（Quest）、功能开启、成就等模块的检查。
系统架构采用了**多态（Polymorphism）**设计，将具体的条件检查逻辑分散到各个 `Condition` 实现类中，通过 `ClassManager` 进行管理和分发，避免了硬编码的 `switch-case` 逻辑。

## 2. 检查模式 (Checking Modes)

条件检查主要分为两种模式，由 `ConditionConfig` 中的 `type` (对应 `ConditionTypeEnum`) 的 `countType` 属性决定。

### 2.1 事件触发检查 (Event Trigger Check)
*   **适用场景**: 只有在任务接取后才开始统计的条件（例如：接任务后击杀 X 只怪）。
*   **对应类型**: `countType = 0`
*   **机制**:
    *   依赖具体的 `Condition` 实例（通常挂载在 `Quest` 对象上）。
    *   实例是有状态的，包含 `finishCount`（当前进度）。
    *   通过 `Condition.handleEvent(PlayerEvent)` 监听游戏事件并更新进度。
    *   **注意**: 此类条件无法通过 `PlayerHelper.getConditionCount` 进行无上下文的直接查询。

### 2.2 直接数值检查 (Direct Value Check)
*   **适用场景**: 基于玩家当前状态或历史累计数据的检查（例如：等级达到 X、拥有 X 个金币、累计登录 X 天）。
*   **对应类型**: `countType = 1` (实时状态) 或 `countType = 2` (累计数据)
*   **机制**:
    *   **无状态 (Stateless)**: 检查逻辑不依赖具体的任务实例。
    *   **统一入口**: `PlayerHelper.getConditionCount(Player player, int conditionId)`。
    *   **多态实现**: `PlayerHelper` 通过 `ClassManager` 找到对应的 `Condition` 类实例，调用其 `getValue(Player player, ConditionConfig config)` 方法获取当前数值。

## 3. 详细类型说明 (Count Types)

| CountType | 含义 | 数据来源 | 实现方式 | 典型示例 |
| :--- | :--- | :--- | :--- | :--- |
| **0** | **任务计数** | `Condition` 实例的 `finishCount` | 监听事件 -> 更新内存字段 -> 存库 | "接任务后击杀10只野猪" |
| **1** | **实时状态** | 玩家当前属性 (`Level`, `Goods`, `Battle`) | 实现 `Condition.getValue` 方法，直接读取 Player 模块数据 | "等级达到50级"、"拥有100金币" |
| **2** | **累计计数** | 全局计数模块 (`CountingModule`) | 默认从 `CountingModule` 读取，或重写 `getValue` 读取特殊模块 | "累计登录天数"、"历史最高战力" |

## 4. 开发指南 (Development Guide)

### 4.1 新增一个条件
1.  **定义类型**: 在 `ConditionTypeEnum` 中添加枚举。
2.  **创建实现类**:
    *   在 `cn.game.games.net.game.module.quest.require` 包下创建类。
    *   继承 `AbstractCondition` (Type 0/1) 或 `AbstractCumulativeCondition` (Type 2)。
    *   添加注解 `@ConditionType(type = ConditionTypeEnum.YourType)`。
3.  **实现逻辑**:
    *   **必须**: 实现 `checkEventParam` 用于事件参数校验。
    *   **必须 (Type 1/2)**: 实现 `getValue(Player player, ConditionConfig config)` 用于直接数值获取。

### 4.2 代码示例

#### 实时状态类 (Type 1)
```java
@ConditionType(type = ConditionTypeEnum.PlayerLevel)
public class PlayerLevelCondition extends AbstractCondition {
    // 1. 实现 getValue，支持 PlayerHelper 直接查询
    @Override
    public long getValue(Player player, ConditionConfig config) {
        return player.getLevel();
    }

    // 2. 监听升级事件，用于任务进度的实时刷新
    @Override
    public EventTypeEnum[] getEventTypes() {
        return new EventTypeEnum[] { EventTypeEnum.LevelUp };
    }
}
```

#### 累计计数类 (Type 2)
```java
@ConditionType(type = ConditionTypeEnum.GemWearNum)
public class GemWearNum extends AbstractCumulativeCondition {
    // 1. 重写 getValue (如果默认的 CountingModule 不满足需求)
    @Override
    public long getValue(Player player, ConditionConfig config) {
        return player.getModule(GemModule.class).getCountGTQualityWearCount(config.extParam[0], true);
    }
}
```

## 5. 核心类引用
*   **接口**: `cn.game.games.net.game.module.quest.Condition`
*   **基类**: `AbstractCondition`, `AbstractCumulativeCondition`
*   **管理类**: `ClassManager` (负责加载和缓存实例)
*   **工具类**: `PlayerHelper` (外部调用的统一入口)
