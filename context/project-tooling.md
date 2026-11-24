<!-- context-meta owner:jitawangzi reviewedAt:2026-11-24 expiresAt:2027-05 -->
# 项目工具与仓库边界

> 底层测试夹具、打包/增量复审导出参数、失败现场清理及历史性能测量细节已拆分至按需文档 [tooling-reference.md](tooling-reference.md)。

## 1. 工具链与编译

项目根 `pom.xml` 声明六个 Maven 模块（`util`/`protocol`/`core`/`game`/`login`/`simulationclient`），Java release 为 21，流程脚本使用 PowerShell 7 (`pwsh`)。

```powershell
mvn -B '-DskipTests' compile
mvn -B '-DskipTests' test-compile
```

根 POM 默认 `skipTests=true`。编译成功、`test-compile` 成功或 Maven 报 `BUILD SUCCESS` 均**不保证测试实际执行**。执行真实 JUnit 用例须显式 `-DskipTests=false` 并核对报告；`simulationclient` 场景位于 `src/main/java`，`mvn test` 不会自动运行它们。

## 2. 服务端优化批次的多 Agent 独立审核约定（按范围适用）

> **适用范围澄清**：本节仅适用于**服务端架构/核心链路优化批次**（如存储/保存/支付/跨服优化专项）或**用户显式要求独立审核的任务**；常规日常业务功能开发、小 Bug 修复与文档任务仍严格按 [AGENTS.md](../../AGENTS.md) 默认 **T2** 执行（不强制独立审核、不自动升级为 T3，也不依赖独立 subagent）。

触发本节约定的批次默认仍按 T2 执行，并追加下列交付要求（不因此升级为 T3 或重复索取已有授权）：

- 每批由至少两位独立审核者先分别审查同一源码版本；一位侧重业务预期、调用方与兼容，另一位侧重异常、资源生命周期与证据，首轮不共享结论。
- 审核者只读，controller 保持修改任务归属并统一修复；审核遵循宿主 context，区分本次引入/放大缺陷、耦合风险与既有问题。
- 确认问题后按独立修复任务登记、验证和提交（一个修改任务一个功能 commit）；修复后复审须附当前编译与相关测试证据。
- 交付汇总记录审核者、源码版本、发现及处理、复审结论、实际测试结果与未验证范围。宿主、`.ai-workspace` 与 `specs` 按真实 Git 归属分别提交，保留用户原有改动，不自动推送未授权分支。

## 3. SOP 验证入口与 Profile

[verification-commands.json](verification-commands.json) 提供以下 Profile（均从项目根通过 `ai-sop.ps1 Task -Operation Run ... -Profile <名>` 执行）。各入口的环境前提、资源写入与清理边界见 [verification-effects.md](verification-effects.md)。

| Profile | 类型 | 实际范围 |
|---|---|---|
| `compile` | compile | Maven 生产编译（30 分钟） |
| `compile-tests` | compile | Maven 生产与测试源码编译，不执行测试（30 分钟） |
| `java-unit-smoke` | test | `core` 的 `TagManagerTest`（附 [目标清单](test-suites/java-unit-smoke.json)） |
| `java-tests` | test | reactor 全量 Maven 测试（运行前审查环境依赖，不默认用于每次任务） |
| `workspace-syntax` | compile | 本工作区脚本 PowerShell 解析、JSON 与 Profile Schema 校验 |
| `workspace-script-tests` | test | 临时 Git 仓库同步行为与真实 Java classpath 加载回归 |
| `workspace-contract` | test | 目录、文档链接、知识完备性、项目适配与安装投影一致性 |
| `sop-tests` | test | 自动发现引擎全部测试套件（混合 VCS 回归需 `svn`/`svnadmin`） |
| `module-acceptance-platform` | test | 进程内模块双轨验收引擎（`CONTRACT` + `MATRIX_SCAN`）与已注册模块套件回归 |
| `state-integrity` | test | `game` 模块保存快照、保存顺序、风险恢复与支付幂等四组测试 |
| `payment-trial-tools` | test | 正式反证工具的退出、超时、清理与报告判定回归（不连业务服务） |
| `first-charge-calibration` | test | 在线首充分支的替身与正式买入契约校准 |
| `runtime-evidence-tests` | test | 本机 HTTP 夹具、失败证据与参数编码回归（不连游戏服） |
| `runtime-identity-java` | test | 制品与配置摘要、挑战/实例/玩家/逻辑区服绑定定向 Java 用例 |
| `runtime-concurrency-tests` | test | 独立 pwsh 控制器与持久状态夹具覆盖快照排他锁、清理归属与失败恢复 |

