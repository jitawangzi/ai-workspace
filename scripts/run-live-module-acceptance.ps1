#requires -Version 7.0
<#
.SYNOPSIS
    在真实服务器集群环境 (GameServer + CrossServer + LoginServer) 中运行模块双轨自动化验收套件。
    支持连接已运行的本地 GameServer/CrossServer，或加 -AutoStartServers 自动按需编译并拉起所需服务节点，验收完成后仅停止本脚本新拉起的进程。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ModuleId,

    [ValidateSet('CONTRACT', 'MATRIX_SCAN', 'ALL')]
    [string]$Mode = 'ALL',

    [string]$CaseId = '',

    [int]$MaxMatrixRows = 2000,

    [uri]$GmConsoleUri = 'http://127.0.0.1:18080',

    [uri]$ApolloUri = 'http://127.0.0.1:9888',

    [string]$ApolloCluster = 'SYQ',

    [string]$GmToken = '',

    [switch]$AutoStartServers,

    [switch]$ForceRestartServers,

    [switch]$IncludeLogin,

    [string]$GameId = 'game_test',

    [string]$CrossId = 'cross_test',

    [string]$LoginId = 'login_test',

    [int]$StartupTimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$hostRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Resolve-ModuleIdInt([string]$Raw) {
    $trimmed = $Raw.Trim()
    if ($trimmed.StartsWith('0x') -or $trimmed.StartsWith('0X')) {
        return [Convert]::ToInt32($trimmed.Substring(2), 16)
    }
    return [int]$trimmed
}

$targetModuleId = Resolve-ModuleIdInt $ModuleId
$baseUri = $GmConsoleUri.AbsoluteUri.TrimEnd('/')
$suitesEndpoint = "$baseUri/gm-console/api/workbench/acceptance/suites"
$runEndpoint = "$baseUri/gm-console/api/workbench/acceptance/run"
$effectiveToken = if (-not [string]::IsNullOrWhiteSpace($GmToken)) {
    $GmToken.Trim()
} elseif (-not [string]::IsNullOrWhiteSpace($env:GM_OPS_TOKEN)) {
    $env:GM_OPS_TOKEN.Trim()
} elseif (-not [string]::IsNullOrWhiteSpace($env:GM_HTTP_OPS_TOKEN)) {
    $env:GM_HTTP_OPS_TOKEN.Trim()
} elseif (-not [string]::IsNullOrWhiteSpace($env:GM_HTTP_TOKEN)) {
    $env:GM_HTTP_TOKEN.Trim()
} else {
    ''
}
$requestHeaders = @{}
if ($effectiveToken) {
    $requestHeaders['X-GM-Token'] = $effectiveToken
}

function Get-LiveSuiteSummary([int]$ModId) {
    try {
        $resp = Invoke-RestMethod -Uri $suitesEndpoint -Method Get -Headers $requestHeaders -TimeoutSec 10
        if (-not $resp -or -not $resp.ok -or -not $resp.data -or -not $resp.data.suites) {
            return $null
        }
        foreach ($s in $resp.data.suites) {
            if ([int]$s.moduleId -eq $ModId) {
                return $s
            }
        }
        return $null
    } catch {
        return $null
    }
}

function Stop-ExistingTestNodes([string[]]$NodeIds) {
    $procs = Get-CimInstance Win32_Process -Filter "Name = 'java.exe'" -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        if (-not $p.CommandLine) { continue }
        foreach ($nid in $NodeIds) {
            if ($nid -and $p.CommandLine -match ("\b" + [regex]::Escape($nid) + "\b")) {
                Write-Host ">>> [-ForceRestartServers] 停止已有节点进程 [$nid] (PID=$($p.ProcessId))..." -ForegroundColor Yellow
                $procObj = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
                try {
                    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
                    if ($procObj) {
                        $null = $procObj.WaitForExit(15000)
                    }
                } finally {
                    if ($procObj) { $procObj.Dispose() }
                }
                break
            }
        }
    }
}

