#requires -Version 7.0
# 用隔离 Git 仓库和真实 Java 类加载验证同步脚本及客户端 classpath，不启动游戏服务。
$ErrorActionPreference='Stop'
$hostRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $hostRoot '.ai-sop/scripts/path-identity.ps1')
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('workspace-tooling-'+[guid]::NewGuid().ToString('N'))
function Assert([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Invoke-FixtureGit([string[]]$Arguments) {
    & git @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Fixture Git failed: $($Arguments -join ' ')" }
}
try {
    [IO.Directory]::CreateDirectory($fixture) | Out-Null
    $remote=Join-Path $fixture 'remote.git'
    $repo=Join-Path $fixture 'repo with spaces'
    Invoke-FixtureGit @('init','--bare','--quiet',$remote)
    Invoke-FixtureGit @('init','--quiet','-b','main',$repo)
    Invoke-FixtureGit @('-C',$repo,'config','user.name','Fixture')
    Invoke-FixtureGit @('-C',$repo,'config','user.email','fixture@example.invalid')
    Invoke-FixtureGit @('-C',$repo,'config','commit.gpgsign','false')
    Invoke-FixtureGit @('-C',$repo,'remote','add','origin',$remote)
    $scripts=Join-Path $repo 'scripts'
    [IO.Directory]::CreateDirectory($scripts) | Out-Null
    Copy-Item (Join-Path $PSScriptRoot 'sync-repository.ps1') $scripts
    [IO.File]::WriteAllText((Join-Path $repo 'tracked.txt'),'before')
    Invoke-FixtureGit @('-C',$repo,'add','scripts','tracked.txt')
    Invoke-FixtureGit @('-C',$repo,'commit','--quiet','-m','initial')
    Invoke-FixtureGit @('-C',$repo,'push','--quiet','-u','origin','main')
    [IO.File]::WriteAllText((Join-Path $repo 'tracked.txt'),'staged change')
    [IO.File]::WriteAllText((Join-Path $repo 'unrelated.txt'),'must stay untracked')
    Invoke-FixtureGit @('-C',$repo,'add','tracked.txt')
    & pwsh -NoProfile -File (Join-Path $scripts 'sync-repository.ps1') -Action Commit -Message 'staged only'
    Assert ($LASTEXITCODE -eq 0) 'Staged-only commit failed'
    Assert ((Invoke-FixtureGit @('-C',$repo,'show','HEAD:tracked.txt')) -eq 'staged change') 'Staged edit missing'
    Assert (-not (Invoke-FixtureGit @('-C',$repo,'ls-tree','--name-only','HEAD','unrelated.txt'))) 'Unrelated file was committed'
    $before=Invoke-FixtureGit @('-C',$repo,'rev-parse','HEAD')
    & pwsh -NoProfile -File (Join-Path $scripts 'sync-repository.ps1') -Action Pull 2>&1 | Out-Null
    Assert ($LASTEXITCODE -ne 0) 'Dirty working tree must not pull'
    Assert ((Invoke-FixtureGit @('-C',$repo,'rev-parse','HEAD')) -eq $before) 'Rejected pull changed history'
    Remove-Item -LiteralPath (Join-Path $repo 'unrelated.txt')
    & pwsh -NoProfile -File (Join-Path $scripts 'sync-repository.ps1') -Action Pull
    Assert ($LASTEXITCODE -eq 0) 'Clean fast-forward pull failed'

    # 读取真实脚本的 classpath 赋值，执行真实 Java 加载；旧 JAR 与新 util classes 提供同名类。
    $parseTokens=$null; $parseErrors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $hostRoot 'run_client.ps1'),[ref]$parseTokens,[ref]$parseErrors)
    Assert ($parseErrors.Count -eq 0) 'Client script parse failed'
    $assignments=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and $node.Left.VariablePath.UserPath -eq 'ClassPath'},$true))
    $TargetDir='simulationclient\target'
    $ClassPath=''
    foreach($assignment in $assignments) { . ([scriptblock]::Create($assignment.Extent.Text)) }
    foreach($module in @('util','core','game','protocol')) {
        Assert ($ClassPath.IndexOf("$module\target\classes") -ge 0 -and $ClassPath.IndexOf("$module\target\classes") -lt $ClassPath.IndexOf('dependency\*')) "$module classes must precede dependency JARs"
    }
    foreach($folder in @('new-src','old-src','old-classes','util/target/classes','simulationclient/target/dependency')) { [IO.Directory]::CreateDirectory((Join-Path $fixture $folder))|Out-Null }
    [IO.File]::WriteAllText((Join-Path $fixture 'new-src/ClasspathProbe.java'),'public class ClasspathProbe { public static void main(String[] args) { System.out.print("CURRENT_UTIL"); } }')
    [IO.File]::WriteAllText((Join-Path $fixture 'old-src/ClasspathProbe.java'),'public class ClasspathProbe { public static void main(String[] args) { System.out.print("OLD_JAR"); } }')
    & javac -d (Join-Path $fixture 'util/target/classes') (Join-Path $fixture 'new-src/ClasspathProbe.java')
    Assert ($LASTEXITCODE -eq 0) 'Current class fixture did not compile'
    & javac -d (Join-Path $fixture 'old-classes') (Join-Path $fixture 'old-src/ClasspathProbe.java')
    Assert ($LASTEXITCODE -eq 0) 'Stale class fixture did not compile'
    & jar --create --file (Join-Path $fixture 'simulationclient/target/dependency/util-old.jar') -C (Join-Path $fixture 'old-classes') .
    Assert ($LASTEXITCODE -eq 0) 'Stale JAR fixture failed'
    Push-Location $fixture
    try { $loaded=& java -cp $ClassPath ClasspathProbe; Assert ($LASTEXITCODE -eq 0 -and $loaded -eq 'CURRENT_UTIL') 'Client would load stale util bytecode' }
    finally { Pop-Location }
    Write-Output 'PASS: staged-only commit/push, dirty pull rejection, clean fast-forward and current util bytecode priority'
} finally {
    $physical=Resolve-PhysicalPathIdentity $fixture
    $temp=(Resolve-PhysicalPathIdentity ([IO.Path]::GetTempPath())).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if ($physical.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $physical) -like 'workspace-tooling-*') { Remove-Item -LiteralPath $physical -Recurse -Force }
}
