#requires -Version 7.0
# 只读运行身份观察；不启动服务、不修改业务状态、不把声明当成远端认证。
# JSON 日期必须保持原始字符串；PowerShell 自动 DateTime 转换会丢失时区或小数秒。
function ConvertFrom-RuntimeJson {
    param([string]$Body)
    function ReadValue($Value) {
        switch ($Value.ValueKind.ToString()) {
            'Object' { $map=@{}; foreach ($property in $Value.EnumerateObject()) { $map[$property.Name]=ReadValue $property.Value }; return $map }
            'Array' { return ,@($Value.EnumerateArray()|ForEach-Object { ReadValue $_ }) }
            'String' { return $Value.GetString() }
            'Number' { return $Value.GetDouble() }
            'True' { return $true }
            'False' { return $false }
            'Null' { return $null }
            default { throw 'RUNTIME_JSON_INVALID' }
        }
    }
    $document=[System.Text.Json.JsonDocument]::Parse($Body)
    try { return ReadValue $document.RootElement } finally { $document.Dispose() }
}

# 无 Content-Type 的错误响应在不同 PowerShell 版本中可能作为 byte[] 返回。
function Assert-RuntimeIdentityRevoked {
    param($Response)
    $body=if ($Response.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($Response.Content) } else { [string]$Response.Content }
    if ([int]$Response.StatusCode -ne 503 -or $body -cne 'RUNTIME_IDENTITY_UNVERIFIED') { throw 'RUNTIME_REVOCATION_FAILED' }
}

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
          [ValidateRange(1,60)][int]$TimeoutSeconds=30)
    if (-not $IdentityUri.IsAbsoluteUri -or $IdentityUri.Scheme -notin @('https','http') -or $IdentityUri.UserInfo -or $IdentityUri.Query -or $IdentityUri.Fragment) { throw 'RUNTIME_URI_INVALID: use a dedicated endpoint without credentials, query or fragment' }
    $expectedBytes=[IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $ExpectedPath))
    $expectedHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($expectedBytes)).ToLowerInvariant()
    $expected=ConvertFrom-RuntimeJson ([Text.Encoding]::UTF8.GetString($expectedBytes).TrimStart([char]0xfeff))
    $nonce=[guid]::NewGuid().ToString('N')
    $request=[uri]($IdentityUri.AbsoluteUri+'?challenge='+$nonce)
    $at=[DateTimeOffset]::UtcNow.ToString('o')
    # 禁止重定向以免观察了另一目标；不记录请求 URI 或原始错误响应。
    try { $response=Invoke-WebRequest -Uri $request -Method Get -TimeoutSec $TimeoutSeconds -MaximumRedirection 0 -Headers @{'Cache-Control'='no-cache'} -ErrorAction Stop }
    catch { throw 'RUNTIME_OBSERVATION_UNAVAILABLE: endpoint failed; runtime identity is unverified' }
    $observed=ConvertFrom-RuntimeJson $response.Content
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

# 场景必须回传本次运行独有的前后探针，不能用旧文件或单独HTTP观察替代。
function Assert-ScenarioRuntimeEvidence {
    param([string]$Path,[string]$RunId,$Observation,[int]$ExitCode,[Parameter(Mandatory)][string]$LogicServerId)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'SCENARIO_RUNTIME_EVIDENCE_MISSING' }
    if ((Get-Item -LiteralPath $Path).Length -gt 65536) { throw 'SCENARIO_RUNTIME_EVIDENCE_INVALID' }
    $result=ConvertFrom-RuntimeJson (Get-Content -LiteralPath $Path -Raw)
    if ($result.schemaVersion -cne '1.0' -or $result.runId -cne $RunId -or $result.status -cne 'PROBES_MATCH' -or
        $result.scope -cne 'AUTHENTICATED_GAME_NODE_PROBES' -or $result.scenarioSucceeded -isnot [bool] -or
        $result.scenarioSucceeded -ne ($ExitCode -eq 0)) { throw 'SCENARIO_RUNTIME_EVIDENCE_INVALID' }
    foreach ($point in @('before','after')) {
        $actual=$result[$point]
        if ($actual.challenge -cnotmatch '^[0-9a-f]{32}$' -or $actual.playerId -cnotmatch '^[1-9][0-9]*$' -or
            [string]::IsNullOrWhiteSpace($actual.logicServerId) -or $actual.logicServerId -cne $LogicServerId) { throw 'SCENARIO_RUNTIME_BINDING_INVALID' }
        foreach ($key in @('schemaVersion','targetId','buildId','sourceDigest','artifactSha256','configSha256','protocolSha256','dataNamespace','instanceId','startedAt')) {
            if ($actual[$key] -cne $Observation.identity[$key]) { throw "SCENARIO_RUNTIME_MISMATCH:$key" }
        }
    }
    if ($result.before.challenge -ceq $result.after.challenge -or $result.before.playerId -cne $result.after.playerId -or
        $result.before.logicServerId -cne $result.after.logicServerId) { throw 'SCENARIO_RUNTIME_BINDING_CHANGED' }
    $safe=[ordered]@{scope=$result.scope;runId=$RunId;status=$result.status;scenarioSucceeded=$result.scenarioSucceeded}
    foreach ($point in @('before','after')) {
        $safe[$point]=[ordered]@{}
        foreach ($key in @('targetId','instanceId','startedAt','challenge','playerId','logicServerId')) { $safe[$point][$key]=$result[$point][$key] }
    }
    return $safe
}

# 与通过判定分离：失败或未完成也保留白名单证据，不将其提升为已核验。
function Read-ScenarioRuntimeEvidence {
    param([string]$Path,[string]$RunId)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return [ordered]@{status='MISSING';runId=$RunId} }
    try {
        if ((Get-Item -LiteralPath $Path).Length -gt 65536) { throw 'oversized' }
        $result=ConvertFrom-RuntimeJson (Get-Content -LiteralPath $Path -Raw)
        if ($result.schemaVersion -cne '1.0' -or $result.runId -cne $RunId -or $result.scope -cne 'AUTHENTICATED_GAME_NODE_PROBES' -or
            $result.status -cnotin @('STARTED','FAILED','PROBES_MATCH') -or $result.scenarioSucceeded -isnot [bool]) { throw 'invalid' }
        $safe=[ordered]@{scope=$result.scope;runId=$RunId;status=$result.status;scenarioSucceeded=$result.scenarioSucceeded}
        foreach ($point in @('before','after')) {
            $safe[$point]=$null
            if ($result[$point] -is [System.Collections.IDictionary]) {
                $safe[$point]=[ordered]@{}
                foreach ($key in @('targetId','instanceId','startedAt','challenge','playerId','logicServerId')) {
                    $value=$result[$point][$key]
                    if ($value -is [string] -and $value.Length -le 200 -and $value -notmatch '[\r\n]') { $safe[$point][$key]=$value }
                }
            }
        }
        return $safe
    } catch { return [ordered]@{status='INVALID';runId=$RunId} }
}
