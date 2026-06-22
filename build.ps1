# OverlayIOSTOOL Build Script for Windows
# Usage: .\build.ps1 [ip-address]

param(
    [string]$DeviceIP = ""
)

$ErrorActionPreference = "Stop"

function Write-Header {
    param([string]$Text)
    Write-Host "==========================================`n$Text`n==========================================" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Text)
    Write-Host "✓ $Text" -ForegroundColor Green
}

function Write-Error-Custom {
    param([string]$Text)
    Write-Host "✗ $Text" -ForegroundColor Red
}

function Write-Step {
    param([string]$Number, [string]$Text)
    Write-Host "[$Number] $Text" -ForegroundColor Yellow
}

Write-Header "OverlayIOSTOOL - Windows Build Script"

# Check THEOS
if (-not $env:THEOS) {
    Write-Error-Custom "THEOS environment variable not set!"
    Write-Host "Please set THEOS to your Theos installation directory" -ForegroundColor Red
    Write-Host "Example: `$env:THEOS='C:\theos'" -ForegroundColor Yellow
    exit 1
}

Write-Success "THEOS found at: $env:THEOS"
Write-Host ""

# Step 1: Clean
Write-Step "1/4" "Cleaning previous builds..."
try {
    & make clean 2>$null
    Remove-Item -Path "packages" -Recurse -Force 2>$null
    Write-Success "Clean complete"
} catch {
    Write-Success "Clean (nothing to clean)"
}
Write-Host ""

# Step 2: Build
Write-Step "2/4" "Building tweak and companion app..."
try {
    & make package FINALPACKAGE=1
    Write-Success "Build successful"
} catch {
    Write-Error-Custom "Build failed!"
    exit 1
}
Write-Host ""

# Step 3: Install
Write-Step "3/4" "Installing to device..."

if ([string]::IsNullOrEmpty($DeviceIP)) {
    if (-not $env:THEOS_DEVICE_IP) {
        $DeviceIP = Read-Host "Enter your iPhone IP address"
    } else {
        $DeviceIP = $env:THEOS_DEVICE_IP
    }
}

$env:THEOS_DEVICE_IP = $DeviceIP
Write-Host "Device IP: $DeviceIP" -ForegroundColor Cyan

try {
    & make install
    Write-Success "Installation successful"
} catch {
    Write-Error-Custom "Installation failed!"
    exit 1
}
Write-Host ""

# Step 4: Complete
Write-Step "4/4" "Complete"
Write-Header "OverlayIOSTOOL successfully built and installed!"
Write-Host "📱 Device will respring automatically" -ForegroundColor Green
Write-Host "📲 Launch 'OverlayToolApp' from your home screen to configure" -ForegroundColor Green
Write-Host ""
