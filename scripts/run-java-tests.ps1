#requires -Version 7.0
<#
.SYNOPSIS
    显式使用支持 JUnit 5 的 Surefire 执行测试，拒绝零执行和旧报告。
.PARAMETER Project
    可选 reactor 模块，传入时同时编译依赖。
.PARAMETER Test
    可选 Surefire 测试选择器；省略时执行所选模块的全部测试。
#>
[CmdletBinding()]
param([string]$Project,[string]$Test)
$ErrorActionPreference='Stop'
$hostRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
[xml]$pom=Get-Content -LiteralPath (Join-Path $hostRoot 'pom.xml') -Raw
$modules=@($pom.project.modules.module | ForEach-Object { [string]$_ })
function Get-TestReports {
    foreach ($module in $modules) {
        $dir=Join-Path $hostRoot "$module/target/surefire-reports"
        if (Test-Path -LiteralPath $dir) { Get-ChildItem -LiteralPath $dir -File -Filter 'TEST-*.xml' }
    }
}
$before=@{}
foreach ($file in Get-TestReports) { $before[$file.FullName]=$file.LastWriteTimeUtc.Ticks }
$mavenArgs=@('-B','-DskipTests=false','-Dmaven.test.skip=false','-Dsurefire.failIfNoSpecifiedTests=false')
if ($Project) { $mavenArgs+=@('-pl',$Project,'-am') }
if ($Test) { $mavenArgs+="-Dtest=$Test" }
$mavenArgs+=@('test-compile','org.apache.maven.plugins:maven-surefire-plugin:3.5.2:test')
Push-Location $hostRoot
try {
    & mvn @mavenArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $executed=0; $failed=0; $reports=0
    foreach ($file in Get-TestReports) {
        if ($before.ContainsKey($file.FullName) -and $before[$file.FullName] -eq $file.LastWriteTimeUtc.Ticks) { continue }
        [xml]$report=Get-Content -LiteralPath $file.FullName -Raw
        foreach ($suite in $report.SelectNodes('//testsuite')) {
            $executed += [int]$suite.tests - [int]$suite.skipped
            $failed += [int]$suite.failures + [int]$suite.errors
        }
        $reports++
    }
    if ($executed -le 0 -or $reports -le 0) { throw 'JAVA_TESTS_NOT_EXECUTED: 本轮没有新的实际执行报告，不能以 BUILD SUCCESS 作为测试通过。' }
    if ($failed -ne 0) { throw "JAVA_TESTS_FAILED: $failed failures/errors" }
    Write-Output "JAVA_TESTS_PASS: executed=$executed reports=$reports selector=$Test project=$Project"
} finally { Pop-Location }
