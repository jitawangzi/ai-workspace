
***

# 静态数据配置指南 (Configuration Guide)

为了实现**逻辑与数据分离**的设计目标，游戏中的静态数据（策划数值）独立保存在外部文件中。程序启动时，会读取这些文件并解析为内存中的对象，供全进程读取使用。

## 1. 核心理念与命名规范

### 1.1 设计原则
*   **源文件**：策划人员维护 `.xlsx` (Excel) 文件。
*   **运行时**：程序实际读取的是由工具转化后的 `.xml` 数据文件。
*   **代码映射**：工具自动生成对应的 Java `Config` 类和 `Manager` 管理类。

### 1.2 命名规范
为了明确区分“静态配置”与“运行时逻辑对象”，采用以下命名习惯：
*   **运行时逻辑对象**：通常直接命名（如 `Quest`，代表玩家身上接取的一个具体任务实例）。
*   **静态配置对象**：添加 `Config` 后缀（如 `QuestConfig`，代表策划配置的任务模板数据）。

---

## 2. 配置表定义

### 2.1 类结构示例
以任务模块为例，`Quest.xlsx` 定义了任务的静态属性。生成器会将其解析为 `QuestConfig` 类，每行 Excel 数据对应一个对象实例。

```java
public class QuestConfig {
    public final int ID;              // 任务ID (主键)
    public final int Type;            // 任务类型，对应 QuestTypeEnum
    public final int Condition;       // 任务完成条件，对应 Condition 表ID
    public final int Reward;          // 任务奖励ID (Drop表ID)
    public final int Group;           // 任务分组 (不同类型的任务分组互斥)
    public final int[] OpenQuests;    // 完成时开启的新任务ID列表
    public final boolean IsDeleteOnFinish; // 完成后是否从列表中移除
    // ... 其他字段
}
```

### 2.2 特殊配置表
除了常规的业务数据表，还有两类特殊的配置：

#### A. 全局常量表 (GlobalConst)
用于存储全服通用的常量配置，非列表结构，直接通过静态字段访问。
```java
public class GlobalConst extends ResourceListener {
    public volatile static int UpHeroID;          // 强制下阵英雄ID
    public volatile static int[] CreateUID;       // UID创建时的参数配置
    public volatile static int PayVIPExp;         // 1元人民币兑换的VIP经验值
    public volatile static int[][] PlayerName;    // 修改名字消耗配置
}
```

#### B. 枚举定义表
用于将 Excel 中的状态定义映射为 Java 枚举，便于代码引用。
```java
public enum QuestTypeEnum {
    Daily(1, "Daily", "日常任务"),
    Weekly(2, "Weekly", "周常任务"),
    Achievement(3, "Achievement", "成就任务");
    // ...
}
```
> *注：`GlobalConst` 和枚举类通常由人工协助定义，AI 编写逻辑时可直接使用。*

---

## 3. 数据类型支持

配置表生成工具支持将 Excel 单元格内容解析为以下强类型数据：

### 3.1 基础类型
*   **数值型**：`byte`, `short`, `int`, `long`, `float`, `double`
*   **字符/布尔**：`String`, `boolean`
*   **时间日期**：`Date`, `LocalDateTime`, `CronExpression` (Cron表达式)
*   **枚举**：自定义的 Enum 类型

### 3.2 集合类型
*   **数组**：支持一维和二维数组。
    *   示例：`int[]` (例如 `1,2,3`), `int[][]` (例如 `1,1;2,2`), `LocalDateTime[]` 等。
*   **映射 (Map)**：
    *   示例：`Map<Integer, Integer>`, `Map<Byte, Integer>` 等。

---

## 4. 数据读取方式 (Manager)

