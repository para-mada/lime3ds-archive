[CmdletBinding()]
param([switch]$Quiet)

$ErrorActionPreference = 'Stop'
$clion = Get-ChildItem "$env:ProgramFiles\JetBrains\CLion *" -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
if (-not $clion) { throw 'No se encontro CLion en Program Files. Instala CLion con su toolchain MinGW incluido.' }

$cmake = Join-Path $clion.FullName 'bin\cmake\win\x64\bin\cmake.exe'
$ninja = Join-Path $clion.FullName 'bin\ninja\win\x64\ninja.exe'
$mingw = Join-Path $clion.FullName 'bin\mingw\bin'
foreach ($path in @($cmake, $ninja, (Join-Path $mingw 'g++.exe'))) {
    if (-not (Test-Path $path)) { throw "Falta una herramienta requerida: $path" }
}

$env:Path = "$(Split-Path $cmake);$(Split-Path $ninja);$mingw;$env:Path"
if (-not $Quiet) {
    Write-Host "CLion: $($clion.FullName)"
    Write-Host ((& $cmake --version | Select-Object -First 1) -join '')
    Write-Host ((& (Join-Path $mingw 'g++.exe') --version | Select-Object -First 1) -join '')
    Write-Host "Ninja $(& $ninja --version)"
}
[pscustomobject]@{ CMake = $cmake; Ninja = $ninja; MinGWBin = $mingw; CLion = $clion.FullName }
