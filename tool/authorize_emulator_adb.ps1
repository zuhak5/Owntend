Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class EmulatorAuthWinApi {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@

$found = [IntPtr]::Zero
$callback = [EmulatorAuthWinApi+EnumWindowsProc]{
  param($hwnd, $lparam)
  if ([EmulatorAuthWinApi]::IsWindowVisible($hwnd)) {
    $sb = New-Object System.Text.StringBuilder 512
    [void][EmulatorAuthWinApi]::GetWindowText($hwnd, $sb, $sb.Capacity)
    $title = $sb.ToString()
    if ($title -like '*Android Emulator*Small_Phone_2026*') {
      $script:found = $hwnd
      return $false
    }
  }
  return $true
}

[void][EmulatorAuthWinApi]::EnumWindows($callback, [IntPtr]::Zero)
if ($found -eq [IntPtr]::Zero) {
  throw 'Emulator window not found'
}

[void][EmulatorAuthWinApi]::SetForegroundWindow($found)
Start-Sleep -Milliseconds 700

$rect = New-Object EmulatorAuthWinApi+RECT
[void][EmulatorAuthWinApi]::GetWindowRect($found, [ref]$rect)

function Click-At([int]$x, [int]$y) {
  [void][EmulatorAuthWinApi]::SetCursorPos($x, $y)
  Start-Sleep -Milliseconds 150
  [EmulatorAuthWinApi]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  [EmulatorAuthWinApi]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
}

# Coordinates are relative to the emulator window captured by capture_emulator_window.ps1.
Click-At ($rect.Left + 114) ($rect.Top + 476)
Start-Sleep -Milliseconds 350
Click-At ($rect.Left + 360) ($rect.Top + 543)
Start-Sleep -Seconds 3

[PSCustomObject]@{
  Left = $rect.Left
  Top = $rect.Top
  Width = $rect.Right - $rect.Left
  Height = $rect.Bottom - $rect.Top
}
