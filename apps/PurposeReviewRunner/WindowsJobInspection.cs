using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace PurposeReviewRunner;

public enum WindowsWorkerLaunchStrategy
{
    DetachedCreateProcess,
    ExternalWin32ProcessCreate
}

public sealed record WindowsJobSnapshot(
    bool InJob,
    uint? LimitFlags,
    bool? BreakawayOk,
    bool? SilentBreakawayOk,
    bool? KillOnJobClose)
{
    public const uint BreakawayOkFlag = 0x00000800;
    public const uint SilentBreakawayOkFlag = 0x00001000;
    public const uint KillOnJobCloseFlag = 0x00002000;

    public static WindowsJobSnapshot NotInJob() =>
        new(false, null, null, null, null);

    public static WindowsJobSnapshot FromLimitFlags(uint limitFlags) =>
        new(
            true,
            limitFlags,
            (limitFlags & BreakawayOkFlag) != 0,
            (limitFlags & SilentBreakawayOkFlag) != 0,
            (limitFlags & KillOnJobCloseFlag) != 0);
}

public static class WindowsWorkerLaunchStrategySelector
{
    public const uint DetachedProcess = 0x00000008;
    public const uint CreateNewProcessGroup = 0x00000200;
    public const uint CreateUnicodeEnvironment = 0x00000400;
    public const uint CreateBreakawayFromJob = 0x01000000;

    public static readonly uint BaseCreationFlags = DetachedProcess | CreateNewProcessGroup | CreateUnicodeEnvironment;

    public static WindowsWorkerLaunchStrategy Select(WindowsJobSnapshot snapshot)
    {
        // nested Job では QueryInformationJobObject(NULL) は immediate Job しか返さない。
        // immediate Job の breakaway 許可だけを見て CreateProcess すると ancestor の KillOnJobClose に残る。
        // Job 内は一律 Win32_Process.Create で呼び出し元 Job chain を切る。
        return snapshot.InJob
            ? WindowsWorkerLaunchStrategy.ExternalWin32ProcessCreate
            : WindowsWorkerLaunchStrategy.DetachedCreateProcess;
    }

    public static uint GetCreationFlags(WindowsWorkerLaunchStrategy strategy) => strategy switch
    {
        WindowsWorkerLaunchStrategy.DetachedCreateProcess => BaseCreationFlags,
        // WMI provider host 側 Job に残さないため CREATE_BREAKAWAY_FROM_JOB は必須。失敗時のフラグなし再試行はしない。
        WindowsWorkerLaunchStrategy.ExternalWin32ProcessCreate => BaseCreationFlags | CreateBreakawayFromJob,
        _ => throw new ArgumentOutOfRangeException(nameof(strategy), strategy, "Unsupported Windows worker launch strategy.")
    };

    public static string ToLogName(WindowsWorkerLaunchStrategy strategy) => strategy switch
    {
        WindowsWorkerLaunchStrategy.DetachedCreateProcess => "detached-create-process",
        WindowsWorkerLaunchStrategy.ExternalWin32ProcessCreate => "external-win32-process-create",
        _ => strategy.ToString()
    };

    public static bool UsesCreateProcess(WindowsWorkerLaunchStrategy strategy) =>
        strategy != WindowsWorkerLaunchStrategy.ExternalWin32ProcessCreate;
}

public interface IWindowsJobInspector
{
    WindowsJobSnapshot InspectCurrentProcess();
}

public sealed class WindowsJobInspector : IWindowsJobInspector
{
    public WindowsJobSnapshot InspectCurrentProcess()
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("Windows job inspection requires Windows.");
        }

        return InspectCurrentProcessWindows();
    }

    [SupportedOSPlatform("windows")]
    private static WindowsJobSnapshot InspectCurrentProcessWindows()
    {
        if (!NativeMethods.IsProcessInJob(NativeMethods.GetCurrentProcess(), IntPtr.Zero, out var inJob))
        {
            throw CreateNativeFailure("The current process job membership could not be queried.");
        }

        if (!inJob)
        {
            return WindowsJobSnapshot.NotInJob();
        }

        var information = new NativeMethods.JobObjectExtendedLimitInformation();
        var size = Marshal.SizeOf<NativeMethods.JobObjectExtendedLimitInformation>();
        if (!NativeMethods.QueryInformationJobObject(
                IntPtr.Zero,
                NativeMethods.JobObjectExtendedLimitInformationClass,
                ref information,
                size,
                out _))
        {
            var nativeError = Marshal.GetLastWin32Error();
            Trace.TraceError(new Win32Exception(nativeError).ToString());
            return new WindowsJobSnapshot(true, null, null, null, null);
        }

        return WindowsJobSnapshot.FromLimitFlags(information.BasicLimitInformation.LimitFlags);
    }

    private static RunnerException CreateNativeFailure(string message)
    {
        var nativeError = Marshal.GetLastWin32Error();
        var exception = new Win32Exception(nativeError);
        Trace.TraceError(exception.ToString());
        return new RunnerException(
            "WORKER_START_FAILED",
            $"{message} {exception.Message} (Win32 error {nativeError})",
            ExitCodes.RuntimeError,
            exception);
    }
}

internal static class NativeMethods
{
    public const int JobObjectExtendedLimitInformationClass = 9;

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetCurrentProcess();

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool IsProcessInJob(IntPtr processHandle, IntPtr jobHandle, out bool result);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool QueryInformationJobObject(
        IntPtr jobHandle,
        int jobObjectInformationClass,
        ref JobObjectExtendedLimitInformation jobObjectInformation,
        int jobObjectInformationLength,
        out int returnLength);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CreateProcess(
        string? lpApplicationName,
        System.Text.StringBuilder lpCommandLine,
        IntPtr lpProcessAttributes,
        IntPtr lpThreadAttributes,
        bool bInheritHandles,
        uint dwCreationFlags,
        IntPtr lpEnvironment,
        string? lpCurrentDirectory,
        ref StartupInfo lpStartupInfo,
        out ProcessInformation lpProcessInformation);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr handle);

    [StructLayout(LayoutKind.Sequential)]
    public struct IoCounters
    {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct JobObjectBasicLimitInformation
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public nuint MinimumWorkingSetSize;
        public nuint MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public nuint Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct JobObjectExtendedLimitInformation
    {
        public JobObjectBasicLimitInformation BasicLimitInformation;
        public IoCounters IoInfo;
        public nuint ProcessMemoryLimit;
        public nuint JobMemoryLimit;
        public nuint PeakProcessMemoryUsed;
        public nuint PeakJobMemoryUsed;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct StartupInfo
    {
        public int Cb;
        public IntPtr LpReserved;
        public IntPtr LpDesktop;
        public IntPtr LpTitle;
        public int DwX;
        public int DwY;
        public int DwXSize;
        public int DwYSize;
        public int DwXCountChars;
        public int DwYCountChars;
        public int DwFillAttribute;
        public int DwFlags;
        public short WShowWindow;
        public short CbReserved2;
        public IntPtr LpReserved2;
        public IntPtr HStdInput;
        public IntPtr HStdOutput;
        public IntPtr HStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct ProcessInformation
    {
        public IntPtr HProcess;
        public IntPtr HThread;
        public int DwProcessId;
        public int DwThreadId;
    }
}
