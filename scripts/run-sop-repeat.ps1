#requires -Version 7.0
[CmdletBinding()]
param(
 [string]$EngineRoot=(Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '.ai-sop'),
 [ValidateCount(1,100)][ValidatePattern('^[A-Za-z0-9._-]+$')][string[]]$Suites=@('workflow-evidence-safety','workflow-task-scope','workflow-task-recovery'),
 [ValidateRange(1,100)][int]$Rounds=3,
 [ValidateRange(1,86400)][int]$TimeoutSeconds=900,
 [ValidateRange(1,60)][int]$DrainTimeoutSeconds=5,
 [string]$LogRoot=(Join-Path (Split-Path -Parent $PSScriptRoot) '.runtime/sop-repeat')
)
$ErrorActionPreference='Stop'
. (Join-Path $EngineRoot 'scripts/hidden-process.ps1')
# 子套件自建会话，不继承宿主执行身份；脚本退出时恢复调用环境。
$savedSession=$env:AI_SOP_INVOCATION_SESSION_ID
$runRoot=Join-Path $LogRoot ('runs-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($runRoot)|Out-Null
$results=[Collections.Generic.List[object]]::new()
Write-Output "REPEAT_LOG_ROOT:$runRoot"
try {
 Remove-Item Env:AI_SOP_INVOCATION_SESSION_ID -ErrorAction SilentlyContinue
 for($round=1;$round -le $Rounds;$round++){
  $jobs=@($Suites|ForEach-Object {@{name=$_;handle=$null;out=(Join-Path $runRoot "$round-$_.stdout.log");err=(Join-Path $runRoot "$round-$_.stderr.log");cleanupError=$null;executionError=$null;state='NOT_STARTED';completedAt=$null}});$primary=$null
  try {
   foreach($job in $jobs){
    try {
     $job.handle=Start-AiSopHiddenProcess -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile','-File',(Join-Path $EngineRoot "scripts/tests/$($job.name).tests.ps1")) -RedirectStandardOutput $job.out -RedirectStandardError $job.err -TimeoutSeconds $TimeoutSeconds -DrainTimeoutSeconds $DrainTimeoutSeconds -HeartbeatSeconds 30 -Label "$round-$($job.name)" -CloseStandardInput -PassThru
     $job.state='RUNNING'
    } catch {$job.state='START_FAILED';$job.executionError=$_.Exception.Message;throw}
   }
   do {
    $pending=$false
    # 每个句柄每轮都 Poll；不能用 HasExited 或短路表达式跳过超时与输出收尾。
    foreach($job in $jobs){
     try {if(-not $job.handle.Poll()){$pending=$true}elseif(-not $job.completedAt){$job.completedAt=[DateTimeOffset]::UtcNow.ToString('o');$job.state='COMPLETED'}}
     catch {$job.state='POLL_FAILED';$job.executionError=$_.Exception.Message;throw}
    }
    if($pending){Start-Sleep -Milliseconds 50}
   } while($pending)
  } catch {$primary=$_} finally {
   # 一项清理失败不能跳过其他进程；最终结果在所有清理尝试后读取。
   foreach($job in $jobs){if($job.handle){try{$job.handle.Dispose()}catch{$job.cleanupError=$_.Exception.Message}}}
  }
  foreach($job in $jobs){
   $exitCode=125;$diagnostic=(@($job.executionError,$job.cleanupError)|Where-Object {$_}) -join '; ';$confirmed=$false;$handleConfirmed=$false
   try {
    if($job.handle){$exitCode=$job.handle.ExitCode;$handleConfirmed=[bool]$job.handle.Completed -and [bool]$job.handle.Disposed -and [bool]$job.handle.Cleanup.confirmed}
    $diagnostic=(@($diagnostic,$job.handle.Diagnostic)|Where-Object {$_}) -join '; '
    # 当前句柄释放不能证明已重挂的持管道后代已清理。
    $confirmed=$handleConfirmed -and $diagnostic -notmatch 'OUTPUT_DRAIN_TIMED_OUT|descendant cleanup is unconfirmed'
    if($null -eq $exitCode -or ($exitCode -eq 0 -and (-not $confirmed -or $job.cleanupError -or $job.executionError))){$exitCode=125}
   } catch {$diagnostic=(@($diagnostic,$_.Exception.Message)|Where-Object {$_}) -join '; ';$confirmed=$false;if($null -eq $exitCode -or $exitCode -eq 0){$exitCode=125}}
   $result=@{round=$round;name=$job.name;exitCode=$exitCode;cleanupConfirmed=$confirmed;handleCleanupConfirmed=$handleConfirmed;diagnostic=$diagnostic;executionState=$job.state;completedAt=$job.completedAt;stdout=$job.out;stderr=$job.err}
   $results.Add($result);Write-Output ($result|ConvertTo-Json -Compress)
  }
  ConvertTo-Json -InputObject $results.ToArray() -Depth 6|Set-Content (Join-Path $runRoot results.json) -Encoding utf8
  if($primary){[IO.File]::WriteAllText((Join-Path $runRoot 'runner-error.txt'),$primary.ToString());throw $primary}
 }
 if(@($results|Where-Object exitCode -ne 0).Count){exit 1}
} finally {
 [Environment]::SetEnvironmentVariable('AI_SOP_INVOCATION_SESSION_ID',$savedSession)
}
