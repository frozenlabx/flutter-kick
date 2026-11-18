# ==============================================================================
# mobile-toolchain-setup: Windows PowerShell Entrypoint
# Automates headless Android SDK & Flutter development environment setup
# ==============================================================================
[CmdletBinding()]
param (
    [switch]$Default,
    [switch]$DryRun,
    [switch]$Uninstall,
    [switch]$Yes,
    [string]$Jdk = "",
    [string]$Api = "",
    [string]$BuildTools = "",
    [string]$Ndk = "",
    [string]$Cmake = "",
    [string]$Gradle = "",
    [string]$Flutter = "",
    [string]$AndroidHome = "",
    [string]$FlutterHome = "",
    [string]$GradleHome = ""
)

$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot
$projectRoot = Split-Path -Parent $scriptDir
$configDir = Join-Path $projectRoot "config"
$libDir = Join-Path $scriptDir "lib"

# Import PowerShell Modules
Import-Module (Join-Path $libDir "ui.psm1") -Force
Import-Module (Join-Path $libDir "os_detect.psm1") -Force
Import-Module (Join-Path $libDir "env.psm1") -Force
Import-Module (Join-Path $libDir "jdk.psm1") -Force
Import-Module (Join-Path $libDir "android.psm1") -Force
Import-Module (Join-Path $libDir "gradle.psm1") -Force
Import-Module (Join-Path $libDir "flutter.psm1") -Force

# Read single source of truth defaults
$defaultsPath = Join-Path $configDir "defaults.env"
$cfg = Get-DefaultsConfig -ConfigPath $defaultsPath

if ($PSBoundParameters['Verbose']) {
    $global:IsVerboseMode = $true
}

# ------------------------------------------------------------------------------
# Initialize UI and Logging
# ------------------------------------------------------------------------------
Init-Logging
Show-Banner

# ------------------------------------------------------------------------------
# Step 1: Detect Operating System & Architecture
# ------------------------------------------------------------------------------
Write-LogStep "1" "7" "Detecting Host Operating System & Shell"
$osInfo = Detect-WindowsOS

# Resolve platform default paths
$resolvedAndroidHome = if ($AndroidHome) { $AndroidHome } else { Join-Path $env:USERPROFILE "AppData\Local\Android\Sdk" }
$resolvedFlutterHome = if ($FlutterHome) { $FlutterHome } else { Join-Path $env:USERPROFILE "development\flutter" }
$resolvedGradleDir = Join-Path $env:USERPROFILE ".local\share\gradle"
$resolvedJdkDir = Join-Path $env:USERPROFILE ".local\share\jdks"

# ------------------------------------------------------------------------------
# Handle Uninstallation Routine
# ------------------------------------------------------------------------------
if ($Uninstall) {
    Remove-ToolchainEnvironment `
        -AndroidHome $resolvedAndroidHome `
        -FlutterHome $resolvedFlutterHome `
        -AutoConfirm $Yes `
        -DryRun $DryRun
    exit 0
}

# ------------------------------------------------------------------------------
# Step 2: Pre-Flight Disk Space & Prerequisites Check
# ------------------------------------------------------------------------------
Write-LogStep "2" "7" "Pre-Flight Checks"
$diskSpaceSufficient = Test-DiskSpace -TargetPath $env:USERPROFILE -MinGB ([int]$cfg['MIN_DISK_SPACE_GB'])
if (-not $diskSpaceSufficient -and -not $DryRun -and -not $Yes -and [Environment]::UserInteractive) {
    if (-not (Prompt-Confirm "Free disk space is lower than recommended. Continue anyway?" $false)) {
        Write-LogError "Installation cancelled due to low disk space."
        exit 1
    }
}

# ------------------------------------------------------------------------------
# Mode Selection & Configuration Gathering
# ------------------------------------------------------------------------------
$hasCliOverrides = ($Jdk -or $Api -or $BuildTools -or $Ndk -or $Cmake -or $Gradle -or $Flutter)
$mode = ""

