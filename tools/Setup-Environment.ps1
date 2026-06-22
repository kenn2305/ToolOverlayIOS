[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Launcher = Join-Path $ProjectRoot "SETUP_ENVIRONMENT.cmd"
$LogDirectory = Join-Path $ProjectRoot "setup-logs"
$Distro = $null

function Write-Step([string]$Text) {
    Write-Host "`n==> $Text" -ForegroundColor Cyan
}

function Get-WslDistros {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        return @()
    }

    return @(
        & wsl.exe --list --quiet 2>$null |
            ForEach-Object { ($_ -replace "`0", "").Trim() } |
            Where-Object { $_ }
    )
}

function Get-UbuntuDistro {
    $distros = @(Get-WslDistros)
    $exact = $distros | Where-Object { $_ -eq "Ubuntu" } | Select-Object -First 1
    if ($exact) {
        return $exact
    }

    return $distros |
        Where-Object { $_ -match "^Ubuntu(?:-|$)" } |
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

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Step "Requesting Administrator permission"
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$PSCommandPath`""
    )
    exit 0
}

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw "This installer requires Windows 10 2004+ or Windows 11 with WSL support."
}

New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
$LogFile = Join-Path $LogDirectory ("setup-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
Start-Transcript -Path $LogFile -Force | Out-Null

Write-Step "Checking WSL and Ubuntu"
$Distro = Get-UbuntuDistro
if (-not $Distro) {
    Write-Host "Ubuntu is not installed. Windows will install WSL2 and Ubuntu now."
    & wsl.exe --install -d Ubuntu --no-launch

    $Distro = Get-UbuntuDistro
    if (-not $Distro) {
        $RunOncePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
        New-Item -Path $RunOncePath -Force | Out-Null
        Set-ItemProperty -Path $RunOncePath -Name "OverlayIOSTOOLSetup" -Value "`"$Launcher`""
        Write-Host ""
        Write-Host "Windows must restart to finish installing WSL." -ForegroundColor Yellow
        Write-Host "The setup will resume automatically after you sign in." -ForegroundColor Yellow
        $answer = Read-Host "Restart now? [Y/n]"
        if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match "^[Yy]") {
            Restart-Computer
        }
        exit 0
    }
}

Write-Host "Using WSL distribution: $Distro"
& wsl.exe --set-version $Distro 2 | Out-Host

Write-Step "Creating the isolated Linux builder account"
$RootBootstrap = @'
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y sudo ca-certificates curl git build-essential fakeroot rsync perl python3 zip unzip xz-utils dpkg-dev libxml2 libtinfo6 libplist-utils g++ make
if ! id builder >/dev/null 2>&1; then
    useradd -m -s /bin/bash builder
fi
usermod -aG sudo builder
printf 'builder ALL=(ALL) NOPASSWD:ALL\n' >/etc/sudoers.d/90-overlay-builder
chmod 0440 /etc/sudoers.d/90-overlay-builder
chown -R builder:builder /home/builder
'@
& wsl.exe -d $Distro -u root -- bash -lc $RootBootstrap
if ($LASTEXITCODE -ne 0) { throw "Ubuntu dependency installation failed." }

Write-Step "Installing Theos, iOS toolchain, and patched SDK"
$TheosBootstrap = @'
set -e
export HOME=/home/builder
export USER=builder
export LOGNAME=builder
export SHELL=/bin/bash
export THEOS=/home/builder/theos
export CI=1
export PATH="$THEOS/bin:$PATH"
touch "$HOME/.profile" "$HOME/.bashrc"
grep -qxF 'export THEOS=$HOME/theos' "$HOME/.profile" || echo 'export THEOS=$HOME/theos' >>"$HOME/.profile"
grep -qxF 'export PATH=$THEOS/bin:$PATH' "$HOME/.profile" || echo 'export PATH=$THEOS/bin:$PATH' >>"$HOME/.profile"
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"
if [ ! -x "$THEOS/toolchain/linux/iphone/bin/clang" ]; then
    echo "Theos toolchain is missing." >&2
    exit 1
fi
if [ ! -d "$THEOS/sdks/iPhoneOS14.5.sdk" ]; then
    "$THEOS/bin/install-sdk" 14.5
fi
# do_build.sh installs a pinned allemande revision and refuses unsafe arm64e output.
'@
& wsl.exe -d $Distro -u builder -- bash -lc $TheosBootstrap
if ($LASTEXITCODE -ne 0) { throw "Theos installation failed." }

Write-Step "Building OverlayIOSTOOL to verify the environment"
$LinuxProjectPath = Convert-ToWslPath $ProjectRoot $Distro
if (-not $LinuxProjectPath) { throw "Could not translate the project path for WSL." }

& wsl.exe -d $Distro -u builder -- bash "$LinuxProjectPath/do_build.sh"
if ($LASTEXITCODE -ne 0) { throw "The environment was installed, but the verification build failed." }

Write-Step "Installing an editor when Windows Package Manager is available"
if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
    $CodeCommand = Get-Command code.cmd -ErrorAction SilentlyContinue
    if (-not $CodeCommand) {
        try {
            & winget.exe install --id Microsoft.VisualStudioCode --exact --silent --accept-package-agreements --accept-source-agreements
        } catch {
            Write-Host "VS Code installation was skipped: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "Environment ready." -ForegroundColor Green
Write-Host "Build button: $ProjectRoot\BUILD_PROJECT.cmd"
Write-Host "Output folder: $ProjectRoot\packages"
Write-Host "Setup log: $LogFile"
Stop-Transcript | Out-Null
