#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'runtime-evidence.ps1')
$count=0
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
            foreach ($n in 1..2) {
                $client=$listener.AcceptTcpClient(); $client.ReceiveTimeout=5000
                try {
                    $stream=$client.GetStream(); $reader=[IO.StreamReader]::new($stream)
                    $request=$reader.ReadLine(); while ($reader.ReadLine()) { }
                    $response=$body|ConvertFrom-Json -AsHashtable
                    $response.challenge=[regex]::Match($request,'challenge=([a-f0-9]+)').Groups[1].Value
                    $bytes=[Text.Encoding]::UTF8.GetBytes(($response|ConvertTo-Json -Compress))
                    $header=[Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n")
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
    Wait-Job $job -Timeout 10 | Out-Null
    Receive-Job $job -ErrorAction Stop | Out-Null
    Reject { Get-RuntimeIdentityObservation -ExpectedPath $path -IdentityUri "http://127.0.0.1:$port/identity" -TimeoutSeconds 1 } 'RUNTIME_OBSERVATION_UNAVAILABLE'
    # 执行真实客户端入口；替换 Maven/Java 和远端响应，仅检查故障时的证据与退出传播。
    $driver=Join-Path $temp 'entry-test.ps1'
    @'
param($ClientScript,$ExpectedPath,$Mode)
$ErrorActionPreference='Stop'
$global:calls=0
function global:cmd.exe { $global:LASTEXITCODE=0 }
function global:Start-Process { [pscustomobject]@{ExitCode=17} }
function global:Invoke-RestMethod {
    param($Uri)
    $global:calls++
    if ($global:calls -eq 2 -and $Mode -eq 'unavailable') { throw 'fixture unavailable' }
    $r=Get-Content -LiteralPath $ExpectedPath -Raw|ConvertFrom-Json
    $r|Add-Member instanceId $(if ($global:calls -eq 2) {'restarted'} else {'original'})
    $r|Add-Member startedAt '2026-01-01T00:00:00Z'
    $r|Add-Member challenge ([regex]::Match($Uri.Query,'challenge=([a-f0-9]+)').Groups[1].Value)
    return $r
}
& $ClientScript -TestClass fixture.Only -ExpectedRuntime $ExpectedPath -RuntimeIdentityUri http://127.0.0.1/identity -RequireRuntimeIdentity
'@ | Set-Content -LiteralPath $driver -Encoding utf8
    $clientScript=Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'run_client.ps1'
    foreach ($mode in @('unavailable','restarted')) {
        $out=& pwsh -NoProfile -File $driver -ClientScript $clientScript -ExpectedPath $path -Mode $mode 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -or $out -notmatch 'RUNTIME_BEFORE_OBSERVATION:' -or $out -notmatch 'SCENARIO_PROCESS_EXIT: 17' -or $out -notmatch '"exitCode":17' -or $out -notmatch '"runtimeStatus":"FAILED"' -or $out -match 'SCENARIO_PROCESS_PASS:') { throw "Client failure evidence regression: $mode $out" }
        $count++
    }
    Write-Output "PASS: $count runtime evidence checks; HTTP fixture only, no game server tested"
} finally {
    if ($job) { Stop-Job $job; Remove-Job $job }
    $resolved=[IO.Path]::GetFullPath($temp)
    $parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if ($resolved.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'runtime-evidence-*') { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
