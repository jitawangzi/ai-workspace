# 验证入口的环境与副作用

本表帮助选择已有验证入口，不新增批准、门禁或档位要求。沿用任务已有授权；人工明确的区服、数据范围和操作权限持续有效。缺少实际运行前提时说明缺口，不把环境失败或跳过记为通过。

| 入口 | 前提与资源操作 | 隔离、清理与失败材料 | 能证明的范围 |
|---|---|---|---|
| compile / compile-tests | Java/Maven及协议模块生成输入；写各模块 target，可能下载依赖 | 当前工作树编译；Task日志保留 | 指定输入能编译，不证明测试已执行或干净检出完整 |
| java-unit-smoke / state-integrity | 指定进程内JUnit；编译依赖模块，写target和Surefire报告 | 新鲜报告及精确方法清单；失败保留Task日志 | 被执行的断言；不证明真实数据库与完整业务进程 |
| java-tests | reactor全量测试，部分用例有外部服务条件 | 执行前审查实际选择器和环境；不能假设全部无副作用 | 报告实际执行范围；零执行、缺失目标或跳过不等于验收 |
| workspace-syntax / workspace-contract | PowerShell、JSON及安装投影；主要读取脚本/文档 | Task保存结果；不启动Game/Login或连接数据库 | 语法、配置与文档契约，不证明业务行为 |
| runtime-concurrency-tests | 启动独立pwsh控制器，以持久状态夹具替代业务进程 | 随机快照；finally结束自有控制器；成功清除夹具，失败保留材料 | 登记/清理/恢复组合、归属与参数边界；不是真实JVM故障注入 |
| runtime-evidence-tests | 本机HTTP夹具、Java参数测试及停止归属替身 | 随机本机资源和临时目录，结束夹具；Task日志保留 | 身份材料与异常路径，不连接游戏服 |
| run-payment-process-tests.ps1 | Apollo读取数据库/Zookeeper配置，启动两个独立业务测试JVM；真实库写测试玩家并建专用表 | 随机玩家、claim/receipt表和ZK命名空间；结束自有进程后校验归属清理；凭据删除，私有日志/JUnit/逐场景证据保留 | 普通充值发货的重复、超时及强杀恢复；不含平台扣款、完整登录和Redis写权 |
| local-runtime / check-local-runtime | Prepare生成独立制品；Start实际启动Game/Login，可能执行现有迁移和存储初始化 | 固定快照、独立期望和持久启动意图；Stop核对实际参数与进程句柄；失败保留身份和日志供再次Stop | 明确区服/数据范围下的真实启动及选定场景；不能仅凭进程存在宣称业务验收 |
| sop-tests | Git/SVN及对应运行依赖；串行执行引擎全部套件 | 临时仓库、HTTP/子进程等各套夹具，逐套日志和结果保留；不默认连接游戏库 | 引擎回归；不替代Java或真实业务验收 |
| verify-clean-checkout.ps1 | 显式清单锁定宿主及协议等仓库提交；新目录克隆，执行声明构建，可使用本机依赖缓存 | 不复制未跟踪源码或旧target；成功/失败均保留checkout、清单快照与日志；不自动删除目录 | 这些提交在已声明生成步骤与环境下的构建完整性；不证明启动或业务语义 |

进程、事务、锁和外部资源修改按实际调用链检查补救再次失败、控制器退出、换执行者恢复。优先检查最终不变量：资源未遗漏、未误处理其他归属、未知状态可追踪、重复恢复安全；不用所有失败排列组合扩展任务。

干净构建需执行研发手册第3.9、4.3节的完整流程：协议自举、原始配置全量生成及复制，再做Maven构建。生成器静态依赖修复后，固定源码提交与258份配置/工具输入快照已通过六模块干净打包，见规格仓 `features/ServerArchitectureAndAgentReadiness/tasks/clean-build-doc-retry/acceptance.md`。原失败保留为历史证据，发现状态以 findings 为准；已有本机生成文件仍不能替代交付完整性验证。独立DataChecker旧包存在检查通过后线程池驻留问题；后续源码修复及部署验收见 `features/ServerArchitectureAndAgentReadiness/tasks/datachecker-process-exit/acceptance.md`，状态以 `CONFIG-CHECKER-EXIT-001` 为准，不沿用旧临时包装作为已修复依据。

