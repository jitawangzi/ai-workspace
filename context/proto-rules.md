# 通讯协议规范 (Protocol Specification)

本文档旨在规范客户端与服务端之间的通讯协议设计。协议基于 Google Protobuf 3 (`proto3`) 定义，涵盖文件管理、命名规则、ID 分配、代码生成配置及数据同步策略。

## 1. 文件组织与存放

*   **存放位置**：位于 `protocol` maven 子模块中。
*   **具体路径**：`src/main/proto` 文件夹下。

## 2. 基础定义规范

### 2.1 文件定义
*   **划分粒度**：以“功能模块”为单位划分 `.proto` 文件（例如：宠物系统、商店系统）。
*   **命名格式**：`[模块名]Msg.proto`。
    *   *示例*：宠物系统协议文件命名为 `PetMsg.proto`。
*   **包名定义**：所有协议文件统一使用以下包名：
    ```protobuf
    package cn.game.protocol.protobuf;
    ```
*   **依赖管理**：
    *   每个功能模块文件（如 `ShopMsg.proto`）可独立存在。
    *   公共数据结构定义在 `BaseMsg.proto` 或 `RewardMsg.proto` 中。
    *   功能模块可 `import` 基础模块，但**严禁**功能模块之间产生循环引用。

### 2.2 消息命名
消息（Message）名需遵循以下语义格式：
> **格式**：`[模块名][行为][类型]_[协议ID]`

| 组成部分 | 说明 | 示例 |
| :--- | :--- | :--- |
| **模块名** | 功能的英文名称（首字母大写） | `Pet` |
| **行为** | 该协议的具体操作动作 | `Composite` |
| **类型** | `Request` (请求) / `Response` (响应) / `Push` (推送) | `Request` |
| **协议ID** | 唯一标识符（详见下方 ID 规则） | `19000001` |

**完整示例**：
```protobuf
// 碎片合成宠物请求
message PetCompositeRequest_19000001 { ... }
```

## 3. 协议 ID 规则

协议 ID 为全局唯一的 16 进制数字，结构如下：
*   **高 8 位**：模块 ID（Module ID），同一模块下的所有协议此位必须相同。
*   **低 24 位**：消息 ID，用于区分同一模块下的不同协议。

**模块ID取值**：不同的模块模块ID不能相同，所以在定义时，需要搜索全部的.proto文件，确保不能重复。

### 3.1 请求与响应 (Request/Response)
遵循 `Request ID + 1 = Response ID` 的配对规则，便于通过 ID 自动关联请求与返回。
*   **Request**：由客户端发起。
*   **Response**：由服务器返回。

### 3.2 服务器推送 (Push)
表示服务器主动下发的消息（如聊天推送、踢人下线），无需客户端请求。
*   **ID 规则**：
    *   不得与 Request/Response 的 ID 冲突。
    *   应避免 `PushID` 与 `PushID - 1` 覆盖现有的 Request/Response ID 范围。
    *   *建议*：使用较高的低位 ID 区段来专门定义 Push 消息。

### 3.3 ID 定义示例
```protobuf
// [Request] 碎片合成宠物
message PetCompositeRequest_19000001 {
    int32 id = 1; // Pet表配置ID
}

// [Response] 合成结果（ID = 请求ID + 1）
message PetCompositeResponse_19000002 {
}

// [Push] 玩家退出/被踢推送
message PlayerLogoutPush_01100030 {
}
```

## 4. 代码生成配置 (Annotations)

在 `.proto` 文件中，通过注释形式配置参数，供代码生成器 (`PbProtocolGenerator`) 使用。

### 4.1 配置项说明

| 标签 | 说明 | 必选性 | 示例 |
| :--- | :--- | :--- | :--- |
| `HandlerPackage` | 生成的服务端 Handler 类所在的包路径。<br>`cn.game.games.net.game.module.[模块名小写]` | **必选** | `cn.game.games.net.game.module.pet` |
| `MessageModule` | 模块的数字编号（对应 ID 高 8 位）。 | **必选** | `19` |
| `ClientHandlerPackage` | 生成的客户端测试类 Handler 包路径。 | *可选* | `cn.game.simulation.client.handler` |
| `Function` | 对应功能的枚举名（InitialUI），用于默认的功能开启校验。 | *可选* | `Pet` |

### 4.2 配置示例
```protobuf
//@HandlerPackage cn.game.games.net.game.module.develop.pet
//@ClientHandlerPackage cn.game.simulation.client.handler
//@Function Pet
//@MessageModule 19

package cn.game.protocol.protobuf;
// ... 协议内容
```

## 5. 开发工作流

1.  **编写协议**：修改或新增 `.proto` 文件。
2.  **生成代码**：运行`protocol.bat`会运行 `PbProtocolGenerator` 。
3.  **产出物检查**：
    *   **服务端**：
        *   `.proto` 文件被编译为 Java 代码。
        *   生成对应模块的 Handler 桩代码（如 `PetHandler`）。
        *   生成 `PbProtocol` 类（框架内部使用，开发可忽略）。
    *   **客户端**：
        *   生成客户端开发所需的协议文件（开发可忽略具体生成过程及文件）。

## 6. 通讯模式与数据同步设计

### 6.1 玩家数据分类
玩家数据在架构上分为两类，采用不同的同步策略：

