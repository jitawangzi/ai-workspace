<!-- context-meta owner:jitawangzi reviewedAt:2026-10-22 expiresAt:2027-01 -->
# 项目工具与仓库边界

## 工具链与编译

项目根 `pom.xml` 声明六个 Maven 模块，Java release 为 21。流程脚本使用 PowerShell 7 (`pwsh`)；不要搬入参考项目的 Gradle、Tomcat/JSP 或 SVN 流程。

从项目根运行：

```powershell
mvn -B '-DskipTests' compile
mvn -B '-DskipTests' test-compile
```

根 POM 默认 `skipTests=true`。编译成功、`test-compile` 成功或 Maven 报 BUILD SUCCESS 都不保证测试实际执行。选用真实 JUnit 用例时显式 `-DskipTests=false`，核对测试计数与报告；模拟客户端场景位于 `src/main/java`，不能假设 `mvn test` 会自动运行它们。

## SOP 验证入口

### 本项目批次的独立审核约定

用户已明确要求服务端优化后续每批修改加入多 agent 独立审核。默认仍按 T2 执行，并追加下列交付要求，不因此升级为 T3 或重复索取已经给出的实施授权：

- 每批由至少两位独立审核者先分别审查同一源码版本；优先覆盖并发时序、异常传播和测试证据，首轮不以其他审核者结论替代独立走查。
- 审核者只读，controller 保持修改任务归属并统一修复。审核遵循宿主 context，不套用其他项目的存储或协议约定；区分本次引入/放大的缺陷、直接耦合风险和既有问题。
- 确认问题后按独立修复任务登记、验证和提交，一个修改任务一个功能 commit；修复后的复审附当前编译、相关测试证据。后续修改影响已审范围时，请对应审核者重新核对，不复用旧版本的通过结论。
- 交付汇总记录审核者、源码版本、发现及处理、复审结论、实际测试结果和未验证范围。计划讨论不等于代码审核，编译/单测也不等于真实集群或数据库验收。
- 宿主、`.ai-workspace` 与 `specs` 按真实 Git 归属分别提交；任务证据另仓提交时说明对应关系，保留用户原有改动，不自动推送。

[verification-commands.json](verification-commands.json) 提供以下 Profile，均从项目根执行。

每个入口的环境、资源写入、隔离清理、失败材料与结论范围见 [验证副作用说明](verification-effects.md)。说明用于选择已有入口，不增加审批；已有明确授权持续有效。

跨任务发现存放在规格仓 `features/<Feature>/findings/<编号>.json`。修改前按实际范围检查未关闭发现；关闭须关联修复提交、真实回归与适用审核依据。当前状态以发现记录为准，避免将本文中的历史状态当成实时结论；当前任务 PASS 不改变其他发现状态。通用规则见 `.ai-sop/docs/REVIEW_AND_FINDINGS.md`。

需要审查材料时，从宿主根执行 `.ai-sop/scripts/export-review.ps1 -WorkspacePath . -Feature <实际功能> -TaskId <实际任务> -CheckCurrent -Scope <受影响路径>`。多仓增加 RepositoryPaths（本项目还包括 protocol）。输出是派生导航，不是第二份权威状态；缺报告、缺基线和未知清理必须保留缺口，摘要一致不代表业务正确。只读入口不隐式运行构建或测试。

| Profile | 类型 | 实际范围 |
|---|---|---|
| `compile` | compile | Maven 生产编译，30 分钟 |
| `compile-tests` | compile | Maven 生产与测试源码编译，不执行测试，30 分钟 |
| `java-unit-smoke` | test | core 的 `TagManagerTest`，显式开启测试；需核对实际 Surefire 测试数，不等于业务全覆盖 |
| `java-tests` | test | reactor 全量 Maven 测试，显式开启测试；运行前审查用例环境依赖，不能默认用于每次任务 |
| `workspace-syntax` | compile | 本次治理脚本 PowerShell 解析、JSON 与 Profile Schema 校验，5 分钟 |
| `workspace-script-tests` | test | 临时 Git 仓库同步行为与真实 Java classpath 加载回归 |
| `workspace-contract` | test | 目录、文档链接、旧知识覆盖、项目适配和安装投影一致性，5 分钟 |
| `sop-tests` | test | 自动发现引擎全部测试套件，60 分钟 |
| `state-integrity` | test | game 模块保存快照、保存顺序、风险恢复和支付幂等四组现有测试；逐方法检查目标清单，不证明真实数据库或崩溃恢复 |
| `runtime-evidence-tests` | test | 本机 HTTP 夹具、失败证据、真实 Java 参数编码；不连接游戏服 |
| `runtime-identity-java` | test | 制品与配置摘要、挑战/实例/玩家/逻辑区服绑定的定向 Java 用例 |

