# Feed Remote helper
# Listens for global hotkeys and mouse side buttons and passes them to the
# Feed Remote userscript through a small local HTTP server (localhost only).

# ===== SETTINGS =====
# Keyboard combos:  "Ctrl+Shift+2", "Alt+F", "Ctrl+Down"
# Single keys:      "F13".."F24", "Pause", "ScrollLock", "Insert",
#                   "NumAdd", "NumSub", "NumMul", "NumDiv", "Num0".."Num9"
# Use "" to disable a hotkey. Keyboard hotkeys are captured everywhere,
# even when no feed is open, so pick keys you don't use for anything else.
$Hotkeys = [ordered]@{
    next   = "Ctrl+Shift+2"   # next video
    prev   = "Ctrl+Shift+1"   # previous video
    toggle = "Ctrl+Shift+3"   # play / pause
}

# Mouse side buttons. They only control the feed while a TikTok home feed,
# YouTube Shorts or Instagram Reels tab is visible. Otherwise they keep
# working as normal back / forward buttons.
# Values: "next", "prev", "toggle", or "" to leave the button alone.
$MouseForward = "next"   # forward side button (usually the front one)
$MouseBack    = "prev"   # back side button

$Port = 17345   # must match PORT in feed-remote.user.js
# ====================

$code = @"
using System;
using System.Collections.Generic;
using System.Net;
using System.Text;
using System.Threading;
using System.Runtime.InteropServices;

