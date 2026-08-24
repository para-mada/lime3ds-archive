[CmdletBinding()]
param([switch]$Bundle, [switch]$CleanConfigure)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$tools = & "$PSScriptRoot\Find-LimeToolchain.ps1" -Quiet
$env:Path = "$($tools.MinGWBin);$(Split-Path $tools.CMake);$(Split-Path $tools.Ninja);$env:Path"
Push-Location $repo
try {
    $args = @('--preset', 'windows-mingw-relwithdebinfo')
    if ($CleanConfigure) { $args += '--fresh' }
    & $tools.CMake @args
    if ($LASTEXITCODE) { throw 'Fallo la configuracion de CMake.' }
    # Qt 6.7.2 predates GCC 15. Its explicit variable-template specialization
    # needs inline linkage with current MinGW to avoid one definition per TU.
    $qtHeader = Join-Path $repo 'build\windows-mingw-relwithdebinfo\externals\qt\6.7.2\mingw_64\include\QtCore\qcomparehelpers.h'
    if (Test-Path $qtHeader) {
        $qtText = Get-Content $qtHeader -Raw
        $qtFixed = $qtText.Replace("template <>`r`nconstexpr bool IsFloatType_v<QtPrivate::NativeFloat16Type> = true;", "template <>`r`ninline constexpr bool IsFloatType_v<QtPrivate::NativeFloat16Type> = true;")
        if ($qtFixed -ne $qtText) { Set-Content $qtHeader $qtFixed -NoNewline }
    }
    $preset = if ($Bundle) { 'windows-mingw-bundle' } else { 'windows-mingw-relwithdebinfo' }
    & $tools.CMake --build --preset $preset
    if ($LASTEXITCODE) { throw 'Fallo la compilacion.' }
    if ($Bundle) {
        $bundleDir = Join-Path $repo 'build\windows-mingw-relwithdebinfo\bundle'
        $runDir = Join-Path $repo 'build\windows-mingw-relwithdebinfo\bin\RelWithDebInfo'
        function Copy-RuntimeFile([string]$source, [string]$destination) {
            try {
                Copy-Item -LiteralPath $source -Destination $destination -Force
            } catch [System.IO.IOException] {
                Write-Warning "No se pudo actualizar $([IO.Path]::GetFileName($source)) en $destination porque LimoMada3DS/Lime3DS lo está usando. El bundle compilado sigue siendo válido."
            }
        }
        foreach ($runtime in @('libwinpthread-1.dll', 'libgcc_s_seh-1.dll', 'libstdc++-6.dll')) {
            $source = Join-Path $tools.MinGWBin $runtime
            if (-not (Test-Path $source)) { throw "Falta el runtime de MinGW: $runtime" }
            Copy-RuntimeFile $source $bundleDir
            Copy-RuntimeFile $source $runDir
        }
        Get-ChildItem -Path (Join-Path $bundleDir '*.dll') | ForEach-Object {
            Copy-RuntimeFile $_.FullName $runDir
        }
        try {
            Copy-Item -LiteralPath (Join-Path $bundleDir 'plugins') -Destination $runDir -Recurse -Force
        } catch [System.IO.IOException] {
            Write-Warning 'No se pudieron actualizar todos los plugins del directorio de ejecución porque LimoMada3DS/Lime3DS está abierto. El bundle compilado sigue siendo válido.'
        }
    }
} finally { Pop-Location }
