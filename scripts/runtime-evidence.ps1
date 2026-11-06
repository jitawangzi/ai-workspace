#requires -Version 7.0
# 只读运行身份观察；不启动服务、不修改业务状态、不把声明当成远端认证。
function Assert-RuntimeIdentity {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Expected,
          [Parameter(Mandatory)][System.Collections.IDictionary]$Observed,
          [Parameter(Mandatory)][string]$Challenge)
    if ($Expected.schemaVersion -cne '1.0' -or $Observed.schemaVersion -cne '1.0') { throw 'RUNTIME_SCHEMA_INVALID' }
    foreach ($key in @('targetId','buildId','sourceDigest','artifactSha256','configSha256','protocolSha256','dataNamespace')) {
        if ($Expected[$key] -isnot [string] -or [string]::IsNullOrWhiteSpace($Expected[$key]) -or $Expected[$key] -match '[\r\n]') { throw "RUNTIME_EXPECTED_INVALID:$key" }
        if ($key -match 'Sha256$|Digest$' -and $Expected[$key] -cnotmatch '^[0-9a-f]{64}$') { throw "RUNTIME_EXPECTED_INVALID:$key" }
        if ($Observed[$key] -isnot [string] -or $Expected[$key] -cne $Observed[$key]) { throw "RUNTIME_IDENTITY_MISMATCH:$key" }
    }
    if ($Observed.challenge -cne $Challenge) { throw 'RUNTIME_CHALLENGE_MISMATCH' }
    if ($Observed.instanceId -isnot [string] -or [string]::IsNullOrWhiteSpace($Observed.instanceId) -or $Observed.instanceId -match '[\r\n]') { throw 'RUNTIME_INSTANCE_MISSING' }
    $started=[DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$Observed.startedAt,[ref]$started) -or $started -gt [DateTimeOffset]::UtcNow.AddSeconds(30)) { throw 'RUNTIME_START_TIME_INVALID' }
    # 只保留契约字段，不把响应中的任意凭据或调试内容归档。
    $safe=[ordered]@{}
    foreach ($key in @('schemaVersion','targetId','buildId','sourceDigest','artifactSha256','configSha256','protocolSha256','dataNamespace','instanceId','startedAt','challenge')) { $safe[$key]=$Observed[$key] }
    return $safe
}

function Get-RuntimeIdentityObservation {
    param([Parameter(Mandatory)][string]$ExpectedPath,
          [Parameter(Mandatory)][uri]$IdentityUri,
          [ValidateRange(1,60)][int]$TimeoutSeconds=10)
    if (-not $IdentityUri.IsAbsoluteUri -or $IdentityUri.Scheme -notin @('https','http') -or $IdentityUri.UserInfo -or $IdentityUri.Query -or $IdentityUri.Fragment) { throw 'RUNTIME_URI_INVALID: use a dedicated endpoint without credentials, query or fragment' }
    $expectedBytes=[IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $ExpectedPath))
    $expectedHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($expectedBytes)).ToLowerInvariant()
    $expected=[Text.Encoding]::UTF8.GetString($expectedBytes).TrimStart([char]0xfeff) | ConvertFrom-Json -AsHashtable
    $nonce=[guid]::NewGuid().ToString('N')
    $request=[uri]($IdentityUri.AbsoluteUri+'?challenge='+$nonce)
    $at=[DateTimeOffset]::UtcNow.ToString('o')
    # 禁止重定向以免观察了另一目标；不记录请求 URI 或原始错误响应。
    try { $response=Invoke-RestMethod -Uri $request -Method Get -TimeoutSec $TimeoutSeconds -MaximumRedirection 0 -Headers @{'Cache-Control'='no-cache'} -ErrorAction Stop }
    catch { throw 'RUNTIME_OBSERVATION_UNAVAILABLE: endpoint failed; runtime identity is unverified' }
    $observed=$response | ConvertTo-Json -Depth 8 | ConvertFrom-Json -AsHashtable
    $safe=Assert-RuntimeIdentity -Expected $expected -Observed $observed -Challenge $nonce
    return [ordered]@{status='OBSERVED_MATCH';requestedAt=$at;receivedAt=[DateTimeOffset]::UtcNow.ToString('o');expectedSha256=$expectedHash;identity=$safe}
}

function Assert-RuntimeIdentityStable {
    param([Parameter(Mandatory)]$Before,[Parameter(Mandatory)]$After)
    if ($Before.expectedSha256 -cne $After.expectedSha256) { throw 'RUNTIME_EXPECTATION_CHANGED' }
    foreach ($key in @('targetId','buildId','sourceDigest','artifactSha256','configSha256','protocolSha256','dataNamespace','instanceId','startedAt')) {
        if ($Before.identity[$key] -cne $After.identity[$key]) { throw "RUNTIME_CHANGED_DURING_TEST:$key" }
    }
}
