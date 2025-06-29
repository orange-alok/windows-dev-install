# Windows Development Environment Setup Script
#
# This script installs a set of common development tools on a fresh Windows machine.
# It uses the winget package manager, which is included in modern versions of Windows.
#
# To run this script:
# 1. Open PowerShell as an Administrator.
# 2. Navigate to the directory where you saved this script.
# 3. If you get an error about scripts being disabled on your system, run:
#    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
# 4. Run the script: .\install_dev_tools.ps1

# --- Configuration: Add or remove tools here ---
$packages = @(
    @{id="Microsoft.VisualStudioCode"; name="Visual Studio Code"},
    @{id="Python.Python.3.9"; name="Python 3.9"; override='InstallAllUsers=1 PrependPath=1'},
    @{id="Rustlang.Rustup"; name="Rust (via rustup)"},
    @{id="Git.Git"; name="Git"},
    @{id="Oracle.VirtualBox"; name="VirtualBox"},
    @{id="Docker.DockerDesktop"; name="Docker Desktop"},
    @{id="CoreyButler.NVMforWindows"; name="NVM for Windows"},
    @{id="Mozilla.Firefox"; name="Firefox"},
    @{id="Surfshark.Surfshark"; name="Surfshark"},
    @{id="Valve.Steam"; name="Steam"}
)

# --- Main Script ---

# Check if running as Administrator
if (-Not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script must be run as an Administrator. Please re-run this script in an elevated PowerShell session."
    exit
}

Write-Host "Starting development environment setup..." -ForegroundColor Green

# --- WSL and Docker ---
Write-Host "Checking for Docker prerequisites (WSL 2)..." -ForegroundColor Cyan
$wsl_feature = "Microsoft-Windows-Subsystem-Linux"
$vm_platform_feature = "VirtualMachinePlatform"

$wsl_status = Get-WindowsOptionalFeature -Online -FeatureName $wsl_feature
if (-not $wsl_status.State -eq 'Enabled') {
    Write-Host "Windows Subsystem for Linux (WSL) is not enabled. It is required for Docker Desktop."
    Write-Host "This script can enable it for you, which will require a system restart."
    $choice = Read-Host "Do you want to enable WSL and Virtual Machine Platform? (y/n)"
    if ($choice -eq 'y') {
        Write-Host "Enabling WSL and Virtual Machine Platform..."
        dism.exe /online /enable-feature /featurename:$wsl_feature /all /norestart
        dism.exe /online /enable-feature /featurename:$vm_platform_feature /all /norestart
        Write-Host "WSL and Virtual Machine Platform have been enabled." -ForegroundColor Green
        Write-Host "A RESTART IS REQUIRED for these changes to take effect." -ForegroundColor Yellow
        Write-Host "After restarting, you may need to install a Linux distribution from the Microsoft Store (e.g., Ubuntu)."
        Write-Host "Then, open PowerShell and run 'wsl --set-default-version 2' to set WSL 2 as the default."
        Write-Host "Please restart your computer and then re-run this script to install Docker and other tools."
        exit
    } else {
        Write-Host "Skipping WSL setup. Docker Desktop installation will be skipped." -ForegroundColor Yellow
    }
} else {
    Write-Host "WSL seems to be enabled." -ForegroundColor Green
}


# --- Set WSL 2 as default ---
Write-Host "Attempting to set WSL 2 as the default version..." -ForegroundColor Cyan
try {
    wsl --set-default-version 2
    Write-Host "WSL 2 has been set as the default version." -ForegroundColor Green
} catch {
    Write-Warning "Failed to set WSL 2 as default. This is often because the WSL kernel is not installed."
    $choice = Read-Host "Do you want this script to run 'wsl --update' for you? (y/n)"
    if ($choice -eq 'y') {
        Write-Host "Running 'wsl --update'..."
        wsl --update --web-download
        if ($LASTEXITCODE -eq 0) {
            Write-Host "WSL update completed. The script will now try to set WSL 2 as the default version again." -ForegroundColor Green
            Write-Host "If the update requires a restart, please do so and then re-run this script." -ForegroundColor Yellow
            try {
                wsl --set-default-version 2
                Write-Host "Successfully set WSL 2 as the default version after the update." -ForegroundColor Green
            } catch {
                Write-Warning "Still failed to set WSL 2 as default after update. A restart is likely required."
                Write-Warning "Please restart your computer and then re-run this script."
                exit
            }
        } else {
            Write-Warning "Failed to run 'wsl --update'. Please run it manually from an Administrator PowerShell."
            Write-Warning "You can download the kernel manually from: https://aka.ms/wsl2kernel"
        }
    } else {
        Write-Warning "Skipping WSL kernel update. Docker Desktop installation will likely fail."
    }
}


