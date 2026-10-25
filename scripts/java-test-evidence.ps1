#requires -Version 7.0
# 将报告核对与 Maven 调用分离，便于验证目标缺失、跳过和旧报告不能被其他用例的成功掩盖。

function Read-ExpectedJavaTests {
    <#
    .SYNOPSIS
        读取可选的目标清单，在构建前拒绝空清单或无效条目。
    .PARAMETER Path
        JSON 字符串数组文件；条目为完整类名或完整类名#方法名，空路径表示沿用原有汇总校验。
    .OUTPUTS
        已校验的目标字符串；方法名使用 Surefire 报告名称或不带参数的 Java 方法名。
    #>
    param([string]$Path)
    if (-not $Path) { return }
    $items = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path)) -NoEnumerate
    if ($items -isnot [array] -or $items.Count -eq 0) {
        throw 'JAVA_EXPECTATIONS_INVALID: 目标清单必须为非空 JSON 字符串数组。'
    }
    foreach ($item in $items) {
        if ($item -isnot [string] -or $item -notmatch '^[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)+(?:#[^#\r\n]+)?$' -or $item -cne $item.Trim()) {
            throw "JAVA_EXPECTATIONS_INVALID: 无效目标 $item"
        }
        $item
    }
}

function Assert-JavaTestEvidence {
    <#
    .SYNOPSIS
        核对本轮新报告的真实用例及目标执行情况，不将汇总成功当成目标方法已执行。
    .PARAMETER ReportFiles
        Maven 完成后的 Surefire XML 文件集合。
    .PARAMETER Before
        调用 Maven 前按文件绝对路径保存的 LastWriteTimeUtc.Ticks。
    .PARAMETER ExpectedTests
        可选目标清单。类目标至少实际执行一个用例；方法目标的所有匹配调用均不得跳过。
    .OUTPUTS
        实际执行数、使用的新报告数及已核对目标数；缺失、跳过或失败时抛出异常。
    #>
    param(
        [AllowEmptyCollection()][IO.FileInfo[]]$ReportFiles = @(),
        [System.Collections.IDictionary]$Before = @{},
        [AllowEmptyCollection()][string[]]$ExpectedTests = @()
    )
    $cases = [Collections.Generic.List[object]]::new()
    $reports = 0
    $suiteFailures = 0
    foreach ($file in $ReportFiles) {
        if ($Before.Contains($file.FullName) -and $Before[$file.FullName] -eq $file.LastWriteTimeUtc.Ticks) { continue }
        [xml]$report = [IO.File]::ReadAllText($file.FullName)
        foreach ($suite in $report.SelectNodes('//testsuite')) {
            $suiteFailures += [int]$suite.GetAttribute('failures') + [int]$suite.GetAttribute('errors')
        }
        foreach ($case in $report.SelectNodes('//testcase')) {
            $cases.Add([pscustomobject]@{
                Class = $case.GetAttribute('classname')
                Name = $case.GetAttribute('name')
                Skipped = $null -ne $case.SelectSingleNode('skipped')
                Failed = $null -ne $case.SelectSingleNode('failure|error')
            })
        }
        $reports++
    }
    $executed = @($cases | Where-Object { -not $_.Skipped }).Count
    if ($executed -le 0 -or $reports -le 0) {
        throw 'JAVA_TESTS_NOT_EXECUTED: 本轮没有新的实际执行用例，不能以 BUILD SUCCESS 作为测试通过。'
    }
    if ($suiteFailures -gt 0 -or @($cases | Where-Object Failed).Count -gt 0) {
        throw 'JAVA_TESTS_FAILED: 本轮报告含失败或错误。'
    }
    foreach ($expected in $ExpectedTests) {
        $parts = $expected -split '#', 2
        $matched = @($cases | Where-Object { $_.Class -ceq $parts[0] })
        if ($parts.Count -eq 2) {
            # 不带参数的方法名可匹配参数化调用；显式报告名称仍按大小写精确匹配。
            $matched = @($matched | Where-Object {
                $_.Name -ceq $parts[1] -or ($parts[1] -notmatch '[\(\[]' -and ($_.Name -replace '[\(\[].*$', '') -ceq $parts[1])
            })
        }
        if ($matched.Count -eq 0) { throw "JAVA_EXPECTED_TEST_MISSING: $expected" }
        if (@($matched | Where-Object { -not $_.Skipped }).Count -eq 0 -or ($parts.Count -eq 2 -and @($matched | Where-Object Skipped).Count -gt 0)) {
            throw "JAVA_EXPECTED_TEST_SKIPPED: $expected"
        }
    }
    [pscustomobject]@{ Executed = $executed; Reports = $reports; Expected = $ExpectedTests.Count }
}
