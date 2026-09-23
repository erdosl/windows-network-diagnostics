using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace NetworkDiagnostics {
    // A suspended process is assigned before any worker code can run. Closing the
    // non-inheritable job handle kills every descendant, including native tools.
    public sealed class WorkerProcess : IDisposable {
        private IntPtr job, process;
        public int Id { get; private set; }
        [StructLayout(LayoutKind.Sequential)] struct IO_COUNTERS {
            public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount;
            public ulong ReadTransferCount, WriteTransferCount, OtherTransferCount;
        }
        [StructLayout(LayoutKind.Sequential)] struct BASIC_LIMIT {
            public long PerProcessUserTimeLimit, PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass, SchedulingClass;
        }
        [StructLayout(LayoutKind.Sequential)] struct EXTENDED_LIMIT {
            public BASIC_LIMIT BasicLimitInformation;
            public IO_COUNTERS IoInfo;
            public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
        }
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct STARTUPINFO {
            public uint cb;
            public string lpReserved, lpDesktop, lpTitle;
            public uint dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
            public ushort wShowWindow, cbReserved2;
            public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
        }
        [StructLayout(LayoutKind.Sequential)] struct PROCESS_INFORMATION {
            public IntPtr hProcess, hThread;
            public uint dwProcessId, dwThreadId;
        }
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr attributes, string name);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job, int kind, ref EXTENDED_LIMIT info, uint length);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CreateProcess(string application, StringBuilder command, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr environment, string directory, ref STARTUPINFO startup, out PROCESS_INFORMATION pi);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [DllImport("kernel32.dll", SetLastError=true)] static extern uint ResumeThread(IntPtr thread);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool TerminateJobObject(IntPtr job, uint exitCode);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool TerminateProcess(IntPtr process, uint exitCode);
        [DllImport("kernel32.dll", SetLastError=true)] static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
        public WorkerProcess(string executable, string arguments, string directory) {
            PROCESS_INFORMATION pi = new PROCESS_INFORMATION();
            try {
                job = CreateJobObject(IntPtr.Zero, null);
                if (job == IntPtr.Zero) throw new Win32Exception();
                EXTENDED_LIMIT limit = new EXTENDED_LIMIT();
                limit.BasicLimitInformation.LimitFlags = 0x2000; // KILL_ON_JOB_CLOSE
                if (!SetInformationJobObject(job, 9, ref limit, (uint)Marshal.SizeOf(limit))) throw new Win32Exception();
                STARTUPINFO startup = new STARTUPINFO();
                startup.cb = (uint)Marshal.SizeOf(startup);
                if (!CreateProcess(executable, new StringBuilder("\"" + executable + "\" " + arguments), IntPtr.Zero, IntPtr.Zero,
                    false, 0x08000004, IntPtr.Zero, directory, ref startup, out pi)) throw new Win32Exception(); // NO_WINDOW | SUSPENDED
                process = pi.hProcess;
                Id = (int)pi.dwProcessId;
                if (!AssignProcessToJobObject(job, process)) throw new Win32Exception();
                if (ResumeThread(pi.hThread) == 0xffffffff) throw new Win32Exception();
            } catch {
                if (process != IntPtr.Zero) { TerminateProcess(process, 1); WaitForSingleObject(process, 5000); }
                Dispose();
                throw;
            } finally { if (pi.hThread != IntPtr.Zero) CloseHandle(pi.hThread); }
        }
        public bool Wait(int milliseconds) {
            uint result = WaitForSingleObject(process, (uint)milliseconds);
            if (result == 0xffffffff) throw new Win32Exception();
            return result == 0;
        }
        public void Dispose() {
            // Termination is not cooperative: blocked cmdlets cannot keep running.
            if (job != IntPtr.Zero) { TerminateJobObject(job, 1); CloseHandle(job); job = IntPtr.Zero; }
            if (process != IntPtr.Zero) { WaitForSingleObject(process, 5000); CloseHandle(process); process = IntPtr.Zero; }
            GC.SuppressFinalize(this);
        }
        ~WorkerProcess() { Dispose(); }
    }
}