# --- Install Packages ---
foreach ($pkg in $packages) {
    Write-Host "Installing $($pkg.name)..." -ForegroundColor Cyan
    
    # Check if package is already installed (winget returns exit code 0 if found, 2 if not)
    winget list --id $pkg.id -n 1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "$($pkg.name) is already installed. Skipping." -ForegroundColor Green
        continue
    }

    # Docker has a dependency on WSL, so we check again.
    $wsl_status_check = Get-WindowsOptionalFeature -Online -FeatureName $wsl_feature
    if (($pkg.id -eq "Docker.DockerDesktop") -and (-not $wsl_status_check.State -eq 'Enabled')) {
        Write-Host "Cannot install Docker Desktop because WSL is not enabled. Please enable it and restart." -ForegroundColor Red
        continue
    }
    
    Write-Host "Running: winget install -e --id $($pkg.id) --accept-source-agreements --accept-package-agreements"
    winget install -e --id $pkg.id --accept-source-agreements --accept-package-agreements
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to install $($pkg.name)." -ForegroundColor Red
    } else {
        Write-Host "$($pkg.name) installed successfully." -ForegroundColor Green
    }
}

# --- Automated Post-installation Actions ---
Write-Host "Running automated post-installation steps..." -ForegroundColor Cyan

# 1. Update Rust toolchain via rustup
$rutool = Join-Path $env:USERPROFILE ".cargo\bin\rustup.exe"
if (Test-Path $rutool) {
    Write-Host "Updating Rust toolchain (rustup update)..." -ForegroundColor Cyan
    & $rutool update stable
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Rust toolchain updated." -ForegroundColor Green
    } else {
        Write-Warning "rustup update failed. You can run it manually later."
    }
} else {
    Write-Warning "rustup.exe not found. Rust might not have installed correctly or a restart is required before it is available in PATH."
}

# 2. Install latest Node.js via nvm-windows
# Detect nvm.exe
$nvmExe = $null
$nvmCmd = Get-Command "nvm.exe" -ErrorAction SilentlyContinue
if ($nvmCmd) {
    $nvmExe = $nvmCmd.Path
} else {
    $possibleNvm = @(
        "C:\Program Files\nvm\nvm.exe",
        "$env:LOCALAPPDATA\Programs\nvm\nvm.exe",
        "$env:APPDATA\nvm\nvm.exe"
    )
    foreach ($p in $possibleNvm) {
        if (Test-Path $p) { $nvmExe = $p; break }
    }
}

if ($nvmExe) {
    Write-Host "Installing latest Node.js via nvm-windows (using $nvmExe)..." -ForegroundColor Cyan
    & $nvmExe install latest
    if ($LASTEXITCODE -eq 0) {
        & $nvmExe use latest
        Write-Host "Latest Node.js installed and activated." -ForegroundColor Green
    } else {
        Write-Warning "nvm failed to install Node.js. You can run 'nvm install lts' manually later."
    }
} else {
    Write-Warning "nvm.exe not found. NVM for Windows may require a system logoff/logon before it is available in PATH, or the installation path may differ."
}

