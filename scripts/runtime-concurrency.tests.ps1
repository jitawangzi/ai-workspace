#requires -Version 7.0
# 真实独立 pwsh 竞争同一快照；业务 JVM 替换为受控进程夹具，绝不连接存储。
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'runtime-state.ps1')
. (Join-Path $PSScriptRoot 'native-arguments.ps1')
$hostRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtimeRoot=Join-Path $hostRoot '.ai-workspace/.runtime/local-runtime'
$fixture=Join-Path $runtimeRoot ('concurrency-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture)|Out-Null
$children=@()
function Wait-File([string]$Path) {
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds(20)
    while (-not (Test-Path -LiteralPath $Path)) {
        if ([DateTimeOffset]::UtcNow -gt $deadline) { throw "FIXTURE_TIMEOUT:$Path" }
        Start-Sleep -Milliseconds 50
    }
}
function Launch([string]$Mode,[string]$Target) {
    $out=Join-Path $fixture ($Mode+'.out');$err=Join-Path $fixture ($Mode+'.err')
    $arguments=@('-NoProfile','-File',(Join-Path $fixture driver.ps1),'-Mode',$Mode,'-Snapshot',$Target,'-ScriptRoot',$PSScriptRoot)
    $p=Start-Process pwsh -ArgumentList ($arguments|ForEach-Object { ConvertTo-NativeArgument $_ }) -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    $script:children+=,$p
    return $p
}
function Finish($Process,[bool]$Success) {
    if (-not $Process.WaitForExit(20000)) { throw 'FIXTURE_CHILD_TIMEOUT' }
    if (($Process.ExitCode -eq 0) -ne $Success) { throw "FIXTURE_EXIT_UNEXPECTED:$($Process.ExitCode) logs=$fixture" }
}
try {
    @'
param($Mode,$Snapshot,$ScriptRoot)
$ErrorActionPreference='Stop';$global:starts=0;$global:held=$null
function global:java {
    $output=$args[-1]
    '{"schemaVersion":"fixture"}'|Set-Content -LiteralPath $output
    if ($Mode -eq 'winner' -and -not (Test-Path -LiteralPath (Join-Path $Snapshot entered))) {
        ''|Set-Content -LiteralPath (Join-Path $Snapshot entered)
        $deadline=[DateTimeOffset]::UtcNow.AddSeconds(20)
        while (-not (Test-Path -LiteralPath (Join-Path $Snapshot release))) {
            if([DateTimeOffset]::UtcNow -gt $deadline){throw 'FIXTURE_BARRIER_TIMEOUT'}
            Start-Sleep -Milliseconds 30
        }
    }
    $global:LASTEXITCODE=0
}
function global:Start-Process {
    param($FilePath,$ArgumentList)
    if (($ArgumentList -join ' ') -notmatch '-Druntime.config.freeze=true' -or ($ArgumentList -join ' ') -notmatch '-Druntime.expected=') { throw 'IN_PROCESS_GATE_MISSING' }
    $global:starts++
    if ($Mode -in @('writefail','cleanupfail') -and $global:starts -eq 2) {
        $global:held=[IO.File]::Open((Join-Path $Snapshot processes.json),'Open','Read','None')
    }
    [pscustomobject]@{Id=(400000+$global:starts);StartTime=[DateTime]::Parse('2026-01-01T00:00:00Z',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)}
}
function global:Get-Process { param([int]$Id) [pscustomobject]@{Id=$Id;StartTime=[DateTime]::Parse('2026-01-01T00:00:00Z',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)} }
function global:Get-CimInstance { param($ClassName,$Filter) [pscustomobject]@{CommandLine='-Druntime.launchId=fixture cn.game.login.LoginServer cn.game.games.net.game.GameServer'} }
function global:Stop-Process { param([int]$Id) Add-Content -LiteralPath (Join-Path $Snapshot stopped) -Value $Id; if($Mode -eq 'cleanupfail' -and $Id -eq 400001){throw 'fixture first cleanup failed'} }
function global:Wait-Process { param([int]$Id) }
function global:Get-NetTCPConnection { [pscustomobject]@{OwningProcess=400002} }
# 实际身份函数是 dot-source 的局部函数；拦截其 HTTP 调用，提供完整夹具观察。
function global:Invoke-WebRequest {
    param($Uri)
    $expected=Get-Content -LiteralPath (Join-Path $Snapshot expected-runtime.json) -Raw|ConvertFrom-Json -AsHashtable
    $expected.instanceId='fixture';$expected.startedAt='2026-01-01T00:00:00Z'
    $expected.challenge=[regex]::Match($Uri.Query,'challenge=([a-f0-9]+)').Groups[1].Value
    [pscustomobject]@{Content=($expected|ConvertTo-Json)}
}
try {
    if($Mode -eq 'loser') {
        & (Join-Path $ScriptRoot check-local-runtime.ps1) -Snapshot $Snapshot -LoginUrl http://127.0.0.1:9390 -ConfirmDataScope
    } elseif($Mode -eq 'status') {
        & (Join-Path $ScriptRoot local-runtime.ps1) -Action Status -Snapshot $Snapshot
    } elseif($Mode -eq 'lockowner') {
        . (Join-Path $ScriptRoot runtime-state.ps1)
        $global:held=Enter-RuntimeSnapshotLock $Snapshot
        ''|Set-Content -LiteralPath (Join-Path $Snapshot lockentered)
        Start-Sleep -Seconds 40
    } else {
        & (Join-Path $ScriptRoot local-runtime.ps1) -Action Start -Snapshot $Snapshot -ConfirmDataScope
    }
} finally { if($global:held){$global:held.Dispose()} }
'@|Set-Content -LiteralPath (Join-Path $fixture driver.ps1)
    foreach($name in @('race','writefail','cleanupfail','lockexit')) {
        $target=Join-Path $fixture $name;[IO.Directory]::CreateDirectory($target)|Out-Null
        @{runId='fixture';gameId='game_test';loginId='login_test';identityPort=17011;apolloCluster='fixture';apolloUri='http://127.0.0.1:1'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $target settings.json)
        # 预检夹具不参与业务身份；用完整期望验证脚本真实的就绪观察路径。
        $expected=@{schemaVersion='1.0';targetId='game_test';buildId='fixture';sourceDigest=('a'*64);artifactSha256=('b'*64);protocolSha256=('c'*64);configSha256=('d'*64);dataNamespace='fixture'}
        $expected|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $target expected-runtime.json)
        $expected|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $target expected-login.json)
    }
    # 预检夹具复制期望，而不自行制造与门禁不一致的字段。
    $driver=Join-Path $fixture driver.ps1
    $body=[IO.File]::ReadAllText($driver).Replace("'{`"schemaVersion`":`"fixture`"}'|Set-Content -LiteralPath `$output", "Get-Content -LiteralPath (Join-Path `$Snapshot expected-runtime.json) -Raw|Set-Content -LiteralPath `$output")
    [IO.File]::WriteAllText($driver,$body)
    $race=Join-Path $fixture race
    $winner=Launch winner $race
    Wait-File (Join-Path $race entered)
    Finish (Launch loser $race) $false
    Finish (Launch status $race) $false
    if (Test-Path -LiteralPath (Join-Path $race stopped)) { throw 'LOSER_STOPPED_WINNER' }
    foreach($mode in @('loser','status')) { if ((Get-Content -LiteralPath (Join-Path $fixture ($mode+'.err')) -Raw) -notmatch 'LOCAL_RUNTIME_BUSY') { throw 'EXPECTED_LOCK_REJECTION_MISSING' } }
    ''|Set-Content -LiteralPath (Join-Path $race release)
    Finish $winner $true
    $records=Get-Content -LiteralPath (Join-Path $race processes.json) -Raw|ConvertFrom-Json
    if ($records.Count -ne 2 -or ($records.pid -join ',') -cne '400001,400002') { throw 'CONCURRENT_REGISTRATION_LOST' }
    Finish (Launch duplicate $race) $false
    if (Test-Path -LiteralPath (Join-Path $race stopped)) { throw 'DUPLICATE_STOPPED_WINNER' }
    $failed=Join-Path $fixture writefail
    Finish (Launch writefail $failed) $false
    $records=Get-Content -LiteralPath (Join-Path $failed processes.json) -Raw|ConvertFrom-Json
    if ($records.Count -ne 1 -or $records[0].pid -ne 400001) { throw 'ATOMIC_WRITE_DAMAGED_PRIOR_STATE' }
    if (((Get-Content -LiteralPath (Join-Path $failed stopped)) -join ',') -cne '400001,400002') { throw 'PARTIAL_START_CLEANUP_FAILED' }
    $cleanupFailed=Join-Path $fixture cleanupfail
    Finish (Launch cleanupfail $cleanupFailed) $false
    if (((Get-Content -LiteralPath (Join-Path $cleanupFailed stopped)) -join ',') -cne '400001,400002') { throw 'CLEANUP_FAILURE_SKIPPED_NEXT_PROCESS' }
    if ((Get-Content -LiteralPath (Join-Path $fixture cleanupfail.out) -Raw) -notmatch 'LOCAL_RUNTIME_PARTIAL_CLEANUP_FAILED') { throw 'CLEANUP_FAILURE_NOT_REPORTED' }
    $lockTarget=Join-Path $fixture lockexit
    $owner=Launch lockowner $lockTarget;Wait-File (Join-Path $lockTarget lockentered)
    $owner.Kill();$owner.WaitForExit()
    $lock=Enter-RuntimeSnapshotLock $lockTarget;$lock.Dispose()
    if (-not (Test-Path -LiteralPath (Join-Path $lockTarget lifecycle.lock))) { throw 'LOCK_FILE_DELETED' }
    Write-Output 'PASS: concurrent Start, Start/Status exclusion, loser cleanup ownership, duplicate Start, atomic write failure cleanup, continued cleanup after failure, owner-exit lock recovery (7 checks)'
} finally {
    foreach($child in $children) { if (-not $child.HasExited) { $child.Kill();$child.WaitForExit() } }
    $resolved=[IO.Path]::GetFullPath($fixture)
    if (-not $resolved.StartsWith([IO.Path]::GetFullPath($runtimeRoot)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'FIXTURE_CLEANUP_OUTSIDE_RUNTIME' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
