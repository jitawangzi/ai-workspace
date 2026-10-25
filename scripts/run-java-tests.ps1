#requires -Version 7.0
<#
.SYNOPSIS
    显式使用支持 JUnit 5 的 Surefire 执行测试，拒绝零执行和旧报告。
.PARAMETER Project
    可选 reactor 模块，传入时同时编译依赖。
.PARAMETER Test
    可选 Surefire 测试选择器；省略时执行所选模块的全部测试。
.PARAMETER ExpectedTestsFile
    可选 JSON 目标清单；逐项核对完整类名或完整类名#方法名在本轮报告中实际执行。
#>
[CmdletBinding()]
param([string]$Project,[string]$Test,[string]$ExpectedTestsFile)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'java-test-evidence.ps1')
$expectedTests = @(Read-ExpectedJavaTests -Path $ExpectedTestsFile)
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
    $evidence = Assert-JavaTestEvidence -ReportFiles @(Get-TestReports) -Before $before -ExpectedTests $expectedTests
    Write-Output "JAVA_TESTS_PASS: executed=$($evidence.Executed) reports=$($evidence.Reports) expected=$($evidence.Expected) selector=$Test project=$Project"
} finally { Pop-Location }