if ($hasCliOverrides) {
    # Non-interactive CLI flags mode
    $mode = "2"
    $cfgJdk = if ($Jdk) { $Jdk } else { $cfg['JDK_VERSION'] }
    $cfgApi = if ($Api) { $Api } else { $cfg['ANDROID_API'] }
    $cfgBuildTools = if ($BuildTools) { $BuildTools } else { $cfg['BUILD_TOOLS_VERSION'] }
    $cfgNdk = if ($Ndk) { $Ndk } else { $cfg['NDK_VERSION'] }
    $cfgCmake = if ($Cmake) { $Cmake } else { $cfg['CMAKE_VERSION'] }
    $cfgGradle = if ($Gradle) { $Gradle } else { $cfg['GRADLE_VERSION'] }
    $cfgFlutter = if ($Flutter) { $Flutter } else { $cfg['FLUTTER_CHANNEL'] }
}
elseif ($Default) {
    $mode = "1"
    Write-LogInfo "Applying Recommended LTS default configurations."
    $cfgJdk = $cfg['JDK_VERSION']
    $cfgApi = $cfg['ANDROID_API']
    $cfgBuildTools = $cfg['BUILD_TOOLS_VERSION']
    $cfgNdk = $cfg['NDK_VERSION']
    $cfgCmake = $cfg['CMAKE_VERSION']
    $cfgGradle = $cfg['GRADLE_VERSION']
    $cfgFlutter = $cfg['FLUTTER_CHANNEL']
}
else {
    if ([Environment]::UserInteractive) {
        $mode = Prompt-ModeSelection -Config $cfg
    }
    else {
        Write-LogInfo "Non-interactive environment detected. Using Recommended (Default) mode."
        $mode = "1"
    }

    if ($mode -eq "1") {
        Write-LogInfo "Applying Recommended LTS default configurations."
        $cfgJdk = $cfg['JDK_VERSION']
        $cfgApi = $cfg['ANDROID_API']
        $cfgBuildTools = $cfg['BUILD_TOOLS_VERSION']
        $cfgNdk = $cfg['NDK_VERSION']
        $cfgCmake = $cfg['CMAKE_VERSION']
        $cfgGradle = $cfg['GRADLE_VERSION']
        $cfgFlutter = $cfg['FLUTTER_CHANNEL']
    }
    else {
        Write-Host "`n--- Custom Configuration ---" -ForegroundColor Cyan
        Write-Host "Press [Enter] to accept the bracketed default values.`n" -ForegroundColor DarkGray

        $cfgJdk = Prompt-WithDefault "JDK Version (17/21)" $cfg['JDK_VERSION']
        $cfgApi = Prompt-WithDefault "Android API Level" $cfg['ANDROID_API']
        $cfgBuildTools = Prompt-WithDefault "Android Build-Tools" $cfg['BUILD_TOOLS_VERSION']
        $cfgNdk = Prompt-WithDefault "Android NDK Version (version or 'skip')" $cfg['NDK_VERSION']
        $cfgCmake = Prompt-WithDefault "CMake Version (version or 'skip')" $cfg['CMAKE_VERSION']
        $cfgGradle = Prompt-WithDefault "Gradle Version (version or 'skip')" $cfg['GRADLE_VERSION']
        $cfgFlutter = Prompt-WithDefault "Flutter Channel/Tag or 'fvm'" $cfg['FLUTTER_CHANNEL']
    }
}

$resolvedJavaHome = Join-Path $resolvedJdkDir "temurin-$cfgJdk"
$resolvedGradleHome = if ($cfgGradle -ne "skip") { Join-Path $resolvedGradleDir "gradle-$cfgGradle" } else { Join-Path $env:USERPROFILE ".gradle" }

# ------------------------------------------------------------------------------
# Summary and User Confirmation
# ------------------------------------------------------------------------------
Show-SummaryBox `
    -OSName $osInfo.OSName `
    -Arch $osInfo.Architecture `
    -JdkVer $cfgJdk `
    -ApiVer $cfgApi `
    -BuildToolsVer $cfgBuildTools `
    -NdkVer $cfgNdk `
    -CmakeVer $cfgCmake `
    -GradleVer $cfgGradle `
    -FlutterVer $cfgFlutter `
    -DryRun $DryRun

if (-not $DryRun -and -not $Yes -and [Environment]::UserInteractive) {
    if (-not (Prompt-Confirm "Proceed with toolchain installation?" $true)) {
        Write-LogWarn "Installation cancelled by user."
        exit 0
    }
}

# ------------------------------------------------------------------------------
# Step 3: Base System Prerequisites
# ------------------------------------------------------------------------------
Write-LogStep "3" "7" "Installing Base Prerequisites"
$gitOk = Ensure-Prerequisites -DryRun $DryRun
if (-not $gitOk -and -not $DryRun) {
    exit 1
}

# ------------------------------------------------------------------------------
# Step 4: Installing Toolchain Components
# ------------------------------------------------------------------------------
Write-LogStep "4" "7" "Installing Toolchain Components"

# JDK
$jdkResult = Install-WindowsJDK `
    -TargetVersion $cfgJdk `
    -InstallRoot $resolvedJdkDir `
    -Architecture $osInfo.Architecture `
    -DryRun $DryRun

if ($jdkResult -and $jdkResult.JavaHome) {
    $resolvedJavaHome = $jdkResult.JavaHome
}

# Android SDK
$androidResult = Install-WindowsAndroidSDK `
    -ApiArg $cfgApi `
    -BuildToolsArg $cfgBuildTools `
    -NdkArg $cfgNdk `
    -CmakeArg $cfgCmake `
    -SdkRoot $resolvedAndroidHome `
    -FallbackCmdlineUrl $cfg['CMDLINE_TOOLS_URL_WIN'] `
    -DryRun $DryRun

# Gradle
$gradleResult = Install-WindowsGradle `
    -TargetVersion $cfgGradle `
    -InstallDir $resolvedGradleDir `
    -DryRun $DryRun

