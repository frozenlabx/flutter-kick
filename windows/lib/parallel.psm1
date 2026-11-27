# ==============================================================================
# mobile-toolchain-setup: Windows Parallel Ingestion Module
# Concurrently pre-fetches JDK, Android cmdline-tools, Gradle, and Flutter SDK
# Provides live progress indicators for all concurrent workers
# ==============================================================================

Import-Module (Join-Path $PSScriptRoot "ui.psm1") -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "os_detect.psm1") -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "jdk.psm1") -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "android.psm1") -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "gradle.psm1") -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "flutter.psm1") -ErrorAction SilentlyContinue

function Get-TargetSizeMb {
    param([string]$Path)
    if (Test-Path -Path $Path -PathType Leaf) {
        $bytes = (Get-Item $Path).Length
        return [math]::Round($bytes / 1MB, 1).ToString("F1") + " MB"
    }
    elseif (Test-Path -Path $Path -PathType Container) {
        $measure = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
        if ($measure -and $measure.Sum) {
            return [math]::Round($measure.Sum / 1MB, 1).ToString("F1") + " MB"
        }
    }
    return "0.0 MB"
}

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
        [bool]$DryRun = $false,
        [bool]$ReuseJdk = $false,
        [bool]$ReuseAndroid = $false,
        [bool]$ReuseGradle = $false,
        [bool]$ReuseFlutter = $false
    )

    if ($DryRun) {
        if ($ReuseJdk) {
            Write-LogDryRun "Worker 1: Reusing existing JDK ($JdkVer)"
        } else {
            Write-LogDryRun "Worker 1: Fetch Eclipse Temurin OpenJDK $JdkVer"
        }
        if ($ReuseAndroid) {
            Write-LogDryRun "Worker 2: Reusing existing Android SDK ($SdkRoot)"
        } else {
            Write-LogDryRun "Worker 2: Fetch Android SDK cmdline-tools"
        }
        if ($ReuseGradle) {
            Write-LogDryRun "Worker 3: Reusing existing Gradle ($GradleVer)"
        } else {
            Write-LogDryRun "Worker 3: Fetch Gradle $GradleVer distribution"
        }
        if ($ReuseFlutter) {
            Write-LogDryRun "Worker 4: Reusing existing Flutter SDK ($FlutterChannel)"
        } else {
            Write-LogDryRun "Worker 4: Clone Flutter SDK ($FlutterChannel)"
        }
        Write-LogDryRun "Configuration Pipeline:"
        Write-LogDryRun "  -> Extract JDK & export JAVA_HOME"
        Write-LogDryRun "  -> Extract cmdline-tools into $SdkRoot\cmdline-tools\latest"
        Write-LogDryRun "  -> Run sdkmanager packages"
        Write-LogDryRun "  -> Finalize Flutter Android SDK linkage and doctor licenses"

        if (-not $ReuseJdk) {
            Install-WindowsJDK -TargetVersion $JdkVer -InstallRoot $JdkInstallDir -Architecture $Architecture -DryRun $true
        }
        Install-WindowsAndroidSDK -ApiArg $ApiVer -BuildToolsArg $BuildToolsVer -NdkArg $NdkVer -CmakeArg $CmakeVer -SdkRoot $SdkRoot -DryRun $true
        if (-not $ReuseGradle) {
            Install-WindowsGradle -TargetVersion $GradleVer -InstallDir $GradleInstallDir -DryRun $true
        }
        if (-not $ReuseFlutter) {
            Install-WindowsFlutter -ChannelArg $FlutterChannel -FlutterRoot $FlutterHome -AndroidSdk $SdkRoot -DryRun $true
        }
        return
    }

    $parallelScratch = Join-Path ([System.IO.Path]::GetTempPath()) ("mto-parallel-" + [System.Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $parallelScratch -Force | Out-Null

    $jdkZip = Join-Path $parallelScratch "jdk.zip"
    $cmdlineZip = Join-Path $parallelScratch "cmdline.zip"
    $gradleZip = Join-Path $parallelScratch "gradle.zip"

    $archSlug = if ($Architecture -eq "arm64") { "aarch64" } else { "x64" }
    $jdkUrl = "https://api.adoptium.net/v3/binary/latest/$JdkVer/ga/windows/$archSlug/jdk/hotspot/normal/eclipse"
    $cmdlineUrl = Resolve-WindowsCmdlineToolsUrl -FallbackUrl $FallbackCmdlineUrl
    $gradleUrl = "https://services.gradle.org/distributions/gradle-$GradleVer-bin.zip"

    $startTime = Get-Date

    $jobs = @{}
    if (-not $ReuseJdk) {
        $jobs["JDK"] = Start-Job -ScriptBlock {
            param($url, $dest)
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 180
        } -ArgumentList $jdkUrl, $jdkZip
    }

    if (-not $ReuseAndroid) {
        $jobs["Cmdline"] = Start-Job -ScriptBlock {
            param($url, $dest)
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 180
        } -ArgumentList $cmdlineUrl, $cmdlineZip
    }

    if (-not $ReuseGradle -and $GradleVer -ne "skip" -and -not [string]::IsNullOrWhiteSpace($GradleVer)) {
        $jobs["Gradle"] = Start-Job -ScriptBlock {
            param($url, $dest)
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 180
        } -ArgumentList $gradleUrl, $gradleZip
    }

    $flutterGitFolder = Join-Path $FlutterHome ".git"
    if (-not $ReuseFlutter -and -not (Test-Path $flutterGitFolder) -and $FlutterChannel -ne "fvm") {
        $jobs["Flutter"] = Start-Job -ScriptBlock {
            param($channel, $dest)
            git clone --progress --depth 1 -b $channel "https://github.com/flutter/flutter.git" $dest 2>$null
        } -ArgumentList $FlutterChannel, $FlutterHome
    }

    $jobTargets = @{
        "JDK" = $jdkZip
        "Cmdline" = $cmdlineZip
    }
    if ($jobs.ContainsKey("Gradle")) { $jobTargets["Gradle"] = $gradleZip }
    if ($jobs.ContainsKey("Flutter")) { $jobTargets["Flutter"] = $FlutterHome }

    try {
        # Active progress monitoring loop
        $completedJobs = @{}
        while ($true) {
            $hasRunning = $false
            foreach ($key in $jobs.Keys) {
                $job = $jobs[$key]
                if ($job.State -eq 'Running') {
                    $hasRunning = $true
                } elseif (-not $completedJobs.ContainsKey($key)) {
                    $completedJobs[$key] = $true
                    $sz = Get-TargetSizeMb -Path $jobTargets[$key]
                    if ($job.State -eq 'Completed') {
                        Write-LogSuccess "$key download completed ($sz)."
                    } else {
                        Write-LogError "$key worker failed with state: $($job.State)"
                        Receive-Job -Job $job -Keep | Out-Host
                    }
                }
            }

            if (-not $hasRunning) { break }

            $statusParts = @()
            foreach ($key in $jobs.Keys) {
                $sz = Get-TargetSizeMb -Path $jobTargets[$key]
                if ($jobs[$key].State -eq 'Running') {
                    $statusParts += "$key`: $sz"
                } else {
                    $statusParts += "$key`: Done"
                }
            }
            Write-Progress -Activity "Parallel Toolchain Ingestion" -Status ($statusParts -join " | ")
            Start-Sleep -Milliseconds 800
        }
        Write-Progress -Activity "Parallel Toolchain Ingestion" -Completed

        # Check for any failures
        $failedJobs = $jobs.Values | Where-Object { $_.State -ne 'Completed' }
        if ($failedJobs) {
            Write-LogError "One or more parallel workers failed."
            return
        }

        # Staged extraction and toolchain configuration pipeline
        if ($ReuseJdk) {
            Write-LogSuccess "Using existing JDK: $env:JAVA_HOME"
        } else {
            Write-LogInfo "Configuring Eclipse Temurin OpenJDK $JdkVer..."
            Install-WindowsJDK -TargetVersion $JdkVer -InstallRoot $JdkInstallDir -Architecture $Architecture -PredownloadedArchive $jdkZip
        }

        if ($ReuseAndroid) {
            Write-LogInfo "Verifying packages on existing Android SDK at $SdkRoot..."
            Install-WindowsAndroidSDK -ApiArg $ApiVer -BuildToolsArg $BuildToolsVer -NdkArg $NdkVer -CmakeArg $CmakeVer -SdkRoot $SdkRoot
        } else {
            Write-LogInfo "Configuring Android SDK Command-line Tools and Packages..."
            Install-WindowsAndroidSDK -ApiArg $ApiVer -BuildToolsArg $BuildToolsVer -NdkArg $NdkVer -CmakeArg $CmakeVer -SdkRoot $SdkRoot -PredownloadedArchive $cmdlineZip
        }

        if ($ReuseGradle) {
            Write-LogSuccess "Using existing Gradle"
        } elseif ($jobs.ContainsKey("Gradle")) {
            Write-LogInfo "Configuring Gradle $GradleVer..."
            Install-WindowsGradle -TargetVersion $GradleVer -InstallDir $GradleInstallDir -PredownloadedArchive $gradleZip
        }

        if ($ReuseFlutter) {
            Write-LogInfo "Configuring existing Flutter SDK linkage at $FlutterHome..."
            $flutterBat = Join-Path $FlutterHome "bin\flutter.bat"
            if (Test-Path $flutterBat) {
                & $flutterBat config --android-sdk $SdkRoot 2>$null
                for ($i=0; $i -lt 30; $i++) { "y" } | & $flutterBat doctor --android-licenses 2>$null
            }
            Write-LogSuccess "Existing Flutter SDK linked."
        } else {
            Write-LogInfo "Configuring Flutter SDK ($FlutterChannel)..."
            Install-WindowsFlutter -ChannelArg $FlutterChannel -FlutterRoot $FlutterHome -AndroidSdk $SdkRoot
        }

        $elapsed = [int]((Get-Date) - $startTime).TotalSeconds
        Write-LogSuccess "All toolchain components ingested & configured in ${elapsed}s."
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
