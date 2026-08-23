using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace PurposeReviewRunnerRestrictiveJobHelper;

public static class Program
{
    private const uint JobObjectLimitKillOnJobClose = 0x00002000;
    private const int JobObjectExtendedLimitInformationClass = 9;

    public static int Main(string[] args)
    {
        if (!OperatingSystem.IsWindows())
        {
            Console.Error.WriteLine("Restrictive job helper requires Windows.");
            return 2;
        }

        return RunWindows(args);
    }

    [SupportedOSPlatform("windows")]
    private static int RunWindows(string[] args)
    {
        var runner = RequiredOption(args, "--runner");
        var repository = RequiredOption(args, "--repository");
        var context = RequiredOption(args, "--context");
        if (!File.Exists(runner))
        {
            Console.Error.WriteLine("Runner executable was not found: " + runner);
            return 2;
        }

        var job = CreateJobObject(IntPtr.Zero, IntPtr.Zero);
        if (job == IntPtr.Zero)
        {
            WriteNativeError("CreateJobObject");
            return 1;
        }

        try
        {
            var information = new JobObjectExtendedLimitInformation
            {
                BasicLimitInformation = new JobObjectBasicLimitInformation
                {
                    LimitFlags = JobObjectLimitKillOnJobClose
                }
            };
            var size = Marshal.SizeOf<JobObjectExtendedLimitInformation>();
            if (!SetInformationJobObject(job, JobObjectExtendedLimitInformationClass, ref information, size))
            {
                WriteNativeError("SetInformationJobObject");
                return 1;
            }

            if (!AssignProcessToJobObject(job, GetCurrentProcess()))
            {
                WriteNativeError("AssignProcessToJobObject");
                return 1;
            }

            var startInfo = new ProcessStartInfo
            {
                FileName = runner,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            startInfo.ArgumentList.Add("start");
            startInfo.ArgumentList.Add("--repository");
            startInfo.ArgumentList.Add(repository);
            startInfo.ArgumentList.Add("--context");
            startInfo.ArgumentList.Add(context);

            using var process = Process.Start(startInfo);
            if (process is null)
            {
                Console.Error.WriteLine("The purpose-review-runner start process did not start.");
                return 1;
            }

            var stdout = process.StandardOutput.ReadToEnd();
            var stderr = process.StandardError.ReadToEnd();
            process.WaitForExit();
            Console.Out.Write(stdout);
            Console.Error.Write(stderr);
            return process.ExitCode;
        }
        finally
        {
            CloseHandle(job);
        }
    }

    private static string RequiredOption(string[] args, string name)
    {
        var index = Array.IndexOf(args, name);
        if (index < 0 || index + 1 >= args.Length || string.IsNullOrWhiteSpace(args[index + 1]))
        {
            throw new InvalidOperationException(name + " is required.");
        }

        return args[index + 1];
    }

    private static void WriteNativeError(string api)
    {
        var error = Marshal.GetLastWin32Error();
        var exception = new Win32Exception(error);
        Console.Error.WriteLine(exception.ToString());
        Console.Error.WriteLine(api + " failed with Win32 error " + error + ": " + exception.Message);
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GetCurrentProcess();

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateJobObject(IntPtr jobAttributes, IntPtr name);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetInformationJobObject(
        IntPtr jobHandle,
        int jobObjectInformationClass,
        ref JobObjectExtendedLimitInformation jobObjectInformation,
        int jobObjectInformationLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AssignProcessToJobObject(IntPtr jobHandle, IntPtr processHandle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    [StructLayout(LayoutKind.Sequential)]
    private struct IoCounters
    {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct JobObjectBasicLimitInformation
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
    private struct JobObjectExtendedLimitInformation
    {
        public JobObjectBasicLimitInformation BasicLimitInformation;
        public IoCounters IoInfo;
        public nuint ProcessMemoryLimit;
        public nuint JobMemoryLimit;
        public nuint PeakProcessMemoryUsed;
        public nuint PeakJobMemoryUsed;
    }
}
