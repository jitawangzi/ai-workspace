# ai-workspace — 游戏服务端领域上下文与工作区

本目录保存当前 Java 游戏服务端的领域知识、自建 Skill、验证配置与校验脚本，位于宿主项目根 `.ai-workspace/`。

- **项目全景地图（人 + AI 首屏导航）**：[项目根 README](../README.md)
- **SOP 流程入口**：宿主根 [AGENTS.md](../AGENTS.md) 与 `ai-sop.ps1`（通用引擎位于 `.ai-sop/`，严禁宿主手改）
- **项目知识总索引**：[context/README.md](context/README.md)

## 目录结构

```text
.ai-workspace/
├── context/       本服领域知识、编码规范、业务模式、排障手册与验证 Profile
├── skills/        本服自建 Skill 真源（由安装器投影至宿主 .agents/ 与 .claude/）
├── schemas/       项目 Schema 扩展说明（通用 Schema 真源在 .ai-sop/schemas/）
├── scripts/       本服工作区校验、JUnit 报告门禁、本地运行时与回归脚本
├── workflows/     并行开发、发布恢复与历史迁移记录
├── specs/         独立规格与任务仓库（外层 Git 忽略，仅保存本服功能/平台资料）
├── commit.cmd     仅提交已手动暂存文件并推送
└── pull.cmd       干净工作树的 fast-forward 拉取
```

## 快速开始

从宿主项目根 `server/` 执行：

```powershell
pwsh -NoProfile -File ./ai-sop.ps1 Verify
pwsh -NoProfile -File ./ai-sop.ps1 Doctor
pwsh -NoProfile -File ./ai-sop.ps1 Task -Operation Discover
```

纯问答或只读排查无需启动任务；准备修改代码、配置或文档时，由主会话执行 `Task Start` / `Resume`（默认 T2；T1/T3 由人工显式指定）。

构建、测试与验证 Profile 用法见 [project-tooling.md](context/project-tooling.md)。

## 仓库边界与同步

- **本目录（`.ai-workspace`）**：`https://github.com/jitawangzi/ai-workspace.git`（分支 `main`），专供本服务端项目。
- **通用引擎（`.ai-sop`）**：`https://github.com/jitawangzi/agent-sop.git`，由宿主子模块与 `tools/ai-sop/ai-sop.lock.json` 共同固定版本，不在宿主直接修改。
- **规格仓（`.ai-workspace/specs`）**：`https://github.com/jitawangzi/game_specs.git`（分支 `main`），外层 `.gitignore` 已隔离，须独立同步任务与 `.artifacts/`；仅存放本服功能/平台资料，详见 [specs/README.md](specs/README.md)。
- **宿主与协议仓**：宿主 `server.git` 与 `protocol/` 独立仓库不随本目录推送。

同步前先确认所在仓库并审阅暂存 diff，不要默认 `git add .`：

```powershell
git -C .ai-workspace status
git -C .ai-workspace add -- <本任务文件>
git -C .ai-workspace diff --cached
# 然后在目标仓库内执行 ./commit.cmd -Message "说明" 或普通 git commit / push；拉取用 ./pull.cmd
```

## 在新机器恢复完整工作区

1. 克隆宿主 `server.git` 与独立 `protocol.git`，核对本机 JDK 21、Maven、PowerShell 7 与外部 `../configs`、`../dic_generate`。
2. 按官方安装锁初始化 `.ai-sop/` 并投影入口文件（`tools/ai-sop/install-ai-sop.ps1`）。
3. 克隆 `ai-workspace.git` 到 `.ai-workspace/`，单独克隆 `game_specs.git` 到 `.ai-workspace/specs/`。
4. 从宿主根运行 `Verify`、`Doctor` 与 `workspace-contract` 校验；客户端 Hook 按引擎 `HARNESS_ADAPTERS` 文档启用。
5. 跨机器续做任务须先在原处 `Suspend`，同步代码与 `specs` 后在接收处 `Resume`，不得复制本机 Session/Grant 权限文件。

> 历史背景：本工作区由早期项目迁移适配而来，完整迁移对照与复核记录留档于 [migration-20261021.md](workflows/migration-20261021.md) 与 [migration-audit-20261022.md](workflows/migration-audit-20261022.md)。