Java Profile 通过 `scripts/run-java-tests.ps1` 运行 `test-compile` 和明确版本的 Surefire 3.5.2，避免本机 Maven 默认 Surefire 2.12.4 不执行 JUnit 5；检查本轮新生成的 XML，零执行、全跳过或失败都不能通过。定向测试可使用同一脚本的 `-Project` / `-Test`，按 Task Run 记录。JUnit 5 提供器依据见 [Surefire 官方说明](https://maven.apache.org/surefire-archives/surefire-3.5.5/maven-surefire-plugin/examples/junit-platform.html)。

关键定向任务另传 `-ExpectedTestsFile <JSON文件>`，用非空字符串数组列出完整类名或 `完整类名#方法名`。只核对本轮新报告中的实际 testcase：类目标至少执行一个用例，方法目标必须存在且所有匹配调用均未跳过；其他用例成功不能补足缺失目标。嵌套类使用报告中的 `$` 名称，方法名可用报告原名或不带参数的 Java 方法名。类目标不代表该类所有方法均执行，需要逐方法保证时逐项列出。未传清单时仍保留真实执行数、新报告和失败门禁，兼容原入口。

`java-unit-smoke` 使用 [目标清单](test-suites/java-unit-smoke.json)；报告门禁自身的回归入口为 `scripts/java-test-evidence.tests.ps1`，仅验证报告判定，不冒充 Java 行为测试。清单中的方法变更应随真实测试同步，不能删除缺失项来掩盖未执行。

`workspace-*` 适用于只改工作流资料/脚本的任务，不能作为 Java 改动的编译或行为测试证据。业务变更选择 `compile` 或 `compile-tests`，并运行与功能相关的实际测试。

`sop-tests` 的混合 VCS 回归需要 PATH 中同时存在 `svn` 与 `svnadmin`。Windows 可使用 [VisualSVN 提供的独立命令行工具](https://www.visualsvn.com/downloads/)；本次临时工具只加入测试进程的 PATH，后续运行需自行提供该依赖。

```powershell
pwsh -NoProfile -File ./ai-sop.ps1 Task -Operation Run -Feature <Feature> -TaskId <TaskId> -Agent <Agent> -Profile compile
```

模拟客户端沿用根 `run_client.ps1 -TestClass <完整类名>`。在已 Start/Resume 的任务中，PowerShell 内用参数数组记录真实执行：

```powershell
& ./ai-sop.ps1 Task -Operation Run -Feature <Feature> -TaskId <TaskId> -Agent <Agent> -Kind test -Batch simulation -Executable pwsh -Arguments @('-NoProfile','-File','./run_client.ps1','-TestClass','<实际完整类名>') -TimeoutSeconds 600
```

尖括号参数必须替换。先核对目标类、断言与环境；不默认启动完整服务。`run_server.ps1` 默认仅 Prepare 独立制品快照；Start 须确认测试数据范围，Stop 仅处理本次登记的进程。完整入口见 [runtime-verification.md](runtime-verification.md)，日常编译不需要启动服务。测试具体规则见 [client-test.md](client-test.md)。

协议生成沿用根 `protocol.bat`；运行前确认协议子仓库状态、生成器和输出范围。生成 Java 代码及生效配置属于实现，不得当成文档延期。

`export_api.bat` 调用 `tools/util-1.0.jar` 中的 `cn.game.util.ai.AiContextExporter`，扫描 game/login/util 的 `@AiExport` API，输出到 `.ai-workspace/context/api-whitelist.md`。运行前设置 `workspace` 为本宿主根，核实工具 JAR 版本；会重写 API 快照，生成后检查 diff 和保留的手工说明，不将执行成功等同于知识审核完成。

`run_client.ps1` 的 classpath 将 simulationclient、util、core、game、protocol 的 `target/classes` 放在依赖 JAR 前；仅存在目录不代表本轮编译了所有模块。当前 simulationclient 的 reactor 依赖由 POM 决定，跨模块改动须编译其实际依赖闭包。

输入指纹在引擎默认范围之上，通过 `verification-inputs.json` 显式纳入本工作区的 README、context、schemas、scripts 和 workflows，确保迁移资料与验证脚本变动能使旧证据过期。仅额外排除宿主根 `logs/`：它由 GameSSLogger、LoggerManager 和 Log4j2 写入，已被宿主 Git 忽略，包含不符合默认 `.log` 后缀规则的实时日志。日志配置和 Java 源码仍纳入检查；没有申请执行豁免，也不补造 Start 起点。共享 specs 中的其他项目历史任务不在本次重新验收；后续接管须回到原项目兼容的策略与代码副本。

## 验证效率与失败现场

本地默认仍为T2，不新增审批或完成门禁。先完成定向回归、独立审核（本任务已明确要求时）和文档同步，再冻结输入运行最终完整检查。可按需运行现有 `.ai-sop/scripts/export-review.ps1 -CheckCurrent`：其 preparation 字段只是当前摘要、最新批次和收尾提示，不授权跳过测试；命令定义、用例覆盖及清理结果仍需核对。工作树差异可能包含其他任务，不能直接整仓暂存。

在 Complete 前完成发现记录、审核说明和验收索引；完成状态以 task.json 为准，交付版本以各仓 Git 提交及远端为准，避免 Complete 后再次编辑重复状态说明导致补收尾任务。

引擎 workflow-evidence-safety 失败会保留临时夹具、各场景输出、runner-result 和 failure.json，并尝试有界清理所属进程。主故障不掩盖补救故障；预期非零业务退出不能替代输出与清理确认。成功且清理确认才删除现场。retained-fixture 回归会故意生成失败夹具，控制台给出路径；这些是本机合成数据，不连接 Apollo、业务数据库或游戏服。保留目录不代表仍有进程运行，清理未知必须读报告，不自动删除或上传整份现场。

同一PowerShell安装升级后继续自检时，已编译.NET类型仍留在进程中。清理辅助实现使用版本命名空间隔离旧六/七参类型；不要以重新加载脚本代替编译类型升级。`hidden-process-upgrade`回归先加载冻结旧脚本再加载新版，覆盖升级前后句柄及异常退出，失败时独立回收测试进程。新版句柄在清理启动前失败可重试，已记录清理超时不能重复耗时；旧句柄已有ScriptMethod及此前已误置的Disposed状态不自动重写。

Inputs 完整诊断提供文件数、读取量、路径解析和哈希耗时。2026-11-09 对同一宿主输入的对照为3188文件、89,358,100字节，文件摘要一致；本机单次完整诊断约4.28秒降至1.84秒，仅作为测量结果。默认Start仍有500ms/8MiB预算，超过8MiB仍准确记录UNAVAILABLE，不扩大预算或排除真实源码。需要完整起点时在修改前使用已有Start -CaptureBaseline，不用后续快照补造起点。

## 大型项目起点与交付材料

本项目在 context/start-inputs.json 为新 T1/T2 Start 配置 15000ms、128MiB 预算，适配约 85MiB 输入；默认档位仍为 T2。完整输入未能在预算内读完时仍记录 UNAVAILABLE，不保存部分起点、不阻断普通测试。配置不重拍已有任务起点。旧版本的 500ms/8MiB 测量记录是历史事实；新入口使用记录中的实际预算。底层单次 IO 不提供硬超时保证。

可按需调用 `.ai-sop/scripts/pack-review-evidence.ps1 -WorkspacePath . -Feature <功能> -TaskId <任务> -OutputPath <不存在的目录>`，复制已有执行记录明确引用的日志、报告、输入清单和补充证据，生成来源索引与摘要清单。输出到本任务 specs 的 evidence 目录，避免项目根下的材料进入输入扫描导致验证过期；先核对原始日志内容，再按清单显式暂存。入口不自动上传、不改变任务状态。使用已有 export-review 的 DeliveryManifest 检查实际入库字节和遗漏。通用限制见 `.ai-sop/docs/BASELINE_AND_DELIVERY.md`。

共用测试清理遇到 OUTPUT_DRAIN_TIMED_OUT 时保留未知诊断与登记；Cleanup.confirmed 仅能说明本地清理结果，不能抵消后代退出未知。再次调用清理也不会自动确认；测试以独立可信句柄回收自身探针，保留失败现场和补救错误。

## Git 归属与同步

- 宿主根：`server.git`，保存 Java 工程和 SOP 安装入口；按当前任务与用户授权提交相关改动，保留其他已有改动。历史迁移任务的“只安装本地”不限制后续已授权交付。
- `.ai-sop/`：通用引擎子模块，版本由 `tools/ai-sop/ai-sop.lock.json` 锁定；不得在投影副本里修改通用规则。
- `.ai-workspace/`：个人项目独立 `ai-workspace.git`；与 aircraft 本地工作树完全分离。该远端专供本次个人项目；其他工作区旧的同名远端由用户另行调整，禁止直接把其项目分支合并进来。
- `.ai-workspace/specs/`：按 [工作区 README](../README.md) 中登记的独立归属同步；外层忽略整个 specs，不把它当普通目录打包提交。
- `protocol/` 本机另有 `.git`，由其既有仓库管理；修改协议前检查真实归属，不能只在宿主根 add 后声称已同步。
- 每次提交前先 `git -C <仓库根> status` 和检查暂存 diff，只提交当前任务相关内容。保留 `.artifacts/` 输入证据与任务记录，本机 Session/Grant/owner、日志和 `.runtime/` 不作为可迁移权限。

工作区与 specs 各自提供 `commit.cmd` / `pull.cmd`：前者只提交已手动暂存的内容再 push，不执行 `git add .`；后者要求工作树干净并只允许 fast-forward。脚本固定在所在仓库运行，不注入本机代理，不递归同步嵌套仓库。示例：先在目标仓库 `git add -- <本任务文件>`，检查 `git diff --cached`，再 `./commit.cmd -Message "说明"`；拉取执行 `./pull.cmd`。

宿主根的 `.git/info/exclude` 已本地忽略 `.ai-workspace/`、`.claude_old/` 和运行目录；无需为了它们再改共享 `.gitignore`。`.ai-sop` 子模块、锁及生成入口是可复现安装资产，不能一律忽略。提交范围以当前任务及实际 diff 为准；历史迁移说明不代表当前工作树状态，不把其他任务的改动并入本次提交。用户已明确授权的仓库和目标分支可直接推送，无需重复确认。

共享 specs 保留其他项目历史是既定安排。开始工作优先 `pwsh -NoProfile -File ./ai-sop.ps1 Task -Operation Discover -Feature SopMigration`（实际开发替换为目标功能）；查询旧记录加 `-IncludeHistory`。`LEGACY` 表示尚无任务记录，`PAUSED` / `TASK_BASELINE_REQUIRED` 不代表本项目必须恢复它们；不得因列表出现其他项目旧任务而选择接管。

独立功能需要并行时用独立完整工作副本与运行环境；SOP 不提供跨机器实时锁。参见 [parallel-development.md](../workflows/parallel-development.md)。

## 安装诊断与能力边界

```powershell
pwsh -NoProfile -File ./ai-sop.ps1 Verify
pwsh -NoProfile -File ./ai-sop.ps1 Doctor
```

Verify 检查安装版本、manifest 和投影；Doctor 检查本机依赖与接入状态。存在 Hook 配置文件不等于客户端已加载/信任 Hook，实际启用方式遵循 `.ai-sop/docs/HARNESS_ADAPTERS.md`。缺少 Superpowers 时可执行 T1/T2；T3 按引擎能力规则处理，不宣称已经可用。

交付补充材料可给 pack-review-evidence 传 `-AttachmentsManifest`，使用工作区相对文件路径的 JSON 数组显式列出全量、干净检出等报告；清单及附件自动进入来源索引和交付摘要，不递归收集未知内容。沿用本任务 evidence 输出目录及现有 Git 字节核对。

全量并行验证可给 run-all-tests 传 `-DurationReport <已有results.json>`，在原并发上限内优先启动耗时长的套件。保留所有发现的测试、断言、默认900秒单套超时和独立进程；历史报告只影响顺序，损坏或DurationMs含布尔值时提示并回退名称顺序。查看 schedule.json、summary.json 和 native-harness-adapters 的 STAGE_MS 输出，区分排队收益与内部执行耗时；不把一次本机提速视为普遍保证。