每个配置表都会生成一个对应的单例 `Manager` 类（如 `QuestManager`）。
**规则**：Excel 的第一列必须是数字类型的 ID，作为默认的主键索引。
一般默认情况下，是把excel中的表数据，读取出来，组织成一个java 的map类型的结构， key为id或者索引，一般按照id或者索引读数据。
还有一种称之为list类型的表结构，按照行顺序，读取出来一个java 中list结构的数据来保存，有序，并且随机行数据，一般如果不需要按照id或者索引取数据，
可以设置为list类型，数据也更紧凑。

### 4.1 常用读取接口

```java
// 1. 按 ID 获取 (不存在时抛出异常，适用于逻辑上必须存在的配置)
QuestConfig config = QuestManager.instance().get(id);

// 2. 按 ID 获取 (允许返回 null，适用于尝试性查找)
QuestConfig config = QuestManager.instance().getNullable(id);

// 3. 获取全量数据列表
Collection<QuestConfig> allQuests = QuestManager.instance().list();

// 4. 获取全量数据列表，假设这个表是使用list方式存储的
List<QuestGroupConfig> allGroupQuests = QuestGroupManager.instance().list();

// 5. 获取原始索引 Map
Map<Integer, QuestConfig> allMap = QuestManager.instance().getMap();


```

### 4.2 索引查询
如果在配置中定义了索引字段（例如按 `Type` 字段索引，同时支持多字段联合索引，唯一索引），工具会生成额外的查询方法：

```java
// 按类型获取任务列表
List<QuestConfig> dailyQuests = QuestManager.instance().getTypeList(QuestTypeEnum.Daily.getId());

// 获取按类型分组的 Map
Map<Integer, List<QuestConfig>> typeMap = QuestManager.instance().getTypes();
```

> **注意**：Manager 类及其方法完全由工具生成，**禁止手动修改**。

---


## 5. Excel表结构

### 5.1 文件名规则
一般设计为.xlsx文件，文件名可以为功能名，一个.xlsx文件可以包含多个静态配置表，也就是多个sheet,sheet名规则为[配置表名]#[中文注释名]。
例如公会功能Guild.xlsx,第一个sheet为GuildBasic#公会基础信息 ，第二个sheet为GuildPermissions#公会权限，而实际通过工具生成java类时，
会生成GuildBasicConfig，GuildPermissionsConfig，增加Config后缀。

### 5.2 表结构规则
表的结构，一共需要4行，第5行开始为数据区。
第一行表示这个字段是客户端读取还是服务端读取，或者是都读，c/s/cs
第二行为英文字段名， 第一列的字段名始终固定叫ID,其他字段使用驼峰命名规则。
第三行为数据类型，例如 int、int[]  等。
第四行为中文注释说明。

### 5.3 枚举表结构规则
枚举表的结构，遵循通用的表结构规则，不过在字段的命名上，有更严格的规则：
第一列为ID,这个是通用的规则，一般第二列字段名叫name，string类型，表示这个枚举的英文字段名，
第三列叫desc，string类型，表示这个枚举的中文说明，这3列是固定的名字，后续的字段可以随意添加。

---


## 6. 开发工作流与维护

### 6.1 数据维护流程
1.  **策划编辑**：策划人员在独立的 Git 仓库中维护 `.xlsx` 源文件。
2.  **工具解析**：
    *   执行解析工具，读取 Excel。
    *   生成 Java 代码（`Config` 类, `Manager` 类, `Enum` 类, `GlobalConst` 类）。
    *   生成数据文件（`.xml`），供程序运行时读取。

### 6.2 同步至工程 (Sync)
*   **操作脚本**：`update_copy.bat`。
*   **作用**：将解析工具生成的代码和 XML 数据复制到服务器/客户端的工程目录下。
*   **操作建议**：
    该步骤建议由**人工手动执行**，而非 CI/CD 自动触发。
    *   *原因*：避免策划频繁修改或不稳定的中间数据实时同步到开发环境，导致程序运行出错。开发人员应在确认数据环境稳定后，主动执行脚本同步数据。

---

## 7. 常用设计模式 (Design Patterns)

