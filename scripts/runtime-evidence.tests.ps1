#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'runtime-evidence.ps1')
$count=0
$dates=ConvertFrom-RuntimeJson '{"startedAt":"2026-01-01T01:02:03.641Z","nested":{"startedAt":"2026-01-01T01:02:03.641Z"}}'
if ($dates.startedAt -isnot [string] -or $dates.startedAt -cne '2026-01-01T01:02:03.641Z' -or $dates.nested.startedAt -cne $dates.startedAt) { throw 'JSON timestamp coercion regression' }; $count++
$records=ConvertFrom-RuntimeJson '[{"pid":1,"startedAt":"2026-01-01T01:02:03.6410000Z"},{"pid":2,"startedAt":"2026-01-01T01:02:04.6410000Z"}]'
if ($records.Count -ne 2 -or $records[0].startedAt -isnot [string] -or $records[1].pid -ne 2) { throw 'Process identity JSON regression' }; $count++
function Reject([scriptblock]$Action,[string]$Code) {
    try { & $Action; throw 'UNEXPECTED_PASS' } catch { if ($_.Exception.Message -notlike "$Code*") { throw } }
    $script:count++
}
$expected=@{schemaVersion='1.0';targetId='isolated-fixture';buildId='fixture-build';sourceDigest=('a'*64);artifactSha256=('b'*64);configSha256=('c'*64);protocolSha256=('d'*64);dataNamespace='fixture-only'}
$observed=$expected.Clone(); $observed.instanceId='process-one'; $observed.startedAt=[DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o'); $observed.challenge='fresh'; $observed.secret='must-not-be-retained'
$safe=Assert-RuntimeIdentity $expected $observed 'fresh'
if ($safe.Contains('secret')) { throw 'Secret retained' }; $count++
foreach ($field in @('targetId','buildId','sourceDigest','artifactSha256','configSha256','protocolSha256','dataNamespace')) {
    $bad=$observed.Clone(); $bad[$field]='different'
    Reject { Assert-RuntimeIdentity $expected $bad 'fresh' } "RUNTIME_IDENTITY_MISMATCH:$field"
}
Reject { Assert-RuntimeIdentity $expected $observed 'new-request' } 'RUNTIME_CHALLENGE_MISMATCH'
$bad=$expected.Clone(); $bad.artifactSha256='not-a-hash'
Reject { Assert-RuntimeIdentity $bad $observed 'fresh' } 'RUNTIME_EXPECTED_INVALID'
$first=@{expectedSha256='same';identity=$safe}
$second=@{expectedSha256='same';identity=($observed.Clone())}; $second.identity.instanceId='restarted'
Reject { Assert-RuntimeIdentityStable $first $second } 'RUNTIME_CHANGED_DURING_TEST:instanceId'
$second=@{expectedSha256='changed';identity=$safe}
Reject { Assert-RuntimeIdentityStable $first $second } 'RUNTIME_EXPECTATION_CHANGED'

# 真正通过本机 HTTP 采集一次，验证 challenge 传递、JSON 解析和前后核对。
$temp=Join-Path ([IO.Path]::GetTempPath()) ('runtime-evidence-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp)|Out-Null
$job=$null
try {
    $path=Join-Path $temp 'expected.json'; $expected|ConvertTo-Json|Set-Content -LiteralPath $path -Encoding utf8
    $job=Start-Job -ArgumentList ($observed|ConvertTo-Json -Compress) -ScriptBlock {
        param($body)
        $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0); $listener.Start()
        try {
            Write-Output $listener.LocalEndpoint.Port
            foreach ($n in 1..3) {
                $client=$listener.AcceptTcpClient(); $client.ReceiveTimeout=5000
                try {
                    $stream=$client.GetStream(); $reader=[IO.StreamReader]::new($stream)
                    $request=$reader.ReadLine(); while ($reader.ReadLine()) { }
                    $response=$body|ConvertFrom-Json -AsHashtable
                    $response.challenge=[regex]::Match($request,'challenge=([a-f0-9]+)').Groups[1].Value
                    $bytes=[Text.Encoding]::UTF8.GetBytes(($response|ConvertTo-Json -Compress))
                    $header=[Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n")
                    if ($n -eq 3) {
                        $bytes=[Text.Encoding]::UTF8.GetBytes('RUNTIME_IDENTITY_UNVERIFIED')
                        $header=[Text.Encoding]::ASCII.GetBytes("HTTP/1.1 503 Service Unavailable`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n")
                    }
                    $stream.Write($header); $stream.Write($bytes); $stream.Flush()
                } finally { $client.Dispose() }
            }
        } finally { $listener.Stop() }
    }
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds(15); $port=$null
    while (-not $port -and [DateTimeOffset]::UtcNow -lt $deadline) { $port=Receive-Job $job; if (-not $port) { Start-Sleep -Milliseconds 50 } }
    if (-not $port) { throw 'Fixture listener failed' }
    $a=Get-RuntimeIdentityObservation -ExpectedPath $path -IdentityUri "http://127.0.0.1:$port/identity"
    $b=Get-RuntimeIdentityObservation -ExpectedPath $path -IdentityUri "http://127.0.0.1:$port/identity"
    Assert-RuntimeIdentityStable $a $b
    if ($a.identity.challenge -ceq $b.identity.challenge) { throw 'Challenge reused' }; $count++
    $revoked=Invoke-WebRequest -Uri "http://127.0.0.1:$port/identity" -SkipHttpErrorCheck -TimeoutSec 5
    Assert-RuntimeIdentityRevoked $revoked; $count++
    Reject { Assert-RuntimeIdentityRevoked @{StatusCode=200;Content='RUNTIME_IDENTITY_UNVERIFIED'} } 'RUNTIME_REVOCATION_FAILED'
    Reject { Assert-RuntimeIdentityRevoked @{StatusCode=503;Content='unrelated failure'} } 'RUNTIME_REVOCATION_FAILED'
    Wait-Job $job -Timeout 10 | Out-Null
    Receive-Job $job -ErrorAction Stop | Out-Null
    Reject { Get-RuntimeIdentityObservation -ExpectedPath $path -IdentityUri "http://127.0.0.1:$port/identity" -TimeoutSeconds 1 } 'RUNTIME_OBSERVATION_UNAVAILABLE'
    # HTTP匹配不能代替场景；绑定本次运行、两个挑战和实际玩家/逻辑区服。
    $scenarioPath=Join-Path $temp 'scenario.json'; $runId=[guid]::NewGuid().ToString('N')
    $probeBefore=@{}; foreach ($key in $a.identity.Keys) { $probeBefore[$key]=$a.identity[$key] }
    $probeBefore.playerId='42'; $probeBefore.logicServerId='logic-two'
    $probeAfter=$probeBefore.Clone(); $probeAfter.challenge=[guid]::NewGuid().ToString('N')
    $scenario=@{schemaVersion='1.0';runId=$runId;status='PROBES_MATCH';scope='AUTHENTICATED_GAME_NODE_PROBES';scenarioSucceeded=$true;before=$probeBefore;after=$probeAfter;secret='must-not-retain'}
    $scenario|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $scenarioPath
    $accepted=Assert-ScenarioRuntimeEvidence $scenarioPath $runId $a 0 -LogicServerId 'logic-two'
    if ($accepted.Contains('secret')) { throw 'Scenario secret retained' }; $count++
    Reject { Assert-ScenarioRuntimeEvidence $scenarioPath 'another-run' $a 0 -LogicServerId 'logic-two' } 'SCENARIO_RUNTIME_EVIDENCE_INVALID'
    Reject { Assert-ScenarioRuntimeEvidence $scenarioPath $runId $a 17 -LogicServerId 'logic-two' } 'SCENARIO_RUNTIME_EVIDENCE_INVALID'
    $probeAfter.instanceId='other-process'; $scenario|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $scenarioPath
    Reject { Assert-ScenarioRuntimeEvidence $scenarioPath $runId $a 0 -LogicServerId 'logic-two' } 'SCENARIO_RUNTIME_MISMATCH:instanceId'
    $probeAfter.instanceId=$probeBefore.instanceId; $probeAfter.playerId='43'; $scenario|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $scenarioPath
    Reject { Assert-ScenarioRuntimeEvidence $scenarioPath $runId $a 0 -LogicServerId 'logic-two' } 'SCENARIO_RUNTIME_BINDING_CHANGED'
    $probeAfter.playerId='42'; $probeAfter.challenge=$probeBefore.challenge; $scenario|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $scenarioPath
    Reject { Assert-ScenarioRuntimeEvidence $scenarioPath $runId $a 0 -LogicServerId 'logic-two' } 'SCENARIO_RUNTIME_BINDING_CHANGED'
    Remove-Item -LiteralPath $scenarioPath
    Reject { Assert-ScenarioRuntimeEvidence $scenarioPath $runId $a 0 -LogicServerId 'logic-two' } 'SCENARIO_RUNTIME_EVIDENCE_MISSING'
    # 执行真实客户端入口；替换 Maven/Java 和远端响应，仅检查故障时的证据与退出传播。
    $driver=Join-Path $temp 'entry-test.ps1'
    @'
param($ClientScript,$ExpectedPath,$Mode)
$ErrorActionPreference='Stop'
$global:calls=0
function global:cmd.exe { $global:LASTEXITCODE=0 }
function global:Start-Process {
    param($FilePath,$ArgumentList)
    $props=@{}
    foreach($arg in $ArgumentList) { $v=$arg.Trim('"'); if($v -match '^-D([^=]+)=(.*)$'){$props[$Matches[1]]=$Matches[2]} }
    $probe=@{targetId='isolated-fixture';instanceId='original';startedAt='2026-01-01T00:00:00Z';playerId='42';logicServerId='logic-two';challenge=('a'*32)}
    $report=@{schemaVersion='1.0';runId=$props['scenario.runtime.runId'];scope='AUTHENTICATED_GAME_NODE_PROBES';status='FAILED';scenarioSucceeded=$false;before=$probe;after=$null;secret='must-not-retain'}
    $report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $props['scenario.runtime.output']
    [pscustomobject]@{ExitCode=17}
}
function global:Invoke-WebRequest {
    param($Uri)
    $global:calls++
    if ($global:calls -eq 2 -and $Mode -eq 'unavailable') { throw 'fixture unavailable' }
    $r=Get-Content -LiteralPath $ExpectedPath -Raw|ConvertFrom-Json
    $r|Add-Member instanceId $(if ($global:calls -eq 2) {'restarted'} else {'original'})
    $r|Add-Member startedAt '2026-01-01T00:00:00Z'
    $r|Add-Member challenge ([regex]::Match($Uri.Query,'challenge=([a-f0-9]+)').Groups[1].Value)
    return [pscustomobject]@{Content=($r|ConvertTo-Json -Compress)}
}
& $ClientScript -TestClass fixture.Only -ExpectedRuntime $ExpectedPath -RuntimeIdentityUri http://127.0.0.1/identity -RequireRuntimeIdentity -LogicServerId logic-two
'@ | Set-Content -LiteralPath $driver -Encoding utf8
    $clientScript=Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'run_client.ps1'
    foreach ($mode in @('unavailable','restarted')) {
        $out=& pwsh -NoProfile -File $driver -ClientScript $clientScript -ExpectedPath $path -Mode $mode 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -or $out -notmatch 'RUNTIME_BEFORE_OBSERVATION:' -or $out -notmatch 'SCENARIO_PROCESS_EXIT: 17' -or $out -notmatch '"exitCode":17' -or $out -notmatch '"runtimeStatus":"FAILED"' -or $out -notmatch '\"playerId\":\"42\"' -or $out -match 'must-not-retain' -or $out -match 'SCENARIO_PROCESS_PASS:') { throw "Client failure evidence regression: $mode $out" }
        $count++
    }
    # 真正调用 Java，验证 Windows 含空格、空值、引号及尾反斜杠参数编码。
    . (Join-Path $PSScriptRoot 'native-arguments.ps1')
    $argDir=Join-Path $temp 'with spaces'; [IO.Directory]::CreateDirectory($argDir)|Out-Null
    $argJava=Join-Path $argDir 'ArgumentProbe.java'
    'class ArgumentProbe { public static void main(String[] args) { for(String s:args) System.out.println(java.util.Base64.getEncoder().encodeToString(s.getBytes(java.nio.charset.StandardCharsets.UTF_8))); } }'|Set-Content -LiteralPath $argJava
    $values=@('path with spaces','quote"inside','C:\end with space\','')
    $argOutput=Join-Path $argDir 'output.txt'
    $p=Start-Process java -ArgumentList (@($argJava)+$values|ForEach-Object { ConvertTo-NativeArgument $_ }) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $argOutput
    $actual=@(Get-Content -LiteralPath $argOutput)
    $wanted=@($values|ForEach-Object {[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($_))})
    if ($p.ExitCode -ne 0 -or ($actual -join '|') -cne ($wanted -join '|')) { throw 'Native Java argument encoding regression' }; $count++
    # 首条 PID 被复用时必须跳过它，继续停止后续确属本次的进程，并最终报告清理不完整。
    $runtimeRoot=Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '.ai-workspace/.runtime/local-runtime'
    $stopFixture=Join-Path $runtimeRoot ('stop-check-'+[guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($stopFixture)|Out-Null
    try {
        '{}'|Set-Content -LiteralPath (Join-Path $stopFixture settings.json)
        '[{"app":"login","pid":111,"startedAt":"2026-01-01T00:00:00.0000000Z","runId":"fixture","main":"game.Main"},{"app":"game","pid":222,"startedAt":"2026-01-01T00:00:00.0000000Z","runId":"fixture","main":"game.Main"}]'|Set-Content -LiteralPath (Join-Path $stopFixture processes.json)
        $stopDriver=Join-Path $temp 'stop-test.ps1'
        @'
param($StopScript,$Snapshot)
$ErrorActionPreference='Stop';$global:stopped=@()
function global:Get-Process { param([int]$Id) $p=[pscustomobject]@{Id=$Id;Handle=1;StartTime=[DateTime]::Parse('2026-01-01T00:00:00Z',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)};$p|Add-Member -MemberType ScriptMethod -Name Dispose -Value {};$p|Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {param($Timeout) return $true};$p }
function global:Get-CimInstance { param($ClassName,$Filter) [pscustomobject]@{CommandLine=$(if($Filter -eq 'ProcessId=111'){'java.exe unrelated.Main'}else{'java.exe -Druntime.launchId=fixture game.Main'})} }
function global:Stop-Process { param([int]$Id,$InputObject) if($InputObject){$Id=$InputObject.Id};$global:stopped+=$Id }
try { & $StopScript -Action Stop -Snapshot $Snapshot; throw 'UNEXPECTED_STOP_SUCCESS' }
catch { if($_.Exception.Message -notlike 'LOCAL_RUNTIME_STOP_INCOMPLETE:*'){throw} }
if(($global:stopped -join ',') -cne '222'){throw 'MIXED_PROCESS_CLEANUP_REGRESSION'}
'@|Set-Content -LiteralPath $stopDriver
        & pwsh -NoProfile -File $stopDriver -StopScript (Join-Path $PSScriptRoot local-runtime.ps1) -Snapshot $stopFixture
        if($LASTEXITCODE -ne 0){throw 'Mixed process cleanup failed'};$count++
    } finally {
        $resolvedFixture=[IO.Path]::GetFullPath($stopFixture)
        if(-not $resolvedFixture.StartsWith([IO.Path]::GetFullPath($runtimeRoot)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture cleanup path rejected'}
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    }
    Write-Output "PASS: $count runtime evidence checks; HTTP fixture only, no game server tested"
} finally {
    if ($job) { Stop-Job $job; Remove-Job $job }
    $resolved=[IO.Path]::GetFullPath($temp)
    $parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if ($resolved.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'runtime-evidence-*') { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
