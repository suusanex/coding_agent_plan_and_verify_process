using System.Collections;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.Management;
using System.Runtime.Versioning;
using System.Text;

namespace PurposeReviewRunner;

public sealed record WindowsProcessLaunchRequest(
    string Executable,
    string CommandLine,
    string? WorkingDirectory,
    uint CreationFlags)
{
    public static WindowsProcessLaunchRequest ForWorker(string executable, string runId, uint creationFlags)
    {
        var commandLine = new StringBuilder();
        commandLine.Append('"').Append(executable.Replace("\"", "\\\"", StringComparison.Ordinal)).Append('"');
        commandLine.Append(" work --run ").Append(runId);
        return new(executable, commandLine.ToString(), Path.GetDirectoryName(executable), creationFlags);
    }
}

public sealed record WindowsProcessLaunchResult(
    bool Success,
    int? ProcessId,
    int NativeErrorCode,
    string NativeErrorMessage,
    string LaunchApi,
    uint CreationFlags,
    uint? WmiReturnValue = null);

public interface IWindowsProcessLauncher
{
    WindowsProcessLaunchResult CreateDetachedProcess(WindowsProcessLaunchRequest request);

    WindowsProcessLaunchResult CreateExternalProcess(WindowsProcessLaunchRequest request);
}

public sealed class WindowsProcessLauncher : IWindowsProcessLauncher
{
    public WindowsProcessLaunchResult CreateDetachedProcess(WindowsProcessLaunchRequest request)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("CreateProcess worker launch requires Windows.");
        }

        return CreateDetachedProcessWindows(request);
    }

    public WindowsProcessLaunchResult CreateExternalProcess(WindowsProcessLaunchRequest request)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("Win32_Process.Create worker launch requires Windows.");
        }

        return CreateExternalProcessWindows(request);
    }

    public static string[] CaptureCurrentEnvironmentBlock()
    {
        var variables = new List<string>();
        foreach (DictionaryEntry entry in Environment.GetEnvironmentVariables())
        {
            var name = entry.Key as string;
            if (string.IsNullOrEmpty(name) || name.Contains('=', StringComparison.Ordinal))
            {
                continue;
            }

            variables.Add(name + "=" + (entry.Value as string ?? string.Empty));
        }

        return variables.ToArray();
    }

    [SupportedOSPlatform("windows")]
    private static WindowsProcessLaunchResult CreateDetachedProcessWindows(WindowsProcessLaunchRequest request)
    {
        var commandLine = new StringBuilder(request.CommandLine);
        var startupInfo = new NativeMethods.StartupInfo { Cb = System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.StartupInfo>() };
        var started = NativeMethods.CreateProcess(
            request.Executable,
            commandLine,
            IntPtr.Zero,
            IntPtr.Zero,
            false,
            request.CreationFlags,
            IntPtr.Zero,
            request.WorkingDirectory,
            ref startupInfo,
            out var information);
        if (!started)
        {
            var nativeError = System.Runtime.InteropServices.Marshal.GetLastWin32Error();
            var exception = new Win32Exception(nativeError);
            Trace.TraceError(exception.ToString());
            return new(
                false,
                null,
                nativeError,
                exception.Message,
                "CreateProcess",
                request.CreationFlags);
        }

        try
        {
            return new(
                true,
                information.DwProcessId,
                0,
                string.Empty,
                "CreateProcess",
                request.CreationFlags);
        }
        finally
        {
            if (information.HProcess != IntPtr.Zero)
            {
                NativeMethods.CloseHandle(information.HProcess);
            }

            if (information.HThread != IntPtr.Zero)
            {
                NativeMethods.CloseHandle(information.HThread);
            }
        }
    }

    [SupportedOSPlatform("windows")]
    private static WindowsProcessLaunchResult CreateExternalProcessWindows(WindowsProcessLaunchRequest request) =>
        InvokeWin32ProcessCreate(request);

    [SupportedOSPlatform("windows")]
    private static WindowsProcessLaunchResult InvokeWin32ProcessCreate(WindowsProcessLaunchRequest request)
    {
        try
        {
            using var processClass = new ManagementClass(@"\\.\root\cimv2:Win32_Process");
            using var startupClass = new ManagementClass(@"\\.\root\cimv2:Win32_ProcessStartup");
            using var startup = startupClass.CreateInstance()
                ?? throw new InvalidOperationException("Win32_ProcessStartup instance was not created.");
            startup["CreateFlags"] = request.CreationFlags;
            startup["ShowWindow"] = (ushort)0;
            startup["EnvironmentVariables"] = CaptureCurrentEnvironmentBlock();

            using var inParams = processClass.GetMethodParameters("Create");
            inParams["CommandLine"] = request.CommandLine;
            inParams["CurrentDirectory"] = request.WorkingDirectory;
            inParams["ProcessStartupInformation"] = startup;
            using var outParams = processClass.InvokeMethod("Create", inParams, null)
                ?? throw new InvalidOperationException("Win32_Process.Create returned no out parameters.");

            var returnValue = Convert.ToUInt32(outParams["ReturnValue"], CultureInfo.InvariantCulture);
            var processIdValue = outParams["ProcessId"];
            var processId = processIdValue is null ? 0 : Convert.ToInt32(processIdValue, CultureInfo.InvariantCulture);
            if (returnValue != 0)
            {
                return new(
                    false,
                    null,
                    unchecked((int)returnValue),
                    DescribeWmiCreateReturn(returnValue),
                    "Win32_Process.Create",
                    request.CreationFlags,
                    returnValue);
            }

            if (processId <= 0)
            {
                return new(
                    false,
                    null,
                    0,
                    "Win32_Process.Create succeeded but returned no process id.",
                    "Win32_Process.Create",
                    request.CreationFlags,
                    returnValue);
            }

            return new(
                true,
                processId,
                0,
                string.Empty,
                "Win32_Process.Create",
                request.CreationFlags,
                returnValue);
        }
        catch (Exception exception)
        {
            Trace.TraceError(exception.ToString());
            var nativeError = exception is Win32Exception win32 ? win32.NativeErrorCode : -1;
            var wmiReturn = exception is ManagementException management
                ? unchecked((uint)management.ErrorCode)
                : (uint?)null;
            return new(
                false,
                null,
                nativeError,
                exception.Message,
                "Win32_Process.Create",
                request.CreationFlags,
                wmiReturn);
        }
    }

    private static string DescribeWmiCreateReturn(uint returnValue) => returnValue switch
    {
        2 => "Access denied",
        3 => "Insufficient privilege",
        8 => "Unknown failure",
        9 => "Path not found",
        21 => "Invalid parameter",
        _ => "Create failed"
    };
}
