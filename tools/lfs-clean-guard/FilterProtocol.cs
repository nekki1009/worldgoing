using System.Diagnostics;
using System.Globalization;
using System.Text;

// Git's documented long-running filter v2 protocol. Clean output is a tiny pointer;
// smudge streams through the installed Git LFS client, including its normal downloads.
internal static class FilterProtocol
{
    internal static void Run()
    {
        Stream input = Console.OpenStandardInput(), output = Console.OpenStandardOutput();
        if (!Headers(input).SequenceEqual(["git-filter-client", "version=2"]))
            throw new IOException("Unsupported Git filter handshake.");
        Text(output, "git-filter-server");
        Text(output, "version=2");
        Flush(output);
        var capabilities = Headers(input);
        foreach (string capability in new[] { "capability=clean", "capability=smudge" })
            if (capabilities.Contains(capability)) Text(output, capability);
        Flush(output);

        while (true)
        {
            var headers = Headers(input);
            if (headers.Count == 0) return;
            using var content = new ContentStream(input);
            string? command = headers.SingleOrDefault(header => header.StartsWith("command="));
            if (command == "command=smudge")
            {
                string? pathname = headers.SingleOrDefault(header => header.StartsWith("pathname="));
                // Streaming has already sent its initial status. A transport exception must
                // end the process, rather than write a second initial status into file content.
                Smudge(content, output, pathname?["pathname=".Length..]);
                continue;
            }
            try
            {
                if (command != "command=clean") throw new IOException("Unsupported Git filter command.");
                using var pointer = new MemoryStream();
                Program.Clean(content, pointer);
                Text(output, "status=success");
                Flush(output);
                Packet(output, pointer.ToArray());
                Flush(output);
                Flush(output);
            }
            catch (Exception error)
            {
                content.CopyTo(Stream.Null); // Finish the request before accepting another one.
                Console.Error.WriteLine("LFS clean guard: " + error.Message);
                Text(output, "status=error");
                Flush(output);
            }
        }
    }

    private static void Smudge(Stream content, Stream output, string? pathname)
    {
        var start = new ProcessStartInfo("git-lfs")
        {
            UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true
        };
        start.ArgumentList.Add("smudge");
        if (pathname is not null)
        {
            start.ArgumentList.Add("--");
            start.ArgumentList.Add(pathname);
        }
        using var process = Process.Start(start) ?? throw new IOException("Could not start upstream Git LFS.");
        var error = process.StandardError.ReadToEndAsync();
        Exception? feedError = null;
        // Feed and receive concurrently: historical non-LFS blobs can exceed pipe capacity.
        var feed = Task.Run(async () =>
        {
            try { await content.CopyToAsync(process.StandardInput.BaseStream); }
            catch (IOException failure) { feedError = failure; content.CopyTo(Stream.Null); }
            finally { process.StandardInput.Close(); }
        });
        try
        {
            Text(output, "status=success");
            Flush(output);
            var buffer = new byte[65516];
            int count;
            while ((count = process.StandardOutput.BaseStream.Read(buffer)) != 0)
                Packet(output, buffer.AsSpan(0, count));
            Flush(output);
            feed.GetAwaiter().GetResult();
            process.WaitForExit(); // Keep upstream transfer/cancellation behavior for downloads.
            if (process.ExitCode != 0 || feedError is not null)
            {
                Console.Error.Write(error.GetAwaiter().GetResult());
                if (feedError is not null) Console.Error.WriteLine(feedError.Message);
                Text(output, "status=error");
            }
            Flush(output);
        }
        catch
        {
            if (!process.HasExited) process.Kill(entireProcessTree: true);
            throw;
        }
    }

    private static List<string> Headers(Stream input)
    {
        var headers = new List<string>();
        byte[]? packet;
        while ((packet = ReadPacket(input)) is { Length: > 0 })
            headers.Add(Encoding.UTF8.GetString(packet).TrimEnd('\n'));
        return headers;
    }

    private static byte[]? ReadPacket(Stream input)
    {
        Span<byte> header = stackalloc byte[4];
        int read = input.ReadAtLeast(header, 4, throwOnEndOfStream: false);
        if (read == 0) return null;
        if (read != 4) throw new EndOfStreamException("Truncated Git packet header.");
        int length = int.Parse(Encoding.ASCII.GetString(header), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        if (length == 0) return [];
        if (length < 4 || length > 65520) throw new IOException("Invalid Git packet length.");
        var payload = new byte[length - 4];
        input.ReadExactly(payload);
        return payload;
    }

    private static void Text(Stream output, string text) => Packet(output, Encoding.UTF8.GetBytes(text + "\n"));
    private static void Flush(Stream output) { output.Write("0000"u8); output.Flush(); }
    private static void Packet(Stream output, ReadOnlySpan<byte> payload)
    {
        if (payload.Length == 0) return;
        output.Write(Encoding.ASCII.GetBytes((payload.Length + 4).ToString("x4", CultureInfo.InvariantCulture)));
        output.Write(payload);
    }

    private sealed class ContentStream(Stream input) : Stream
    {
        private byte[] packet = [];
        private int offset;
        private bool finished;
        public override int Read(byte[] buffer, int start, int count)
        {
            if (count == 0 || finished) return 0;
            if (offset == packet.Length)
            {
                packet = ReadPacket(input) ?? throw new EndOfStreamException("Truncated Git file content.");
                offset = 0;
                if (packet.Length == 0) { finished = true; return 0; }
            }
            int take = Math.Min(count, packet.Length - offset);
            packet.AsSpan(offset, take).CopyTo(buffer.AsSpan(start, take));
            offset += take;
            return take;
        }
        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => throw new NotSupportedException();
        public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
        public override void Flush() { }
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    }
}