public static class FeedRemote {
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr h, int id, uint mod, uint vk);
    [DllImport("user32.dll")] static extern int GetMessage(out MSG m, IntPtr h, uint a, uint b);
    [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int idHook, MouseProc fn, IntPtr hMod, uint threadId);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string name);

    [StructLayout(LayoutKind.Sequential)]
    public struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam; public uint time; public int x; public int y; }
    [StructLayout(LayoutKind.Sequential)]
    struct MSLLHOOKSTRUCT { public int x; public int y; public uint mouseData; public uint flags; public uint time; public IntPtr extra; }
    public delegate IntPtr MouseProc(int nCode, IntPtr wParam, IntPtr lParam);

    class Client { public bool feed; public DateTime seen; }

    static readonly object L = new object();
    static readonly Dictionary<string, Client> clients = new Dictionary<string, Client>();
    static int seq = 0;
    static string last = "";
    static string boot = Guid.NewGuid().ToString("N").Substring(0, 8);

    static string mouseFwd = "", mouseBack = "";
    static bool swallowFwd = false, swallowBack = false;
    static MouseProc hookProc = HookProc;   // keep a reference so it isn't garbage collected
    static IntPtr hook = IntPtr.Zero;

    public static void Run(int port, string[] names, string[] cmds, uint[] mods, uint[] vks, string fwd, string back) {
        mouseFwd = fwd ?? ""; mouseBack = back ?? "";

        var listener = new HttpListener();
        listener.Prefixes.Add("http://localhost:" + port + "/");
        listener.Start();
        var t = new Thread(() => {
            while (true) {
                try { var ctx = listener.GetContext(); ThreadPool.QueueUserWorkItem(_ => Handle(ctx)); }
                catch { }
            }
        });
        t.IsBackground = true;
        t.Start();

        for (int i = 0; i < names.Length; i++) {
            if (RegisterHotKey(IntPtr.Zero, i + 1, mods[i] | 0x4000, vks[i]))
                Console.WriteLine("  OK      " + names[i]);
            else
                Console.WriteLine("  FAILED  " + names[i] + " (key may already be used by another program)");
        }

        if (mouseFwd != "" || mouseBack != "") {
            hook = SetWindowsHookEx(14 /* WH_MOUSE_LL */, hookProc, GetModuleHandle(null), 0);
            Console.WriteLine(hook != IntPtr.Zero ? "  OK      mouse side buttons" : "  FAILED  mouse side buttons");
        }
        Console.WriteLine("Ready. Closing this window stops the hotkeys.");

        MSG m;
        while (GetMessage(out m, IntPtr.Zero, 0, 0) > 0) {
            if (m.message == 0x0312) Fire(cmds[(int)m.wParam - 1]);
        }
    }

    static void Fire(string cmd) {
        lock (L) { seq++; last = cmd; Monitor.PulseAll(L); }
        Console.WriteLine(DateTime.Now.ToString("HH:mm:ss") + "  -> " + cmd);
    }

    static bool FeedOpen() {
        lock (L) {
            var now = DateTime.UtcNow;
            foreach (var c in clients.Values)
                if (c.feed && (now - c.seen).TotalSeconds < 15) return true;
        }
        return false;
    }

    // Side buttons: take them over only while a feed is visible, otherwise pass them through.
    static IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam) {
        if (nCode >= 0) {
            int msg = (int)wParam;
            if (msg == 0x020B || msg == 0x020C) {   // WM_XBUTTONDOWN / WM_XBUTTONUP
                var d = (MSLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(MSLLHOOKSTRUCT));
                int btn = (int)(d.mouseData >> 16);  // 1 = back, 2 = forward
                string cmd = btn == 2 ? mouseFwd : btn == 1 ? mouseBack : "";
                if (msg == 0x020B) {
                    if (cmd != "" && FeedOpen()) {
                        if (btn == 2) swallowFwd = true; else swallowBack = true;
                        Fire(cmd);
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

    // /state: the userscript reports whether it shows a feed.
    // /wait:  long-poll, "anything newer than seq?", waits up to 10 s.
    static void Handle(HttpListenerContext ctx) {
        try {
            var q = ctx.Request.QueryString;
            string id = q["id"] ?? "";
            bool feed = q["feed"] == "1";
            int since; int.TryParse(q["since"], out since);
            string clientBoot = q["boot"] ?? "";
            bool wait = ctx.Request.Url.AbsolutePath == "/wait";
            string cmd = "";
            int s;
            lock (L) {
                if (id != "") {
                    if (q["gone"] == "1") clients.Remove(id);
                    else clients[id] = new Client { feed = feed, seen = DateTime.UtcNow };
                }
                if (wait && clientBoot == boot) {
                    if (seq <= since) Monitor.Wait(L, 10000);
                    if (seq > since) cmd = last;
                }
                Client c;
                if (id != "" && clients.TryGetValue(id, out c)) c.seen = DateTime.UtcNow;
                s = seq;
            }
            byte[] b = Encoding.UTF8.GetBytes("{\"boot\":\"" + boot + "\",\"seq\":" + s + ",\"cmd\":\"" + cmd + "\"}");
            ctx.Response.ContentType = "application/json";
            ctx.Response.AddHeader("Access-Control-Allow-Origin", "*");
            ctx.Response.ContentLength64 = b.Length;
            ctx.Response.OutputStream.Write(b, 0, b.Length);
            ctx.Response.OutputStream.Close();
        } catch { }
    }
}
"@

function Convert-Hotkey([string]$s) {
    $mods = 0; $vk = 0
    $named = @{ UP=0x26; DOWN=0x28; LEFT=0x25; RIGHT=0x27; PAGEUP=0x21; PAGEDOWN=0x22; HOME=0x24; END=0x23; SPACE=0x20;
               PAUSE=0x13; SCROLLLOCK=0x91; INSERT=0x2D; DELETE=0x2E;
               NUMADD=0x6B; NUMSUB=0x6D; NUMMUL=0x6A; NUMDIV=0x6F }
    foreach ($part in $s.Split('+')) {
        $t = $part.Trim().ToUpper()
        if     ($t -eq 'CTRL' -or $t -eq 'CONTROL') { $mods = $mods -bor 2 }
        elseif ($t -eq 'ALT')   { $mods = $mods -bor 1 }
        elseif ($t -eq 'SHIFT') { $mods = $mods -bor 4 }
        elseif ($t -eq 'WIN')   { $mods = $mods -bor 8 }
        elseif ($t -match '^F([1-9]|1[0-9]|2[0-4])$') { $vk = 0x6F + [int]$Matches[1] }
        elseif ($t -match '^NUM([0-9])$') { $vk = 0x60 + [int]$Matches[1] }
        elseif ($t -match '^[A-Z0-9]$') { $vk = [int][char]$t }
        elseif ($named.ContainsKey($t)) { $vk = $named[$t] }
        else { throw "Unknown key: '$part' ($s)" }
    }
    if ($vk -eq 0) { throw "No key given: $s" }
    return ,@([uint32]$mods, [uint32]$vk)
}

Add-Type -TypeDefinition $code
$names = @(); $cmds = @(); $mods = @(); $vks = @()
foreach ($k in $Hotkeys.Keys) {
    if ([string]::IsNullOrWhiteSpace($Hotkeys[$k])) { continue }
    $r = Convert-Hotkey $Hotkeys[$k]
    $names += "$k ($($Hotkeys[$k]))"; $cmds += $k; $mods += $r[0]; $vks += $r[1]
}
[FeedRemote]::Run($Port, [string[]]$names, [string[]]$cmds, [uint32[]]$mods, [uint32[]]$vks, $MouseForward, $MouseBack)
