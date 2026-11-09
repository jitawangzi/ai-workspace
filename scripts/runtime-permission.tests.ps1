#requires -Version 7.0
# 仅对本脚本创建的隔离Java进程测试真实查询拒绝；监督句柄负责恢复和清理。
$ErrorActionPreference='Stop'
if(-not [OperatingSystem]::IsWindows()){throw 'WINDOWS_PERMISSION_FIXTURE_REQUIRED'}
. (Join-Path $PSScriptRoot 'native-arguments.ps1')
Add-Type -Path (Join-Path $PSScriptRoot 'fixtures/ProcessAclFixture.cs')
$hostRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtimeScript=Join-Path $hostRoot '.ai-workspace/scripts/local-runtime.ps1'
$runId='acl_'+[guid]::NewGuid().ToString('N')
$snapshot=Join-Path $hostRoot ".ai-workspace/.runtime/local-runtime/$runId"
[IO.Directory]::CreateDirectory($snapshot)|Out-Null
$classes=Join-Path $snapshot classes
[IO.Directory]::CreateDirectory($classes)|Out-Null
function Assert($value,$message){if(-not $value){throw $message}}
foreach($entry in @(@{package='cn.game.login';name='LoginServer'},@{package='cn.game.games.net.game';name='GameServer'})){
 $javaPath=Join-Path $snapshot ($entry.name+'.java')
 $source='package '+$entry.package+'; public class '+$entry.name+' { public static void main(String[] a) throws Exception { java.nio.file.Files.writeString(java.nio.file.Path.of(a[0]), "READY"); Thread.sleep(300000); } }'
 [IO.File]::WriteAllText($javaPath,$source)
 & javac -d $classes $javaPath
 Assert ($LASTEXITCODE -eq 0) 'Fixture Java compile failed'
}
$results=@();$children=@();$handles=@();$protectedHandle=$null;$original=$null;$primaryFailure=$null
function Alive($h){return [SopFixtureAcl]::WaitChecked($h,0) -eq 258}
function Control([string]$action,[string]$label){
 $out=Join-Path $snapshot "$label.stdout.log";$err=Join-Path $snapshot "$label.stderr.log"
 $arguments=@('-NoProfile','-File',$runtimeScript,'-Action',$action,'-Snapshot',$snapshot)|ForEach-Object {ConvertTo-NativeArgument $_}
 $p=Start-Process pwsh -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
 try{if(-not $p.WaitForExit(45000)){$p.Kill($true);throw 'Control timeout'};$p.Refresh();return @{exitCode=$p.ExitCode;output=([IO.File]::ReadAllText($out)+[IO.File]::ReadAllText($err));stdout=$out;stderr=$err}}finally{$p.Dispose()}
}
try {
 foreach($mode in @('intent','registered')){
  $children=@();$handles=@();$original=$null;$protectedHandle=$null
  $settings=Join-Path $snapshot settings.json;$intent=Join-Path $snapshot launch-intent.json;$state=Join-Path $snapshot processes.json
  if(Test-Path $intent){Remove-Item -LiteralPath $intent};if(Test-Path $state){Remove-Item -LiteralPath $state}
  @{schemaVersion='1.0';runId=$runId}|ConvertTo-Json|Set-Content $settings
  if($mode -eq 'intent'){ConvertTo-Json -InputObject @(@{schemaVersion='1.0';runId=$runId})|Set-Content $intent}
  $records=@()
  for($i=0;$i -lt 3;$i++){
   $main=if($i -eq 1){'cn.game.login.LoginServer'}else{'cn.game.games.net.game.GameServer'}
   $launch=if($i -eq 2){'foreign_'+$runId}else{$runId}
   $ready=Join-Path $snapshot "$mode-$i.ready"
   # Process.Start 保留创建时句柄；后续 ACL 和清理都绑定同一内核对象。
   $p=[Diagnostics.Process]::new();$p.StartInfo.FileName=(@(Get-Command java -CommandType Application)[0]).Source
   $p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true
   foreach($arg in @("-Druntime.launchId=$launch",'-cp',$classes,$main,$ready)){[void]$p.StartInfo.ArgumentList.Add($arg)}
   Assert ($p.Start()) 'Java start failed'
   $children+=,$p
   $h=[SopFixtureAcl]::Retain($p.SafeHandle);Assert (-not $h.IsInvalid) 'Supervisor handle failed';$handles+=,$h
   $deadline=[DateTime]::UtcNow.AddSeconds(15);while(-not (Test-Path $ready)){Assert (([DateTime]::UtcNow -lt $deadline) -and (Alive $h)) 'Java fixture not ready';Start-Sleep -Milliseconds 50}
   if($i -lt 2){$records+=@{app=$(if($i -eq 1){'login'}else{'game'});pid=$p.Id;startedAt=$p.StartTime.ToUniversalTime().ToString('o');main=$main;runId=$runId}}
  }
  if($mode -eq 'registered'){ConvertTo-Json -InputObject @($records)|Set-Content $state}
  $recordPath=if($mode -eq 'intent'){$intent}else{$state};$before=(Get-FileHash $recordPath).Hash
  Copy-Item -LiteralPath $recordPath -Destination (Join-Path $snapshot "$mode-record-before.json")
  $protectedHandle=$handles[0];$original=[SopFixtureAcl]::Read($protectedHandle)
  [SopFixtureAcl]::Deny($protectedHandle,$original,[Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
  $probe=& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'runtime-permission-observer.ps1') -TargetPid $children[0].Id|ConvertFrom-Json
  Assert ($probe.queryError -eq 5) 'Real query denial not observed'
  $status=Control Status "$mode-denied-status"
  Assert ($status.exitCode -ne 0 -and $status.output.Contains('LOCAL_RUNTIME_STOP_INCOMPLETE')) 'Status falsely succeeded'
  Assert ((Alive $handles[0]) -and (Alive $handles[1]) -and (Alive $handles[2])) 'Status killed fixture'
  $stop=Control Stop "$mode-denied-stop"
  Assert ($stop.exitCode -ne 0 -and $stop.output.Contains('LOCAL_RUNTIME_STOP_INCOMPLETE')) 'Stop falsely succeeded'
  Assert ((Alive $handles[0]) -and -not (Alive $handles[1]) -and (Alive $handles[2])) 'Unknown/foreign killed or known not cleaned'
  $retry=Control Stop "$mode-denied-retry"
  Assert ($retry.exitCode -ne 0 -and (Alive $handles[0]) -and (Alive $handles[2])) 'Repeated denied Stop failed invariant'
  Assert ((Get-FileHash $recordPath).Hash -eq $before) 'Recovery record changed'
  [SopFixtureAcl]::Restore($protectedHandle,$original)
  $actual=[Security.AccessControl.RawSecurityDescriptor]::new([SopFixtureAcl]::Read($protectedHandle),0).GetSddlForm([Security.AccessControl.AccessControlSections]::Access)
  $expected=[Security.AccessControl.RawSecurityDescriptor]::new($original,0).GetSddlForm([Security.AccessControl.AccessControlSections]::Access)
  Assert ($actual -eq $expected) 'DACL restoration mismatch'
  $restored=Control Stop "$mode-restored-stop"
  Assert ($restored.exitCode -eq 0 -and -not (Alive $handles[0]) -and (Alive $handles[2])) 'Restored Stop failed'
  $again=Control Stop "$mode-restored-retry"
  Assert ($again.exitCode -eq 0 -and (Alive $handles[2])) 'Repeated restored Stop failed'
  Assert ((Get-FileHash $recordPath).Hash -eq $before) 'Recovery record not retained'
  Copy-Item -LiteralPath $recordPath -Destination (Join-Path $snapshot "$mode-record-after.json")
  $results+=@{mode=$mode;result='PASSED';queryError=$probe.queryError;commandLineReadable=$probe.commandLineReadable;deniedStatus=$status.exitCode;deniedStop=$stop.exitCode;restoredStop=$restored.exitCode;recordUnchanged=$true;recordBefore="$mode-record-before.json";recordAfter="$mode-record-after.json";beforeSha256=$before.ToLowerInvariant();afterSha256=(Get-FileHash $recordPath).Hash.ToLowerInvariant();foreignSurvived=$true}
  foreach($h in $handles){if(Alive $h){Assert ([SopFixtureAcl]::TerminateProcess($h,0)) 'Fixture terminate failed';Assert ([SopFixtureAcl]::WaitForSingleObject($h,10000) -eq 0) 'Fixture cleanup timeout'};$h.Dispose()};foreach($p in $children){$p.Dispose()};$handles=@();$children=@();$original=$null;$protectedHandle=$null
 }
 $results|ConvertTo-Json -Depth 6|Set-Content (Join-Path $snapshot result.json)
 Write-Output "REAL_PERMISSION_ACCEPTANCE_PASS:$snapshot"
}catch{$primaryFailure=$_;throw}finally{
 # 一次恢复失败不能跳过其他专用进程的清理，也不能覆盖首个失败。
 $cleanupErrors=[Collections.Generic.List[string]]::new()
 try{if($protectedHandle -and -not $protectedHandle.IsClosed -and $original){[SopFixtureAcl]::Restore($protectedHandle,$original)}}catch{$cleanupErrors.Add('RESTORE:'+ $_.Exception.Message)}
 foreach($h in $handles){
  try{if(-not $h.IsClosed -and (Alive $h)){Assert ([SopFixtureAcl]::TerminateProcess($h,1)) 'Emergency fixture termination failed';Assert ([SopFixtureAcl]::WaitForSingleObject($h,10000) -eq 0) 'Emergency cleanup timeout'}}catch{$cleanupErrors.Add('TERMINATE:'+ $_.Exception.Message)}
  finally{try{$h.Dispose()}catch{$cleanupErrors.Add('HANDLE:'+ $_.Exception.Message)}}
 }
 foreach($p in $children){
  try{if(-not $p.HasExited){$p.Kill($true);Assert ($p.WaitForExit(10000)) 'Fallback cleanup timeout'}}catch{$cleanupErrors.Add('PROCESS:'+ $_.Exception.Message)}
  finally{try{$p.Dispose()}catch{$cleanupErrors.Add('PROCESS_DISPOSE:'+ $_.Exception.Message)}}
 }
 if($cleanupErrors.Count){$message='PERMISSION_FIXTURE_CLEANUP_FAILED:'+($cleanupErrors -join ';');if($primaryFailure){Write-Warning $message}else{throw $message}}
}
