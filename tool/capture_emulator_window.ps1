Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class WinApi {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@

$found = [IntPtr]::Zero
$titles = New-Object System.Collections.Generic.List[string]
$callback = [WinApi+EnumWindowsProc]{
  param($hwnd, $lparam)
  if ([WinApi]::IsWindowVisible($hwnd)) {
    $sb = New-Object System.Text.StringBuilder 512
    [void][WinApi]::GetWindowText($hwnd, $sb, $sb.Capacity)
    $title = $sb.ToString()
    if ($title) {
      $titles.Add($title)
    }
    if ($title -like '*Android Emulator*Small_Phone_2026*') {
      $script:found = $hwnd
      return $false
    }
  }
  return $true
}

[void][WinApi]::EnumWindows($callback, [IntPtr]::Zero)
if ($found -eq [IntPtr]::Zero) {
  $titles | Select-Object -First 80
  throw 'Emulator window not found'
}

[void][WinApi]::SetForegroundWindow($found)
Start-Sleep -Milliseconds 700
$rect = New-Object WinApi+RECT
[void][WinApi]::GetWindowRect($found, [ref]$rect)
$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
$bmp = New-Object System.Drawing.Bitmap $width, $height
$gfx = [System.Drawing.Graphics]::FromImage($bmp)
$gfx.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
$out = Join-Path (Get-Location) 'artifacts\emulator-window.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$gfx.Dispose()
$bmp.Dispose()
[PSCustomObject]@{
  Path = $out
  Left = $rect.Left
  Top = $rect.Top
  Width = $width
  Height = $height
}
