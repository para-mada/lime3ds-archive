[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop 'MadaLime.lnk'
$launcher = Join-Path $PSScriptRoot 'Easy-Launch.ps1'
$icon = Join-Path $repo 'dist\madalime.ico'
if (-not (Test-Path $icon)) { $icon = Join-Path $repo 'build\windows-mingw-relwithdebinfo\bundle\madalime.exe' }
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = 'powershell.exe'
$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$launcher`""
$shortcut.WorkingDirectory = $repo
$shortcut.Description = 'Seleccionar y abrir un juego .3ds con MadaLime'
if (Test-Path $icon) { $shortcut.IconLocation = "$icon,0" }
$shortcut.Save()
if (-not (Test-Path $shortcutPath)) { throw 'No se pudo crear el acceso directo.' }
Write-Host "Acceso directo creado: $shortcutPath" -ForegroundColor Green
