#requires -Version 7.0
<# 为真实跨进程充值验收读取 Apollo 配置；凭据只存本轮私有目录，结束后删除。 #>
[CmdletBinding()]
param([string]$ApolloUri='http://127.0.0.1:9888',[string]$Cluster='SYQ')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime=Join-Path $root ('.ai-workspace/.runtime/payment-process-recovery/'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runtime | Out-Null
$identity=[Security.Principal.WindowsIdentity]::GetCurrent().User
$acl=[Security.AccessControl.DirectorySecurity]::new()
$acl.SetAccessRuleProtection($true,$false)
$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($identity,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
Set-Acl -LiteralPath $runtime -AclObject $acl
$names=@('S2_DB_CONFIG','PAYMENT_PROCESS_ROOT','JAVA_TOOL_OPTIONS','MAVEN_OPTS')
$before=@{}
foreach($name in $names){$before[$name]=[Environment]::GetEnvironmentVariable($name)}
$config=Join-Path $runtime 'jdbc.properties'
$code=1
try {
    $jdbc=(Invoke-RestMethod -Uri "$ApolloUri/configs/game/$Cluster/jdbc" -NoProxy -TimeoutSec 10).configurations
    $zk=(Invoke-RestMethod -Uri "$ApolloUri/configs/game/$Cluster/zookeeper" -NoProxy -TimeoutSec 10).configurations
    $values=@{}
    foreach($name in @('driverClassName','dburl','dbuser','dbpass')){
        if([string]::IsNullOrEmpty([string]$jdbc.$name)){throw 'APOLLO_DATABASE_CONFIG_MISSING'}
        $values[$name]=[string]$jdbc.$name
    }
    $values.zk=[string]$zk.zk
    if([string]::IsNullOrEmpty($values.zk)){throw 'APOLLO_ZOOKEEPER_CONFIG_MISSING'}
    $lines=foreach($name in $values.Keys){
        $escaped=($values[$name].ToCharArray() | ForEach-Object {'\u{0:x4}' -f [int]$_}) -join ''
        "$name=$escaped"
    }
    [IO.File]::WriteAllLines($config,$lines,[Text.Encoding]::ASCII)
    $logConfig=Join-Path $runtime 'log4j2.xml'
    [IO.File]::WriteAllText($logConfig,'<Configuration status="OFF"><Appenders><Console name="console"><PatternLayout pattern="%level %logger %msg%n%throwable"/></Console></Appenders><Loggers><Root level="warn"><AppenderRef ref="console"/></Root></Loggers></Configuration>')
    $env:S2_DB_CONFIG=$config
    $env:PAYMENT_PROCESS_ROOT=$runtime
    $env:JAVA_TOOL_OPTIONS="-Dlog4j.configurationFile=$(([uri]$logConfig).AbsoluteUri)"
    $env:MAVEN_OPTS='-Xmx1024m -Dexec.skip=true'
    Push-Location $root
    try {
        $testStarted=[DateTime]::UtcNow
        & pwsh -NoProfile -File ./.ai-workspace/scripts/run-java-tests.ps1 -Project game -Test PaymentProcessRecoveryIT -ExpectedTestsFile ./game/src/test/resources/payment-process-recovery-expected.json *> (Join-Path $runtime 'tests.log')
        $code=$LASTEXITCODE
        $report=Join-Path $root 'game/target/surefire-reports/TEST-cn.game.games.net.game.helper.PaymentProcessRecoveryIT.xml'
        if((Test-Path -LiteralPath $report) -and (Get-Item -LiteralPath $report).LastWriteTimeUtc -ge $testStarted){
            Copy-Item -LiteralPath $report -Destination (Join-Path $runtime 'junit.xml')
        } elseif($code -eq 0){throw 'PAYMENT_PROCESS_FRESH_JUNIT_MISSING'}
    } finally {Pop-Location}
    Write-Output "PAYMENT_PROCESS_TEST_RESULT exit=$code runtime=$runtime"
    if($code -eq 0){Get-Content -LiteralPath (Join-Path $runtime 'tests.log') -Tail 3}
} finally {
    if(Test-Path -LiteralPath $config){Remove-Item -LiteralPath $config -Force}
    foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$before[$name])}
}
exit $code
