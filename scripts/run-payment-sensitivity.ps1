#requires -Version 7.0
<#
.SYNOPSIS
    在新源码副本中执行支付凭证反证；保留原版、两个独立变异及恢复版的原始材料。
.PARAMETER Workspace
    源宿主；相对路径按调用者 PowerShell 位置解析，永不修改源树。
.PARAMETER OutputPath
    本轮不存在的材料目录；建议位于任务 evidence 下。隔离源码放入独立临时目录并保留。
#>
[CmdletBinding()]
param([string]$Workspace=(Split-Path (Split-Path $PSScriptRoot)),[Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
$Workspace=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Workspace)
$output=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if(Test-Path -LiteralPath $output){throw 'OUTPUT_ALREADY_EXISTS'}
. (Join-Path $Workspace '.ai-sop/scripts/hidden-process.ps1')
. (Join-Path $PSScriptRoot 'payment-trial-result.ps1')
# 每次创建独占副本；不接受外部提供的可变源码根，避免误变异工作区或复用旧报告。
$root=Join-Path ([IO.Path]::GetTempPath()) ('payment-sensitivity-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
New-Item -ItemType Directory -Path $output -ErrorAction Stop|Out-Null
$files=[Collections.Generic.List[object]]::new()
$paths=@('pom.xml','.ai-workspace/scripts/run-java-tests.ps1','.ai-workspace/scripts/java-test-evidence.ps1')
foreach($module in @('util','protocol','core','game','login','simulationclient')){
    $paths+="$module/pom.xml"
    $base=Join-Path $Workspace "$module/src"
    if(Test-Path -LiteralPath $base){
        foreach($entry in Get-ChildItem -LiteralPath $base -Recurse -Force){
            if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "LINKED_INPUT_UNSUPPORTED: $($entry.FullName)"}
            if(-not $entry.PSIsContainer){$paths+=[IO.Path]::GetRelativePath($Workspace,$entry.FullName).Replace('\','/')}
        }
    }
}
foreach($path in $paths){
    $from=Join-Path $Workspace $path;$to=Join-Path $root $path
    [IO.Directory]::CreateDirectory((Split-Path $to))|Out-Null
    Copy-Item -LiteralPath $from -Destination $to
    $hash=(Get-FileHash -LiteralPath $from).Hash.ToLowerInvariant()
    if((Get-FileHash -LiteralPath $to).Hash.ToLowerInvariant() -cne $hash){throw "COPY_DRIFT: $path"}
    $files.Add(@{path=$path;sha256=$hash})
}
$snapshot=@{root=$root;source=$Workspace;files=$files.ToArray();kind='source copy, not clean checkout'}
$snapshot|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $output 'trial-inputs.json')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../context/test-suites/payment-sensitivity.json') -Destination (Join-Path $output 'payment-expected.json')
# Git 与 Maven 共用独立子进程边界，不在调用者进程中清空/恢复全局环境。
$childEntry=Join-Path $PSScriptRoot 'payment-trial-child.ps1'
$gitChild=Start-AiSopHiddenProcess -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile','-File',$childEntry,'-Mode','Initialize','-Root',$root) -RedirectStandardOutput (Join-Path $output 'git.stdout.log') -RedirectStandardError (Join-Path $output 'git.stderr.log') -TimeoutSeconds 60 -CloseStandardInput -PassThru
try{$gitChild.WaitForExit()}finally{$gitChild.Dispose()}
@{exitCode=$gitChild.ExitCode;rawExitCode=$gitChild.RawExitCode;failureCode=$gitChild.FailureCode;diagnostic=$gitChild.Diagnostic;completed=$gitChild.Completed;disposed=$gitChild.Disposed;exitKnown=$gitChild.ExitKnown;cleanup=$gitChild.Cleanup}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $output 'git-process.json')
Assert-TrialProcessResult -Handle $gitChild -Stage baseline
Copy-Item -LiteralPath (Join-Path $root '.trial-git/identity.json') -Destination (Join-Path $output 'git-isolation.json')
$source=Join-Path $root 'game/src/main/java/cn/game/games/net/game/module/recharge/PayItem.java'
$original=[IO.File]::ReadAllBytes($source)
$text=[Text.Encoding]::UTF8.GetString($original)
$runs=[Collections.Generic.List[object]]::new()
try {
    foreach($stage in @('baseline','early-proof','wrong-identity','restored')) {
        $modified=$text
        if($stage -eq 'early-proof'){$modified=$text.Replace('!proofAwaitingCommit && isFinish','isFinish')}
        if($stage -eq 'wrong-identity'){$modified=$text.Replace('&& completionProof.equals(proofFor(playerId))','&& true')}
        if($stage -in @('early-proof','wrong-identity') -and $modified -ceq $text){throw 'MUTATION_NOT_APPLIED'}
        [IO.File]::WriteAllText($source,$modified,[Text.UTF8Encoding]::new($false))
        $out=Join-Path $output $stage
        [IO.Directory]::CreateDirectory($out)|Out-Null
        Copy-Item -LiteralPath $source -Destination (Join-Path $out 'PayItem.java')
        $report=Join-Path $root 'game/target/surefire-reports/TEST-cn.game.games.net.game.helper.PaymentIdempotencyTest.xml'
        # 只删除隔离副本中这个报告，确保本轮失败不能误用旧报告。
        if([IO.File]::Exists($report)){[IO.File]::Delete($report)}
        $child=Start-AiSopHiddenProcess -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile','-File',$childEntry,'-Mode','Test','-Root',$root,'-ExpectedTestsFile',(Join-Path $output 'payment-expected.json')) -Environment @{AI_SOP_INVOCATION_SESSION_ID=$null} -RedirectStandardOutput (Join-Path $out 'stdout.log') -RedirectStandardError (Join-Path $out 'stderr.log') -TimeoutSeconds 1800 -HeartbeatSeconds 30 -Label $stage -CloseStandardInput -PassThru
        try{$child.WaitForExit()}finally{$child.Dispose()}
        $code=$child.ExitCode
        @{exitCode=$code;rawExitCode=$child.RawExitCode;failureCode=$child.FailureCode;diagnostic=$child.Diagnostic;completed=$child.Completed;disposed=$child.Disposed;exitKnown=$child.ExitKnown;cleanup=@{confirmed=$child.Cleanup.confirmed;exited=$child.Cleanup.exited;exitCode=$child.Cleanup.exitCode;diagnostic=$child.Cleanup.diagnostic}}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $out 'process.json')
        Assert-TrialProcessResult -Handle $child -Stage $stage
        if(-not [IO.File]::Exists($report)){throw "NO_FRESH_REPORT: $stage exit=$code"}
        Copy-Item -LiteralPath $report -Destination (Join-Path $out 'junit.xml')
        $result=Assert-PaymentTrialReport -Report $report -Stage $stage
        $runs.Add(@{stage=$stage;exitCode=$code;tests=$result.tests;failedMethods=$result.failedMethods;sourceSha256=(Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant();outcome='EXPECTED_RESULT'})
        ConvertTo-Json -InputObject @($runs.ToArray()) -Depth 6|Set-Content -LiteralPath (Join-Path $output 'trial-results.json')
        Write-Output "TRIAL_PASS $stage exit=$code methods=$($result.tests)"
    }
} finally {
    [IO.File]::WriteAllBytes($source,$original)
    $drift=[Collections.Generic.List[string]]::new()
    foreach($entry in $snapshot.files){
        foreach($base in @($root,$Workspace)){
            $path=Join-Path $base $entry.path
            if(-not [IO.File]::Exists($path) -or (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $entry.sha256){$drift.Add($path)}
        }
    }
    @{restored=($drift.Count -eq 0);files=$files.Count;root=$root;sourceAndCopyMatch=($drift.Count -eq 0);drift=$drift.ToArray()}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $output 'restoration.json')
    if($drift.Count){throw "TRIAL_INPUT_DRIFT_AFTER: $($drift -join ',')"}
}
