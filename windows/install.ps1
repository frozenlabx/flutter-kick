# ==============================================================================
# mobile-toolchain-setup: Windows PowerShell Entrypoint
# Automates headless Android SDK & Flutter development environment setup
# ==============================================================================
[CmdletBinding()]
param (
    [switch]$Default,
    [switch]$Parallel,
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
Import-Module (Join-Path $libDir "parallel.psm1") -Force

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
        Write-Host "Select or enter your preferred versions below." -ForegroundColor DarkGray
        Write-Host "Press [Enter] to accept the bracketed default values.`n" -ForegroundColor DarkGray

        # 1. JDK
        Write-Host "  • Java Development Kit (JDK):" -ForegroundColor White
        Write-Host "    Options: 17 (LTS, Recommended for AGP 8 & Flutter), 21 (LTS)" -ForegroundColor DarkGray
        $cfgJdk = Prompt-WithDefault "JDK Version (17/21)" $cfg['JDK_VERSION']

        # 2. Android API
        Write-Host "`n  • Android SDK Platform API:" -ForegroundColor White
        Write-Host "    Common: 36 (Android 16), 35 (Android 15), 34 (Android 14), 33 (Android 13)" -ForegroundColor DarkGray
        Write-Host "    Tip: You can specify multiple APIs separated by commas (e.g. 34,35,36)" -ForegroundColor DarkGray
        $cfgApi = Prompt-WithDefault "Android API Level" $cfg['ANDROID_API']

        # 3. Android Build-Tools
        Write-Host "`n  • Android SDK Build-Tools:" -ForegroundColor White
        Write-Host "    Common: 36.0.0 (pairs with API 36), 35.0.0, 34.0.0" -ForegroundColor DarkGray
        $cfgBuildTools = Prompt-WithDefault "Android Build-Tools" $cfg['BUILD_TOOLS_VERSION']

        # 4. Android NDK
        Write-Host "`n  • Android NDK (Native Development Kit):" -ForegroundColor White
        Write-Host "    Common: 28.0 (r28 LTS), 27.2 (r27c LTS), 26.3 (r26d), 25.2, or 'skip'" -ForegroundColor DarkGray
        Write-Host "    Tip: Partial versions like '28.0' auto-resolve to full revisions" -ForegroundColor DarkGray
        $cfgNdk = Prompt-WithDefault "Android NDK Version (version or 'skip')" $cfg['NDK_VERSION']

        # 5. CMake
        Write-Host "`n  • CMake (Native build tool):" -ForegroundColor White
        Write-Host "    Common: 3.22.1 (Recommended for Android Gradle Plugin), 3.28.0, or 'skip'" -ForegroundColor DarkGray
        $cfgCmake = Prompt-WithDefault "CMake Version (version or 'skip')" $cfg['CMAKE_VERSION']

        # 6. Gradle
        Write-Host "`n  • Gradle Build Tool:" -ForegroundColor White
        Write-Host "    Common: 8.11.1 (Current Stable), 8.10.2, 8.9, 8.7, or 'skip'" -ForegroundColor DarkGray
        $cfgGradle = Prompt-WithDefault "Gradle Version (version or 'skip')" $cfg['GRADLE_VERSION']

        # 7. Flutter
        Write-Host "`n  • Flutter SDK Channel / Version Management:" -ForegroundColor White
        Write-Host "    Options: stable (Recommended), beta, master, git tag (e.g. 3.27.0), or 'fvm'" -ForegroundColor DarkGray
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

Invoke-WindowsParallelIngestion `
    -JdkVer $cfgJdk `
    -ApiVer $cfgApi `
    -BuildToolsVer $cfgBuildTools `
    -NdkVer $cfgNdk `
    -CmakeVer $cfgCmake `
    -GradleVer $cfgGradle `
    -FlutterChannel $cfgFlutter `
    -JdkInstallDir $resolvedJdkDir `
    -SdkRoot $resolvedAndroidHome `
    -GradleInstallDir $resolvedGradleDir `
    -FlutterHome $resolvedFlutterHome `
    -Architecture $osInfo.Architecture `
    -FallbackCmdlineUrl $cfg['CMDLINE_TOOLS_URL_WIN'] `
    -DryRun $DryRun

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
