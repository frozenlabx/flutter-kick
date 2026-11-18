# ==============================================================================
# mobile-toolchain-setup: Windows JDK Installation Module
# Downloads and installs Eclipse Temurin OpenJDK (17 or 21) portable zip
# ==============================================================================

Import-Module (Join-Path $PSScriptRoot "ui.psm1") -ErrorAction SilentlyContinue

function Install-WindowsJDK {
    param (
        [string]$TargetVersion = "17",
        [string]$InstallRoot = (Join-Path $env:USERPROFILE ".local\share\jdks"),
        [string]$Architecture = "x64",
        [bool]$DryRun = $false
    )
    Write-LogStep "Installing / Verifying JDK $TargetVersion"

    $targetDir = Join-Path $InstallRoot "temurin-$TargetVersion"

    # Check if target local folder already has a functional JDK
    if (Test-Path (Join-Path $targetDir "bin\java.exe")) {
        $env:JAVA_HOME = $targetDir
        $env:Path = (Join-Path $targetDir "bin") + ";" + $env:Path
        Write-LogSuccess "Matching JDK $TargetVersion already installed at: $targetDir"
        return @{ JavaHome = $targetDir }
    }

    # Check active JAVA_HOME
    if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME "bin\java.exe"))) {
        $verCheck = try { (& "$env:JAVA_HOME\bin\java.exe" -version 2>&1 | Select-Object -First 1) } catch { "" }
        if ($verCheck -match "`"$TargetVersion\." -or $verCheck -match "`"1\.$TargetVersion\.") {
            Write-LogSuccess "Active JAVA_HOME already points to JDK $TargetVersion: $env:JAVA_HOME"
            return @{ JavaHome = $env:JAVA_HOME }
        }
    }

    $archSlug = if ($Architecture -eq "arm64") { "aarch64" } else { "x64" }
    $adoptiumUrl = "https://api.adoptium.net/v3/binary/latest/$TargetVersion/ga/windows/$archSlug/jdk/hotspot/normal/eclipse"

    if ($DryRun) {
        Write-LogDryRun "Would download Eclipse Temurin OpenJDK $TargetVersion ($archSlug) from:"
        Write-LogDryRun "  $adoptiumUrl"
        Write-LogDryRun "Would extract archive into: $targetDir"
        Write-LogDryRun "Would configure JAVA_HOME = $targetDir"
        $env:JAVA_HOME = $targetDir
        return @{ JavaHome = $targetDir }
    }

    Write-LogInfo "Downloading Eclipse Temurin OpenJDK $TargetVersion ($archSlug)..."
    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    $tmpZip = Join-Path $tmpDir "temurin-$TargetVersion.zip"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $adoptiumUrl -OutFile $tmpZip -UseBasicParsing -TimeoutSec 60
    }
    catch {
        Write-LogError "Failed to download OpenJDK $TargetVersion: $($_.Exception.Message)"
        Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        return $null
    }

    Write-LogInfo "Extracting JDK archive into $targetDir..."
    $extractTmp = Join-Path $tmpDir "extracted"
    New-Item -ItemType Directory -Path $extractTmp -Force | Out-Null

    try {
        Expand-Archive -Path $tmpZip -DestinationPath $extractTmp -Force
        $innerRoot = Get-ChildItem -Path $extractTmp -Directory | Select-Object -First 1
        if (-not $innerRoot) {
            Write-LogError "Unexpected archive structure in Temurin download."
            return $null
        }

        if (-not (Test-Path $InstallRoot)) {
            New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
        }
        if (Test-Path $targetDir) {
            Remove-Item -Path $targetDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        Move-Item -Path $innerRoot.FullName -Destination $targetDir -Force
    }
    finally {
        Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    $env:JAVA_HOME = $targetDir
    $env:Path = (Join-Path $targetDir "bin") + ";" + $env:Path

    if (Test-Path (Join-Path $targetDir "bin\java.exe")) {
        $installedVer = (& "$targetDir\bin\java.exe" -version 2>&1 | Select-Object -First 1)
        Write-LogSuccess "Configured JDK $TargetVersion at $targetDir"
        Write-LogInfo "Version: $installedVer"
        return @{ JavaHome = $targetDir }
    }
    else {
        Write-LogError "java.exe not found at $targetDir\bin\java.exe after extraction."
        return $null
    }
}

Export-ModuleMember -Function Install-WindowsJDK