- **JUnit 5 报告门禁**：Java Profile 通过 `scripts/run-java-tests.ps1` 调用 Surefire 3.5.2（避免默认 2.12.4 跳过 JUnit 5），核对本轮新生成 XML，零执行/全跳过/失败均不通过；定向验证可传 `-Project` / `-Test` / `-ExpectedTestsFile <JSON>`。
- **适用边界**：`workspace-*` 仅适用于只改工作流资料/脚本的任务，不能替代 Java 编译或行为测试。

## 4. 常用开发与测试脚本

- **模拟客户端**：沿用根 `run_client.ps1 -TestClass <完整类名>`（classpath 将各模块 `target/classes` 置于依赖 JAR 前，跨模块改动须编译完整依赖闭包）。在 SOP 任务内执行示例：
  ```powershell
  & ./ai-sop.ps1 Task -Operation Run -Feature <Feature> -TaskId <TaskId> -Agent <Agent> -Kind test -Batch simulation -Executable pwsh -Arguments @('-NoProfile','-File','./run_client.ps1','-TestClass','<实际完整类名>') -TimeoutSeconds 600
  ```
- **运行实例联调**：`run_server.ps1` 默认仅 `Prepare` 独立制品快照；`Start`/`Stop` 规则见 [runtime-verification.md](runtime-verification.md)。
- **协议生成**：根 `protocol.bat`（先核对 `protocol/` 独立仓库状态；生成的 Java 代码及生效配置属于实现，不能当文档延期）。
- **核心 API 查询**：不维护静态全量签名快照；通过 [ai-coding.md](ai-coding.md) 第 16 节类路径速查表直接读取最新源码。

## 5. 五仓 Git 归属与同步

| 目录 | 仓库归属 | 说明 |
|---|---|---|
| `server/`（含 `doc/`、根 `README.md`） | `server.git`（宿主主仓） | `.gitignore` 已忽略 `.ai-workspace/`、`protocol/` 与投影目录（`ANTIGRAVITY.md`/`GEMINI.md`/`ai-sop.ps1` 由宿主跟踪，禁止手改）；仅提交本次任务改动 |
| `protocol/` | `protocol.git`（独立仓库） | 改协议或配置生成类前先 `git -C protocol status`，须独立提交 |
| `.ai-sop/` | `agent-sop.git`（Git Submodule） | 版本由 `tools/ai-sop/ai-sop.lock.json` 锁定；**严禁在宿主投影副本修改** |
| `.ai-workspace/`（不含 `specs/`） | `ai-workspace.git`（独立仓库） | 存放本服领域上下文、自建 Skill 与校验脚本 |
| `.ai-workspace/specs/` | `game_specs.git`（独立仓库） | 外层 `.gitignore` 隔离；仅存放本服功能设计与任务，见 [specs/README.md](../specs/README.md) |

- `.ai-workspace/` 与 `specs/` 各自提供 `commit.cmd` / `pull.cmd`（前者只提交已手动暂存文件并 push，不执行 `git add .`；后者要求工作树干净且只做 fast-forward）。
- 保留 `.artifacts/` 输入证据与任务记录；本机 Session/Grant/owner、日志与 `.runtime/` 不作为可迁移权限。
- 跨任务发现保存在 `specs/features/<Feature>/findings/<编号>.json`，修改前按范围核对未关闭项；通用规则见 `.ai-sop/docs/REVIEW_AND_FINDINGS.md`。
- 独立功能并行开发遵循 [parallel-development.md](../workflows/parallel-development.md)。

## 6. 安装诊断与常用运维命令

```powershell
pwsh -NoProfile -File ./ai-sop.ps1 Verify   # 检查安装版本、manifest 与投影一致性
pwsh -NoProfile -File ./ai-sop.ps1 Doctor   # 检查本机依赖与接入状态
```

- Hook 配置文件存在不代表客户端已启用，接入详见 `.ai-sop/docs/HARNESS_ADAPTERS.md`。
- **只读探索阶段防误触 PreToolUse Guard**：未执行 `Task Start/Resume` 前，只读排查优先使用原生文件读取工具；如需执行只读命令，使用**单条无分号、无变量 `$`、无脚本块 `{}`、无重定向 `>`、不越界 `..`** 的命令（如 `rg`、`git status|diff|log`、`Get-ChildItem`、`Select-String`）。Antigravity 客户端若遇 `update_focus`/`update_steps` 被报 `AI_SOP_GUARD_TOOL_UNKNOWN`，属上游 `agent-sop` Hook 工具白名单范围（不得在宿主 `.ai-sop/` 副本手改）。
- 审查导出（`export-review.ps1`）、证据打包（`pack-review-evidence.ps1`）、大型输入基线预算（`start-inputs.json`）及底层测试清理细节见 [tooling-reference.md](tooling-reference.md)。
