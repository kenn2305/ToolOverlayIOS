[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

function Get-UbuntuDistro {
    return @(
        & wsl.exe --list --quiet 2>$null |
            ForEach-Object { ($_ -replace "`0", "").Trim() } |
            Where-Object { $_ -match "^Ubuntu(?:-|$)" }
    ) |
        Sort-Object -Descending |
        Select-Object -First 1
}

function Convert-ToWslPath([string]$WindowsPath, [string]$Distribution) {
    $normalizedPath = $WindowsPath -replace "\\", "/"
    $result = & wsl.exe -d $Distribution -- wslpath -a -u $normalizedPath
    if ($LASTEXITCODE -ne 0) {
        throw "Could not translate the project path for WSL."
    }

    return (($result | Select-Object -Last 1) -replace "`0", "").Trim()
}

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw "WSL is not installed. Run SETUP_ENVIRONMENT.cmd first."
}

$Distro = Get-UbuntuDistro
if (-not $Distro) {
    throw "Ubuntu is not installed. Run SETUP_ENVIRONMENT.cmd first."
}

Write-Host "Using WSL distribution: $Distro" -ForegroundColor DarkGray
$LinuxProjectPath = Convert-ToWslPath $ProjectRoot $Distro
if (-not $LinuxProjectPath) {
    throw "Could not translate the project path for WSL."
}

Write-Host "Building OverlayIOSTOOL..." -ForegroundColor Cyan
& wsl.exe -d $Distro -u builder -- bash "$LinuxProjectPath/do_build.sh"
if ($LASTEXITCODE -ne 0) {
    throw "The build failed."
}

$Package = Get-ChildItem (Join-Path $ProjectRoot "packages") -Filter *.deb |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $Package) {
    throw "The build completed but no .deb package was found."
}

Write-Host "Package ready: $($Package.FullName)" -ForegroundColor Green
