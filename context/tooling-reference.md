<!-- context-meta owner:jitawangzi reviewedAt:2026-11-21 expiresAt:2027-04 -->
# 工具链高级参考：失败现场、大型基线与交付导出

> 本文件承接自 [project-tooling.md](project-tooling.md)，仅在排查引擎回归、执行审查导出/证据打包、调整大型输入预算或定位测试清理故障时按需加载。

## 1. 输入指纹范围与大型项目起点预算

- 输入指纹在引擎默认范围之上，通过 [verification-inputs.json](verification-inputs.json) 显式纳入本工作区的 `README.md`、`context`、`skills`、`scripts` 和 `workflows`，确保知识、自建 Skill 与脚本变动能使旧证据过期。
- 仅额外排除宿主根 `logs/`（由 `GameSSLogger`、`LoggerManager` 和 Log4j2 写入，已被宿主 Git 忽略，包含不符合默认 `.log` 后缀的实时日志）。日志配置和 Java 源码仍纳入检查。
- 本项目在 [start-inputs.json](start-inputs.json) 为新 T1/T2 Start 配置 `15000ms`、`128MiB` 预算，适配约 85MiB 输入（默认档位仍为 T2）。完整输入未能在预算内读完时仍记录 `UNAVAILABLE`，不保存部分起点、不阻断普通测试；底层单次 IO 不提供硬超时保证。
- `Inputs` 完整诊断提供文件数、读取量、路径解析和哈希耗时（历史测量参考：3188 文件、89,358,100 字节，单次诊断约 1.84 秒，仅作观测不作承诺）。需要完整起点时在修改前使用 `Start -CaptureBaseline`，不用后续快照补造起点。

## 2. 审查导出与证据打包（`export-review` / `pack-review-evidence`）

- **审查导出**：从宿主根执行：
  ```powershell
  .ai-sop/scripts/export-review.ps1 -WorkspacePath . -Feature <实际功能> -TaskId <实际任务> -CheckCurrent -Scope <受影响路径>
  ```
  多仓增加 `-RepositoryPaths`（本项目还包括 `protocol`）。输出是派生导航，不是第二份权威状态；`preparation` 字段不授权跳过测试；只读入口不隐式运行构建或测试。
- **增量复审**：可传 `-PreviousReview <工作区相对旧导出路径>`，在完整报告中附逐仓提交差异、两次工作树变化及当前 `runId`；漏选旧仓标 `NOT_SELECTED/PARTIAL`。
- **证据打包**：可按需调用：
  ```powershell
  .ai-sop/scripts/pack-review-evidence.ps1 -WorkspacePath . -Feature <功能> -TaskId <任务> -OutputPath <不存在的目录>
  ```
  建议输出到本任务 `specs` 的 `evidence` 目录，避免项目根材料进入输入扫描导致验证过期。可传 `-AttachmentsManifest`（工作区相对路径 JSON 数组）显式收集补充报告；同一个清单也可传给 `export-review` 核对本地链接引用和已提交字节（`DeliveryManifest` / `deliveryCheck.arguments`）。通用限制见 `.ai-sop/docs/BASELINE_AND_DELIVERY.md`。
- **本地引用核对语义**：支持文档相对路径、本机绝对路径与无主机名 `file:///` URI；缺失标 `MISSING`，越界/网络共享/带主机名 URI 标 `UNAVAILABLE`；零可检查本地链接标 `NO_SUPPORTED_LOCAL_LINKS`。
- **收尾顺序**：在 `Complete` 前完成发现记录、审核说明和验收索引；完成状态以 `task.json` 为准，交付版本以各仓 Git 提交为准，避免 `Complete` 后再编辑文档触发补收尾。

## 3. 全量并行测试、失败现场与清理诊断

- **定向测试与门禁自检**：`java-unit-smoke` 使用 [目标清单](test-suites/java-unit-smoke.json)；报告门禁自身回归入口为 `scripts/java-test-evidence.tests.ps1`（仅验证报告判定，不冒充 Java 行为测试）。
- **混合 VCS 依赖**：`sop-tests` 的混合 VCS 回归需要 `svn` 与 `svnadmin`（Windows 可用 VisualSVN 独立命令行工具，或通过 `-ToolDirectory D:/work-all/.tmp/sop-svn-1.15.0/tools/bin` 传入，避免改全局 PATH；缺依赖用例直接失败，不静默跳过）。
- **并行调度优化**：`run-all-tests` 可传 `-DurationReport <已有results.json>` 在原并发上限内优先启动长耗时套件；异常报告自动提示并回退名称顺序。
- **失败现场与清理边界**：
  - 引擎 `workflow-evidence-safety` 失败会保留临时夹具、场景输出、`runner-result` 和 `failure.json`，并尝试有界清理所属进程；成功且清理确认才删除现场。`retained-fixture` 回归产生的合成夹具不连 Apollo/数据库/游戏服。
  - 共用测试清理遇到 `OUTPUT_DRAIN_TIMED_OUT` 时保留未知诊断；`Cleanup.confirmed` 不能抵消后代退出未知。清理未知时即使套件全过，`summary.outcome` 仍为 `FAILED`、退出码 1。遗留回收按 PID + 启动时间确认归属，不按进程名或裸 PID 误杀。
  - 同一 PowerShell 进程升级脚本后，已编译 `.NET` 类型驻留进程中，清理辅助使用版本命名空间隔离旧类型（`hidden-process-upgrade` 回归覆盖此边界）。
  - `native-harness-adapters` 保留原全部客户端探针与 Hook 链（外层 900s、单次 25s）；Windows 原生辅助代码冷进程合并编译，Unix 不加载 Win32 代码；`HOOK_PROCESS_METRICS` 用于定位准备与调用开销。
  - 审查准备提示、测试摘要（仅看 `test`）和关注项（含 `compile`）共享记录字段解释，但不合成整体 `PASS`；版本探测 `UNAVAILABLE` 与清理未知分开记录。
