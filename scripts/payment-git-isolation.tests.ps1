#requires -Version 7.0
<# 真实 Git + 合成 Java 运行器；只操作自建仓库，成功/失败现场均保留。 #>
param([string]$Workspace=(Split-Path (Split-Path $PSScriptRoot)),[string]$EntryPath=(Join-Path $PSScriptRoot 'run-payment-sensitivity.ps1'))
$ErrorActionPreference='Stop'
$Workspace=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Workspace)
$EntryPath=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($EntryPath)
$root=Join-Path ([IO.Path]::GetTempPath()) ('payment-git-isolation-'+[guid]::NewGuid().ToString('N'))
$fixture=Join-Path $root workspace
$other=Join-Path $root other
$rows=[Collections.Generic.List[object]]::new()
# 夹具设置与观测也不能受启动回归时的 Git 环境重定向。
function Read-GitEnvironment {
    $values=[ordered]@{}
    foreach($entry in Get-ChildItem Env:|Where-Object Name -like 'GIT_*'|Sort-Object Name){$values[$entry.Name]=$entry.Value}
    return $values
}
function Clear-GitEnvironment {
    foreach($entry in Get-ChildItem Env:|Where-Object Name -like 'GIT_*'){Remove-Item -LiteralPath ('Env:'+$entry.Name) -ErrorAction Stop}
}
function Use-ControlGit {
    Clear-GitEnvironment
    $env:GIT_CONFIG_GLOBAL=Join-Path $root empty.config
    $env:GIT_CONFIG_NOSYSTEM='1';$env:GIT_TEMPLATE_DIR=Join-Path $root empty-template
}
function Invoke-FixtureGit([string[]]$Arguments) {
    $result=& git @Arguments
    if($LASTEXITCODE){throw "FIXTURE_GIT_FAILED: $($Arguments -join ' ')"}
    return $result
}
$saved=Read-GitEnvironment
$savedFailure=[Environment]::GetEnvironmentVariable('PAYMENT_GIT_FIXTURE_FAIL')
try {
    foreach($dir in @($root,$fixture,$other,(Join-Path $root empty-template),(Join-Path $fixture '.ai-sop/scripts'),(Join-Path $fixture '.ai-workspace/scripts'),(Join-Path $fixture 'game/src/main/java/cn/game/games/net/game/module/recharge'))){[IO.Directory]::CreateDirectory($dir)|Out-Null}
    [IO.File]::WriteAllText((Join-Path $root empty.config),'')
    Use-ControlGit
    $null=Invoke-FixtureGit @('-C',$other,'init','--quiet')
    [IO.File]::WriteAllText((Join-Path $other tracked.txt),'committed value')
    $null=Invoke-FixtureGit @('-C',$other,'add','--','tracked.txt')
    $null=Invoke-FixtureGit @('-C',$other,'-c','user.name=Fixture','-c','user.email=fixture@localhost','-c','commit.gpgsign=false','commit','--no-verify','-qm','baseline')
    [IO.File]::WriteAllText((Join-Path $other staged.txt),'must remain staged')
    $null=Invoke-FixtureGit @('-C',$other,'add','--','staged.txt')
    [IO.File]::WriteAllText((Join-Path $other tracked.txt),'must remain unstaged')
    $beforeHead=Invoke-FixtureGit @('-C',$other,'rev-parse','HEAD')
    $beforeStatus=@(Git @('-C',$other,'status','--porcelain=v1')) -join "`n"
    $beforeIndex=(Get-FileHash -LiteralPath (Join-Path $other '.git/index')).Hash
    $beforeWork=(Get-FileHash -LiteralPath (Join-Path $other tracked.txt)).Hash
    $beforeStaged=(Get-FileHash -LiteralPath (Join-Path $other staged.txt)).Hash
    foreach($module in @('util','protocol','core','game','login','simulationclient')){
        [IO.Directory]::CreateDirectory((Join-Path $fixture $module))|Out-Null
        [IO.File]::WriteAllText((Join-Path $fixture "$module/pom.xml"),'<project />')
    }
    [IO.File]::WriteAllText((Join-Path $fixture pom.xml),'<project />')
    [IO.File]::WriteAllText((Join-Path $fixture '.ai-workspace/scripts/java-test-evidence.ps1'),'# unused synthetic dependency')
    Copy-Item -LiteralPath (Join-Path $Workspace '.ai-sop/scripts/hidden-process.ps1') -Destination (Join-Path $fixture '.ai-sop/scripts/hidden-process.ps1')
    [IO.File]::WriteAllText((Join-Path $fixture 'game/src/main/java/cn/game/games/net/game/module/recharge/PayItem.java'),'!proofAwaitingCommit && isFinish && completionProof.equals(proofFor(playerId))')
    # 合成报告只验证 Git/进程边界，不冒充 Java 编译或支付业务结果。
    @'
param([string]$Project,[string]$Test,[string]$ExpectedTestsFile)
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot)
$actual=& git -C $root rev-parse --show-toplevel
if($LASTEXITCODE){throw 'SYNTHETIC_GIT_LOOKUP_FAILED'}
$names=@(Get-ChildItem Env:|Where-Object Name -like 'GIT_*'|Select-Object -ExpandProperty Name)
@{root=$root;gitRoot=$actual;gitNames=$names}|ConvertTo-Json -Compress|Add-Content -LiteralPath (Join-Path $root git-observations.jsonl)
if([IO.Path]::GetFullPath($actual) -cne [IO.Path]::GetFullPath($root) -or @($names|Where-Object {$_ -notin @('GIT_CONFIG_NOSYSTEM','GIT_CONFIG_SYSTEM','GIT_CONFIG_GLOBAL','GIT_TEMPLATE_DIR')}).Count){throw 'SYNTHETIC_GIT_ENV_LEAK'}
$text=Get-Content -LiteralPath (Join-Path $root 'game/src/main/java/cn/game/games/net/game/module/recharge/PayItem.java') -Raw
$names=@('concurrentAndRepeatedNotificationsSucceedOnlyAfterCommit','legacyAndUnprovenStatesRemainBlocked','proofRejectsIdentityProductAndAmountMismatch','versionedProofRoundTripAndOldJsonCompatibility','baselineJsonSchemaRejectsNewProofAndRequiresStoppedUpgrade')
$failed=@()
if(-not $text.Contains('!proofAwaitingCommit && isFinish')){$failed=@($names[0],$names[3])}
if(-not $text.Contains('&& completionProof.equals(proofFor(playerId))')){$failed=@($names[2],$names[3])}
$xml='<testsuite>'
foreach($name in $names){
    $xml+='<testcase classname="cn.game.games.net.game.helper.PaymentIdempotencyTest" name="'+$name+'">'
    if($name -in $failed){$xml+='<failure type="org.opentest4j.AssertionFailedError" message="expected: &lt;false&gt; but was: &lt;true&gt;" />'}
    $xml+='</testcase>'
}
$xml+='</testsuite>'
$reports=Join-Path $root 'game/target/surefire-reports'
[IO.Directory]::CreateDirectory($reports)|Out-Null
[IO.File]::WriteAllText((Join-Path $reports 'TEST-cn.game.games.net.game.helper.PaymentIdempotencyTest.xml'),$xml)
if($env:PAYMENT_GIT_FIXTURE_FAIL -eq '1'){exit 2}
if($failed.Count){exit 1}
exit 0
'@ | Set-Content -LiteralPath (Join-Path $fixture '.ai-workspace/scripts/run-java-tests.ps1')
    foreach($case in @('dir-worktree','all-redirections','failure')){
        Use-ControlGit
        $env:GIT_DIR=Join-Path $other '.git';$env:GIT_WORK_TREE=$other
        if($case -ne 'dir-worktree'){
            $env:GIT_COMMON_DIR=Join-Path $other '.git';$env:GIT_INDEX_FILE=Join-Path $other '.git/index'
            $env:GIT_OBJECT_DIRECTORY=Join-Path $other '.git/objects';$env:GIT_ALTERNATE_OBJECT_DIRECTORIES=Join-Path $other '.git/objects'
            $env:GIT_CONFIG_COUNT='1';$env:GIT_CONFIG_KEY_0='core.worktree';$env:GIT_CONFIG_VALUE_0=$other
            $env:GIT_CONFIG_PARAMETERS="'core.worktree=$other'"
        }
        $env:PAYMENT_GIT_FIXTURE_FAIL=if($case -eq 'failure'){'1'}else{'0'}
        $callerBefore=Read-GitEnvironment|ConvertTo-Json -Compress
        $output=Join-Path $root $case
        $failure=''
        try{& $EntryPath -Workspace $fixture -OutputPath $output}catch{$failure=$_.Exception.Message}
        $callerAfter=Read-GitEnvironment|ConvertTo-Json -Compress
        Use-ControlGit
        $afterHead=Invoke-FixtureGit @('-C',$other,'rev-parse','HEAD')
        $afterStatus=@(Git @('-C',$other,'status','--porcelain=v1')) -join "`n"
        $unchanged=$beforeHead -ceq $afterHead -and $beforeStatus -ceq $afterStatus -and
            $beforeIndex -ceq (Get-FileHash -LiteralPath (Join-Path $other '.git/index')).Hash -and
            $beforeWork -ceq (Get-FileHash -LiteralPath (Join-Path $other tracked.txt)).Hash -and
            $beforeStaged -ceq (Get-FileHash -LiteralPath (Join-Path $other staged.txt)).Hash
        $rows.Add(@{case=$case;failure=$failure;externalUnchanged=$unchanged;headBefore=$beforeHead;headAfter=$afterHead;callerEnvironmentUnchanged=($callerBefore -ceq $callerAfter);output=$output})
        if(-not $unchanged){throw 'EXTERNAL_REPOSITORY_CHANGED'}
        if($callerBefore -cne $callerAfter){throw 'CALLER_ENVIRONMENT_CHANGED'}
        if(($case -eq 'failure' -and $failure -notlike 'TRIAL_UNEXPECTED_EXIT:*') -or ($case -ne 'failure' -and $failure)){throw "WRONG_ENTRY_RESULT: $case $failure"}
        $snapshot=Get-Content -LiteralPath (Join-Path $output trial-inputs.json) -Raw|ConvertFrom-Json
        if(-not (Test-Path -LiteralPath (Join-Path $snapshot.root '.git'))){throw 'OWN_REPOSITORY_MISSING'}
        $observations=@(Get-Content -LiteralPath (Join-Path $snapshot.root git-observations.jsonl)|ForEach-Object {$_|ConvertFrom-Json})
        if($observations.Count -ne $(if($case -eq 'failure'){1}else{4})){throw 'SYNTHETIC_STAGE_MISSING'}
        $restored=Get-Content -LiteralPath (Join-Path $output restoration.json) -Raw|ConvertFrom-Json
        if(-not $restored.restored -or -not $restored.sourceAndCopyMatch){throw 'SOURCE_RESTORATION_FAILED'}
    }
    Write-Output "GIT_ISOLATION_PASS: 3 cases; external HEAD/index/status/worktree and caller environment unchanged; fixture=$root"
} finally {
    Clear-GitEnvironment
    foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}
    if($null -eq $savedFailure){Remove-Item -LiteralPath Env:PAYMENT_GIT_FIXTURE_FAIL -ErrorAction SilentlyContinue}else{Set-Item -LiteralPath Env:PAYMENT_GIT_FIXTURE_FAIL -Value $savedFailure}
    @{cases=$rows.ToArray();fixture=$root;scope='Real Git and PowerShell; synthetic Java reports; no Maven/DB'}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $root results.json)
    Write-Output "GIT_ISOLATION_RESULTS: $(Join-Path $root results.json)"
}