### 7.1 阶梯消耗与通用物品消耗
对于“次数递增消耗”或“多种物品混合消耗”的场景，优先使用 `int[][]` (二维数组) 存储，而非创建单独的子表。

*   **格式**: `ItemId;Count;...|ItemId;Count;...`
    *   **分隔符**: `|` 分隔外层数组（如不同的次数阶梯），`;` 分隔内层数组（具体的物品列表）。
*   **示例 1 (阶梯消耗)**:
    *   需求：第1次消耗 100金币，第2次消耗 200金币。
    *   配置：`1001;100|1001;200`
    *   解析：`int[][] cost = {{1001, 100}, {1001, 200}};`
*   **示例 2 (混合消耗)**:
    *   需求：消耗 100金币 和 1个令牌。
    *   配置：`1001;100;2001;1`
    *   解析：`int[][] cost = {{1001, 100, 2001, 1}};` (视具体逻辑，也可能是一维数组)
*   **代码处理**:
    *   服务端通常提供 `PlayerHelper.delResources(player, int[] costs)` 方法，直接支持解析 `{ItemId, Count, ItemId, Count...}` 格式的数组。

***

## 8. 环境与测试来源约束

- 区分策划 XLSX 源文件、生成 Java 类、运行 XML 与当前环境配置；核对实际解析代码及启动参数后选择路径，不能仅凭目录名推测生效数据。
- 不把其他项目的配置版本选择算法、绝对路径或表结构当作本项目事实。
- 表生成与复制前检查工作树 diff；使用既有工具同步，不直接改生成类来掩盖源数据问题。外部工具 `update_copy.bat` 的实际位置和参数由对应配置仓库确认，本仓库不提供该入口。
- 真实配表验证记录来源版本、路径和环境；隔离夹具不得修改共享原始表。

### 8.1 已核实的仓库路径

| 资产 | 本项目位置 | 使用边界 |
|---|---|---|
| 运行 XML | `game/src/main/resources/xml/` | 打包/部署后仍核对实际加载路径和版本，不能把源码目录当成运行中真源 |
| 生成配置类 | `protocol/src/main/java/cn/game/protocol/generated/config/` | 修改源表后重新生成，禁止手改生成类 |
| 枚举 / Manager / Helper | 同级 `enume/`、`manager/`、`helper/` | 参数解释与查询方法以当前生成产物为准 |
| 新 XLSX 辅助生成 | `tools/generate_excel.py` | JSON → XLSX；不是 XLSX → Java/XML 的正式导表器 |

旧 design-architect 的命令可继续使用：`python tools/generate_excel.py <json_path>`。脚本依赖 pandas/openpyxl；JSON 包含 `fileName`、`sheets[]`，每张表含 `name`、`cs`、`fields`、`types`、`comments`、`data`。输出在 JSON 所在目录，四行表头与第 5 节一致；字段列表长度要先核对，脚本会截断/补齐表头，且捕获异常后不保证非零退出码，因此必须检查输出文件及实际表内容。此工具仅辅助新表，正式解析与 `update_copy.bat` 仍由配置仓库既有链路负责。

### 8.2 配置校验与局部扩展

- 在加载/初始化阶段校验引用 ID 存在、数组形状与长度、数量/概率/上下限、周期起止与枚举有效性；不能等玩家扣费后才发现奖励配置损坏。
- 校验依赖跨表数据时选择所有相关 Manager 已加载的既有扩展点，报错带表名、行 ID、字段与非法值；不在每次玩家请求中全表扫描。
- 单功能优先新增功能内字段、独立表或既有索引扩展；不能为了本功能改公共字段含义、解析器或加载顺序。已确认公共加载器缺陷才单独定位修复并验证受影响模块。
- 上线兼容同时检查旧 XML 缺字段、新 XML 被旧服务读取、旧枚举/ID 的行为；保留已约定缺省值，禁止以任意默认奖励掩盖坏表。
- 生成后审查源表、XML、Java 三者 diff 和实际加载结果；测试 fixture 与共享真实表隔离。
