using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using Microsoft.Win32.SafeHandles;
// 只修改监督者已持有句柄的专用进程 DACL；原始描述符用于精确恢复。
public static class SopFixtureAcl {
 [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool DuplicateHandle(IntPtr sourceProcess,SafeProcessHandle source,IntPtr targetProcess,out SafeProcessHandle target,uint access,bool inherit,uint options);
 // 复制启动时的真实句柄，不根据可能复用的 PID 重新选择权限修改目标。
 public static SafeProcessHandle Retain(SafeProcessHandle source){SafeProcessHandle target;if(!DuplicateHandle(GetCurrentProcess(),source,GetCurrentProcess(),out target,0,false,2))throw new Win32Exception();return target;}
 [DllImport("kernel32.dll",SetLastError=true)] public static extern SafeProcessHandle OpenProcess(uint access,bool inherit,uint pid);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetKernelObjectSecurity(SafeProcessHandle h,uint info,byte[] sd,uint length,out uint needed);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool SetKernelObjectSecurity(SafeProcessHandle h,uint info,byte[] sd);
 [DllImport("kernel32.dll",SetLastError=true)] public static extern uint WaitForSingleObject(SafeProcessHandle h,uint ms);
 public static uint WaitChecked(SafeProcessHandle h,uint ms){uint result=WaitForSingleObject(h,ms);if(result!=0 && result!=258)throw new Win32Exception(Marshal.GetLastWin32Error(),"Unexpected process wait result: "+result);return result;}
 [DllImport("kernel32.dll",SetLastError=true)] public static extern bool TerminateProcess(SafeProcessHandle h,uint code);
 public static byte[] Read(SafeProcessHandle h) {uint n;GetKernelObjectSecurity(h,4,null,0,out n);if(n==0)throw new Win32Exception();var b=new byte[n];if(!GetKernelObjectSecurity(h,4,b,n,out n))throw new Win32Exception();return b;}
 public static void Restore(SafeProcessHandle h,byte[] b){if(!SetKernelObjectSecurity(h,4,b))throw new Win32Exception();}
 public static void Deny(SafeProcessHandle h,byte[] original,string sid){var sd=new RawSecurityDescriptor(original,0);if(sd.DiscretionaryAcl==null)throw new InvalidOperationException("NULL_DACL_UNSUPPORTED");sd.DiscretionaryAcl.InsertAce(0,new CommonAce(AceFlags.None,AceQualifier.AccessDenied,0x1411,new SecurityIdentifier(sid),false,null));var b=new byte[sd.BinaryLength];sd.GetBinaryForm(b,0);Restore(h,b);}
 public static int QueryError(uint pid){using(var h=OpenProcess(0x1000,false,pid)){return h.IsInvalid?Marshal.GetLastWin32Error():0;}}
}
