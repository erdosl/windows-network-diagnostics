using System;
using System.Runtime.InteropServices;
using System.ComponentModel;
namespace NetworkDiagnostics {
    public static class NativeInventory {
        [StructLayout(LayoutKind.Sequential)] struct ProxyInfo { public uint Access; public IntPtr Proxy; public IntPtr Bypass; }
        [DllImport("winhttp.dll",SetLastError=true)] static extern bool WinHttpGetDefaultProxyConfiguration(out ProxyInfo info);
        [DllImport("kernel32.dll")] static extern IntPtr GlobalFree(IntPtr value);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr LoadLibraryEx(string name,IntPtr file,uint flags);
        [DllImport("kernel32.dll",CharSet=CharSet.Ansi,ExactSpelling=true)] static extern IntPtr GetProcAddress(IntPtr module,string name);
        [DllImport("kernel32.dll")] static extern bool FreeLibrary(IntPtr module);
        public static string[] DefaultProxy() {
            ProxyInfo info;if(!WinHttpGetDefaultProxyConfiguration(out info))throw new Win32Exception(Marshal.GetLastWin32Error());
            try {return new string[]{info.Access.ToString(),Marshal.PtrToStringUni(info.Proxy),Marshal.PtrToStringUni(info.Bypass)};}
            finally {if(info.Proxy!=IntPtr.Zero)GlobalFree(info.Proxy);if(info.Bypass!=IntPtr.Zero)GlobalFree(info.Bypass);}
        }
        public static bool HasCaptureSessionApi() {
            // Inspect export availability only. Do not initialize the capture driver.
            IntPtr module=LoadLibraryEx(System.IO.Path.Combine(Environment.SystemDirectory,"pktmonapi.dll"),IntPtr.Zero,0x800);
            if(module==IntPtr.Zero)return false;
            try {foreach(string name in new string[]{"PacketMonitorInitialize","PacketMonitorCreateLiveSession","PacketMonitorSetSessionActive","PacketMonitorAddCaptureConstraint","PacketMonitorCloseSessionHandle"})if(GetProcAddress(module,name)==IntPtr.Zero)return false;return true;}
            finally {FreeLibrary(module);}
        }
    }
}
