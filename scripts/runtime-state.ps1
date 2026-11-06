#requires -Version 7.0
# 同一快照的生命周期锁：保留锁文件，仅释放句柄，避免删除重建导致双锁。
function Enter-RuntimeSnapshotLock([string]$Snapshot) {
    try { return [IO.File]::Open((Join-Path $Snapshot 'lifecycle.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
    catch [IO.IOException] { throw 'LOCAL_RUNTIME_BUSY: another lifecycle operation owns this snapshot' }
}

# 同目录原子替换；调用者持锁，写入失败不会留下截断的登记文件。
function Write-RuntimeProcessState([string]$Path,$Records) {
    $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        $bytes=[Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @($Records) -Depth 8))
        $stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $stream.Write($bytes); $stream.Flush($true) } finally { $stream.Dispose() }
        [IO.File]::Move($temporary,$Path,$true)
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
}
