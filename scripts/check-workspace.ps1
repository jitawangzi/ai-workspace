#requires -Version 7.0
<#
.SYNOPSIS
    只读检查工作区脚本/配置或迁移契约，不替代 Java 编译与业务测试。
.PARAMETER Mode
    Syntax 校验 PowerShell 语法、JSON 及验证命令 Schema；Contract 校验目录、链接、项目适配及安装一致性。
#>
[CmdletBinding()]
param([ValidateSet('Syntax', 'Contract')][string]$Mode = 'Contract')
$ErrorActionPreference = 'Stop'
$aiRoot = Split-Path -Parent $PSScriptRoot
$hostRoot = Split-Path -Parent $aiRoot
. (Join-Path $hostRoot '.ai-sop/scripts/path-identity.ps1')
$aiRoot = Resolve-PhysicalPathIdentity $aiRoot
$hostRoot = Resolve-PhysicalPathIdentity $hostRoot
$checked = 0

function Assert-Contract([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:checked++
}

if ($Mode -eq 'Syntax') {
    # 解析而不执行新增脚本，避免检查过程启动服务或改业务数据。
    foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File -Recurse) {
        $parseTokens = $null
        $parseErrors = $null
        [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$parseTokens, [ref]$parseErrors) | Out-Null
        Assert-Contract ($parseErrors.Count -eq 0) "PowerShell parse failed: $($file.FullName): $parseErrors"
    }
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $aiRoot 'context') -Filter '*.json' -File -Recurse) {
        $body = [IO.File]::ReadAllText($file.FullName)
        Assert-Contract (Test-Json -Json $body) "Invalid JSON: $($file.FullName)"
    }
    $profilePath = Join-Path $aiRoot 'context/verification-commands.json'
    $schemaPath = Join-Path $hostRoot '.ai-sop/schemas/verification-commands.schema.json'
    Assert-Contract (Test-Json -Json ([IO.File]::ReadAllText($profilePath)) -SchemaFile $schemaPath) 'Verification profiles violate engine Schema'
    $policyPath = Join-Path $aiRoot 'context/verification-inputs.json'
    $policySchema = Join-Path $hostRoot '.ai-sop/schemas/verification-inputs.schema.json'
    Assert-Contract (Test-Json -Json ([IO.File]::ReadAllText($policyPath)) -SchemaFile $policySchema) 'Verification input policy violates engine Schema'
} else {
    foreach ($relative in @('context', 'schemas', 'scripts', 'specs', 'workflows')) {
        Assert-Contract (Test-Path -LiteralPath (Join-Path $aiRoot $relative) -PathType Container) "Missing directory: $relative"
    }
    foreach ($relative in @('project-summary.md', 'coding-style.md', 'ai-coding.md', 'api-whitelist.md', 'client-test.md', 'config-rules.md', 'proto-rules.md', 'systems/condition-system.md')) {
        Assert-Contract (Test-Path -LiteralPath (Join-Path $aiRoot "context/$relative") -PathType Leaf) "Legacy knowledge missing: $relative"
    }
    $documents = @(
        Get-Item -LiteralPath (Join-Path $aiRoot 'README.md')
        foreach ($directory in @('context', 'workflows', 'schemas')) {
            Get-ChildItem -LiteralPath (Join-Path $aiRoot $directory) -Recurse -File -Filter '*.md'
        }
    )
    foreach ($document in $documents) {
        $body = [IO.File]::ReadAllText($document.FullName)
        # 只校验实际 Markdown 文件链接；代码内的占位命令不作为可点击路径。
        foreach ($match in [regex]::Matches($body, '\[[^\]\r\n]+\]\(([^)\r\n]+)\)')) {
            $link = $match.Groups[1].Value.Trim('<', '>')
            if ($link -match '^[A-Za-z][A-Za-z0-9+.-]*:|^#') { continue }
            $pathPart = [Uri]::UnescapeDataString(($link -split '#', 2)[0])
            $target = Join-Path $document.DirectoryName $pathPart
            Assert-Contract (Test-Path -LiteralPath $target) "Broken link in $($document.FullName): $link"
        }
    }
    $style = [IO.File]::ReadAllText((Join-Path $aiRoot 'context/coding-style.md'))
    Assert-Contract ($style.Contains('## Part A.') -and $style.Contains('## Part B.')) 'Coding rules lost the portable/project distinction'
    Assert-Contract ($style.Contains('至少使用 `warn`') -and $style.Contains('中文注释')) 'Recent comment/logging experience is missing'
    Assert-Contract ($style.Contains('定时全量保存') -and $style.Contains('DbEntity')) 'Persistence adaptation is missing'
    $contextText = (Get-ChildItem -LiteralPath (Join-Path $aiRoot 'context') -Recurse -File -Filter '*.md' | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
    Assert-Contract ($contextText -notmatch 'com\.joyfort|AirParam|ServerEntrance|updateAirData|AbsSinglePlayerModelMongoDao|AirExcelConfig|air_test_protocol\.jsp') 'Reference-project APIs leaked into active context'
    Assert-Contract ($contextText -notmatch 'D:\\work-all\\work_2025|\]\(human-sop\.md\)|\]\(protocol\.md\)') 'Obsolete paths survived migration'
    $profiles = Get-Content -LiteralPath (Join-Path $aiRoot 'context/verification-commands.json') -Raw | ConvertFrom-Json
    Assert-Contract (($profiles.commands.compile.arguments -join ' ') -match 'mvn.*compile') 'Java compile profile must invoke Maven'
    & pwsh -NoProfile -File (Join-Path $hostRoot 'tools/ai-sop/install-ai-sop.ps1') -Mode Git -Action Verify -WorkspaceRoot $hostRoot -OutputFormat Json
    Assert-Contract ($LASTEXITCODE -eq 0) 'Installed SOP projections or version lock are inconsistent'
}
Write-Output "$Mode PASS: $checked checks; scope=AI workspace only"
