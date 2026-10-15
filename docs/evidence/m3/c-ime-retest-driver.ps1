#requires -Version 7
# Real-input driver for the C spike IME retest: physical mouse clicks and key
# presses via SendInput (same input path as Computer Use). Coordinates are
# physical screen pixels. Every action ends with a window screenshot.
param(
  [Parameter(Mandatory)][ValidateSet('click','key','shot')] [string]$Action,
  [int]$X = 0, [int]$Y = 0,
  [int]$Vk = 0,                      # virtual key code for -Action key
  [string]$OutPng = 'D:\MyAgent\.tmp-spike-step.png',
  [string]$ProcessName = 'paraselene_editor_spike',
  [int]$SettleMs = 700
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class Win32Io {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] p, int cb);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Explicit)] public struct INPUT {
    [FieldOffset(0)] public uint type;
    [FieldOffset(8)] public MOUSEINPUT mi;
    [FieldOffset(8)] public KEYBDINPUT ki;
  }
  public const uint INPUT_MOUSE = 0, INPUT_KEYBOARD = 1;
  public const uint LEFTDOWN = 0x2, LEFTUP = 0x4;
  public const uint KEYUP = 0x2;
  public static void Click(int x, int y) {
    SetCursorPos(x, y);
    System.Threading.Thread.Sleep(120);
    INPUT[] down = new INPUT[1]; down[0].type = INPUT_MOUSE; down[0].mi.dwFlags = LEFTDOWN;
    INPUT[] up = new INPUT[1]; up[0].type = INPUT_MOUSE; up[0].mi.dwFlags = LEFTUP;
    SendInput(1, down, Marshal.SizeOf(typeof(INPUT)));
    System.Threading.Thread.Sleep(60);
    SendInput(1, up, Marshal.SizeOf(typeof(INPUT)));
  }
  public static void Key(int vk) {
    INPUT[] down = new INPUT[1]; down[0].type = INPUT_KEYBOARD; down[0].ki.wVk = (ushort)vk;
    INPUT[] up = new INPUT[1]; up[0].type = INPUT_KEYBOARD; up[0].ki.wVk = (ushort)vk; up[0].ki.dwFlags = KEYUP;
    SendInput(1, down, Marshal.SizeOf(typeof(INPUT)));
    System.Threading.Thread.Sleep(50);
    SendInput(1, up, Marshal.SizeOf(typeof(INPUT)));
  }
}
'@
[void][Win32Io]::SetProcessDpiAwarenessContext([IntPtr]::new(-4))
$proc = Get-Process -Name $ProcessName -ErrorAction Stop | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
$h = $proc.MainWindowHandle
switch ($Action) {
  'click' { [Win32Io]::Click($X, $Y) }
  'key'   { [Win32Io]::Key($Vk) }
}
Start-Sleep -Milliseconds $SettleMs
$r = New-Object Win32Io+RECT
[void][Win32Io]::GetWindowRect($h, [ref]$r)
$w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
$bmp = New-Object System.Drawing.Bitmap $w, $ht
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
$bmp.Save($OutPng, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
[pscustomobject]@{ Action = $Action; X = $X; Y = $Y; Vk = $Vk; Png = $OutPng } | ConvertTo-Json -Compress
