# ==============================================================================
# mobile-toolchain-setup: Windows Parallel Ingestion Module
# Concurrently pre-fetches JDK, Android cmdline-tools, Gradle, and Flutter SDK
# ==============================================================================

Import-Module (Join-Path $PSScriptRoot "ui.psm1") -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "os_detect.psm1") -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "jdk.psm1") -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "android.psm1") -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "gradle.psm1") -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "flutter.psm1") -ErrorAction SilentlyContinue

function Invoke-WindowsParallelIngestion {
    param (
        [string]$JdkVer,
        [string]$ApiVer,
        [string]$BuildToolsVer,
        [string]$NdkVer,
        [string]$CmakeVer,
        [string]$GradleVer,
        [string]$FlutterChannel,
        [string]$JdkInstallDir,
        [string]$SdkRoot,
        [string]$GradleInstallDir,
        [string]$FlutterHome,
        [string]$Architecture = "x64",
        [string]$FallbackCmdlineUrl = "https://dl.google.com/android/repository/commandlinetools-win-16111833_latest.zip",
        [bool]$DryRun = $false
    )

    if ($DryRun) {
        Write-LogInfo "Parallel Toolchain Ingestion enabled (4 concurrent download workers)"
        Write-LogDryRun "Parallel Worker 1: Fetch Eclipse Temurin OpenJDK $JdkVer"
        Write-LogDryRun "Parallel Worker 2: Fetch Android SDK cmdline-tools"
        Write-LogDryRun "Parallel Worker 3: Fetch Gradle $GradleVer distribution"
        Write-LogDryRun "Parallel Worker 4: Clone Flutter SDK ($FlutterChannel)"
        Write-LogDryRun "Staged Configuration Pipeline:"
        Write-LogDryRun "  -> Extract JDK & export JAVA_HOME"
        Write-LogDryRun "  -> Extract cmdline-tools into $SdkRoot\cmdline-tools\latest"
        Write-LogDryRun "  -> Concurrently run sdkmanager packages and Flutter precache"
        Write-LogDryRun "  -> Finalize Flutter Android SDK linkage and doctor licenses"

        Install-WindowsJDK -TargetVersion $JdkVer -InstallRoot $JdkInstallDir -Architecture $Architecture -DryRun $true
        Install-WindowsAndroidSDK -ApiArg $ApiVer -BuildToolsArg $BuildToolsVer -NdkArg $NdkVer -CmakeArg $CmakeVer -SdkRoot $SdkRoot -DryRun $true
        Install-WindowsGradle -TargetVersion $GradleVer -InstallDir $GradleInstallDir -DryRun $true
        Install-WindowsFlutter -ChannelArg $FlutterChannel -FlutterRoot $FlutterHome -AndroidSdk $SdkRoot -DryRun $true
        return
    }

    Write-LogStep "Parallel Toolchain Ingestion (Windows Concurrent Pipeline)"
    $parallelScratch = Join-Path ([System.IO.Path]::GetTempPath()) ("mto-parallel-" + [System.Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $parallelScratch -Force | Out-Null

    $jdkZip = Join-Path $parallelScratch "jdk.zip"
    $cmdlineZip = Join-Path $parallelScratch "cmdline.zip"
    $gradleZip = Join-Path $parallelScratch "gradle.zip"

    $archSlug = if ($Architecture -eq "arm64") { "aarch64" } else { "x64" }
    $jdkUrl = "https://api.adoptium.net/v3/binary/latest/$JdkVer/ga/windows/$archSlug/jdk/hotspot/normal/eclipse"
    $cmdlineUrl = Resolve-WindowsCmdlineToolsUrl -FallbackUrl $FallbackCmdlineUrl
    $gradleUrl = "https://services.gradle.org/distributions/gradle-$GradleVer-bin.zip"

    Write-LogInfo "Spawning 4 concurrent download workers..."
    $startTime = Get-Date

    $jobs = @{}
    $jobs["JDK"] = Start-Job -ScriptBlock {
        param($url, $dest)
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 180
    } -ArgumentList $jdkUrl, $jdkZip

    $jobs["Cmdline"] = Start-Job -ScriptBlock {
        param($url, $dest)
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 180
    } -ArgumentList $cmdlineUrl, $cmdlineZip

    if ($GradleVer -ne "skip" -and -not [string]::IsNullOrWhiteSpace($GradleVer)) {
        $jobs["Gradle"] = Start-Job -ScriptBlock {
            param($url, $dest)
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 180
        } -ArgumentList $gradleUrl, $gradleZip
    }

    $flutterGitFolder = Join-Path $FlutterHome ".git"
    if (-not (Test-Path $flutterGitFolder) -and $FlutterChannel -ne "fvm") {
        $jobs["Flutter"] = Start-Job -ScriptBlock {
            param($channel, $dest)
            git clone --depth 1 -b $channel "https://github.com/flutter/flutter.git" $dest 2>$null
        } -ArgumentList $FlutterChannel, $FlutterHome
    }

    try {
        # Wait for JDK and Cmdline first
        Wait-Job -Job $jobs["JDK"], $jobs["Cmdline"] | Out-Null
        Write-LogSuccess "Eclipse Temurin OpenJDK $JdkVer downloaded."
        Write-LogSuccess "Android SDK cmdline-tools downloaded."

        # Staged extraction and immediate package installation
        Install-WindowsJDK -TargetVersion $JdkVer -InstallRoot $JdkInstallDir -Architecture $Architecture -PredownloadedArchive $jdkZip
        Install-WindowsAndroidSDK -ApiArg $ApiVer -BuildToolsArg $BuildToolsVer -NdkArg $NdkVer -CmakeArg $CmakeVer -SdkRoot $SdkRoot -PredownloadedArchive $cmdlineZip

        if ($jobs.ContainsKey("Gradle")) {
            Wait-Job -Job $jobs["Gradle"] | Out-Null
            Write-LogSuccess "Gradle $GradleVer downloaded."
            Install-WindowsGradle -TargetVersion $GradleVer -InstallDir $GradleInstallDir -PredownloadedArchive $gradleZip
        }

        if ($jobs.ContainsKey("Flutter")) {
            Wait-Job -Job $jobs["Flutter"] | Out-Null
            Write-LogSuccess "Flutter SDK repository ready."
        }
        Install-WindowsFlutter -ChannelArg $FlutterChannel -FlutterRoot $FlutterHome -AndroidSdk $SdkRoot

        $elapsed = [int]((Get-Date) - $startTime).TotalSeconds
        Write-LogSuccess "All toolchain components ingested in ${elapsed}s (parallel execution)."
    }
    finally {
        foreach ($j in $jobs.Values) {
            Stop-Job -Job $j -ErrorAction SilentlyContinue
            Remove-Job -Job $j -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -Path $parallelScratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function Invoke-WindowsParallelIngestion
