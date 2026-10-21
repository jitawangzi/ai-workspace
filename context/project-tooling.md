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
| `workspace-syntax` | compile | 本次治理脚本 PowerShell 解析、JSON 与 Profile Schema 校验，5 分钟 |
| `workspace-contract` | test | 目录、文档链接、旧知识覆盖、项目适配和安装投影一致性，5 分钟 |
| `sop-tests` | test | 自动发现引擎全部测试套件，60 分钟 |

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

输入指纹在引擎默认范围之上，通过 `verification-inputs.json` 显式纳入本工作区的 README、context、schemas、scripts 和 workflows，确保迁移资料与验证脚本变动能使旧证据过期。仅额外排除宿主根 `logs/`：它由 GameSSLogger、LoggerManager 和 Log4j2 写入，已被宿主 Git 忽略，包含不符合默认 `.log` 后缀规则的实时日志。日志配置和 Java 源码仍纳入检查；没有申请执行豁免，也不补造 Start 起点。共享 specs 中的其他项目历史任务不在本次重新验收；后续接管须回到原项目兼容的策略与代码副本。

## Git 归属与同步

- 宿主根：`server.git`，保存 Java 工程和 SOP 安装入口；本次只安装本地，不提交或推送宿主源码及其已有改动。
- `.ai-sop/`：通用引擎子模块，版本由 `tools/ai-sop/ai-sop.lock.json` 锁定；不得在投影副本里修改通用规则。
- `.ai-workspace/`：个人项目独立 `ai-workspace.git`；与 aircraft 本地工作树完全分离。该远端专供本次个人项目；其他工作区旧的同名远端由用户另行调整，禁止直接把其项目分支合并进来。
- `.ai-workspace/specs/`：按 [工作区 README](../README.md) 中登记的独立归属同步；外层忽略整个 specs，不把它当普通目录打包提交。
- `protocol/` 本机另有 `.git`，由其既有仓库管理；修改协议前检查真实归属，不能只在宿主根 add 后声称已同步。
- 每次提交前先 `git -C <仓库根> status` 和检查暂存 diff，只提交当前任务相关内容。保留 `.artifacts/` 输入证据与任务记录，本机 Session/Grant/owner、日志和 `.runtime/` 不作为可迁移权限。

独立功能需要并行时用独立完整工作副本与运行环境；SOP 不提供跨机器实时锁。参见 [parallel-development.md](../workflows/parallel-development.md)。

## 安装诊断与能力边界

```powershell
pwsh -NoProfile -File ./ai-sop.ps1 Verify
pwsh -NoProfile -File ./ai-sop.ps1 Doctor
```

Verify 检查安装版本、manifest 和投影；Doctor 检查本机依赖与接入状态。存在 Hook 配置文件不等于客户端已加载/信任 Hook，实际启用方式遵循 `.ai-sop/docs/HARNESS_ADAPTERS.md`。缺少 Superpowers 时可执行 T1/T2；T3 按引擎能力规则处理，不宣称已经可用。
