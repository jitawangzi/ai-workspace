param([string]$Workspace=(Split-Path (Split-Path $PSScriptRoot)), [string]$OutputPath)
$ErrorActionPreference='Stop'
. (Join-Path $Workspace '.ai-sop/scripts/hidden-process.ps1')
. (Join-Path $PSScriptRoot 'payment-trial-result.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('trial-result-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
$names=@('concurrentAndRepeatedNotificationsSucceedOnlyAfterCommit','legacyAndUnprovenStatesRemainBlocked','proofRejectsIdentityProductAndAmountMismatch','versionedProofRoundTripAndOldJsonCompatibility','baselineJsonSchemaRejectsNewProofAndRequiresStoppedUpgrade')
$fixture='<testsuite>'
foreach($name in $names){
    $fixture+='<testcase classname="cn.game.games.net.game.helper.PaymentIdempotencyTest" name="'+$name+'">'
    if($name -in @($names[0],$names[3])){$fixture+='<failure type="org.opentest4j.AssertionFailedError" message="expected: &lt;false&gt; but was: &lt;true&gt;" />'}
    $fixture+='</testcase>'
}
$fixture+='</testsuite>'
$fixturePath=Join-Path $root 'source.xml'
[IO.File]::WriteAllText($fixturePath,$fixture)
@'
param([string]$Source,[string]$Report,[int]$Code,[switch]$Hang)
$ErrorActionPreference='Stop'
Copy-Item -LiteralPath $Source -Destination $Report
if($Hang){Start-Sleep -Seconds 30}
exit $Code
'@|Set-Content -LiteralPath (Join-Path $root 'child.ps1')
$rows=[Collections.Generic.List[object]]::new()
foreach($case in @(@{name='assertion-exit-1';code=1;accept=$true},@{name='exit-0-with-failures';code=0;accept=$false},@{name='unrelated-exit-2';code=2;accept=$false},@{name='raw-exit-124';code=124;accept=$false},@{name='raw-exit-125';code=125;accept=$false},@{name='report-then-timeout';code=1;hang=$true;accept=$false})) {
    $report=Join-Path $root ($case.name+'.xml')
    $childArgs=@('-NoProfile','-File',(Join-Path $root 'child.ps1'),'-Source',$fixturePath,'-Report',$report,'-Code',[string]$case.code)
    if($case.hang){$childArgs+='-Hang'}
    $handle=Start-AiSopHiddenProcess -FilePath (Get-Process -Id $PID).Path -ArgumentList $childArgs -RedirectStandardOutput (Join-Path $root ($case.name+'.out')) -RedirectStandardError (Join-Path $root ($case.name+'.err')) -TimeoutSeconds $(if($case.hang){2}else{15}) -CloseStandardInput -PassThru
    try{$handle.WaitForExit()}finally{$handle.Dispose()}
    if(-not $handle.Cleanup.confirmed -or -not $handle.Cleanup.exited){throw ('FIXTURE_CLEANUP_UNCONFIRMED '+$case.name)}
    if(-not [IO.File]::Exists($report)){throw 'REPORT_WAS_NOT_WRITTEN'}
    $stage='early-proof';$code=$handle.ExitCode;$accepted=$true;$reason=''
    try{Assert-TrialProcessResult $handle $stage; $null=Assert-PaymentTrialReport $report $stage}catch{$accepted=$false;$reason=$_.Exception.Message}
    if($accepted -ne $case.accept){throw ('WRONG_CLASSIFICATION '+$case.name)}
    if($case.name -eq 'report-then-timeout' -and ($code -ne 124 -or $handle.FailureCode -ne 124)){throw 'REAL_TIMEOUT_RED_NOT_REPRODUCED'}
    $rows.Add(@{case=$case.name;exitCode=$code;newAccepted=$accepted;diagnostic=$handle.Diagnostic;rejection=$reason;fixtureCleanupConfirmed=$true})
}
# 替身单独覆盖清理、排空、输出读取及未完成状态；不声称注入了真实系统IO故障。
function HealthyHandle {
    return [pscustomobject]@{Completed=$true;Disposed=$true;ExitKnown=$true;ExitCode=1;RawExitCode=1;FailureCode=0;Diagnostic='';Cleanup=@{confirmed=$true;exited=$true;exitCode=1;diagnostic=''}}
}
foreach($kind in @('cleanup-unknown','cleanup-diagnostic','drain-timeout','capture-failed','incomplete','undisposed','exit-unknown','failure-code','raw-mismatch','cleanup-exit-mismatch')){
    $h=HealthyHandle
    switch($kind){
        'cleanup-unknown' {$h.Cleanup.confirmed=$false}
        'cleanup-diagnostic' {$h.Cleanup.diagnostic='PROCESS_CLEANUP_FAILED'}
        'drain-timeout' {$h.Diagnostic='OUTPUT_DRAIN_TIMED_OUT';$h.FailureCode=125}
        'capture-failed' {$h.Diagnostic='OUTPUT_CAPTURE_FAILED';$h.FailureCode=125}
        'incomplete' {$h.Completed=$false}
        'undisposed' {$h.Disposed=$false}
        'exit-unknown' {$h.ExitKnown=$false}
        'failure-code' {$h.FailureCode=125}
        'raw-mismatch' {$h.RawExitCode=2}
        'cleanup-exit-mismatch' {$h.Cleanup.exitCode=2}
    }
    $rejected=$false
    try{Assert-TrialProcessResult $h 'early-proof'}catch{$rejected=$true}
    if(-not $rejected){throw ('RUNNER_FAULT_ACCEPTED '+$kind)}
    $rows.Add(@{case=$kind;fixture='terminal-state substitute';newAccepted=$false})
}
$healthy=HealthyHandle;$healthy.ExitCode=0;$healthy.RawExitCode=0;$healthy.Cleanup.exitCode=0
Assert-TrialProcessResult $healthy 'baseline'
Assert-TrialProcessResult $healthy 'restored'
# 报告结构与断言语义的反例独立于进程终态；报告自身不能证明执行健康。
foreach($bad in @(
    $fixture.Replace($names[4],$names[0]),
    $fixture.Replace('AssertionFailedError','IllegalStateException'),
    $fixture.Replace('expected: &lt;false&gt; but was: &lt;true&gt;','different assertion'),
    $fixture.Replace('</testcase>','<skipped /></testcase>'),
    $fixture.Replace('</testcase>','<error /></testcase>'),
    $fixture.Replace('PaymentIdempotencyTest','AnotherTest'))){
    [IO.File]::WriteAllText((Join-Path $root 'invalid.xml'),$bad)
    $rejected=$false
    try{$null=Assert-PaymentTrialReport (Join-Path $root 'invalid.xml') 'early-proof'}catch{$rejected=$true}
    if(-not $rejected){throw 'INVALID_REPORT_ACCEPTED'}
}
$baseline=[regex]::Replace($fixture,'<failure[^>]*/>','')
[IO.File]::WriteAllText((Join-Path $root 'baseline.xml'),$baseline)
$null=Assert-PaymentTrialReport (Join-Path $root 'baseline.xml') 'baseline'
$null=Assert-PaymentTrialReport (Join-Path $root 'baseline.xml') 'restored'
@{cases=$rows.ToArray();invalidReportsRejected=6;baselineAndRestoredZeroAccepted=$true;retainedFixture=$root;limits='Six real children; ten terminal-state substitutes; no business environment'}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $(if($OutputPath){$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)}else{Join-Path $root 'classification-results.json'})
Write-Output "PASS: $($rows.Count) classification cases plus healthy baseline/restored; real report-before-timeout rejected"
