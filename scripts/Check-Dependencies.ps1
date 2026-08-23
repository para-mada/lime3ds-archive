[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$tools = & "$PSScriptRoot\Find-LimeToolchain.ps1"
$gitRoot = Join-Path $env:ProgramFiles 'Git'
$env:Path = "$(Join-Path $gitRoot 'usr\bin');$(Join-Path $gitRoot 'mingw64\bin');$(Join-Path $gitRoot 'cmd');$($tools.MinGWBin);$(Split-Path $tools.CMake);$(Split-Path $tools.Ninja);$env:Path"
$env:GIT_CONFIG_COUNT = '1'
$env:GIT_CONFIG_KEY_0 = 'safe.directory'
$env:GIT_CONFIG_VALUE_0 = $repo.Replace('\','/')
Push-Location $repo
try {
    git --version
    $bash = Join-Path $gitRoot 'bin\bash.exe'
    $repoUnix = $repo.Replace('\','/')
    & $bash -lc "cd '$repoUnix' && git -c safe.directory='$repoUnix' submodule status --recursive"
    if ($LASTEXITCODE) { throw 'Hay submodulos sin inicializar. Ejecuta: git submodule update --init --recursive' }
    Write-Host 'Dependencias basicas y submodulos: OK' -ForegroundColor Green
} finally { Pop-Location }
