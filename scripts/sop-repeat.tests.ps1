#requires -Version 7.0
$ErrorActionPreference='Stop'
$hostRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$helper=Join-Path $hostRoot '.ai-sop/scripts/hidden-process.ps1'
. $helper
$runner=Join-Path $PSScriptRoot 'run-sop-repeat.ps1'
$root=Join-Path ([IO.Path]::GetTempPath()) ('sop-repeat-regression-'+[guid]::NewGuid().ToString('N'))
$engine=Join-Path $root engine;$fixtures=Join-Path $engine scripts/tests
[IO.Directory]::CreateDirectory($fixtures)|Out-Null
Copy-Item $helper (Join-Path $engine scripts/hidden-process.ps1)
function Assert($ok,[string]$message){if(-not $ok){throw $message}}
function Get-FixtureProcess([int]$ProcessId){
 try{$p=Get-Process -Id $ProcessId -ErrorAction Stop}catch{if($_.CategoryInfo.Category -eq 'ObjectNotFound'){return $null};throw}
 try{$null=$p.Handle;return $p}catch{$p.Dispose();throw}
}
function Run-Case([string[]]$suites,[int]$timeout=10,[int]$rounds=1){
 $id=[guid]::NewGuid().ToString('N');$out=Join-Path $root "$id.out";$err=Join-Path $root "$id.err"
 # 参数数组由小脚本传入，避免 PowerShell -File 将逗号当作文件名。
 $command=Join-Path $root "$id.ps1"
 $quoted=($suites|ForEach-Object {"'"+$_.Replace("'","''")+"'"}) -join ','
 [IO.File]::WriteAllText($command,"& '"+$runner.Replace("'","''")+"' -EngineRoot '"+$engine.Replace("'","''")+"' -Suites @($quoted) -Rounds $rounds -TimeoutSeconds $timeout -DrainTimeoutSeconds 1 -LogRoot '"+$root.Replace("'","''")+"'; exit `$LASTEXITCODE")
 $p=Start-AiSopHiddenProcess -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile','-File',$command) -RedirectStandardOutput $out -RedirectStandardError $err -TimeoutSeconds 25 -PassThru
 try{$p.WaitForExit();$code=$p.ExitCode}finally{$p.Dispose()}
 $text=[IO.File]::ReadAllText($out)
 Assert ($text -match 'REPEAT_LOG_ROOT:([^\r\n]+)') "No run output: $text / $([IO.File]::ReadAllText($err))"
 $runPath=$Matches[1]
 return @{code=$code;items=@(Get-Content (Join-Path $runPath results.json) -Raw|ConvertFrom-Json);root=$runPath}
}
try {
 $savedIdentity=$env:AI_SOP_INVOCATION_SESSION_ID
 try {
  $env:AI_SOP_INVOCATION_SESSION_ID='repeat-regression-identity'
  $invalidLogRoot=Join-Path $root blocked-log-root
  [IO.File]::WriteAllText($invalidLogRoot,'not a directory')
  $failed=$false
  try{& $runner -EngineRoot $engine -Suites @('good') -Rounds 1 -LogRoot $invalidLogRoot}catch{$failed=$true}
  Assert ($failed -and $env:AI_SOP_INVOCATION_SESSION_ID -eq 'repeat-regression-identity') 'Initialization failure changed caller identity'
 } finally {[Environment]::SetEnvironmentVariable('AI_SOP_INVOCATION_SESSION_ID',$savedIdentity)}
 'Write-Output "first"; [Console]::Error.WriteLine("stderr-final"); Write-Output "stdout-final"'|Set-Content (Join-Path $fixtures 'good.tests.ps1')
 $ok=Run-Case @('good') -rounds 2
 Assert ($ok.code -eq 0 -and $ok.items.Count -eq 2) 'Normal rounds failed'
 foreach($item in $ok.items){
  Assert ($item.exitCode -eq 0 -and $item.cleanupConfirmed) 'Normal cleanup incomplete'
  Assert ([IO.File]::ReadAllText($item.stdout).Contains('stdout-final') -and [IO.File]::ReadAllText($item.stderr).Contains('stderr-final')) 'Final output lost'
  $exclusive=[IO.File]::Open($item.stdout,'Open','ReadWrite','None');$exclusive.Dispose()
 }
 @'
@{id=$PID;startedTicks=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks}|ConvertTo-Json|Set-Content (Join-Path $PSScriptRoot sleeper.json)
Start-Sleep 60
'@|Set-Content (Join-Path $fixtures 'sleep.tests.ps1')
 $clock=[Diagnostics.Stopwatch]::StartNew();$timed=Run-Case @('sleep','good') -timeout 1
 Assert ($clock.Elapsed.TotalSeconds -lt 15 -and $timed.code -ne 0) 'Timeout was not enforced'
 $sleepResult=@($timed.items|Where-Object name -eq sleep)[0]
 Assert ($sleepResult.exitCode -eq 124 -and $sleepResult.diagnostic -match 'PROCESS_TIMED_OUT') 'Timeout result lost'
 $identity=Get-Content (Join-Path $fixtures sleeper.json) -Raw|ConvertFrom-Json
 $p=Get-FixtureProcess $identity.id
 if($p){try{Assert ($p.HasExited -or $p.StartTime.ToUniversalTime().Ticks -ne $identity.startedTicks) 'Sleeping process remained'}finally{$p.Dispose()}}
 @'
$info=[Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
$info.UseShellExecute=$false;$info.CreateNoWindow=$true
foreach($a in @('-NoProfile','-Command','Write-Output "held-output"; Start-Sleep 12')){$info.ArgumentList.Add($a)}
$p=[Diagnostics.Process]::Start($info)
@{id=$p.Id;startedTicks=$p.StartTime.ToUniversalTime().Ticks}|ConvertTo-Json|Set-Content (Join-Path $PSScriptRoot descendant.json)
exit 0
'@|Set-Content (Join-Path $fixtures 'pipe.tests.ps1')
 try {
  $pipe=Run-Case @('pipe')
  Assert ($pipe.code -ne 0 -and $pipe.items[0].exitCode -eq 125 -and $pipe.items[0].diagnostic -match 'OUTPUT_DRAIN_TIMED_OUT') 'Exited parent bypassed output drain failure'
  Assert (-not $pipe.items[0].cleanupConfirmed) 'Unknown descendant cleanup reported confirmed'
 } finally {
  $identityPath=Join-Path $fixtures descendant.json
  if(Test-Path $identityPath){$identity=Get-Content $identityPath -Raw|ConvertFrom-Json;$p=Get-FixtureProcess $identity.id;if($p){try{if(-not $p.HasExited -and $p.StartTime.ToUniversalTime().Ticks -eq $identity.startedTicks){$p.Kill($true);Assert ($p.WaitForExit(5000)) 'Descendant fixture cleanup timeout'}}finally{$p.Dispose()}}}
 }
 # 协议替身注入清理与部分启动失败；真实超时、管道由以上进程覆盖。
 $mock=@'
$script:fixtureRoot=$PSScriptRoot;$script:count=0
function Start-AiSopHiddenProcess {
 $script:count++
 if('__MODE__' -eq 'start' -and $script:count -eq 2){throw 'INJECTED_START_FAILURE'}
 $h=[pscustomobject]@{Id=$script:count;PollCount=0;ExitCode=0;Completed=$false;Disposed=$false;Cleanup=@{confirmed=$false};Diagnostic='';Root=$script:fixtureRoot}
 $h|Add-Member ScriptMethod Poll {if('__MODE__' -eq 'poll' -and $this.Id -eq 1){throw 'INJECTED_POLL_FAILURE'};if('__MODE__' -eq 'mixed' -and $this.Id -eq 2){$this.PollCount++;if($this.PollCount -eq 1){return $false};throw 'INJECTED_SECOND_POLL_FAILURE'};$this.Completed=$true;$this.Cleanup.confirmed=$true;return $true}
 $h|Add-Member ScriptMethod Dispose {
  Add-Content (Join-Path $this.Root disposed.txt) $this.Id
  if('__MODE__' -eq 'mixed' -and $this.Id -ne 2){$this.Disposed=$true;return}
  $this.Disposed=$true;$this.Completed=$true;$this.ExitCode=125;$this.Cleanup.confirmed=$false;$this.Diagnostic='INJECTED_CLEANUP_FAILURE'
  if('__MODE__' -eq 'timeout-cleanup'){$this.ExitCode=124;$this.Diagnostic='PROCESS_TIMED_OUT';throw 'INJECTED_DISPOSE_THROW'}
  if('__MODE__' -eq 'throw' -and $this.Id -eq 1){throw 'INJECTED_DISPOSE_THROW'}
  if('__MODE__' -eq 'getter' -and $this.Id -eq 1){$this|Add-Member ScriptProperty ExitCode {throw 'INJECTED_RESULT_FAILURE'} -Force}
 }
 return $h
}
'@
 foreach($mode in @('late','throw','start','poll','getter','mixed','timeout-cleanup')){
  $marker=Join-Path $engine scripts/disposed.txt
  [IO.File]::WriteAllText($marker,'')
  $mock.Replace('__MODE__',$mode)|Set-Content (Join-Path $engine scripts/hidden-process.ps1)
  $failure=Run-Case @('one','two','three')
  Assert ($failure.code -ne 0 -and @($failure.items|Where-Object exitCode -eq 0).Count -eq $(if($mode -eq 'mixed'){2}else{0})) "$mode lost independent final results"
  $count=@(Get-Content $marker).Count
  Assert ($count -eq $(if($mode -eq 'start'){1}else{3})) "$mode skipped another handle cleanup"
  Assert ($failure.items.Count -eq 3) "$mode omitted planned jobs"
  if($mode -eq 'start'){Assert ($failure.items[1].executionState -eq 'START_FAILED' -and $failure.items[2].executionState -eq 'NOT_STARTED') 'Failed/unstarted item not recorded'}
  if($mode -eq 'timeout-cleanup'){Assert (@($failure.items|Where-Object {$_.exitCode -ne 124 -or $_.diagnostic -notmatch 'INJECTED_DISPOSE_THROW'}).Count -eq 0) 'Cleanup overwrote timeout cause'}
 }
 Write-Output "PASS: normal output, real timeout, inherited pipes, late cleanup failure, cleanup exception, partial start, poll exception, result getter failure; fixtures=$root"
} catch {Write-Output "RETAINED_FIXTURE:$root";throw}