function Start-ClusterProcess([string]$App, [string]$NodeId, [string]$LogDir) {
    $classpath = if ($App -in @('game', 'cross')) {
        "$hostRoot\game\target\classes;$hostRoot\util\target\classes;$hostRoot\core\target\classes;$hostRoot\protocol\target\classes;$hostRoot\game\target\lib\*"
    } else {
        "$hostRoot\login\target\classes;$hostRoot\util\target\classes;$hostRoot\core\target\classes;$hostRoot\protocol\target\classes;$hostRoot\game\target\classes;$hostRoot\login\target\lib\*"
    }
    $appId = $App
    $mainClass = switch ($App) {
        'game'  { 'cn.game.games.net.game.GameServer' }
        'cross' { 'cn.game.games.net.cross.CrossServer' }
        'login' { 'cn.game.login.LoginServer' }
    }
    $workDir = Join-Path $LogDir "work-$App"
    [IO.Directory]::CreateDirectory($workDir) | Out-Null
    $outLog = Join-Path $LogDir "$App.stdout.log"
    $errLog = Join-Path $LogDir "$App.stderr.log"
    $metaFolder = Join-Path (Split-Path -Parent $hostRoot) 'configs\Server'
    $apolloMeta = $ApolloUri.AbsoluteUri.TrimEnd('/')
    $javaArgs = @(
        "-Dapp.id=$appId",
        '-Denv=dev',
        "-Dapollo.cluster=$ApolloCluster",
        "-Dapollo.configService=$apolloMeta",
        "-Ddev_meta=$apolloMeta",
        "-DSEVER_PATH=$workDir",
        '-DdefaultNetworkIp=127.0.0.1',
        '-Dserver.run.mode=test',
        "-Dworkspace=$hostRoot",
        "-Dmetafolder=$metaFolder",
        '-Dfile.encoding=UTF-8',
        '--add-opens=java.base/java.lang=ALL-UNNAMED',
        '--add-opens=java.base/java.util=ALL-UNNAMED',
        '-Dio.netty.tryReflectionSetAccessible=true',
        '-Dzookeeper.clientCnxnSocket=org.apache.zookeeper.ClientCnxnSocketNetty',
        '-cp', $classpath,
        $mainClass,
        $NodeId
    )
    Write-Host ">>> 启动真实服务节点 [$App : $NodeId] (日志: $outLog)..." -ForegroundColor Cyan
    return Start-Process -FilePath 'java' -ArgumentList $javaArgs -WorkingDirectory $workDir -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru
}

$spawnedProcesses = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
$runtimeLogDir = Join-Path $hostRoot (".ai-workspace\.runtime\live-acceptance\run-" + [guid]::NewGuid().ToString('N').Substring(0, 8))

