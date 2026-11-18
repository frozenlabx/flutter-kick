# ==============================================================================
# mobile-toolchain-setup: Windows OS Detection Module
# Detects Windows OS version, CPU arch, disk space, and prerequisites (Git)
# ==============================================================================

Import-Module (Join-Path $PSScriptRoot "ui.psm1") -ErrorAction SilentlyContinue

function Detect-WindowsOS {
    $osInfo = @{
        OSName       = "Windows"
        OSVersion    = [System.Environment]::OSVersion.Version.ToString()
        Architecture = "x64"
    }

    try {
        $wmi = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($wmi -and $wmi.Caption) {
            $osInfo.OSName = $wmi.Caption.Trim()
        }
    }
    catch {}

    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($arch -eq "ARM64") {
        $osInfo.Architecture = "arm64"
    }
    elseif ($arch -eq "AMD64" -or $arch -eq "x86_64") {
        $osInfo.Architecture = "x64"
    }
    else {
        $osInfo.Architecture = $arch
    }

    Write-LogInfo "Detected OS: $($osInfo.OSName) ($($osInfo.OSVersion))"
    Write-LogInfo "Detected Architecture: $($osInfo.Architecture)"

    return $osInfo
}

function Test-DiskSpace {
    param (
        [string]$TargetPath = $env:USERPROFILE,
        [int]$MinGB = 15
    )
    try {
        $driveLetter = [System.IO.Path]::GetPathRoot($TargetPath).Replace("\", "").Replace(":", "")
        $drive = Get-PSDrive -Name $driveLetter -ErrorAction Stop
        $freeGB = [math]::Round($drive.Free / 1GB, 1)

        if ($freeGB -lt $MinGB) {
            Write-LogWarn "Low disk space on drive ${driveLetter}:: only ${freeGB} GB free."
            Write-LogWarn "Recommended minimum free disk space is ${MinGB} GB for Android SDK, NDK, and Flutter."
            return $false
        }
        else {
            Write-LogInfo "Disk space check passed: ${freeGB} GB free on drive ${driveLetter}: (minimum: ${MinGB} GB)."
            return $true
        }
    }
    catch {
        Write-LogWarn "Could not determine free disk space for: $TargetPath"
        return $true
    }
}

function Ensure-Prerequisites {
    param (
        [bool]$DryRun = $false
    )
    Write-LogStep "Verifying Windows base prerequisites"

    # Check Git
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCmd) {
        $gitVer = try { (git --version).Trim() } catch { "Git installed" }
        Write-LogSuccess "Git detected: $gitVer"
        return $true
    }

    Write-LogWarn "Git for Windows is not detected in PATH."

    if ($DryRun) {
        Write-LogDryRun "Would check/install Git using: winget install --id Git.Git -e --source winget"
        return $true
    }

    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        Write-LogInfo "Attempting automatic installation of Git via Windows Package Manager (winget)..."
        try {
            winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            if (Get-Command git -ErrorAction SilentlyContinue) {
                Write-LogSuccess "Git installed successfully."
                return $true
            }
        }
        catch {
            Write-LogWarn "winget installation encountered an error."
        }
    }

    Write-LogError "Git is required to clone Flutter and manage toolchain dependencies."
    Write-LogInfo "Please install Git from https://git-scm.com/download/win and restart this setup."
    return $false
}

Export-ModuleMember -Function Detect-WindowsOS, Test-DiskSpace, Ensure-Prerequisites
