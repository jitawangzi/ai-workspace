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

[verification-commands.json](verification-commands.json) 提供以下 Profile，均从项目根执行。

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

Java Profile 通过 `scripts/run-java-tests.ps1` 运行 `test-compile` 和明确版本的 Surefire 3.5.2，避免本机 Maven 默认 Surefire 2.12.4 不执行 JUnit 5；检查本轮新生成的 XML，零执行、全跳过或失败都不能通过。定向测试可使用同一脚本的 `-Project` / `-Test`，按 Task Run 记录。JUnit 5 提供器依据见 [Surefire 官方说明](https://maven.apache.org/surefire-archives/surefire-3.5.5/maven-surefire-plugin/examples/junit-platform.html)。

`workspace-*` 适用于只改工作流资料/脚本的任务，不能作为 Java 改动的编译或行为测试证据。业务变更选择 `compile` 或 `compile-tests`，并运行与功能相关的实际测试。

`sop-tests` 的混合 VCS 回归需要 PATH 中同时存在 `svn` 与 `svnadmin`。Windows 可使用 [VisualSVN 提供的独立命令行工具](https://www.visualsvn.com/downloads/)；本次临时工具只加入测试进程的 PATH，后续运行需自行提供该依赖。

```powershell
pwsh -NoProfile -File ./ai-sop.ps1 Task -Operation Run -Feature <Feature> -TaskId <TaskId> -Agent <Agent> -Profile compile
```

模拟客户端沿用根 `run_client.ps1 -TestClass <完整类名>`。在已 Start/Resume 的任务中，PowerShell 内用参数数组记录真实执行：

```powershell
& ./ai-sop.ps1 Task -Operation Run -Feature <Feature> -TaskId <TaskId> -Agent <Agent> -Kind test -Batch simulation -Executable pwsh -Arguments @('-NoProfile','-File','./run_client.ps1','-TestClass','<实际完整类名>') -TimeoutSeconds 600
```

尖括号参数必须替换。先核对目标类、断言与环境；不默认启动完整服务。`run_server.ps1` 会清理/启动进程，应先核实目标实例归属；日常编译不需要运行它。测试具体规则见 [client-test.md](client-test.md)。

协议生成沿用根 `protocol.bat`；运行前确认协议子仓库状态、生成器和输出范围。生成 Java 代码及生效配置属于实现，不得当成文档延期。

`export_api.bat` 调用 `tools/util-1.0.jar` 中的 `cn.game.util.ai.AiContextExporter`，扫描 game/login/util 的 `@AiExport` API，输出到 `.ai-workspace/context/api-whitelist.md`。运行前设置 `workspace` 为本宿主根，核实工具 JAR 版本；会重写 API 快照，生成后检查 diff 和保留的手工说明，不将执行成功等同于知识审核完成。

`run_client.ps1` 的 classpath 将 simulationclient、util、core、game、protocol 的 `target/classes` 放在依赖 JAR 前；仅存在目录不代表本轮编译了所有模块。当前 simulationclient 的 reactor 依赖由 POM 决定，跨模块改动须编译其实际依赖闭包。

输入指纹在引擎默认范围之上，通过 `verification-inputs.json` 显式纳入本工作区的 README、context、schemas、scripts 和 workflows，确保迁移资料与验证脚本变动能使旧证据过期。仅额外排除宿主根 `logs/`：它由 GameSSLogger、LoggerManager 和 Log4j2 写入，已被宿主 Git 忽略，包含不符合默认 `.log` 后缀规则的实时日志。日志配置和 Java 源码仍纳入检查；没有申请执行豁免，也不补造 Start 起点。共享 specs 中的其他项目历史任务不在本次重新验收；后续接管须回到原项目兼容的策略与代码副本。

## Git 归属与同步

- 宿主根：`server.git`，保存 Java 工程和 SOP 安装入口；本次只安装本地，不提交或推送宿主源码及其已有改动。
- `.ai-sop/`：通用引擎子模块，版本由 `tools/ai-sop/ai-sop.lock.json` 锁定；不得在投影副本里修改通用规则。
- `.ai-workspace/`：个人项目独立 `ai-workspace.git`；与 aircraft 本地工作树完全分离。该远端专供本次个人项目；其他工作区旧的同名远端由用户另行调整，禁止直接把其项目分支合并进来。
- `.ai-workspace/specs/`：按 [工作区 README](../README.md) 中登记的独立归属同步；外层忽略整个 specs，不把它当普通目录打包提交。
- `protocol/` 本机另有 `.git`，由其既有仓库管理；修改协议前检查真实归属，不能只在宿主根 add 后声称已同步。
- 每次提交前先 `git -C <仓库根> status` 和检查暂存 diff，只提交当前任务相关内容。保留 `.artifacts/` 输入证据与任务记录，本机 Session/Grant/owner、日志和 `.runtime/` 不作为可迁移权限。

工作区与 specs 各自提供 `commit.cmd` / `pull.cmd`：前者只提交已手动暂存的内容再 push，不执行 `git add .`；后者要求工作树干净并只允许 fast-forward。脚本固定在所在仓库运行，不注入本机代理，不递归同步嵌套仓库。示例：先在目标仓库 `git add -- <本任务文件>`，检查 `git diff --cached`，再 `./commit.cmd -Message "说明"`；拉取执行 `./pull.cmd`。

宿主根的 `.git/info/exclude` 已本地忽略 `.ai-workspace/`、`.claude_old/` 和运行目录；无需为了它们再改共享 `.gitignore`。`.ai-sop` 子模块、锁及生成入口是可复现安装资产，不能一律忽略。旧 `.claude` 删除/替换和已有业务改动继续保留在宿主工作树，待用户整理提交；本轮仅提交两个嵌套知识仓库及引擎真源，不替用户提交宿主根。

共享 specs 保留其他项目历史是既定安排。开始工作优先 `pwsh -NoProfile -File ./ai-sop.ps1 Task -Operation Discover -Feature SopMigration`（实际开发替换为目标功能）；查询旧记录加 `-IncludeHistory`。`LEGACY` 表示尚无任务记录，`PAUSED` / `TASK_BASELINE_REQUIRED` 不代表本项目必须恢复它们；不得因列表出现其他项目旧任务而选择接管。

独立功能需要并行时用独立完整工作副本与运行环境；SOP 不提供跨机器实时锁。参见 [parallel-development.md](../workflows/parallel-development.md)。

## 安装诊断与能力边界

```powershell
pwsh -NoProfile -File ./ai-sop.ps1 Verify
pwsh -NoProfile -File ./ai-sop.ps1 Doctor
```

Verify 检查安装版本、manifest 和投影；Doctor 检查本机依赖与接入状态。存在 Hook 配置文件不等于客户端已加载/信任 Hook，实际启用方式遵循 `.ai-sop/docs/HARNESS_ADAPTERS.md`。缺少 Superpowers 时可执行 T1/T2；T3 按引擎能力规则处理，不宣称已经可用。
