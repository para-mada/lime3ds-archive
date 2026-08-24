[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop 'LimoMada3DS.lnk'
$launcher = Join-Path $PSScriptRoot 'Easy-Launch.ps1'
$icon = Join-Path $repo 'dist\limomada3ds.ico'
if (-not (Test-Path $icon)) { $icon = Join-Path $repo 'build\windows-mingw-relwithdebinfo\bundle\limomada3ds.exe' }
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = 'powershell.exe'
$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$launcher`""
$shortcut.WorkingDirectory = $repo
$shortcut.Description = 'Seleccionar y abrir un juego .3ds con LimoMada3DS'
if (Test-Path $icon) { $shortcut.IconLocation = "$icon,0" }
$shortcut.Save()
if (-not (Test-Path $shortcutPath)) { throw 'No se pudo crear el acceso directo.' }
Write-Host "Acceso directo creado: $shortcutPath" -ForegroundColor Green