#### A. 核心基础数据 (PlayerAllInfo)
*   **定义**：高频使用、可能被多模块引用的重要数据（如等级、货币、道具、关卡进度、核心养成等）。
*   **同步机制**：
    *   **登录时**：服务器通过 `PlayerLoginResponse` 将全量核心数据下发。
    *   **维护**：客户端需缓存并实时维护这部分数据。
    *   **作用**：客户端利用本地缓存进行预先合法性检查（Pre-check）或 UI 展示。
*   **协议示例**：
    ```protobuf
    message PlayerLoginResponse_01000002 {
        PlayerAllInfo info = 1;     // 用户全量核心数据
        bool reconnect = 2;         // 是否断线重连
        string time = 3;            // 服务器时间戳
    }
    ```
*   **服务端实现**：
    需要在对应的 Logic Module 中复写 `buildPlayerAllInfo` 方法并填充数据。例如 `ItemModule`：
    ```java
    @Override
    public void buildPlayerAllInfo(PlayerAllInfo.Builder builder) {
        for (Item item : list()) {
            builder.addItems(item.toItemInfo());
        }
    }
    ```

#### B. 周边功能数据
*   **定义**：独立性强、低频使用或仅在特定界面展示的数据（如活动详情、排行榜、商店列表、邮件）。
*   **同步机制**：
    *   **按需拉取**：不随登录下发，仅在打开对应功能界面时请求服务器获取。
    *   **独立性**：通常不被其他模块引用。

### 6.2 状态变更与物品同步
当发生业务操作（如消耗碎片合成宠物）时，数据同步遵循以下模式：

#### 1. 资源扣除（隐式处理）
*   **机制**：服务器执行扣除逻辑后，会主动下发通用的“资源/道具变化协议”。
*   **客户端处理**：监听通用协议并更新本地缓存。
*   **协议设计**：具体的业务响应协议（如 `PetCompositeResponse`）**不需要**包含扣除的道具信息。

#### 2. 资源获得（显式携带）
*   **机制**：新获得的物品（特别是如宠物实例、装备实例等包含服务端生成属性的对象），无法由客户端简单构造。
*   **协议设计**：必须在业务响应协议中**显式包含**获得的物品数据。
*   **示例**：
    ```protobuf
    // 领取任务奖励请求
    message QuestReceiveRequest_20000004 {
        repeated int32 ids = 1; // 任务ID列表
    }

    // 领取任务奖励响应
    message QuestReceiveResponse_20000005 {
        repeated RewardInfo rewards = 1; // 必须明确返回获得的奖励详情
    }
    ```

## 7. 可迁移的协议设计与兼容经验

- Handler 负责协议边界、鉴权/入参、调用和响应；Module 维护业务语义。协议描述业务结果，不泄漏内部存储结构。
- 静态配置默认仅传 ID，动态状态和服务端生成属性按实际契约传递；不重复下发客户端已具备的整份配置。
- 字段语义、单位、默认值、可见范围和错误原因要明确。沿用本项目 Protobuf 命名与数据同步约定，不移植其他项目的 JSON 字段名或资源回包协议。
- 扩展优先新增字段/消息；不复用已删除字段编号，不改变旧编号的类型与语义。删除字段时使用 Protobuf 的 reserved 约束，检查生成代码与调用端同步。
- 核对实际服务端/客户端发布顺序、兼容窗口和回退能力；窗口内保留仍在使用的旧协议，不假设全服已经升级。
- 展示他人数据时，按接收方版本/配置能力过滤。原始存储值保持真实；不兼容字段用约定安全值或过滤不支持条目。
- 设计时列明每个变更字段的来源、静态/动态属性、兼容处理和断言点；T2 同步受影响段落，T3 按完整设计契约记录，不用 context 另加审批流程。
- 测试覆盖成功、每类失败、资源通知/响应一致性、重复请求和实际兼容矩阵；语法可解析不代表语义兼容。

### 7.1 集合边界

新增或直接修改的对外协议不暴露裸 `Map<K,V>` / Protobuf `map<K,V>`，使用命名明确的 `repeated XxxInfo` 表达键值及其业务含义。内部 Map 仍可作为索引；在协议边界转换，不直接暴露序列化存储。原有 map 协议只在本功能确需变更时按兼容窗口迁移，不能批量破坏已有客户端。

```protobuf
// 示例字段号仅用于新消息；修改既有消息必须保留原编号。
message ProgressInfo {
    int32 config_id = 1; // 配置主键
    int64 count = 2; // 累计进度，非奖励数量
}
message ProgressList {
    repeated ProgressInfo entries = 1; // 顺序由具体功能约定
}
```

### 7.2 协议字段设计核对表

每个新增/修改字段填写一行，T2 放在现有设计段落，T3 放在设计契约，不另加审批。

| 字段 / 编号 | 来源与权威方 | 静态或动态 | 类型 / 单位 / 缺省含义 | 接收方与权限 | 兼容 / 发布顺序 | 验证断言 |
|---|---|---|---|---|---|---|
| 示例：奖励列表 | `PlayerHelper` 实际发放结果，服务端权威 | 动态增量 | `repeated RewardInfo`；空表示无新增奖励 | 当前玩家 | 新增字段不复用旧编号，旧客户端忽略新字段 | 返回值与真实资源变化一致，重试不重复发放 |

请求字段还须明确范围、唯一性、归属与伪造处理；响应字段明确全量/增量、集合顺序/去重、空集合与缺省值；资源扣除通知和奖励响应分别按第 6 节负责。无法明确来源或客户端用途的字段先查证，不把内部临时状态直接塞入协议。
