# Feed Remote mouse helper (native messaging host for the Chromium extension)
# The browser starts and stops this automatically. It takes over the mouse
# side buttons only while the extension reports that a feed tab is open.

# ===== SETTINGS =====
# Values: "next", "prev", "toggle", or "" to leave the button alone.
$MouseForward = "prev"   # forward side button (the upper / front one) -> scroll up
$MouseBack    = "next"   # back side button (the lower / rear one) -> scroll down
# ====================

$code = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Runtime.InteropServices;

public static class FeedHost {
    [DllImport("user32.dll")] static extern int GetMessage(out MSG m, IntPtr h, uint a, uint b);
    [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int idHook, MouseProc fn, IntPtr hMod, uint threadId);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hhk);
    [DllImport("user32.dll")] static extern bool PostThreadMessage(uint threadId, uint msg, IntPtr w, IntPtr l);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string name);

    [StructLayout(LayoutKind.Sequential)]
    public struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam; public uint time; public int x; public int y; }
    [StructLayout(LayoutKind.Sequential)]
    struct MSLLHOOKSTRUCT { public int x; public int y; public uint mouseData; public uint flags; public uint time; public IntPtr extra; }
    public delegate IntPtr MouseProc(int nCode, IntPtr wParam, IntPtr lParam);

    static volatile bool feed = false;
    static volatile bool stopping = false;
    static uint mainThread;
    static string mouseFwd = "", mouseBack = "";
    static bool swallowFwd = false, swallowBack = false;
    static MouseProc hookProc = HookProc;   // keep a reference so it isn't garbage collected
    static IntPtr hook = IntPtr.Zero;
    static Stream stdout;

    public static void Run(string fwd, string back) {
        mouseFwd = fwd ?? ""; mouseBack = back ?? "";
        mainThread = GetCurrentThreadId();
        stdout = Console.OpenStandardOutput();

        var reader = new Thread(ReadLoop);
        reader.IsBackground = true;
        reader.Start();

        hook = SetWindowsHookEx(14 /* WH_MOUSE_LL */, hookProc, GetModuleHandle(null), 0);
        Send("{\"hello\":true,\"hook\":" + (hook != IntPtr.Zero ? "true" : "false") + "}");

        MSG m;
        while (GetMessage(out m, IntPtr.Zero, 0, 0) > 0) { }

        // Remove the hook before exiting. A hook left behind while the process
        // shuts down makes every mouse movement wait for it (heavy mouse lag).
        if (hook != IntPtr.Zero) { UnhookWindowsHookEx(hook); hook = IntPtr.Zero; }
        Process.GetCurrentProcess().Kill();
    }

    static void Stop() {
        stopping = true;
        PostThreadMessage(mainThread, 0x0012 /* WM_QUIT */, IntPtr.Zero, IntPtr.Zero);
        // Safety net: if the message loop doesn't end for some reason, kill the process.
        // Windows removes the hook of a killed process right away.
        Thread.Sleep(2000);
        Process.GetCurrentProcess().Kill();
    }

    // Messages from the extension: {"feed":true} / {"feed":false}.
    // When the browser closes, stdin ends and the helper exits.
    static void ReadLoop() {
        var s = Console.OpenStandardInput();
        var len = new byte[4];
        while (ReadExact(s, len)) {
            var buf = new byte[BitConverter.ToInt32(len, 0)];
            if (!ReadExact(s, buf)) break;
            string j = Encoding.UTF8.GetString(buf);
            if (j.Contains("\"feed\"")) feed = j.Contains("true");
        }
        Stop();
    }

    static bool ReadExact(Stream s, byte[] b) {
        int off = 0;
        while (off < b.Length) {
            int n = s.Read(b, off, b.Length - off);
            if (n <= 0) return false;
            off += n;
        }
        return true;
    }

    static void Send(string json) {
        var b = Encoding.UTF8.GetBytes(json);
        try {
            lock (stdout) {
                stdout.Write(BitConverter.GetBytes(b.Length), 0, 4);
                stdout.Write(b, 0, b.Length);
                stdout.Flush();
            }
        } catch { Stop(); }   // browser is gone
    }

    static IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam) {
        if (nCode >= 0 && !stopping) {
            int msg = (int)wParam;
            if (msg == 0x020B || msg == 0x020C) {   // WM_XBUTTONDOWN / WM_XBUTTONUP
                var d = (MSLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(MSLLHOOKSTRUCT));
                int btn = (int)(d.mouseData >> 16);  // 1 = back, 2 = forward
                string cmd = btn == 2 ? mouseFwd : btn == 1 ? mouseBack : "";
                if (msg == 0x020B) {
                    if (cmd != "" && feed) {
                        if (btn == 2) swallowFwd = true; else swallowBack = true;
                        ThreadPool.QueueUserWorkItem(_ => Send("{\"cmd\":\"" + cmd + "\"}"));
                        return (IntPtr)1;
                    }
                } else {
                    if (btn == 2 && swallowFwd) { swallowFwd = false; return (IntPtr)1; }
                    if (btn == 1 && swallowBack) { swallowBack = false; return (IntPtr)1; }
                }
            }
        }
        return CallNextHookEx(hook, nCode, wParam, lParam);
    }
}
"@

Add-Type -TypeDefinition $code
[FeedHost]::Run($MouseForward, $MouseBack)
