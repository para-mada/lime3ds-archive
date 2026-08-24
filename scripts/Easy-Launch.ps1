[CmdletBinding()]
param([string]$Game, [switch]$ForgetLastGame, [switch]$NoRemember, [switch]$VerifyOnly)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$stateDir = Join-Path $env:LOCALAPPDATA 'LimoMada3DS-EasyLaunch'
$stateFile = Join-Path $stateDir 'settings.json'
$legacyStateFile = Join-Path $env:LOCALAPPDATA 'Lime3DS-EasyLaunch\settings.json'
if (-not (Test-Path $stateFile) -and (Test-Path $legacyStateFile)) {
    New-Item $stateDir -ItemType Directory -Force | Out-Null
    Copy-Item -LiteralPath $legacyStateFile -Destination $stateFile
}

function Find-LimeExecutable {
    $candidates = @(
        (Join-Path $repo 'build\windows-mingw-relwithdebinfo\bundle\limomada3ds.exe'),
        (Join-Path $repo 'build\windows-mingw-relwithdebinfo\bin\RelWithDebInfo\limomada3ds.exe'),
        (Join-Path $repo 'build\windows-mingw-relwithdebinfo\bin\limomada3ds.exe')
    )
    $found = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $found) {
        $found = Get-ChildItem (Join-Path $repo 'build') -Filter 'limomada3ds.exe' -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
    return $found
}

$exe = Find-LimeExecutable
if (-not $exe) { throw "No se encontro limomada3ds.exe. Compila con: .\scripts\Build-Lime3DS.ps1 -Bundle" }
if ($ForgetLastGame -and (Test-Path $stateFile)) { Remove-Item -LiteralPath $stateFile }
if (-not $NoRemember -and -not $Game -and (Test-Path $stateFile)) {
    try { $Game = (Get-Content $stateFile -Raw | ConvertFrom-Json).lastGame } catch { $Game = $null }
}
if (-not $Game -or -not (Test-Path $Game)) {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = 'Selecciona un juego de Nintendo 3DS'
    $dialog.Filter = 'Juegos 3DS (*.3ds)|*.3ds|Todos los archivos (*.*)|*.*'
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { Write-Host 'Seleccion cancelada.'; exit 0 }
    $Game = $dialog.FileName
}
if ([IO.Path]::GetExtension($Game) -ine '.3ds') { throw 'Easy Launch solo acepta archivos .3ds.' }
if (-not $NoRemember) {
    New-Item $stateDir -ItemType Directory -Force | Out-Null
    @{ lastGame = (Resolve-Path $Game).Path } | ConvertTo-Json | Set-Content $stateFile -Encoding utf8
}
if ($VerifyOnly) { Write-Host "Selector OK: $Game"; Write-Host "Ejecutable: $exe"; exit 0 }
try { Start-Process -FilePath $exe -ArgumentList @((Resolve-Path $Game).Path) -WorkingDirectory (Split-Path $exe) }
catch { throw "No se pudo iniciar LimoMada3DS: $($_.Exception.Message)" }
