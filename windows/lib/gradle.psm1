# ==============================================================================
# mobile-toolchain-setup: Windows Gradle Installation Module
# Downloads and extracts standalone Gradle distribution into ~/.local/share/gradle
# ==============================================================================

Import-Module (Join-Path $PSScriptRoot "ui.psm1") -ErrorAction SilentlyContinue

function Install-WindowsGradle {
    param (
        [string]$TargetVersion = "8.11.1",
        [string]$InstallDir = (Join-Path $env:USERPROFILE ".local\share\gradle"),
        [bool]$DryRun = $false
    )
    if ($TargetVersion -eq "skip" -or [string]::IsNullOrWhiteSpace($TargetVersion)) {
        Write-LogInfo "Skipping Gradle installation as requested."
        return @{ GradleHome = (Join-Path $env:USERPROFILE ".gradle") }
    }

    Write-LogStep "Configuring Gradle $TargetVersion"

    $targetHome = Join-Path $InstallDir "gradle-$TargetVersion"
    $gradleBat = Join-Path $targetHome "bin\gradle.bat"
    $downloadUrl = "https://services.gradle.org/distributions/gradle-$TargetVersion-bin.zip"

    # Check if already installed
    if (Test-Path $gradleBat) {
        $env:GRADLE_HOME = $targetHome
        $env:Path = (Join-Path $targetHome "bin") + ";" + $env:Path
        Write-LogSuccess "Gradle $TargetVersion is already installed at: $targetHome"
        return @{ GradleHome = $targetHome }
    }

    if ($DryRun) {
        Write-LogDryRun "Target GRADLE_HOME: $targetHome"
        Write-LogDryRun "Would download Gradle distribution from: $downloadUrl"
        Write-LogDryRun "Would extract archive into: $InstallDir"
        Write-LogDryRun "Would set GRADLE_HOME = $targetHome"
        Write-LogDryRun "Would prepend $targetHome\bin to PATH"
        $env:GRADLE_HOME = $targetHome
        return @{ GradleHome = $targetHome }
    }

    # Live installation
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    $tmpZip = Join-Path $tmpDir "gradle-$TargetVersion-bin.zip"

    try {
        Write-LogInfo "Downloading Gradle $TargetVersion from $downloadUrl..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tmpZip -UseBasicParsing -TimeoutSec 120

        Write-LogInfo "Extracting Gradle into $InstallDir..."
        Expand-Archive -Path $tmpZip -DestinationPath $InstallDir -Force
    }
    catch {
        Write-LogError "Failed to download/extract Gradle $TargetVersion: $($_.Exception.Message)"
        return $null
    }
    finally {
        Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    $env:GRADLE_HOME = $targetHome
    $env:Path = (Join-Path $targetHome "bin") + ";" + $env:Path

    if (Test-Path $gradleBat) {
        Write-LogSuccess "Gradle $TargetVersion successfully installed at $targetHome"
        $gVer = try { (& $gradleBat -v 2>&1 | Where-Object { $_ -match "^Gradle [0-9]" } | Select-Object -First 1) } catch { "" }
        if ($gVer) { Write-LogInfo "Verified: $gVer" }
        return @{ GradleHome = $targetHome }
    }
    else {
        Write-LogError "gradle.bat not found at $gradleBat."
        return $null
    }
}

Export-ModuleMember -Function Install-WindowsGradle
