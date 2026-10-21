#requires -Version 7.0
<#
.SYNOPSIS
    在脚本所属仓库同步，仅提交已暂存内容或执行 fast-forward 拉取。
.PARAMETER Action
    Commit 提交暂存区并推送；Pull 要求工作树干净。
.PARAMETER Message
    提交说明，省略时交互输入。
#>
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Commit','Pull')][string]$Action,[string]$Message)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
function Invoke-Git([string[]]$GitArguments) {
    & git -C $repo @GitArguments
    if ($LASTEXITCODE -ne 0) { throw "Git failed ($LASTEXITCODE): $($GitArguments[0])" }
}
try {
    $actual=Invoke-Git @('rev-parse','--show-toplevel')
    if ([IO.Path]::GetFullPath(($actual -join '').Trim()) -ne $repo) { throw '脚本必须位于独立仓库的 scripts 目录，不能误操作父仓库。' }
    if ($Action -eq 'Pull') {
        $dirty=Invoke-Git @('status','--porcelain')
        if ($dirty) { throw '工作树有未提交内容，请先检查并处理，再拉取。' }
        Invoke-Git @('pull','--ff-only')
    } else {
        & git -C $repo diff --cached --quiet
        $diffExit=$LASTEXITCODE
        if ($diffExit -eq 0) { throw '暂存区为空；先 git add -- <本任务文件> 并检查 git diff --cached。' }
        if ($diffExit -ne 1) { throw '无法检查暂存区。' }
        Invoke-Git @('diff','--cached','--stat')
        if ([string]::IsNullOrWhiteSpace($Message)) { $Message=Read-Host '提交说明' }
        if ([string]::IsNullOrWhiteSpace($Message)) { throw '提交说明不能为空。' }
        Invoke-Git @('commit','-m',$Message)
        Invoke-Git @('push')
    }
} catch {
    [Console]::Error.WriteLine($_.ToString())
    exit 1
}