if ($gradleResult -and $gradleResult.GradleHome) {
    $resolvedGradleHome = $gradleResult.GradleHome
}

# Flutter
$flutterResult = Install-WindowsFlutter `
    -Channel $cfgFlutter `
    -FlutterRoot $resolvedFlutterHome `
    -AndroidSdk $resolvedAndroidHome `
    -DryRun $DryRun

if ($flutterResult -and $flutterResult.FlutterHome) {
    $resolvedFlutterHome = $flutterResult.FlutterHome
}

# ------------------------------------------------------------------------------
# Step 5: Environment and PATH Configuration
# ------------------------------------------------------------------------------
Write-LogStep "5" "7" "Configuring Windows Environment Variables and User PATH"
Set-ToolchainEnvironment `
    -JavaHome $resolvedJavaHome `
    -AndroidHome $resolvedAndroidHome `
    -GradleHome $resolvedGradleHome `
    -FlutterHome $resolvedFlutterHome `
    -BuildToolsVer $cfgBuildTools `
    -DryRun $DryRun

# ------------------------------------------------------------------------------
# Step 6: Post-Installation Verification
# ------------------------------------------------------------------------------
Write-LogStep "6" "7" "Post-Installation Verification"

if ($DryRun) {
    Write-LogDryRun "Verification: Would execute 'java -version'"
    Write-LogDryRun "Verification: Would execute 'gradle -v'"
    Write-LogDryRun "Verification: Would execute 'adb --version'"
    Write-LogDryRun "Verification: Would execute 'flutter doctor -v'"
}
else {
    Write-Host "`n--- Toolchain Verification Summary ---" -ForegroundColor Cyan

    # Ensure PATH contains freshly installed components in current session
    $env:Path = "$resolvedJavaHome\bin;" + `
                "$resolvedAndroidHome\cmdline-tools\latest\bin;" + `
                "$resolvedAndroidHome\platform-tools;" + `
                "$resolvedAndroidHome\build-tools\$cfgBuildTools;" + `
                "$resolvedGradleHome\bin;" + `
                "$resolvedFlutterHome\bin;" + `
                $env:Path

    # 1. Java check
    if (Get-Command java -ErrorAction SilentlyContinue) {
        $jVer = try { (java -version 2>&1 | Select-Object -First 1) } catch { "Java detected" }
        Write-LogSuccess "Java: $jVer"
    }
    else {
        Write-LogWarn "java.exe not found in session PATH."
    }

    # 2. Gradle check
    if ($cfgGradle -ne "skip") {
        if (Get-Command gradle -ErrorAction SilentlyContinue) {
            $gVer = try { (gradle -v 2>&1 | Where-Object { $_ -match "^Gradle [0-9]" } | Select-Object -First 1) } catch { "Gradle detected" }
            Write-LogSuccess "Gradle: $gVer"
        }
        else {
            Write-LogWarn "gradle.bat not found in session PATH."
        }
    }

    # 3. Android adb check
    if (Get-Command adb -ErrorAction SilentlyContinue) {
        $adbVer = try { (adb --version 2>&1 | Select-Object -First 1) } catch { "adb detected" }
        Write-LogSuccess "Android Platform Tools: $adbVer"
    }
    else {
        Write-LogWarn "adb.exe not found in session PATH."
    }

    # 4. Flutter Doctor check
    if (Get-Command flutter -ErrorAction SilentlyContinue) {
        Write-LogInfo "Running Flutter diagnostic (flutter doctor -v)..."
        try {
            flutter doctor -v
            Write-LogSuccess "Flutter Doctor check complete."
        }
        catch {
            Write-LogWarn "flutter doctor encountered warnings."
        }
    }
    else {
        Write-LogWarn "flutter.bat not found in session PATH."
    }
}

# ------------------------------------------------------------------------------
# Step 7: Completion and Next Steps
# ------------------------------------------------------------------------------
Write-LogStep "7" "7" "Installation Completed"

if ($DryRun) {
    Write-LogSuccess "Dry run simulation finished successfully! No changes were made."
}
else {
    Write-LogSuccess "Mobile toolchain setup finished successfully!"
    Write-Host "`nNext Steps:" -ForegroundColor White
    Write-Host "  1. Restart your PowerShell console or Windows Terminal to reload your User PATH." -ForegroundColor Cyan
    Write-Host "  2. Verify your setup by running:" -ForegroundColor White
    Write-Host "     flutter doctor -v" -ForegroundColor Cyan
    Write-Host "     java -version" -ForegroundColor Cyan
    Write-Host "     sdkmanager --list_installed`n" -ForegroundColor Cyan
}