try {
    if ($AutoStartServers -and $ForceRestartServers) {
        Stop-ExistingTestNodes @($GameId, $CrossId, $LoginId)
        Start-Sleep -Seconds 2
    }
    $suiteSummary = Get-LiveSuiteSummary $targetModuleId
    if (-not $suiteSummary -and $AutoStartServers) {
        [IO.Directory]::CreateDirectory($runtimeLogDir) | Out-Null
        $pGame = Start-ClusterProcess -App 'game' -NodeId $GameId -LogDir $runtimeLogDir
        $spawnedProcesses.Add($pGame)
        if ($IncludeLogin) {
            $pLogin = Start-ClusterProcess -App 'login' -NodeId $LoginId -LogDir $runtimeLogDir
            $spawnedProcesses.Add($pLogin)
        }

        $deadline = [DateTimeOffset]::UtcNow.AddSeconds($StartupTimeoutSeconds)
        while ([DateTimeOffset]::UtcNow -lt $deadline) {
            if ($pGame.HasExited) {
                throw "LIVE_ACCEPTANCE_GAME_EARLY_EXIT: GameServer 进程异常退出 (exitCode=$($pGame.ExitCode))，请检查 $runtimeLogDir\game.stderr.log"
            }
            $suiteSummary = Get-LiveSuiteSummary $targetModuleId
            if ($suiteSummary) {
                break
            }
            Start-Sleep -Seconds 1
        }
    }

    if (-not $suiteSummary) {
        throw "LIVE_ACCEPTANCE_SERVER_UNREACHABLE: 无法从 $suitesEndpoint 获取模块 $ModuleId 的验收套件摘要。请确认 GameServer 已启动且包含最新编译的套件代码（或传入 -AutoStartServers）。"
    }

    $missingTypes = @($suiteSummary.clusterTopology.missingServerTypes | Where-Object { $_ })
    if (($missingTypes -contains 'Cross') -and $AutoStartServers) {
        [IO.Directory]::CreateDirectory($runtimeLogDir) | Out-Null
        $pCross = Start-ClusterProcess -App 'cross' -NodeId $CrossId -LogDir $runtimeLogDir
        $spawnedProcesses.Add($pCross)

        $crossOutLog = Join-Path $runtimeLogDir 'cross.stdout.log'
        $crossErrLog = Join-Path $runtimeLogDir 'cross.stderr.log'
        $crossDeadline = [DateTimeOffset]::UtcNow.AddSeconds($StartupTimeoutSeconds)
        while ([DateTimeOffset]::UtcNow -lt $crossDeadline) {
            if ($pCross.HasExited) {
                throw "LIVE_ACCEPTANCE_CROSS_EARLY_EXIT: CrossServer 进程异常退出 (exitCode=$($pCross.ExitCode))，请检查 $crossErrLog"
            }
            $crossBootDone = ((Test-Path -LiteralPath $crossErrLog) -and ((Get-Content -LiteralPath $crossErrLog -Raw -ErrorAction SilentlyContinue) -match 'Cross Server startup complete')) -or
                             ((Test-Path -LiteralPath $crossOutLog) -and ((Get-Content -LiteralPath $crossOutLog -Raw -ErrorAction SilentlyContinue) -match '跨服\[.+\]启动成功'))
            if ($crossBootDone) {
                $suiteSummary = Get-LiveSuiteSummary $targetModuleId
                $missingTypes = @($suiteSummary.clusterTopology.missingServerTypes | Where-Object { $_ })
                if ($missingTypes -notcontains 'Cross') {
                    break
                }
            }
            Start-Sleep -Seconds 1
        }
    }

    if (($missingTypes -contains 'Login') -and $AutoStartServers) {
        [IO.Directory]::CreateDirectory($runtimeLogDir) | Out-Null
        $pLoginAuto = Start-ClusterProcess -App 'login' -NodeId $LoginId -LogDir $runtimeLogDir
        $spawnedProcesses.Add($pLoginAuto)

        $loginDeadline = [DateTimeOffset]::UtcNow.AddSeconds($StartupTimeoutSeconds)
        while ([DateTimeOffset]::UtcNow -lt $loginDeadline) {
            if ($pLoginAuto.HasExited) {
                throw "LIVE_ACCEPTANCE_LOGIN_EARLY_EXIT: LoginServer 进程异常退出 (exitCode=$($pLoginAuto.ExitCode))，请检查 $runtimeLogDir\login.stderr.log"
            }
            $suiteSummary = Get-LiveSuiteSummary $targetModuleId
            $missingTypes = @($suiteSummary.clusterTopology.missingServerTypes | Where-Object { $_ })
            if ($missingTypes -notcontains 'Login') {
                break
            }
            Start-Sleep -Seconds 1
        }
    }

    if ($missingTypes.Count -gt 0) {
        throw "LIVE_ACCEPTANCE_CLUSTER_NOT_READY: 模块 [$($suiteSummary.title)] 要求真实集群节点 [$($suiteSummary.requiredServerTypes -join ', ')]，但当前缺少活跃节点: [$($missingTypes -join ', ')]。请先启动对应服务（如 CrossServer）或传入 -AutoStartServers。"
    }

    Write-Host ">>> 集群拓扑核验通过: $($suiteSummary.clusterTopology | ConvertTo-Json -Compress)" -ForegroundColor Green

    $reqBody = @{
        moduleId          = $targetModuleId
        mode              = $Mode
        caseId            = $CaseId
        maxMatrixRows     = $MaxMatrixRows
        requireLiveCluster = $true
    } | ConvertTo-Json -Compress

    Write-Host ">>> 触发真实服务器进程内双轨验收: moduleId=$ModuleId ($($suiteSummary.title)), mode=$Mode ..." -ForegroundColor Cyan
    $runResp = Invoke-RestMethod -Uri $runEndpoint -Method Post -Headers $requestHeaders -ContentType 'application/json; charset=utf-8' -Body $reqBody -TimeoutSec 300

    if (-not $runResp -or -not $runResp.ok -or -not $runResp.data) {
        $errMsg = if ($runResp) { ($runResp | ConvertTo-Json -Compress) } else { 'EMPTY_RESPONSE' }
        throw "LIVE_ACCEPTANCE_RUN_FAILED: $errMsg"
    }

    $report = if ($runResp.data.report) { $runResp.data.report } else { $runResp.data }
    Write-Output ("LIVE_ACCEPTANCE_REPORT: " + ($report | ConvertTo-Json -Depth 10 -Compress))

    if (-not $report.success -or [int]$report.failedCases -gt 0) {
        Write-Host ">>> [FAILED] 模块 [$($report.title)] 真实服验收存在失败项: total=$($report.totalCases), passed=$($report.passedCases), failed=$($report.failedCases)" -ForegroundColor Red
        exit 1
    }

    Write-Host ">>> [PASSED] 模块 [$($report.title)] 真实服双轨验收全部通过: total=$($report.totalCases), passed=$($report.passedCases), elapsed=$($report.elapsedMs)ms" -ForegroundColor Green
    exit 0
} finally {
    foreach ($proc in $spawnedProcesses) {
        if ($proc -and -not $proc.HasExited) {
            try {
                Write-Host ">>> 停止本轮自动拉起的服务进程 PID=$($proc.Id)..." -ForegroundColor DarkGray
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                $proc.WaitForExit(10000) | Out-Null
            } catch {}
        }
    }
}
