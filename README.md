# ai-workspace — 个人 Java 游戏服务端

个人服务端的项目知识与 AI 工作目录，安装于宿主项目根 `.ai-workspace/`。通用 SOP 位于同级 `.ai-sop/`，主入口为宿主根 `AGENTS.md` 与 `ai-sop.ps1`。

## 目录

```text
.ai-workspace/
  context/       项目知识、跨项目经验与验证 Profile
  schemas/       项目 Schema 扩展说明（通用 Schema 引用引擎）
  scripts/       本项目工作区校验工具
  specs/         独立规格与任务仓库，外层 Git 忽略
  workflows/     迁移记录、同步与并行约定
  commit.cmd     仅提交已手动暂存文件并推送
  pull.cmd       干净工作树的 fast-forward 拉取
```

结构沿用参考项目；内容已适配本项目 Maven、JDK 21、Protobuf、玩家队列与 Module 保存机制。原 `.claude_old/` 保留供人工比较。

## 开始使用

从宿主项目根执行：

```powershell
pwsh -NoProfile -File ./ai-sop.ps1 Verify
pwsh -NoProfile -File ./ai-sop.ps1 Doctor
pwsh -NoProfile -File ./ai-sop.ps1 Task -Operation Discover
```

随后正常描述开发需求。默认 T2；T1/T3 由用户显式选择。各工具读取根 AGENTS.md 与 [context 索引](context/README.md)，旧 `.claude_old` 不再是活跃流程入口。

构建、测试与 Profile 用法见 [project-tooling.md](context/project-tooling.md)。迁移去向、适配取舍与待核实项见 [迁移记录](workflows/migration-20261021.md)。

## 仓库边界

- 本目录 remote：`https://github.com/jitawangzi/ai-workspace.git`，分支 main，专供个人项目。
- 通用引擎：`https://github.com/jitawangzi/agent-sop.git`，宿主子模块与安装锁共同固定版本。
- specs remote：`https://github.com/jitawangzi/game_specs.git`，分支 main，按用户确认复用。保留现有功能和历史，新加入个人项目 Dragon 资料与 SopMigration 迁移任务；外层 `.gitignore` 隔离 specs，须独立同步任务与 `.artifacts/`。
- 宿主 `server.git`、`protocol/` 子仓库及 `.claude_old` 不随本目录推送。
- aircraft 的旧知识工作区已由用户弃用，保留的旧 remote 不代表继续共享当前 main；不得把其 context 分支合并到个人项目。引擎安装副本可随核心兼容修复同步，不改其旧知识内容。

specs 包含参考项目已有功能；这些资料保留用于查阅，不代表个人项目已经实现，也不授予本地会话原有 ACTIVE 任务的权限。个人项目当前需求从 Dragon 或明确新建的功能开始。

本目录可用普通 `git pull --ff-only` / `git add <本次文件>` / `git commit` / `git push` 同步。操作前确认当前目录和 remote，先审阅暂存 diff。specs 按独立仓库同步，不能依赖外层 push。

也可先 `git add -- <本任务文件>`，检查 `git diff --cached`，再 `./commit.cmd -Message "说明"`；拉取使用 `./pull.cmd`。specs 有相同独立入口，不默认 `git add .`，不改变代理设置。

## 在另一份宿主副本恢复

1. 在宿主根按官方方式安装/初始化 `.ai-sop`，使用受信的版本锁和安装器生成入口。
2. 将本仓库克隆为宿主根 `.ai-workspace`，将 game_specs.git 单独克隆为 `.ai-workspace/specs`。
3. 从宿主根运行 Verify、Doctor 和工作区校验；核对本机 JDK 21/Maven 与协议子仓库。Hook 配置存在不等于客户端已启用，按引擎 HARNESS_ADAPTERS 文档接入。
4. 跨机器续做任务须先在原处 Suspend，再同步代码和 specs，在接收处 Resume；不得复制机器级会话权限。

## 验证范围

工作区脚本与配置用 workspace-syntax、workspace-contract 验证；引擎使用自动发现的全量测试套件。本次结果保存在 specs/features/SopMigration/ 的说明及任务记录中。Java 游戏编译、服务启动、数据库操作和业务联调不属于本次迁移的验证结论。

后续审查补充见 [2026-10-22 处理记录](workflows/migration-audit-20261022.md)：增加同步工具回归和定向 JUnit Profile。定向 core 单测与最初文档迁移的验证范围分别记录，均不代表完整游戏业务验收。
