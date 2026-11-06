#requires -Version 7.0
# Windows 原生命令参数编码：保留空参数、空格、引号及引号前/末尾反斜杠。
function ConvertTo-NativeArgument {
    param([AllowEmptyString()][string]$Value)
    '"'+[regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'
}
