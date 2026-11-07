#requires -Version 7.0
<#
.SYNOPSIS
    准备独立本机制品快照；仅启动指定快照的 Game/Login，并用本次标识精确管理进程。
#>
[CmdletBinding()]
param(
    [ValidateSet('Prepare','Start','Stop','Status')][string]$Action='Prepare',
    [string]$Snapshot,
    [uri]$ApolloUri='http://127.0.0.1:9888',
    [string]$ApolloCluster='SYQ',
    [string]$GameId='game_test',
    [string]$LoginId='login_test',
    [int]$IdentityPort=17011,
    [switch]$ConfirmDataScope
)
$ErrorActionPreference='Stop'
$hostRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtimeRoot=Join-Path $hostRoot '.ai-workspace/.runtime/local-runtime'
. (Join-Path $PSScriptRoot 'runtime-evidence.ps1')
. (Join-Path $PSScriptRoot 'native-arguments.ps1')
. (Join-Path $PSScriptRoot 'runtime-state.ps1')
function RequireSuccess([string]$Operation) { if ($LASTEXITCODE -ne 0) { throw "LOCAL_RUNTIME_FAILED:$Operation" } }
function SourceDigest {
    $items=@(Get-Item -LiteralPath (Join-Path $hostRoot 'pom.xml'))
    foreach ($module in @('util','protocol','core','game','login','simulationclient')) {
        $items+=Get-Item -LiteralPath (Join-Path $hostRoot "$module/pom.xml")
        $items+=Get-ChildItem -LiteralPath (Join-Path $hostRoot "$module/src") -File -Recurse
    }
    $lines=@($items|Sort-Object FullName|ForEach-Object { [IO.Path]::GetRelativePath($hostRoot,$_.FullName).Replace('\','/')+'='+((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()) })
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($lines -join "`n")))).ToLowerInvariant()
}
function RuntimeArgs($Settings,[string]$App) {
    $order=if ($App -eq 'game') { @('game','util','core','protocol') } else { @('login','util','core','protocol','game') }
    $classpath=(@($order|ForEach-Object { Join-Path $Snapshot "artifacts/$_/classes" })+(Join-Path $Snapshot 'artifacts/lib/*')) -join ';'
    return @("-Dapp.id=$App",'-Denv=dev',"-Dapollo.cluster=$($Settings.apolloCluster)","-Dapollo.configService=$($Settings.apolloUri)",
        "-Dapollo.cacheDir=$(Join-Path $Snapshot 'apollo-cache')","-DSEVER_PATH=$(Join-Path $Snapshot ('work/'+$App))",'-DdefaultNetworkIp=127.0.0.1','-Dserver.run.mode=test',
        "-Dworkspace=$hostRoot","-Dmetafolder=$(Join-Path (Split-Path -Parent $hostRoot) 'configs/Server')",
        '-Dfile.encoding=UTF-8','--add-opens=java.base/java.lang=ALL-UNNAMED','--add-opens=java.base/java.util=ALL-UNNAMED',
        '-Dio.netty.tryReflectionSetAccessible=true','-Dzookeeper.clientCnxnSocket=org.apache.zookeeper.ClientCnxnSocketNetty',
        '-Druntime.config.freeze=true',"-Druntime.launchId=$($Settings.runId)","-Dgame.runtimeIdentity.root=$(Join-Path $Snapshot 'artifacts')",'-cp',$classpath)
}
function StartJava([string[]]$JavaArguments,[string]$Name) {
    $workingDirectory=Join-Path $Snapshot ('work/'+$Name)
    [IO.Directory]::CreateDirectory($workingDirectory)|Out-Null
    # 隐藏启动并重定向日志，进程自身以独有 launchId 和启动时间识别。
    $out=Join-Path $Snapshot ($Name+'.stdout.log'); $err=Join-Path $Snapshot ($Name+'.stderr.log')
    $quoted=@($JavaArguments|ForEach-Object { ConvertTo-NativeArgument $_ })
    return Start-Process -FilePath 'java' -ArgumentList $quoted -WorkingDirectory $workingDirectory -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
}
function OwnedProcess($Record) {
    $p=Get-Process -Id $Record.pid -ErrorAction SilentlyContinue
    if(-not $p){return $null}
    try {
    # 先持有内核句柄，后续StartTime、Kill和等待不重新绑定到复用的PID。
    $null=$p.Handle
    $details=Get-CimInstance Win32_Process -Filter "ProcessId=$($Record.pid)" -ErrorAction SilentlyContinue
    if ($p -and $details -and $p.StartTime.ToUniversalTime().ToString('o') -ceq $Record.startedAt -and
        (MatchesLaunch $details.CommandLine $Record.runId $Record.main)) { return $p }
    $p.Dispose()
    return $null
    } catch {$p.Dispose();throw}
}
function MatchesLaunch([string]$CommandLine,[string]$RunId,[string]$Main) {
    if(-not $CommandLine){return $false}
    $tokens=@(ConvertFrom-NativeCommandLine $CommandLine);$launches=@()
    for($i=1;$i -lt $tokens.Count;$i++){
        $token=$tokens[$i]
        if($token -in @('-cp','-classpath','--class-path')){$i++;continue}
        if($token.StartsWith('-Druntime.launchId=')){$launches+=,$token;continue}
        if($token.StartsWith('-D') -or $token.StartsWith('-X') -or $token.StartsWith('--add-opens=')){continue}
        # 首个非支持JVM选项必须是实际主类；后面的业务参数不参与身份。
        return $token -ceq $Main -and $launches.Count -eq 1 -and $launches[0] -ceq ('-Druntime.launchId='+$RunId)
    }
    return $false
}
function ProcessStillExists([int]$ProcessId) {
    $current=Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if(-not $current){return $false}
    try{return -not $current.HasExited}
    catch {Write-Warning ('LOCAL_RUNTIME_LIVENESS_UNKNOWN:'+ $ProcessId+':'+$_);return $true}
    finally{$current.Dispose()}
}
# 意图先于启动落盘，覆盖创建进程后尚未来得及记录PID就退出的窗口。
function RecoverLaunchRecords($Intent,$Settings,$Failures) {
    if ($Intent.schemaVersion -cne '1.0' -or $Intent.runId -cne $Settings.runId -or $Intent.runId -notmatch '^[A-Za-z0-9_-]+$') { throw 'LOCAL_RUNTIME_INTENT_INVALID' }
    try {$candidates=@(Get-CimInstance Win32_Process -Filter "Name='java.exe'" -ErrorAction Stop)}
    catch {Write-Warning ('LOCAL_RUNTIME_DISCOVERY_FAILED:'+$_);$Failures.Add('DISCOVERY_FAILED');return}
    foreach ($app in @('login','game')) {
        $main=if($app -eq 'game'){'cn.game.games.net.game.GameServer'}else{'cn.game.login.LoginServer'}
        foreach ($candidate in $candidates) {
            if (MatchesLaunch $candidate.CommandLine $Intent.runId $main) {
                $p=$null
                try {
                $p=Get-Process -Id $candidate.ProcessId -ErrorAction SilentlyContinue
                if ($p) {
                    $null=$p.Handle
                    $record=@{app=$app;pid=$p.Id;startedAt=$p.StartTime.ToUniversalTime().ToString('o');main=$main;runId=$Intent.runId}
                    $verified=OwnedProcess $record
                    if($verified){$verified.Dispose();$record}
                    elseif(ProcessStillExists $candidate.ProcessId){$Failures.Add('CANDIDATE_IDENTITY_CHANGED:'+ $candidate.ProcessId)}
                }
                } catch {
                    Write-Warning ('LOCAL_RUNTIME_CANDIDATE_UNAVAILABLE:'+ $candidate.ProcessId+':'+$_)
                    if(ProcessStillExists $candidate.ProcessId){$Failures.Add('CANDIDATE_UNAVAILABLE:'+ $candidate.ProcessId)}
                } finally {if($p){$p.Dispose()}}
            }
        }
    }
}
if ($Action -eq 'Prepare') {
    if ($ApolloUri.Scheme -ne 'http' -or -not $ApolloUri.IsLoopback -or $ApolloUri.UserInfo -or $ApolloUri.Query) { throw 'LOCAL_APOLLO_URI_REQUIRED' }
    if ($ApolloCluster -notmatch '^[A-Za-z0-9_.-]+$' -or $GameId -notmatch '^[A-Za-z0-9_.-]+$' -or $LoginId -notmatch '^[A-Za-z0-9_.-]+$') { throw 'LOCAL_RUNTIME_ID_INVALID' }
    $runId=[guid]::NewGuid().ToString('N')
    $Snapshot=Join-Path $runtimeRoot $runId
    $before=SourceDigest
    Push-Location $hostRoot
    try { & mvn -B '-DskipTests' clean package; RequireSuccess 'build' } finally { Pop-Location }
    if ((SourceDigest) -cne $before) { throw 'LOCAL_RUNTIME_SOURCE_CHANGED_DURING_BUILD' }
    $artifactRoot=Join-Path $Snapshot 'artifacts'
    foreach ($module in @('util','protocol','core','game','login','simulationclient')) {
        $destination=Join-Path $artifactRoot $module
        [IO.Directory]::CreateDirectory($destination)|Out-Null
        Copy-Item -LiteralPath (Join-Path $hostRoot "$module/target/classes") -Destination $destination -Recurse
    }
    $lib=Join-Path $artifactRoot 'lib'; [IO.Directory]::CreateDirectory($lib)|Out-Null
    foreach ($module in @('game','login','simulationclient')) {
        foreach ($jar in Get-ChildItem -LiteralPath (Join-Path $hostRoot "$module/target/lib") -Filter '*.jar' -File) {
            if ($jar.Name -match '^(util|core|protocol|game|login|simulationclient)(-1\.0)?\.jar$') { continue }
            $destination=Join-Path $lib $jar.Name
            if (Test-Path -LiteralPath $destination) {
                if ((Get-FileHash -LiteralPath $jar.FullName).Hash -cne (Get-FileHash -LiteralPath $destination).Hash) { throw "LOCAL_RUNTIME_DEPENDENCY_COLLISION:$($jar.Name)" }
            } else { Copy-Item -LiteralPath $jar.FullName -Destination $destination }
        }
    }
    $metadata="buildId=local-$runId`nsourceDigest=$before`n"
    [IO.File]::WriteAllText((Join-Path $artifactRoot 'game/classes/runtime-build.properties'),$metadata,[Text.Encoding]::ASCII)
    $settings=[ordered]@{schemaVersion='1.0';runId=$runId;apolloUri=$ApolloUri.AbsoluteUri.TrimEnd('/');apolloCluster=$ApolloCluster;gameId=$GameId;loginId=$LoginId;identityPort=$IdentityPort;sourceDigest=$before}
    $settings|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $Snapshot 'settings.json') -Encoding utf8
    $argsList=RuntimeArgs $settings 'game'
    & java @argsList 'cn.game.games.core.runtime.RuntimeIdentityManifest' $GameId (Join-Path $Snapshot 'expected-runtime.json')
    RequireSuccess 'expected-manifest'
    $argsList=RuntimeArgs $settings 'login'
    & java @argsList 'cn.game.games.core.runtime.RuntimeIdentityManifest' $LoginId (Join-Path $Snapshot 'expected-login.json')
    RequireSuccess 'expected-login-manifest'
    Write-Output "LOCAL_RUNTIME_PREPARED:$Snapshot"
    exit 0
}
if (-not $Snapshot) { throw 'LOCAL_RUNTIME_SNAPSHOT_REQUIRED' }
$Snapshot=(Resolve-Path -LiteralPath $Snapshot).Path
if (-not $Snapshot.StartsWith($runtimeRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'LOCAL_RUNTIME_SNAPSHOT_OUTSIDE_WORKSPACE' }
$lifecycleLock=Enter-RuntimeSnapshotLock $Snapshot
try {
$settings=Get-Content -LiteralPath (Join-Path $Snapshot 'settings.json') -Raw|ConvertFrom-Json
$statePath=Join-Path $Snapshot 'processes.json'
$intentPath=Join-Path $Snapshot 'launch-intent.json'
if ($Action -eq 'Start') {
    if (-not $ConfirmDataScope) { throw 'LOCAL_RUNTIME_DATA_SCOPE_REQUIRED: Game startup runs existing migrations; confirm this snapshot uses the intended test storage' }
    if ((Test-Path -LiteralPath $statePath) -or (Test-Path -LiteralPath $intentPath)) { throw 'LOCAL_RUNTIME_ALREADY_STARTED: inspect Status; prepare a new snapshot for another run' }
    # 外部预检仅用于提前诊断；两个业务 JVM 仍须在存储初始化前核对自己的固定配置。
    foreach ($app in @('game','login')) {
        $argsList=RuntimeArgs $settings $app
        $id=if ($app -eq 'game') { $settings.gameId } else { $settings.loginId }
        $file=if ($app -eq 'game') { 'expected-runtime.json' } else { 'expected-login.json' }
        $candidate=Join-Path $Snapshot ($app+'-preflight.json')
        & java @argsList 'cn.game.games.core.runtime.RuntimeIdentityManifest' $id $candidate
        RequireSuccess 'preflight-manifest'
        $expected=Get-Content -LiteralPath (Join-Path $Snapshot $file) -Raw|ConvertFrom-Json -AsHashtable
        $actual=Get-Content -LiteralPath $candidate -Raw|ConvertFrom-Json -AsHashtable
        foreach ($key in $expected.Keys) { if ($actual[$key] -cne $expected[$key]) { throw "LOCAL_RUNTIME_PREFLIGHT_DRIFT:$app/$key" } }
    }
    $records=@()
    # 使用已有原子写和Flush(true)；持久意图失败时绝不创建业务进程。
    Write-RuntimeProcessState $intentPath @(@{schemaVersion='1.0';runId=$settings.runId})
    try {
    foreach ($app in @('login','game')) {
        $arguments=RuntimeArgs $settings $app
        $expectedFile=if ($app -eq 'game') { 'expected-runtime.json' } else { 'expected-login.json' }
        $arguments=@("-Druntime.expected=$(Join-Path $Snapshot $expectedFile)")+$arguments
        if ($app -eq 'game') { $arguments=@('-Dgame.runtimeIdentity.enabled=true',"-Dgame.runtimeIdentity.port=$($settings.identityPort)")+$arguments }
        $main=if ($app -eq 'game') { 'cn.game.games.net.game.GameServer' } else { 'cn.game.login.LoginServer' }
        $id=if ($app -eq 'game') { $settings.gameId } else { $settings.loginId }
        $process=StartJava ($arguments+@($main,$id)) $app
        $records+=@{app=$app;pid=$process.Id;startedAt=$process.StartTime.ToUniversalTime().ToString('o');main=$main;runId=$settings.runId}
        Write-RuntimeProcessState $statePath $records
    }
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds(180)
    $ready=$false
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        foreach ($record in $records) { $running=OwnedProcess $record; if (-not $running) { throw "LOCAL_RUNTIME_EARLY_EXIT:$($record.app)" };$running.Dispose() }
        try {
            $null=Get-RuntimeIdentityObservation -ExpectedPath (Join-Path $Snapshot 'expected-runtime.json') -IdentityUri "http://127.0.0.1:$($settings.identityPort)/runtime-identity" -TimeoutSeconds 30
            $gameProcess=@($records|Where-Object app -eq 'game')[0]
            $listener=Get-NetTCPConnection -LocalPort $settings.identityPort -State Listen -ErrorAction Stop
            if ($listener.OwningProcess -contains $gameProcess.pid) { $ready=$true; break }
        } catch { }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { throw 'LOCAL_RUNTIME_READY_TIMEOUT' }
    } catch {
        $startFailure=$_
        foreach ($record in $records) {
            try {
                $p=OwnedProcess $record
                if ($p) { try {Stop-Process -InputObject $p; if(-not $p.WaitForExit(10000)){throw 'LOCAL_RUNTIME_PROCESS_EXIT_TIMEOUT'}} finally {$p.Dispose()} }
            } catch {
                # 一条失败不跳过后续进程；持久启动意图供另一执行者重新发现未登记进程。
                Write-Warning ('LOCAL_RUNTIME_PARTIAL_CLEANUP_FAILED:'+($record|ConvertTo-Json -Compress)+':'+$_.Exception.Message)
            }
        }
        throw $startFailure
    }
    Write-Output "LOCAL_RUNTIME_STARTED:$Snapshot"
    exit 0
}
if (-not (Test-Path -LiteralPath $statePath) -and -not (Test-Path -LiteralPath $intentPath)) { Write-Output 'LOCAL_RUNTIME_NOT_STARTED'; exit 0 }
$storedRecords=@()
$recoveryFailures=[Collections.Generic.List[string]]::new()
if(Test-Path -LiteralPath $statePath){$storedRecords=ConvertFrom-RuntimeJson (Get-Content -LiteralPath $statePath -Raw)}
if(Test-Path -LiteralPath $intentPath){
    $intent=ConvertFrom-RuntimeJson (Get-Content -LiteralPath $intentPath -Raw)
    if($intent.Count -ne 1){throw 'LOCAL_RUNTIME_INTENT_INVALID'}
    $storedRecords+=@(RecoverLaunchRecords $intent[0] $settings $recoveryFailures)
}
$storedRecords=@($storedRecords | Sort-Object -Property pid,startedAt -Unique)
$stopFailures=@($recoveryFailures.ToArray())
foreach ($record in $storedRecords) {
    $owned=$null;$process=$null
    try {
    $process=Get-Process -Id $record.pid -ErrorAction SilentlyContinue
    $owned=OwnedProcess $record
    if ($Action -eq 'Stop' -and $owned) {
        try { Stop-Process -InputObject $owned; if(-not $owned.WaitForExit(10000)){throw 'LOCAL_RUNTIME_PROCESS_EXIT_TIMEOUT'}; Write-Output "LOCAL_RUNTIME_STOPPED:$($record.app)" }
        catch { $stopFailures+='STOP_FAILED:'+ $record.app }
    }
    elseif ($Action -eq 'Status') { [ordered]@{app=$record.app;pid=$record.pid;ownedRunning=[bool]$owned}|ConvertTo-Json -Compress }
    elseif ($process -and (ProcessStillExists $record.pid)) { $stopFailures+='PROCESS_IDENTITY_CHANGED:'+ $record.app }
    } catch {Write-Warning ('LOCAL_RUNTIME_PROCESS_CHECK_FAILED:'+ $record.pid+':'+$_);if(ProcessStillExists $record.pid){$stopFailures+='PROCESS_CHECK_FAILED:'+ $record.app}}
    finally {if($owned){$owned.Dispose()};if($process){$process.Dispose()}}
}
if ($stopFailures.Count) { throw ('LOCAL_RUNTIME_STOP_INCOMPLETE:'+($stopFailures -join ';')) }
} finally { $lifecycleLock.Dispose() }
