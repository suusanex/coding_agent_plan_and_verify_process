using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace PurposeReviewRunner;

public sealed class DetachedWorkerLauncher : IWorkerLauncher
{
    private const uint CreateBreakawayFromJob = 0x01000000;
    private const uint CreateNewProcessGroup = 0x00000200;
    private const uint CreateUnicodeEnvironment = 0x00000400;
    private const uint DetachedProcess = 0x00000008;

    public WorkerLaunchResult Launch(string runId)
    {
        var executable = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(executable) || !File.Exists(executable))
        {
            throw new RunnerException("WORKER_START_FAILED", "The runner executable path was not available.", ExitCodes.RuntimeError);
        }

        return OperatingSystem.IsWindows()
            ? LaunchWindows(executable, runId)
            : LaunchUnix(executable, runId);
    }

    private static WorkerLaunchResult LaunchWindows(string executable, string runId)
    {
        var detachedFlags = DetachedProcess | CreateNewProcessGroup | CreateUnicodeEnvironment;
        if (!TryCreateWindowsProcess(executable, runId, detachedFlags | CreateBreakawayFromJob, out var information, out var firstError))
        {
            Trace.TraceError(new Win32Exception(firstError).ToString());
            // 呼び出し元jobがBREAKAWAY_OKを許可しない場合でも独立processは起動する。in-process実行へは落とさない。
            var retryError = firstError;
            if (firstError != 5 || !TryCreateWindowsProcess(executable, runId, detachedFlags, out information, out retryError))
            {
                var error = new Win32Exception(retryError);
                Trace.TraceError(error.ToString());
                throw new RunnerException("WORKER_START_FAILED", $"The review worker process did not start: {error.Message}", ExitCodes.RuntimeError, error);
            }
        }

        try
        {
            return ReadLaunchResult(information.DwProcessId);
        }
        finally
        {
            if (information.HProcess != IntPtr.Zero)
            {
                CloseHandle(information.HProcess);
            }
            if (information.HThread != IntPtr.Zero)
            {
                CloseHandle(information.HThread);
            }
        }
    }

    private static WorkerLaunchResult LaunchUnix(string executable, string runId)
    {
        const string setsid = "/usr/bin/setsid";
        if (!File.Exists(setsid))
        {
            throw new RunnerException("WORKER_START_FAILED", "setsid was not found at /usr/bin/setsid.", ExitCodes.RuntimeError);
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = setsid,
            WorkingDirectory = Path.GetDirectoryName(executable) ?? Environment.CurrentDirectory,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = false,
            RedirectStandardOutput = false,
            RedirectStandardError = false
        };
        startInfo.ArgumentList.Add(executable);
        startInfo.ArgumentList.Add("work");
        startInfo.ArgumentList.Add("--run");
        startInfo.ArgumentList.Add(runId);

        try
        {
            using var process = Process.Start(startInfo)
                ?? throw new RunnerException("WORKER_START_FAILED", "The review worker process did not start.", ExitCodes.RuntimeError);
            return ReadLaunchResult(process.Id);
        }
        catch (RunnerException)
        {
            throw;
        }
        catch (Exception exception)
        {
            throw new RunnerException("WORKER_START_FAILED", $"The review worker process did not start: {exception.Message}", ExitCodes.RuntimeError, exception);
        }
    }

    private static bool TryCreateWindowsProcess(string executable, string runId, uint flags, out ProcessInformation information, out int error)
    {
        var commandLine = new StringBuilder();
        commandLine.Append('"').Append(executable.Replace("\"", "\\\"", StringComparison.Ordinal)).Append('"');
        commandLine.Append(" work --run ").Append(runId);
        var startupInfo = new StartupInfo { Cb = Marshal.SizeOf<StartupInfo>() };
        var started = CreateProcess(
            executable,
            commandLine,
            IntPtr.Zero,
            IntPtr.Zero,
            false,
            flags,
            IntPtr.Zero,
            Path.GetDirectoryName(executable),
            ref startupInfo,
            out information);
        error = started ? 0 : Marshal.GetLastWin32Error();
        return started;
    }

    private static WorkerLaunchResult ReadLaunchResult(int processId)
    {
        try
        {
            using var process = Process.GetProcessById(processId);
            return new(processId, new DateTimeOffset(process.StartTime.ToUniversalTime()));
        }
        catch (Exception exception)
        {
            Trace.TraceError(exception.ToString());
            return new(processId, DateTimeOffset.UtcNow);
        }
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CreateProcess(
        string? lpApplicationName,
        StringBuilder lpCommandLine,
        IntPtr lpProcessAttributes,
        IntPtr lpThreadAttributes,
        bool bInheritHandles,
        uint dwCreationFlags,
        IntPtr lpEnvironment,
        string? lpCurrentDirectory,
        ref StartupInfo lpStartupInfo,
        out ProcessInformation lpProcessInformation);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct StartupInfo
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
    private struct ProcessInformation
    {
        public IntPtr HProcess;
        public IntPtr HThread;
        public int DwProcessId;
        public int DwThreadId;
    }
}
