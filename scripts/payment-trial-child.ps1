#requires -Version 7.0
<#
.SYNOPSIS
    正式支付反证的内部子进程入口；必须由独立 pwsh 调用，环境变更只作用于该进程及后代。
.PARAMETER Mode
    Initialize 创建空本地仓库；Test 核对仓库身份后调用副本 Java 运行器。
.PARAMETER Root
    由正式入口创建的独占源码副本绝对路径。
.PARAMETER ExpectedTestsFile
    Test 使用的精确方法清单。
#>
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Initialize','Test')][string]$Mode,
    [Parameter(Mandatory)][string]$Root,[string]$ExpectedTestsFile)
$ErrorActionPreference='Stop'
$Root=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Root)
# -C 不覆盖 GIT_DIR/WORK_TREE/INDEX_FILE 等；在任何 Git 或 Maven 启动前清除全部继承的 Git 变量。
foreach($entry in Get-ChildItem Env: | Where-Object Name -like 'GIT_*'){
    Remove-Item -LiteralPath ('Env:'+$entry.Name) -ErrorAction Stop
}
$settings=Join-Path $Root '.trial-git'
$emptyConfig=Join-Path $settings 'empty.config'
$template=Join-Path $settings 'empty-template'
if($Mode -eq 'Initialize'){
    if(Test-Path -LiteralPath (Join-Path $Root '.git')){throw 'FIXTURE_GIT_ALREADY_EXISTS'}
    New-Item -ItemType Directory -Path $settings -ErrorAction Stop|Out-Null
    New-Item -ItemType Directory -Path $template -ErrorAction Stop|Out-Null
    [IO.File]::WriteAllText($emptyConfig,'')
}
if(-not [IO.File]::Exists($emptyConfig) -or (Get-Item -LiteralPath $emptyConfig).Length -ne 0){throw 'FIXTURE_GIT_CONFIG_INVALID'}
# 禁止用户/系统配置和模板引入外部 worktree、索引或 hooks；不改变调用者的配置。
$env:GIT_CONFIG_NOSYSTEM='1';$env:GIT_CONFIG_GLOBAL=$emptyConfig;$env:GIT_CONFIG_SYSTEM=$emptyConfig
$env:GIT_TEMPLATE_DIR=$template
if($Mode -eq 'Initialize'){
    & git -C $Root init --quiet "--template=$template"
    if($LASTEXITCODE){throw 'FIXTURE_GIT_INIT_FAILED'}
}
# 初始化提交及每次 Maven 前均检查真实仓库位置，不以源码摘要代替仓库身份。
$gitDirectory=& git -C $Root rev-parse --absolute-git-dir
if($LASTEXITCODE){throw 'FIXTURE_GIT_DIRECTORY_UNKNOWN'}
$workTree=& git -C $Root rev-parse --show-toplevel
if($LASTEXITCODE){throw 'FIXTURE_GIT_WORKTREE_UNKNOWN'}
$comparison=if([OperatingSystem]::IsWindows()){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
if(-not [string]::Equals([IO.Path]::GetFullPath($gitDirectory),[IO.Path]::GetFullPath((Join-Path $Root '.git')),$comparison) -or
   -not [string]::Equals([IO.Path]::GetFullPath($workTree),[IO.Path]::GetFullPath($Root),$comparison)){throw 'FIXTURE_GIT_IDENTITY_MISMATCH'}
if($Mode -eq 'Initialize'){
    & git -C $Root -c user.name=Fixture -c user.email=fixture@localhost -c commit.gpgsign=false commit --allow-empty --no-verify -m 'isolated build fixture' --quiet
    if($LASTEXITCODE){throw 'FIXTURE_GIT_COMMIT_FAILED'}
}
$head=& git -C $Root rev-parse HEAD
if($LASTEXITCODE){throw 'FIXTURE_GIT_HEAD_UNKNOWN'}
$tracked=@(& git -C $Root ls-tree -r --name-only HEAD)
if($LASTEXITCODE -or $tracked.Count){throw 'FIXTURE_GIT_NOT_EMPTY'}
$identityFile=Join-Path $settings 'identity.json'
if($Mode -eq 'Initialize'){
    @{gitDirectory=$gitDirectory;workTree=$workTree;head=$head;trackedFiles=0;inheritedGitEnvironmentCleared=$true}|ConvertTo-Json|Set-Content -LiteralPath $identityFile
} else {
    $identity=Get-Content -LiteralPath $identityFile -Raw|ConvertFrom-Json
    if($identity.head -cne $head){throw 'FIXTURE_GIT_HEAD_CHANGED'}
    & (Join-Path $Root '.ai-workspace/scripts/run-java-tests.ps1') -Project game -Test PaymentIdempotencyTest -ExpectedTestsFile $ExpectedTestsFile
    exit $LASTEXITCODE
}
