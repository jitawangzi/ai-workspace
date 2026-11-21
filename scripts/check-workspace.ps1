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
    $scriptFiles=@(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File -Recurse) +
        @(Get-Item -LiteralPath (Join-Path $hostRoot 'run_client.ps1')) +
        @(Get-ChildItem -LiteralPath (Join-Path $aiRoot 'specs/scripts') -Filter '*.ps1' -File)
    foreach ($file in $scriptFiles) {
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
    function Get-MarkdownAnchors([string]$FilePath, [hashtable]$Cache) {
        if ($Cache.ContainsKey($FilePath)) { return $Cache[$FilePath] }
        $anchors = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $counts = @{}
        $inFence = $false
        foreach ($line in [IO.File]::ReadLines($FilePath)) {
            if ($line -match '^\s*(```|~~~)') { $inFence = -not $inFence; continue }
            if ($inFence) { continue }
            if ($line -match '^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$') {
                $heading = $Matches[1]
                # 去除行内 Markdown 链接与格式符号（保留标识符中的下划线 _），按 GFM 规则生成 slug
                $heading = [regex]::Replace($heading, '\[([^\]]+)\]\([^)]+\)', '$1')
                $heading = $heading -replace '[`*~]', ''
                $slug = $heading.Trim().ToLowerInvariant()
                $slug = [regex]::Replace($slug, '[^\p{L}\p{N}\s\-_]', '')
                $slug = $slug -replace ' ', '-'
                if ([string]::IsNullOrEmpty($slug)) { continue }
                if ($counts.ContainsKey($slug)) {
                    $counts[$slug]++
                    [void]$anchors.Add("$slug-$($counts[$slug])")
                } else {
                    $counts[$slug] = 0
                    [void]$anchors.Add($slug)
                }
            }
        }
        $Cache[$FilePath] = $anchors
        return $anchors
    }

    $anchorCache = @{}
    $documents = @(
        Get-Item -LiteralPath (Join-Path $hostRoot 'README.md')
        Get-ChildItem -LiteralPath (Join-Path $hostRoot 'doc') -File -Filter '*.md'
        Get-Item -LiteralPath (Join-Path $aiRoot 'README.md')
        Get-Item -LiteralPath (Join-Path $aiRoot 'specs/README.md')
        foreach ($directory in @('context', 'workflows', 'schemas')) {
            Get-ChildItem -LiteralPath (Join-Path $aiRoot $directory) -Recurse -File -Filter '*.md'
        }
    )
    foreach ($document in $documents) {
        $lines = [IO.File]::ReadLines($document.FullName)
        $inFence = $false
        $cleanLines = [System.Collections.Generic.List[string]]::new()
        foreach ($line in $lines) {
            if ($line -match '^\s*(```|~~~)') { $inFence = -not $inFence; continue }
            if (-not $inFence) { $cleanLines.Add($line) }
        }
        $body = $cleanLines -join "`n"
        # 校验非代码块内的 Markdown 文件链接与同文档/跨文档 #anchor 锚点。
        foreach ($match in [regex]::Matches($body, '(?<!!)\[[^\]\r\n]+\]\(([^)\r\n]+)\)')) {
            $link = $match.Groups[1].Value.Trim('<', '>')
            if ($link -match '^[A-Za-z][A-Za-z0-9+.-]*:') { continue }
            $parts = $link -split '#', 2
            $pathPart = [Uri]::UnescapeDataString($parts[0])
            $anchorPart = if ($parts.Count -gt 1) { [Uri]::UnescapeDataString($parts[1]) } else { '' }

            if ([string]::IsNullOrEmpty($pathPart)) {
                $targetPath = $document.FullName
            } else {
                $targetPath = Join-Path $document.DirectoryName $pathPart
                Assert-Contract (Test-Path -LiteralPath $targetPath) "Broken link in $($document.FullName): $link"
                $targetPath = (Get-Item -LiteralPath $targetPath).FullName
            }

            if (-not [string]::IsNullOrEmpty($anchorPart) -and (Test-Path -LiteralPath $targetPath -PathType Leaf) -and $targetPath.EndsWith('.md', [System.StringComparison]::OrdinalIgnoreCase)) {
                $anchors = Get-MarkdownAnchors -FilePath $targetPath -Cache $anchorCache
                Assert-Contract ($anchors.Contains($anchorPart)) "Broken anchor in $($document.FullName): $link"
            }
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
    Assert-Contract (($profiles.commands.'java-unit-smoke'.arguments -join ' ') -match 'run-java-tests.ps1.*core.*TagManagerTest') 'Java smoke profile must execute actual selected JUnit tests'
    foreach ($name in @('project-summary.md','coding-style.md','business-logic-pattern.md','project-tooling.md')) {
        Assert-Contract ((Get-Content -LiteralPath (Join-Path $aiRoot "context/$name") -First 1) -match '^<!-- context-meta .*reviewedAt:.*expiresAt:') "Missing freshness metadata: $name"
    }
    foreach ($repo in @($aiRoot,(Join-Path $aiRoot 'specs'))) {
        foreach ($relative in @('commit.cmd','pull.cmd','scripts/sync-repository.ps1')) {
            Assert-Contract (Test-Path -LiteralPath (Join-Path $repo $relative) -PathType Leaf) "Missing sync entry: $repo/$relative"
        }
    }
    Assert-Contract ([IO.File]::ReadAllText((Join-Path $hostRoot 'export_api.bat')).Contains('.ai-workspace\context\api-whitelist.md')) 'API export still targets inactive context'
    & pwsh -NoProfile -File (Join-Path $hostRoot 'tools/ai-sop/install-ai-sop.ps1') -Mode Git -Action Verify -WorkspaceRoot $hostRoot -OutputFormat Json
    Assert-Contract ($LASTEXITCODE -eq 0) 'Installed SOP projections or version lock are inconsistent'
}
Write-Output "$Mode PASS: $checked checks; scope=AI workspace only"
