#requires -Version 7.0
# 用报告夹具验证门禁本身；真实 Java 执行另由 java-unit-smoke 验证。
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'java-test-evidence.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('java-evidence-' + [guid]::NewGuid().ToString('N'))
$checks = 0

function Assert-EvidenceCheck {
    <#
    .SYNOPSIS
        验证断言成立，否则使整个回归脚本失败。
    .PARAMETER Condition
        本次判定的实际结果。
    .PARAMETER Message
        失败时用于定位场景的说明。
    #>
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
    $script:checks++
}

function Assert-EvidenceFailure {
    <#
    .SYNOPSIS
        确认实际门禁抛出指定错误，不将测试代码自身的断言异常当成通过。
    .PARAMETER Action
        被测报告或清单读取入口。
    .PARAMETER Code
        预期错误标识。
    #>
    param([scriptblock]$Action, [string]$Code)
    $failure = $null
    try { & $Action | Out-Null }
    catch {
        $failure = $_
        Write-Warning "预期拒绝场景：$($_.Exception)`n$($_.ScriptStackTrace)"
    }
    Assert-EvidenceCheck ($null -ne $failure -and $failure.Exception.Message.Contains($Code)) "未得到预期错误 $Code，实际为 $failure"
}

function Write-EvidenceReport {
    <#
    .SYNOPSIS
        创建本轮独有的报告文件，不接触宿主 Surefire 产物。
    .PARAMETER Body
        完整 XML 报告内容。
    .OUTPUTS
        新报告的 FileInfo。
    #>
    param([string]$Body)
    $file = Join-Path $fixture ('TEST-' + [guid]::NewGuid().ToString('N') + '.xml')
    [IO.File]::WriteAllText($file, $Body)
    Get-Item -LiteralPath $file
}

try {
    [IO.Directory]::CreateDirectory($fixture) | Out-Null
    $good = Write-EvidenceReport '<testsuite tests="2" skipped="0" failures="0" errors="0"><testcase classname="example.Target" name="required"/><testcase classname="example.Target" name="other"/></testsuite>'
    $unrelated = Write-EvidenceReport '<testsuite tests="1" skipped="0" failures="0" errors="0"><testcase classname="example.Other" name="passes"/></testsuite>'
    $result = Assert-JavaTestEvidence -ReportFiles @($good) -ExpectedTests @('example.Target','example.Target#required')
    Assert-EvidenceCheck ($result.Executed -eq 2 -and $result.Expected -eq 2) '类与方法的执行数不正确'
    $result = Assert-JavaTestEvidence -ReportFiles @($good)
    Assert-EvidenceCheck ($result.Executed -eq 2 -and $result.Expected -eq 0) '未传清单的兼容入口失败'
    Assert-EvidenceFailure { Assert-JavaTestEvidence @($unrelated) -ExpectedTests 'example.Target' } 'JAVA_EXPECTED_TEST_MISSING'
    Assert-EvidenceFailure { Assert-JavaTestEvidence @($good) -ExpectedTests 'example.Target#missing' } 'JAVA_EXPECTED_TEST_MISSING'
    Assert-EvidenceFailure { Assert-JavaTestEvidence @($good) -ExpectedTests 'example.Target#Required' } 'JAVA_EXPECTED_TEST_MISSING'

    $skipped = Write-EvidenceReport '<testsuite tests="2" skipped="1" failures="0" errors="0"><testcase classname="example.Target" name="required"><skipped/></testcase><testcase classname="example.Target" name="other"/></testsuite>'
    Assert-EvidenceFailure { Assert-JavaTestEvidence @($skipped) -ExpectedTests 'example.Target#required' } 'JAVA_EXPECTED_TEST_SKIPPED'
    $allSkipped = Write-EvidenceReport '<testsuite tests="1" skipped="1" failures="0" errors="0"><testcase classname="example.Target" name="required"><skipped/></testcase></testsuite>'
    Assert-EvidenceFailure { Assert-JavaTestEvidence @($allSkipped,$unrelated) -ExpectedTests 'example.Target' } 'JAVA_EXPECTED_TEST_SKIPPED'
    Assert-EvidenceFailure { Assert-JavaTestEvidence @($allSkipped) } 'JAVA_TESTS_NOT_EXECUTED'
    $failed = Write-EvidenceReport '<testsuite tests="1" skipped="0" failures="1" errors="0"><testcase classname="example.Target" name="required"><failure message="assertion"/></testcase></testsuite>'
    Assert-EvidenceFailure { Assert-JavaTestEvidence @($failed,$unrelated) } 'JAVA_TESTS_FAILED'
    $suiteError = Write-EvidenceReport '<testsuite tests="1" skipped="0" failures="0" errors="1"><testcase classname="example.Target" name="required"/></testsuite>'
    Assert-EvidenceFailure { Assert-JavaTestEvidence @($suiteError) } 'JAVA_TESTS_FAILED'

    $before = @{}; $before[$good.FullName] = $good.LastWriteTimeUtc.Ticks
    Assert-EvidenceFailure { Assert-JavaTestEvidence @($good,$unrelated) -Before $before -ExpectedTests 'example.Target#required' } 'JAVA_EXPECTED_TEST_MISSING'
    Assert-EvidenceFailure { Assert-JavaTestEvidence @($good) -Before $before } 'JAVA_TESTS_NOT_EXECUTED'
    Assert-EvidenceFailure { Assert-JavaTestEvidence @() } 'JAVA_TESTS_NOT_EXECUTED'
    $empty = Write-EvidenceReport '<testsuite tests="5" skipped="0" failures="0" errors="0"/>'
    Assert-EvidenceFailure { Assert-JavaTestEvidence @($empty) } 'JAVA_TESTS_NOT_EXECUTED'

    $parameterized = Write-EvidenceReport '<testsuite tests="2" skipped="0" failures="0" errors="0"><testcase classname="example.Target$Nested" name="required(String)[1]"/><testcase classname="example.Target$Nested" name="required(String)[2]"/></testsuite>'
    $result = Assert-JavaTestEvidence @($parameterized) -ExpectedTests 'example.Target$Nested#required'
    Assert-EvidenceCheck ($result.Executed -eq 2) '参数化调用未按目标方法核对'
    $partialSkip = Write-EvidenceReport '<testsuite tests="2" skipped="1" failures="0" errors="0"><testcase classname="example.Target" name="required(String)[1]"/><testcase classname="example.Target" name="required(String)[2]"><skipped/></testcase></testsuite>'
    Assert-EvidenceFailure { Assert-JavaTestEvidence @($partialSkip) -ExpectedTests 'example.Target#required' } 'JAVA_EXPECTED_TEST_SKIPPED'

    $manifest = Join-Path $fixture 'expected.json'
    [IO.File]::WriteAllText($manifest, '["example.Target$Nested#required","example.Target"]')
    Assert-EvidenceCheck (@(Read-ExpectedJavaTests $manifest).Count -eq 2) '合法目标清单未正确读取'
    Assert-EvidenceCheck (@(Read-ExpectedJavaTests '').Count -eq 0) '未配置目标应沿用原门禁'
    foreach ($invalid in @('[]','{}','[1]','["example.Target "]','["example.Target#"]')) {
        [IO.File]::WriteAllText($manifest, $invalid)
        Assert-EvidenceFailure { Read-ExpectedJavaTests $manifest } 'JAVA_EXPECTATIONS_INVALID'
    }
    Write-Output "JAVA_EVIDENCE_TESTS_PASS: checks=$checks; scope=report validation only"
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    if ($resolvedFixture.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolvedFixture) -like 'java-evidence-*') {
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    }
}
