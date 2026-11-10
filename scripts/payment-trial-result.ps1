# 断言反例只接受自然退出的约定状态；先判运行器，再解释业务报告。
function Assert-TrialProcessResult {
    param($Handle, [ValidateSet('baseline','restored','early-proof','wrong-identity')][string]$Stage)
    if(-not $Handle.Completed -or -not $Handle.Disposed -or -not $Handle.ExitKnown -or
       $Handle.FailureCode -ne 0 -or -not [string]::IsNullOrEmpty($Handle.Diagnostic) -or
       -not $Handle.Cleanup -or -not $Handle.Cleanup.confirmed -or -not $Handle.Cleanup.exited -or
       -not [string]::IsNullOrEmpty($Handle.Cleanup.diagnostic)) {
        throw "TRIAL_RUNNER_FAILED: $Stage exit=$($Handle.ExitCode) diagnostic=$($Handle.Diagnostic)"
    }
    $expected=if($Stage -in @('baseline','restored')){0}else{1}
    if($Handle.ExitCode -ne $expected -or $Handle.RawExitCode -ne $expected -or $Handle.Cleanup.exitCode -ne $expected){
        throw "TRIAL_UNEXPECTED_EXIT: $Stage expected=$expected actual=$($Handle.ExitCode)"
    }
}

# 固定本反证试用的五个方法；计数相同但方法缺失也不能通过。
function Assert-PaymentTrialReport {
    param([string]$Report, [string]$Stage)
    [xml]$xml=[IO.File]::ReadAllText($Report)
    $cases=@($xml.testsuite.testcase)
    $names=@('concurrentAndRepeatedNotificationsSucceedOnlyAfterCommit','legacyAndUnprovenStatesRemainBlocked','proofRejectsIdentityProductAndAmountMismatch','versionedProofRoundTripAndOldJsonCompatibility','baselineJsonSchemaRejectsNewProofAndRequiresStoppedUpgrade')
    if($cases.Count -ne $names.Count){throw "INVALID_EXECUTION: $Stage"}
    foreach($name in $names){
        if(@($cases|Where-Object {$_.name -ceq $name -and $_.classname -ceq 'cn.game.games.net.game.helper.PaymentIdempotencyTest'}).Count -ne 1){throw "MISSING_METHOD: $name"}
    }
    if(@($cases|Where-Object {$_.SelectSingleNode('error') -or $_.SelectSingleNode('skipped')}).Count){throw "INVALID_EXECUTION: $Stage"}
    $failures=@($cases|Where-Object {$_.SelectSingleNode('failure')})
    if($Stage -in @('baseline','restored')){
        if($failures.Count){throw "BASELINE_FAILED: $Stage"}
    } elseif($Stage -in @('early-proof','wrong-identity')) {
        $primary=if($Stage -eq 'early-proof'){$names[0]}else{$names[2]}
        $allowed=@($primary,$names[3])
        if($failures.Count -ne 2){throw "UNEXPECTED_FAILURE: $Stage"}
        foreach($name in $allowed){
            if(@($failures|Where-Object {$_.name -ceq $name -and $_.failure.type -ceq 'org.opentest4j.AssertionFailedError' -and $_.failure.message -like '*expected: <false> but was: <true>*'}).Count -ne 1){throw "MUTATION_NOT_DETECTED_BY_TARGET_ASSERTION: $Stage $name"}
        }
    } else {throw "UNKNOWN_STAGE: $Stage"}
    return @{tests=$cases.Count;failedMethods=@($failures|ForEach-Object {$_.name})}
}