# 3. Download latest Ubuntu Desktop ISO for VirtualBox
Write-Host "Attempting to download latest Ubuntu Desktop ISO..." -ForegroundColor Cyan
try {
    $releasesPage = Invoke-WebRequest -Uri "https://releases.ubuntu.com/" -UseBasicParsing -ErrorAction Stop
    $releaseDirs = $releasesPage.Links | Where-Object { $_.href -match '^[0-9]{2}\.[0-9]{2}/$' } | ForEach-Object { $_.href.TrimEnd('/') }
    $latestRelease = ($releaseDirs | Sort-Object { [double]$_ } -Descending)[0]

    $isoPage = Invoke-WebRequest -Uri "https://releases.ubuntu.com/$latestRelease/" -UseBasicParsing -ErrorAction Stop
    $isoLink = ($isoPage.Links | Where-Object { $_.href -match 'ubuntu-.*-desktop-amd64\.iso$' }).href | Select-Object -First 1
    if (-not $isoLink) {
        throw "ISO link not found on releases page."
    }
    $isoUrl = "https://releases.ubuntu.com/$latestRelease/$isoLink"
    $downloadPath = Join-Path $env:USERPROFILE "Downloads\$isoLink"
    if (-not (Test-Path $downloadPath)) {
        Write-Host "Downloading Ubuntu ISO from $isoUrl ..."
        Invoke-WebRequest -Uri $isoUrl -OutFile $downloadPath -UseBasicParsing
        Write-Host "Ubuntu ISO downloaded to $downloadPath" -ForegroundColor Green
    } else {
        Write-Host "Ubuntu ISO already exists at $downloadPath . Skipping download." -ForegroundColor Green
    }
} catch {
    Write-Warning "Failed to automatically download Ubuntu ISO: $_.Exception.Message"
    Write-Warning "You can download it manually from https://ubuntu.com/download/desktop"
}

# --- Create two isolated Ubuntu VMs using VirtualBox unattended install ---
$vboxManage = Join-Path ${env:ProgramFiles} "Oracle\VirtualBox\VBoxManage.exe"
if (-not (Test-Path $vboxManage)) {
    Write-Warning "VBoxManage.exe not found. Ensure VirtualBox is installed and then re-run the script to create VMs."
} elseif (-not (Test-Path $downloadPath)) {
    Write-Warning "Ubuntu ISO not available. Skipping VM creation."
} else {
    for ($i = 1; $i -le 2; $i++) {
        $vmName = "UbuntuVM$i"
        Write-Host "\n--- Creating $vmName ---" -ForegroundColor Cyan
        # Skip if VM already exists
        & $vboxManage list vms | Select-String -Pattern $vmName -SimpleMatch -Quiet
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$vmName already exists. Skipping creation." -ForegroundColor Yellow
            continue
        }

        # Create the VM container
        & $vboxManage createvm --name $vmName --ostype Ubuntu_64 --register
        
        # Configure basic resources and isolation settings
        & $vboxManage modifyvm $vmName --memory 8192 --cpus 6 --graphicscontroller vmsvga --nic1 nat --clipboard disabled --draganddrop disabled
        
        # Unattended installation (VirtualBox 7+)
        Write-Host "Starting unattended installation for $vmName ..." -ForegroundColor Cyan
        & $vboxManage unattended install $vmName `
            --user ubuntu --password "P@ssw0rd" `
            --full-user-name "Ubuntu User" `
            --hostname $vmName `
            --iso $downloadPath `
            --locale en_US `
            --time-zone UTC `
            --install-additions `
            --start-vm=headless

        if ($LASTEXITCODE -eq 0) {
            Write-Host "$vmName creation started (running headless). It will take a few minutes to finish installation." -ForegroundColor Green
        } else {
            Write-Warning "Failed to start unattended install for $vmName. You can try manual creation later via VirtualBox GUI."
        }
    }
}

# --- Final message ---
Write-Host "--------------------------------------------------" -ForegroundColor Green
Write-Host "Automation complete. Rust toolchain, Node.js, Ubuntu ISO download, and VM creation steps have executed." -ForegroundColor Green
Write-Host "If Ubuntu VMs are still installing, monitor them with 'VBoxManage list runningvms'." -ForegroundColor Yellow