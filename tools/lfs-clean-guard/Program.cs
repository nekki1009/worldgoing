using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

// Repository-local clean filter. Downloads and pointer parsing remain upstream Git LFS.
// Windows closes this process's handles even after TerminateProcess: no orphan temp copy.
internal static class Program
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CreateHardLink(string newName, string existingName, IntPtr security);

    private static int Main(string[] arguments)
    {
        try
        {
            if (!OperatingSystem.IsWindows())
                throw new NotSupportedException("This clean filter requires Windows.");
            if (arguments.Length == 0)
                Clean(Console.OpenStandardInput(), Console.OpenStandardOutput());
            else if (arguments.Length == 1 && arguments[0] == "--filter-process")
                FilterProtocol.Run();
            else
                throw new ArgumentException("Expected no arguments or --filter-process.");
            return 0;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine("LFS clean guard: " + error.Message);
            return 1;
        }
    }

    internal static void Clean(Stream input, Stream output)
    {
        var extensions = Run("git", ["config", "--get-regexp", @"^lfs\.extension\."]);
        if (extensions.ExitCode == 0)
            throw new NotSupportedException("Custom LFS extensions are not supported; restore the upstream clean filter before enabling them.");
        if (extensions.ExitCode != 1)
            throw new IOException("Cannot check Git LFS extension configuration: " + extensions.Error);

        var prefix = new byte[1024];
        int prefixLength = input.ReadAtLeast(prefix, prefix.Length, throwOnEndOfStream: false);
        if (prefixLength == 0) return; // Git LFS represents empty input as empty input.
        if (prefixLength < prefix.Length)
        {
            var check = Run("git-lfs", ["pointer", "--check", "--stdin"], prefix.AsMemory(0, prefixLength));
            if (check.ExitCode == 0)
            {
                output.Write(prefix, 0, prefixLength); // Preserve canonical and accepted legacy pointers byte-for-byte.
                return;
            }
            if (check.ExitCode != 1) throw new IOException("Upstream pointer validation failed.");
        }

        var environment = Run("git-lfs", ["env"]);
        if (environment.ExitCode != 0) throw new IOException("Cannot resolve Git LFS storage: " + environment.Error);
        string media = EnvironmentPath(environment.Output, "LocalMediaDir=");
        string temporaryDirectory = EnvironmentPath(environment.Output, "TempDir=");
        Directory.CreateDirectory(temporaryDirectory);
        string temporaryPath = Path.Combine(temporaryDirectory, "clean-" + Guid.NewGuid().ToString("N") + ".tmp");

        using var temporary = new FileStream(temporaryPath, FileMode.CreateNew, FileAccess.Write,
            FileShare.Read | FileShare.Delete, 65536, FileOptions.DeleteOnClose | FileOptions.SequentialScan);
        using var digest = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        temporary.Write(prefix, 0, prefixLength);
        digest.AppendData(prefix, 0, prefixLength);
        long length = prefixLength;
        var buffer = new byte[1024 * 1024];
        int count;
        while ((count = input.Read(buffer)) != 0)
        {
            temporary.Write(buffer, 0, count);
            digest.AppendData(buffer, 0, count);
            length = checked(length + count);
        }
        temporary.Flush(flushToDisk: true);
        string oid = Convert.ToHexString(digest.GetHashAndReset()).ToLowerInvariant();
        string objectDirectory = Path.Combine(media, oid[..2], oid[2..4]);
        Directory.CreateDirectory(objectDirectory);
        string objectPath = Path.Combine(objectDirectory, oid);

        // Publish only a fully written object. Closing the handle removes the temp name,
        // while the completed object's hard link survives. Concurrent identical writes are safe.
        if (!File.Exists(objectPath) && !CreateHardLink(objectPath, temporaryPath, IntPtr.Zero))
        {
            int error = Marshal.GetLastWin32Error();
            if (error != 80 && error != 183) throw new Win32Exception(error, "Cannot publish completed LFS object.");
        }
        if (new FileInfo(objectPath).Length != length)
            throw new IOException("Existing LFS object size does not match its content address.");

        output.Write(Encoding.ASCII.GetBytes($"version https://git-lfs.github.com/spec/v1\noid sha256:{oid}\nsize {length}\n"));
    }

    private static string EnvironmentPath(string text, string prefix)
    {
        string? line = text.Split('\n').SingleOrDefault(line => line.StartsWith(prefix, StringComparison.Ordinal));
        if (line is null) throw new IOException("Missing Git LFS storage field: " + prefix);
        string path = line[prefix.Length..].TrimEnd('\r');
        if (!Path.IsPathFullyQualified(path)) throw new IOException("Git LFS storage path must be absolute.");
        return path;
    }

    private static (int ExitCode, string Output, string Error) Run(string executable, string[] arguments, ReadOnlyMemory<byte>? input = null)
    {
        var start = new ProcessStartInfo(executable)
        {
            UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
        };
        foreach (string argument in arguments) start.ArgumentList.Add(argument);
        using var process = Process.Start(start) ?? throw new IOException("Could not start " + executable);
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();
        if (input is not null) process.StandardInput.BaseStream.Write(input.Value.Span);
        process.StandardInput.Close();
        if (!process.WaitForExit(15000))
        {
            process.Kill(entireProcessTree: true);
            process.WaitForExit();
            throw new IOException(executable + " did not finish within 15 seconds.");
        }
        return (process.ExitCode, stdout.GetAwaiter().GetResult(), stderr.GetAwaiter().GetResult());
    }
}
