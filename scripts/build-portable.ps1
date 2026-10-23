param(
  [string]$FlutterRoot,
  [switch]$SkipBuild,
  [switch]$DesktopShortcut
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
if (-not $SkipBuild) {
  if (-not $FlutterRoot) {
    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if ($flutterCommand) { $FlutterRoot = Split-Path -Parent (Split-Path -Parent $flutterCommand.Source) }
    elseif (Test-Path 'C:\flutter\flutter\bin\cache\dart-sdk\bin\dart.exe') { $FlutterRoot = 'C:\flutter\flutter' }
    else { throw 'Flutter tidak ditemukan. Gunakan -FlutterRoot <folder SDK>.' }
  }
  $env:PATH = "$FlutterRoot\bin;$env:USERPROFILE\.cargo\bin;$env:PATH"
  $env:FLUTTER_ROOT = $FlutterRoot
  $env:CI = 'true'
  $env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
  $dartExe = Join-Path $FlutterRoot 'bin\cache\dart-sdk\bin\dart.exe'
  $flutterSnapshot = Join-Path $FlutterRoot 'bin\cache\flutter_tools.snapshot'
  $pubOutput = & $dartExe $flutterSnapshot --no-version-check pub get 2>&1
  $pubExitCode = $LASTEXITCODE
  $pubOutput | ForEach-Object { Write-Host $_ }
  if ($pubExitCode -ne 0) {
    if (-not (Test-Path '.flutter-plugins-dependencies') -or
        ($pubOutput -join "`n") -notmatch 'Building with plugins requires symlink support') {
      throw 'Resolusi dependency Flutter gagal.'
    }
  }
  # Directory junctions support Flutter plugins without changing Developer Mode.
  $plugins = Get-Content '.flutter-plugins-dependencies' -Raw | ConvertFrom-Json
  $linksRoot = Join-Path $projectRoot 'windows\flutter\ephemeral\.plugin_symlinks'
  New-Item -ItemType Directory -Path $linksRoot -Force | Out-Null
  foreach ($plugin in $plugins.plugins.windows) {
    $linkPath = Join-Path $linksRoot $plugin.name
    if (-not (Test-Path -LiteralPath $linkPath)) {
      $sourcePath = [IO.Path]::GetFullPath($plugin.path)
      New-Item -ItemType Junction -Path $linkPath -Target $sourcePath | Out-Null
    }
  }
  if ($pubExitCode -ne 0) {
    # The first pub get wrote plugin metadata before failing on symlinks. With
    # junctions in place, a second pass generates native plugin registration.
    & $dartExe $flutterSnapshot --no-version-check pub get
    if ($LASTEXITCODE -ne 0) { throw 'Registrasi plugin Windows gagal.' }
  }
  # Ship the complete icon font so cached subsets cannot omit new controls.
  & $dartExe $flutterSnapshot --no-version-check build windows --release --no-pub --no-tree-shake-icons
  if ($LASTEXITCODE -ne 0) { throw 'Build Windows gagal; paket tidak dibuat.' }
}
$releaseRoot = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$releaseExe = Join-Path $releaseRoot 'nox_panel.exe'
if (-not (Test-Path -LiteralPath $releaseExe)) { throw 'EXE hasil build belum tersedia.' }
$iconFont = Join-Path $releaseRoot 'data\flutter_assets\fonts\MaterialIcons-Regular.otf'
$sdkIconFont = 'C:\flutter\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf'
if ($FlutterRoot) { $sdkIconFont = Join-Path $FlutterRoot 'bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf' }
if ((Test-Path -LiteralPath $sdkIconFont) -and
    (Get-FileHash -LiteralPath $iconFont).Hash -ne (Get-FileHash -LiteralPath $sdkIconFont).Hash) {
  throw 'Font ikon rilis belum lengkap. Build ulang dengan --no-tree-shake-icons sebelum membuat paket.'
}
$distribution = Join-Path $projectRoot 'dist\NoxPanel'
New-Item -ItemType Directory -Path $distribution -Force | Out-Null
Copy-Item -Path (Join-Path $releaseRoot '*') -Destination $distribution -Recurse -Force -Exclude 'dynamic_island.exe'
# Include the redistributable C++ runtime beside the EXE when available.
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path -LiteralPath $vswhere) {
  $visualStudioRoot = & $vswhere -latest -products '*' -property installationPath
  if ($visualStudioRoot) {
    $runtimeDirectory = Get-Item -Path (Join-Path $visualStudioRoot 'VC\Redist\MSVC\*\x64\Microsoft.VC143.CRT') -ErrorAction SilentlyContinue |
      Sort-Object FullName -Descending | Select-Object -First 1
    if ($runtimeDirectory) {
      Copy-Item -Path (Join-Path $runtimeDirectory.FullName '*.dll') -Destination $distribution -Force
    }
  }
}
$exePath = Join-Path $distribution 'nox_panel.exe'
Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md') -Destination (Join-Path $distribution 'README.md') -Force
$shell = New-Object -ComObject WScript.Shell
function New-IslandShortcut([string]$shortcutPath) {
  $shortcut = $shell.CreateShortcut($shortcutPath)
  $shortcut.TargetPath = $exePath
  $shortcut.WorkingDirectory = $distribution
  $shortcut.IconLocation = "$exePath,0"
  $shortcut.Description = 'Nox Panel untuk Windows 11'
  $shortcut.Save()
}
New-IslandShortcut (Join-Path $projectRoot 'dist\Nox Panel.lnk')
if ($DesktopShortcut) {
  $desktop = [Environment]::GetFolderPath('Desktop')
  New-IslandShortcut (Join-Path $desktop 'Nox Panel.lnk')
  Write-Output "Shortcut Desktop: $desktop\Nox Panel.lnk"
}
$zipPath = Join-Path $projectRoot 'dist\NoxPanel-portable.zip'
Compress-Archive -Path $distribution -DestinationPath $zipPath -Force
Write-Output "Aplikasi: $exePath"
Write-Output "Paket portabel: $zipPath"
