#requires -Version 7.0
<# 使用已 Prepare 的独立快照，真实调用 Game/Login；将有效存储配置改到陷阱端口，必须在任何连接前拒绝。 #>
param([Parameter(Mandatory)][string]$Snapshot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'native-arguments.ps1')
$hostRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Snapshot=(Resolve-Path -LiteralPath $Snapshot).Path
$allowed=Join-Path $hostRoot '.ai-workspace/.runtime/local-runtime'
if (-not $Snapshot.StartsWith($allowed+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'BOUNDARY_SNAPSHOT_OUTSIDE_RUNTIME' }
$settings=Get-Content -LiteralPath (Join-Path $Snapshot settings.json) -Raw|ConvertFrom-Json
$traps=@();$process=$null
try {
    foreach($n in 1..3) { $trap=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0);$trap.Start();$traps+=,$trap }
    $jdbcPort=$traps[0].LocalEndpoint.Port;$redisPort=$traps[1].LocalEndpoint.Port;$zkPort=$traps[2].LocalEndpoint.Port
    foreach($app in @('game','login')) {
        $order=if($app -eq 'game'){@('game','util','core','protocol')}else{@('login','util','core','protocol','game')}
        $cp=(@($order|ForEach-Object { Join-Path $Snapshot "artifacts/$_/classes" })+(Join-Path $Snapshot 'artifacts/lib/*')) -join ';'
        $node=if($app -eq 'game'){$settings.gameId}else{$settings.loginId}
        $main=if($app -eq 'game'){'cn.game.games.net.game.GameServer'}else{'cn.game.login.LoginServer'}
        $expected=Join-Path $Snapshot $(if($app -eq 'game'){'expected-runtime.json'}else{'expected-login.json'})
        $base=@("-Dapp.id=$app",'-Denv=dev',"-Dapollo.cluster=$($settings.apolloCluster)","-Dapollo.configService=$($settings.apolloUri)",
            "-Dapollo.cacheDir=$(Join-Path $Snapshot 'apollo-cache')","-DSEVER_PATH=$(Join-Path $Snapshot ('work/'+$app))",'-DdefaultNetworkIp=127.0.0.1','-Dserver.run.mode=test',
            "-Dworkspace=$hostRoot","-Dmetafolder=$(Join-Path (Split-Path -Parent $hostRoot) 'configs/Server')",'-Dfile.encoding=UTF-8',
            '--add-opens=java.base/java.lang=ALL-UNNAMED','--add-opens=java.base/java.util=ALL-UNNAMED','-Dio.netty.tryReflectionSetAccessible=true',
            '-Dzookeeper.clientCnxnSocket=org.apache.zookeeper.ClientCnxnSocketNetty','-Druntime.config.freeze=true',"-Dgame.runtimeIdentity.root=$(Join-Path $Snapshot artifacts)")
        foreach($mode in @('drift','missing-expected','invalid-expected')) {
            $output=Join-Path $Snapshot ("boundary-$app-$mode.out");$errorLog=Join-Path $Snapshot ("boundary-$app-$mode.err")
            $overrides=@("-Ddburl=jdbc:mysql://127.0.0.1:$jdbcPort/unexpected",('-Dredisson={"singleServerConfig":{"address":"redis://127.0.0.1:'+$redisPort+'"}}'),('-Dzk={"hosts":["127.0.0.1:'+$zkPort+'"]}'))
            $wanted='RUNTIME_STARTUP_EXPECTATION_MISMATCH'
            if($mode -eq 'drift') { $overrides+="-Druntime.expected=$expected" }
            elseif($mode -eq 'missing-expected') { $wanted='RUNTIME_EXPECTED_REQUIRED' }
            else {
                $invalid=Join-Path $Snapshot boundary-invalid.json;[IO.File]::WriteAllText($invalid,'not-json')
                $overrides+="-Druntime.expected=$invalid";$wanted='JsonParseException'
            }
            $arguments=$base+$overrides+@('-cp',$cp,$main,$node)
            $process=Start-Process java -ArgumentList ($arguments|ForEach-Object { ConvertTo-NativeArgument $_ }) -WindowStyle Hidden -PassThru -RedirectStandardOutput $output -RedirectStandardError $errorLog
            if(-not $process.WaitForExit(60000)){throw "BOUNDARY_PROCESS_TIMEOUT:$app/$mode"}
            if($process.ExitCode -eq 0 -or (Get-Content -LiteralPath $errorLog -Raw) -notmatch $wanted){throw "BOUNDARY_GATE_NOT_REJECTED:$app/$mode"}
            foreach($trap in $traps) { if($trap.Pending()){throw "BOUNDARY_STORAGE_CONTACTED:$app/$mode"} }
            Write-Output "STARTUP_BOUNDARY_PASS:$app/$mode storageConnections=0"
        }
    }
    Write-Output 'STARTUP_BOUNDARIES_PASS: actual Game/Login entry points, 6 failures before storage; effective Apollo storage overrides injected after independent expectation'
} finally {
    if($process -and -not $process.HasExited){$process.Kill();$process.WaitForExit()}
    foreach($trap in $traps){$trap.Stop()}
}