生成器源码仓 `dic_generate/tests/process-exit.tests.ps1` 是按需退出回归入口：需 Windows、PowerShell 7、Java 11+、已构建 Gen.jar/匹配依赖及原始配置。它复制原始 Excel 到新的隔离目录，分别验证正常、规则失败、读取异常、完整 App；配置变更和生成的 Java/XML/TS 均在副本，生成器另写 `C:/java_temp/exit_<guid>` 独占缓存。启动前 cases.json 保存各用例缓存分支及路径，results.json 汇总存在状态；缓存、全部副本、日志和摘要保留以便排查。超时结束自有测试进程并判失败；不启动游戏服务或访问业务存储。自然退出及错误断言通过不等于业务配置语义完整正确；check.bat 的 pause 也不是 JVM 驻留。

## SOP 并行复跑

复跑历史并行异常使用 `pwsh -NoProfile -File ./.ai-workspace/scripts/run-sop-repeat.ps1`，默认已安装 `.ai-sop`、三套相关测试、三轮、每进程900秒。可显式传 EngineRoot、Suites、Rounds、TimeoutSeconds；不改变套件自身断言/预算。需要PowerShell 7、Git及所选套件依赖；混合VCS套件另需SVN工具在PATH。

入口产生 `.ai-workspace/.runtime/sop-repeat/runs-<guid>` 日志及results.json，持续Poll执行超时和输出收尾，全部清理后才记录最终结果。失败材料保留，不连接游戏存储。退出码0要求计划项完成、清理确认及无运行器错误；管道被已退出父进程的后代持有时报告未完成，不能宣称该后代已清理。`scripts/sop-repeat.tests.ps1` 使用隔离休眠进程及故障替身，验证正常、超时、管道、部分启动和组合清理失败；保留临时材料、仅清理持有身份的夹具进程。

历史任务中的 `evidence/repeat*.ps1` 是缺陷版本的原始归档，不作为当前执行入口。新入口通过不代表历史锁IO、deadline和提前退出根因已定位。

EngineRoot和LogRoot在入口按调用者PowerShell位置解析为绝对文件系统路径，再加载辅助脚本、创建日志及启动测试；不使用原生进程当前目录推断相对路径。双目录反例断言目标测试23不能被另一目录同名测试0替代，且相对日志留在调用目录。
# SOP 并发故障定位补充

引擎 `scripts/tests/workflow-concurrency-boundaries.tests.ps1` 仅在独立临时目录运行，启动自身 PowerShell 子进程并回收；不连接 Apollo、数据库或 Redis。覆盖锁复用与崩溃释放、冷启动操作预算、真实runner读取竞争、连续发布的完整可见性及拒绝后候选保留。成功/失败夹具均保留，空锁哨兵不作为进程存活依据，运行中不要按文件年龄删除锁。

入口通过证明上述脚本机制，不证明游戏业务或所有历史事故已经逐次还原。当前调查、受控反例与原始报告见规格仓 `features/ServerArchitectureAndAgentReadiness/tasks/parallel-runner-timeout-and-root-cause/root-cause.md`；引擎的恢复材料处置见 `.ai-sop/docs/WORKFLOW_IO_BOUNDARIES.md`。

## 支付反证与首充校准

- `payment-trial-tools`：PowerShell 7；六个独占子进程（含先写匹配报告再真实超时）、十个终态替身、六个报告反例。临时现场和 classification-results.json 保留；清理未知即失败。不访问业务服务，不运行 Maven。
- `run-payment-sensitivity.ps1`：Java 21/Maven/Git及依赖缓存或下载权限；复制六模块 pom/src 与两个 Java 运行脚本到新临时目录，变异仅作用于副本。四阶段逐一运行同一五方法清单，不减少测试或放宽原1800秒阶段超时。源码、target和本地空 Git 提交保留，材料写指定的新任务 evidence 子目录。失败保留已产生材料；恢复副本并核对源与副本摘要。不自动删除或上传现场，不连接 Apollo/业务数据库。
- `first-charge-calibration`：三个 JUnit 方法分别走替身和正式 FirstChargeActivity.buy。隔离配置、真实玩家邮箱/发货入口/保存装配、受控 writer；写 target、JUnit与本机日志，关闭邮箱并恢复配置与统计入口。只证明买入资格及共同提交契约，不证明领取发奖或数据库持久化。
