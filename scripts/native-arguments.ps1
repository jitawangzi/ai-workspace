#requires -Version 7.0
# Windows 原生命令参数编码：保留空参数、空格、引号及引号前/末尾反斜杠。
function ConvertTo-NativeArgument {
    param([AllowEmptyString()][string]$Value)
    '"'+[regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'
}
# 读取Windows实际参数边界，不能把引号内的普通文本当作独立身份参数。
function ConvertFrom-NativeCommandLine([string]$CommandLine) {
    if(-not ('RuntimeNativeArgv' -as [type])){
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class RuntimeNativeArgv {
    [DllImport("shell32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr CommandLineToArgvW(string command, out int count);
    [DllImport("kernel32.dll")]
    public static extern IntPtr LocalFree(IntPtr memory);
}
'@
    }
    $count=0;$memory=[RuntimeNativeArgv]::CommandLineToArgvW($CommandLine,[ref]$count)
    if($memory -eq [IntPtr]::Zero){throw 'NATIVE_COMMAND_LINE_PARSE_FAILED'}
    try {for($i=0;$i -lt $count;$i++){[Runtime.InteropServices.Marshal]::PtrToStringUni([Runtime.InteropServices.Marshal]::ReadIntPtr($memory,$i*[IntPtr]::Size))}}
    finally {$null=[RuntimeNativeArgv]::LocalFree($memory)}
}
