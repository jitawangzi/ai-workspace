#requires -Version 7.0
# 独立进程观察真实查询权限，不继承监督句柄。
param([uint32]$TargetPid)
$ErrorActionPreference='Stop'
Add-Type -Path (Join-Path $PSScriptRoot 'fixtures/ProcessAclFixture.cs')
@{pid=$TargetPid;queryError=[SopFixtureAcl]::QueryError($TargetPid);commandLineReadable=(-not [string]::IsNullOrWhiteSpace((Get-CimInstance Win32_Process -Filter "ProcessId=$TargetPid").CommandLine))}|ConvertTo-Json -Compress
