param([string]$Executable)
$ErrorActionPreference = 'Stop'
if (-not $Executable) {
  $Executable = Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\NoxPanel\nox_panel.exe'
}
$Executable = (Resolve-Path -LiteralPath $Executable).Path
$existing = Get-Process -Name nox_panel -ErrorAction SilentlyContinue |
  Where-Object { $_.Path -eq $Executable } | Select-Object -First 1
if ($existing) {
  Write-Output "Nox Panel sudah berjalan (PID $($existing.Id))."
  return
}
# Ask the desktop shell to own the interactive app rather than leaving it as a
# child of a short-lived build/test host and its process cleanup job.
$desktopShell = New-Object -ComObject Shell.Application
$desktopShell.ShellExecute($Executable, '', (Split-Path -Parent $Executable), 'open', 1)
Write-Output 'Nox Panel diluncurkan melalui Windows Shell.'
