# Feed Remote helper
# Listens for global hotkeys and passes them to the Feed Remote userscript
# through a small local HTTP server (localhost only).

# ===== SETTINGS =====
# Combos:      "Ctrl+Shift+2", "Alt+F", "Ctrl+Down"
# Single keys: "F13".."F24", "Pause", "ScrollLock", "Insert",
#              "NumAdd", "NumSub", "NumMul", "NumDiv", "Num0".."Num9"
# A single key is captured system-wide, so pick one you don't use elsewhere.
$Hotkeys = [ordered]@{
    next   = "Ctrl+Shift+2"   # next video
    prev   = "Ctrl+Shift+1"   # previous video
    toggle = "Ctrl+Shift+3"   # play / pause
}
$Port = 17345   # must match PORT in feed-remote.user.js
# ====================

$code = @"
using System;
using System.Net;
using System.Text;
using System.Threading;
using System.Runtime.InteropServices;

public static class FeedRemote {
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr h, int id, uint mod, uint vk);
    [DllImport("user32.dll")] static extern int GetMessage(out MSG m, IntPtr h, uint a, uint b);
    [StructLayout(LayoutKind.Sequential)]
    public struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam; public uint time; public int x; public int y; }

    static readonly object L = new object();
    static int seq = 0;
    static string last = "";
    static string boot = Guid.NewGuid().ToString("N").Substring(0, 8);

    public static void Run(int port, string[] names, uint[] mods, uint[] vks) {
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
        Console.WriteLine("Ready. Closing this window stops the hotkeys.");

        MSG m;
        while (GetMessage(out m, IntPtr.Zero, 0, 0) > 0) {
            if (m.message == 0x0312) {
                string name = names[(int)m.wParam - 1];
                lock (L) { seq++; last = name; Monitor.PulseAll(L); }
                Console.WriteLine(DateTime.Now.ToString("HH:mm:ss") + "  -> " + name);
            }
        }
    }

    // Long-poll: the userscript asks "anything newer than seq?" and waits up to 25 s.
    static void Handle(HttpListenerContext ctx) {
        try {
            int since;
            int.TryParse(ctx.Request.QueryString["since"], out since);
            string clientBoot = ctx.Request.QueryString["boot"] ?? "";
            string cmd = "";
            int s;
            lock (L) {
                if (clientBoot == boot) {
                    if (seq <= since) Monitor.Wait(L, 25000);
                    if (seq > since) cmd = last;
                }
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
$names = @(); $mods = @(); $vks = @()
foreach ($k in $Hotkeys.Keys) {
    $r = Convert-Hotkey $Hotkeys[$k]
    $names += $k; $mods += $r[0]; $vks += $r[1]
    Write-Host ("{0,-7} = {1}" -f $k, $Hotkeys[$k])
}
[FeedRemote]::Run($Port, [string[]]$names, [uint32[]]$mods, [uint32[]]$vks)
