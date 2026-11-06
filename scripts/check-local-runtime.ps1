#requires -Version 7.0
<# 本机快照完整验收：启动、真实登录/心跳、可选撤销检查，最后精确停止本次进程。 #>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Snapshot,
      [Parameter(Mandatory)][uri]$LoginUrl,
      [string]$LogicServerId='server1',
      [string]$TestAccount=('sop_'+[guid]::NewGuid().ToString('N').Substring(0,12)),
      [switch]$ConfirmDataScope,
      [switch]$VerifyArtifactRevocation)
$ErrorActionPreference='Stop'
if (-not $ConfirmDataScope) { throw 'LOCAL_RUNTIME_DATA_SCOPE_REQUIRED' }
$hostRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'runtime-evidence.ps1')
$Snapshot=(Resolve-Path -LiteralPath $Snapshot).Path
$allowed=Join-Path $hostRoot '.ai-workspace/.runtime/local-runtime'
if (-not $Snapshot.StartsWith($allowed+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'LOCAL_RUNTIME_SNAPSHOT_OUTSIDE_WORKSPACE' }
if (-not $LoginUrl.IsLoopback -or $LoginUrl.Scheme -ne 'http' -or $LoginUrl.UserInfo) { throw 'LOCAL_LOGIN_URI_REQUIRED' }
if (Test-Path -LiteralPath (Join-Path $Snapshot processes.json)) { throw 'LOCAL_RUNTIME_ALREADY_STARTED: prepare a new snapshot for each lifecycle' }
$settings=Get-Content -LiteralPath (Join-Path $Snapshot settings.json) -Raw|ConvertFrom-Json
$identity=[uri]("http://127.0.0.1:$($settings.identityPort)/runtime-identity")
$failure=$null
try {
    & (Join-Path $hostRoot 'run_server.ps1') -Action Start -Snapshot $Snapshot -ConfirmDataScope:$ConfirmDataScope
    if ($LASTEXITCODE -ne 0) { throw 'LOCAL_RUNTIME_START_FAILED' }
    & (Join-Path $hostRoot 'run_client.ps1') -TestClass cn.game.simulation.test.ai.ClientRuntimeIdentityTest -RuntimeSnapshot $Snapshot `
        -ExpectedRuntime (Join-Path $Snapshot expected-runtime.json) -RuntimeIdentityUri $identity -RequireRuntimeIdentity `
        -GameId $settings.gameId -LogicServerId $LogicServerId -LoginUrl $LoginUrl -TestAccount $TestAccount
    if ($LASTEXITCODE -ne 0) { throw 'LOCAL_RUNTIME_SCENARIO_FAILED' }
    if ($VerifyArtifactRevocation) {
        # 仅触碰本次已完成场景的快照；恢复字节后仍须保持身份撤销。
        $metadata=Join-Path $Snapshot 'artifacts/game/classes/runtime-build.properties'
        $bytes=[IO.File]::ReadAllBytes($metadata)
        try {
            [IO.File]::AppendAllText($metadata,"`nbuildId=local-revocation-probe`n")
            foreach ($phase in @('changed','restored')) {
                if ($phase -eq 'restored') { [IO.File]::WriteAllBytes($metadata,$bytes) }
                $response=Invoke-WebRequest -Uri ($identity.AbsoluteUri+'?challenge='+[guid]::NewGuid().ToString('N')) -SkipHttpErrorCheck -TimeoutSec 30
                Assert-RuntimeIdentityRevoked $response
                Write-Output "LIVE_REVOCATION_PASS:$phase"
            }
        } finally { [IO.File]::WriteAllBytes($metadata,$bytes) }
    }
} catch { $failure=$_ }
finally {
    try {
        & (Join-Path $hostRoot 'run_server.ps1') -Action Stop -Snapshot $Snapshot
        if ($LASTEXITCODE -ne 0) { throw 'LOCAL_RUNTIME_STOP_FAILED' }
        $state=Join-Path $Snapshot processes.json
        if (Test-Path -LiteralPath $state) {
            $records=ConvertFrom-RuntimeJson (Get-Content -LiteralPath $state -Raw)
            foreach ($record in $records) {
                $p=Get-Process -Id $record.pid -ErrorAction SilentlyContinue
                if ($p -and $p.StartTime.ToUniversalTime().ToString('o') -ceq $record.startedAt) {
                    Wait-Process -Id $p.Id -Timeout 10 -ErrorAction Stop
                }
            }
        }
        Write-Output 'LOCAL_RUNTIME_OWNED_PROCESSES_STOPPED'
    } catch {
        if ($failure) { Write-Warning ('LOCAL_RUNTIME_CLEANUP_FAILED: '+$_.Exception.Message) } else { $failure=$_ }
    }
}
if ($failure) { throw $failure }
Write-Output 'LOCAL_RUNTIME_LIFECYCLE_PASS'
