// Windows-only integration harness. Uses a real pseudoconsole and real PSReadLine.
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using Microsoft.Win32.SafeHandles;

public sealed class CommandHighlighterConPty : IDisposable
{
    [StructLayout(LayoutKind.Sequential)] struct Coord { public short X, Y; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct StartupInfo
    {
        public int cb; public string reserved, desktop, title;
        public int x, y, xSize, ySize, xChars, yChars, fill, flags;
        public short show, reserved2; public IntPtr reservedPtr, stdin, stdout, stderr;
    }
    [StructLayout(LayoutKind.Sequential)] struct StartupInfoEx { public StartupInfo info; public IntPtr attributes; }
    [StructLayout(LayoutKind.Sequential)] struct ProcessInfo { public IntPtr process, thread; public int processId, threadId; }
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool CreatePipe(out IntPtr read, out IntPtr write, IntPtr security, int size);
    [DllImport("kernel32.dll")] static extern int CreatePseudoConsole(Coord size, IntPtr input, IntPtr output, uint flags, out IntPtr console);
    [DllImport("kernel32.dll")] static extern void ClosePseudoConsole(IntPtr console);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool InitializeProcThreadAttributeList(IntPtr list, int count, int flags, ref IntPtr size);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool UpdateProcThreadAttribute(IntPtr list, uint flags, IntPtr attribute, IntPtr value, IntPtr size, IntPtr previous, IntPtr returned);
    [DllImport("kernel32.dll")] static extern void DeleteProcThreadAttributeList(IntPtr list);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool CreateProcess(string app, StringBuilder command, IntPtr procSecurity, IntPtr threadSecurity, bool inherit, uint flags, IntPtr environment, string directory, ref StartupInfoEx startup, out ProcessInfo process);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr handle, uint exitCode);
    [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int id);
    [DllImport("kernel32.dll")] static extern bool SetStdHandle(int id, IntPtr handle);
    private IntPtr console, process;
    private FileStream input, output;
    private readonly StringBuilder transcript = new StringBuilder();
    private readonly object inputLock = new object();

    public CommandHighlighterConPty(string command, string directory)
    {
        IntPtr inRead, inWrite, outRead, outWrite;
        if (!CreatePipe(out inRead, out inWrite, IntPtr.Zero, 0) || !CreatePipe(out outRead, out outWrite, IntPtr.Zero, 0)) throw new IOException("CreatePipe failed");
        int result = CreatePseudoConsole(new Coord { X = 140, Y = 40 }, inRead, outWrite, 0, out console);
        if (result != 0) throw new IOException("CreatePseudoConsole failed: " + result);
        input = new FileStream(new SafeFileHandle(inWrite, true), FileAccess.Write);
        output = new FileStream(new SafeFileHandle(outRead, true), FileAccess.Read);
        IntPtr size = IntPtr.Zero;
        InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref size);
        IntPtr list = Marshal.AllocHGlobal(size);
        try
        {
            if (!InitializeProcThreadAttributeList(list, 1, 0, ref size)) throw new IOException("Attribute list init failed");
            if (!UpdateProcThreadAttribute(list, 0, new IntPtr(0x00020016), console, new IntPtr(IntPtr.Size), IntPtr.Zero, IntPtr.Zero)) throw new IOException("Pseudoconsole attribute failed");
            var startup = new StartupInfoEx();
            startup.info.cb = Marshal.SizeOf(typeof(StartupInfoEx));
            startup.attributes = list;
            ProcessInfo info;
            // WSL interop gives this host redirected standard handles. Clear them
            // during process creation so the child obtains its ConPTY handles.
            var oldIn = GetStdHandle(-10); var oldOut = GetStdHandle(-11); var oldErr = GetStdHandle(-12);
            try
            {
                SetStdHandle(-10, IntPtr.Zero); SetStdHandle(-11, IntPtr.Zero); SetStdHandle(-12, IntPtr.Zero);
                if (!CreateProcess(null, new StringBuilder(command), IntPtr.Zero, IntPtr.Zero, false, 0x00080000, IntPtr.Zero, directory, ref startup, out info)) throw new IOException("CreateProcess failed: " + Marshal.GetLastWin32Error());
            }
            finally { SetStdHandle(-10, oldIn); SetStdHandle(-11, oldOut); SetStdHandle(-12, oldErr); }
            process = info.process;
            CloseHandle(info.thread);
        }
        finally { DeleteProcThreadAttributeList(list); Marshal.FreeHGlobal(list); CloseHandle(inRead); CloseHandle(outWrite); }
        var reader = new Thread(ReadOutput);
        reader.IsBackground = true;
        reader.Start();
    }

    private void ReadOutput()
    {
        var bytes = new byte[8192];
        var chars = new char[8192];
        var decoder = Encoding.UTF8.GetDecoder();
        try
        {
            int count;
            while ((count = output.Read(bytes, 0, bytes.Length)) > 0)
            {
                var text = new string(chars, 0, decoder.GetChars(bytes, 0, count, chars, 0));
                lock (transcript) { transcript.Append(text); }
                if (text.Contains("\x1b[6n")) Send("\x1b[1;1R");
            }
        }
        catch (IOException) { }
        catch (ObjectDisposedException) { }
    }
    public void Send(string text)
    {
        var bytes = Encoding.UTF8.GetBytes(text);
        lock (inputLock) { input.Write(bytes, 0, bytes.Length); input.Flush(); }
    }
    public string Transcript { get { lock (transcript) { return transcript.ToString(); } } }
    public void Dispose()
    {
        if (process != IntPtr.Zero) { TerminateProcess(process, 0); CloseHandle(process); process = IntPtr.Zero; }
        if (input != null) input.Dispose();
        if (console != IntPtr.Zero) { ClosePseudoConsole(console); console = IntPtr.Zero; }
        if (output != null) output.Dispose();
    }
}
