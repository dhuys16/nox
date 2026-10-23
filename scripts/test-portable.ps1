param(
  [string]$Executable,
  [switch]$LeaveRunning
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $Executable) { $Executable = Join-Path $projectRoot 'dist\NoxPanel\nox_panel.exe' }
$Executable = (Resolve-Path -LiteralPath $Executable).Path
$logRoot = Join-Path $projectRoot '.tools'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class IslandNativeCheck {
  [StructLayout(LayoutKind.Sequential)]
  public struct Rect { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hwnd, out Rect rect);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
  [DllImport("user32.dll", EntryPoint="GetWindowLongPtrW")]
  public static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);
  [DllImport("user32.dll")] public static extern int GetWindowRgn(IntPtr hwnd, IntPtr region);
  [DllImport("gdi32.dll")] public static extern IntPtr CreateRectRgn(int left, int top, int right, int bottom);
  [DllImport("gdi32.dll")] public static extern int GetRgnBox(IntPtr region, out Rect rect);
  [DllImport("gdi32.dll")] public static extern bool PtInRegion(IntPtr region, int x, int y);
  [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr handle);
}
'@
$application = Start-Process -FilePath $Executable -WorkingDirectory (Split-Path -Parent $Executable) -PassThru `
  -RedirectStandardOutput (Join-Path $logRoot 'smoke.stdout.log') `
  -RedirectStandardError (Join-Path $logRoot 'smoke.stderr.log')
$nativeRegion = [IntPtr]::Zero
$checksPassed = $false
$previousDpiContext = [IslandNativeCheck]::SetThreadDpiAwarenessContext([IntPtr](-4))
try {
  $timeoutAt = [DateTime]::UtcNow.AddSeconds(20)
  do {
    Start-Sleep -Milliseconds 250
    $application.Refresh()
    if ($application.HasExited) { throw "Aplikasi keluar saat startup: $($application.ExitCode)" }
  } while ($application.MainWindowHandle -eq [IntPtr]::Zero -and [DateTime]::UtcNow -lt $timeoutAt)
  $hwnd = $application.MainWindowHandle
  if ($hwnd -eq [IntPtr]::Zero) { throw 'Window aplikasi tidak muncul dalam 20 detik.' }
  Start-Sleep -Milliseconds 1000
  $client = New-Object IslandNativeCheck+Rect
  if (-not [IslandNativeCheck]::GetClientRect($hwnd, [ref]$client)) { throw 'GetClientRect gagal.' }
  $scale = [IslandNativeCheck]::GetDpiForWindow($hwnd) / 96.0
  $width = ($client.Right - $client.Left) / $scale
  $height = ($client.Bottom - $client.Top) / $scale
  if ([Math]::Abs($width - 600) -gt 2 -or [Math]::Abs($height - 200) -gt 2) {
    throw "Ukuran client bukan 600x200: ${width}x${height}"
  }
  $extendedStyle = [IslandNativeCheck]::GetWindowLongPtr($hwnd, -20).ToInt64()
  if (($extendedStyle -band 0x8) -eq 0) { throw 'Window belum always-on-top.' }
  $nativeRegion = [IslandNativeCheck]::CreateRectRgn(0, 0, 0, 0)
  if ([IslandNativeCheck]::GetWindowRgn($hwnd, $nativeRegion) -le 1) { throw 'Region widget tidak tersedia.' }
  $bounds = New-Object IslandNativeCheck+Rect
  [void][IslandNativeCheck]::GetRgnBox($nativeRegion, [ref]$bounds)
  if ([IslandNativeCheck]::PtInRegion($nativeRegion, 0, 0)) { throw 'Area transparan masih termasuk region klik.' }
  if ([IslandNativeCheck]::PtInRegion($nativeRegion, $bounds.Left, $bounds.Top)) {
    throw 'Sudut transparan masih termasuk region klik.'
  }
  $centerX = [int](($bounds.Left + $bounds.Right) / 2)
  $centerY = [int](($bounds.Top + $bounds.Bottom) / 2)
  if (-not [IslandNativeCheck]::PtInRegion($nativeRegion, $centerX, $centerY)) {
    throw 'Pusat widget tidak termasuk region interaktif.'
  }
  [ordered]@{
    executable = $Executable
    pid = $application.Id
    logicalSize = @($width, $height)
    dpiScale = $scale
    alwaysOnTop = $true
    transparentAreaExcluded = $true
    roundedCornerExcluded = $true
    widgetCenterInteractive = $true
  } | ConvertTo-Json | Tee-Object -FilePath (Join-Path $logRoot 'smoke-result.json')
  $checksPassed = $true
} finally {
  [void][IslandNativeCheck]::SetThreadDpiAwarenessContext($previousDpiContext)
  if ($nativeRegion -ne [IntPtr]::Zero) { [void][IslandNativeCheck]::DeleteObject($nativeRegion) }
  # The probe process always belongs to this test and must be cleaned up. For
  # interactive use, launch a separate instance through the desktop shell.
  if (-not $application.HasExited) {
    [void]$application.CloseMainWindow()
    if (-not $application.WaitForExit(3000)) { $application.Kill() }
  }
}
if ($LeaveRunning -and $checksPassed) {
  & (Join-Path $PSScriptRoot 'start-island.ps1') -Executable $Executable
}
