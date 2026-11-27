# ==============================================================================
# mobile-toolchain-setup: Windows Diagnostic Doctor & Tool Detection Library
# Inspects existing installations of JDK, Android SDK, Gradle, and Flutter.
# Provides comprehensive diagnostics, actionable troubleshooting & auto-fixing.
# ==============================================================================

Import-Module (Join-Path $PSScriptRoot "ui.psm1") -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "os_detect.psm1") -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "env.psm1") -ErrorAction SilentlyContinue

function Get-ExistingTools {
    $results = @{
        Jdk = @{
            Valid = $false
            Path = ""
            Version = ""
            Major = 0
        }
        Android = @{
            Valid = $false
            SdkRoot = ""
            HasCmdline = $false
            CmdlinePath = ""
            HasAdb = $false
            AdbPath = ""
            AdbVersion = ""
            Platforms = @()
            BuildTools = @()
            Ndk = @()
            Cmake = @()
            LicensesAccepted = $false
        }
        Gradle = @{
            Valid = $false
            Path = ""
            Version = ""
        }
        Flutter = @{
            Valid = $false
            Path = ""
            Version = ""
            Channel = ""
        }
    }

    # 1. Detect Existing JDK
    $candidateJdkHomes = @()
    if ($env:JAVA_HOME -and (Test-Path $env:JAVA_HOME)) {
        $candidateJdkHomes += $env:JAVA_HOME
    }

    $localJdks = Join-Path $env:USERPROFILE ".local\share\jdks"
    if (Test-Path $localJdks) {
        Get-ChildItem -Path $localJdks -Directory | ForEach-Object { $candidateJdkHomes += $_.FullName }
    }

    $progFiles = @($env:ProgramFiles, ${env:ProgramFiles(x86)})
    foreach ($pf in $progFiles) {
        if ($pf) {
            $adoptium = Join-Path $pf "Eclipse Adoptium"
            if (Test-Path $adoptium) {
                Get-ChildItem -Path $adoptium -Directory | ForEach-Object { $candidateJdkHomes += $_.FullName }
            }
            $javaDir = Join-Path $pf "Java"
            if (Test-Path $javaDir) {
                Get-ChildItem -Path $javaDir -Directory | ForEach-Object { $candidateJdkHomes += $_.FullName }
            }
        }
    }

    foreach ($homeCand in $candidateJdkHomes) {
        $javaExe = Join-Path $homeCand "bin\java.exe"
        if (Test-Path $javaExe) {
            try {
                $verOut = & $javaExe -version 2>&1
                if ($LASTEXITCODE -eq 0 -or $verOut) {
                    $results.Jdk.Valid = $true
                    $results.Jdk.Path = $homeCand
                    $results.Jdk.Version = ($verOut | Select-Object -First 1)
                    if ($verOut -match 'version "(1\.)?([0-9]+)') {
                        $results.Jdk.Major = [int]$matches[2]
                    }
                    break
                }
            } catch {}
        }
    }

    if (-not $results.Jdk.Valid) {
        $cmdJava = Get-Command java.exe -ErrorAction SilentlyContinue
        if ($cmdJava) {
            try {
                $verOut = & $cmdJava.Source -version 2>&1
                $results.Jdk.Valid = $true
                $results.Jdk.Path = (Split-Path (Split-Path $cmdJava.Source -Parent) -Parent)
                $results.Jdk.Version = ($verOut | Select-Object -First 1)
                if ($verOut -match 'version "(1\.)?([0-9]+)') {
                    $results.Jdk.Major = [int]$matches[2]
                }
            } catch {}
        }
    }

    # 2. Detect Existing Android SDK
    $sdkCandidates = @()
    if ($env:ANDROID_HOME -and (Test-Path $env:ANDROID_HOME)) { $sdkCandidates += $env:ANDROID_HOME }
    if ($env:ANDROID_SDK_ROOT -and (Test-Path $env:ANDROID_SDK_ROOT)) { $sdkCandidates += $env:ANDROID_SDK_ROOT }
    $defaultWinSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
    if (Test-Path $defaultWinSdk) { $sdkCandidates += $defaultWinSdk }

    foreach ($sdk in $sdkCandidates) {
        if (Test-Path (Join-Path $sdk "cmdline-tools") -or (Test-Path (Join-Path $sdk "platform-tools")) -or (Test-Path (Join-Path $sdk "platforms"))) {
            $results.Android.Valid = $true
            $results.Android.SdkRoot = $sdk

            $smCandidates = @(
                (Join-Path $sdk "cmdline-tools\latest\bin\sdkmanager.bat"),
                (Join-Path $sdk "cmdline-tools\bin\sdkmanager.bat"),
                (Join-Path $sdk "tools\bin\sdkmanager.bat")
            )
            foreach ($sm in $smCandidates) {
                if (Test-Path $sm) {
                    $results.Android.HasCmdline = $true
                    $results.Android.CmdlinePath = $sm
                    break
                }
            }

            $adbCand = Join-Path $sdk "platform-tools\adb.exe"
            if (Test-Path $adbCand) {
                $results.Android.HasAdb = $true
                $results.Android.AdbPath = $adbCand
                try {
                    $adbVer = & $adbCand --version 2>&1 | Select-Object -First 1
                    $results.Android.AdbVersion = $adbVer
                } catch { $results.Android.AdbVersion = "ready" }
            }

            $platDir = Join-Path $sdk "platforms"
            if (Test-Path $platDir) {
                $results.Android.Platforms = @(Get-ChildItem -Path $platDir -Directory | ForEach-Object { $_.Name })
            }

            $btDir = Join-Path $sdk "build-tools"
            if (Test-Path $btDir) {
                $results.Android.BuildTools = @(Get-ChildItem -Path $btDir -Directory | ForEach-Object { $_.Name })
            }

            $ndkDir = Join-Path $sdk "ndk"
            if (Test-Path $ndkDir) {
                $results.Android.Ndk = @(Get-ChildItem -Path $ndkDir -Directory | ForEach-Object { $_.Name })
            }

            $cmakeDir = Join-Path $sdk "cmake"
            if (Test-Path $cmakeDir) {
                $results.Android.Cmake = @(Get-ChildItem -Path $cmakeDir -Directory | ForEach-Object { $_.Name })
            }

            if (Test-Path (Join-Path $sdk "licenses\android-sdk-license")) {
                $results.Android.LicensesAccepted = $true
            }
            break
        }
    }

    # 3. Detect Existing Gradle
    $gradleCandidates = @()
    if ($env:GRADLE_HOME -and (Test-Path (Join-Path $env:GRADLE_HOME "bin\gradle.bat"))) {
        $gradleCandidates += (Join-Path $env:GRADLE_HOME "bin\gradle.bat")
    }
    $cmdGradle = Get-Command gradle.bat -ErrorAction SilentlyContinue
    if ($cmdGradle) { $gradleCandidates += $cmdGradle.Source }
    $localGradle = Join-Path $env:USERPROFILE ".local\share\gradle"
    if (Test-Path $localGradle) {
        Get-ChildItem -Path $localGradle -Directory | ForEach-Object {
            $bat = Join-Path $_.FullName "bin\gradle.bat"
            if (Test-Path $bat) { $gradleCandidates += $bat }
        }
    }

    foreach ($g in $gradleCandidates) {
        if (Test-Path $g) {
            try {
                $gOut = & $g -v 2>&1
                if ($LASTEXITCODE -eq 0 -or $gOut) {
                    $results.Gradle.Valid = $true
                    $results.Gradle.Path = $g
                    $match = $gOut | Where-Object { $_ -match '^Gradle [0-9]' } | Select-Object -First 1
                    $results.Gradle.Version = if ($match) { $match } else { "ready" }
                    break
                }
            } catch {}
        }
    }

    # 4. Detect Existing Flutter
    $flutterCandidates = @()
    if ($env:FLUTTER_HOME -and (Test-Path (Join-Path $env:FLUTTER_HOME "bin\flutter.bat"))) {
        $flutterCandidates += (Join-Path $env:FLUTTER_HOME "bin\flutter.bat")
    }
    $cmdFlutter = Get-Command flutter.bat -ErrorAction SilentlyContinue
    if ($cmdFlutter) { $flutterCandidates += $cmdFlutter.Source }
    $defFlutter = Join-Path $env:USERPROFILE "development\flutter\bin\flutter.bat"
    if (Test-Path $defFlutter) { $flutterCandidates += $defFlutter }

    foreach ($f in $flutterCandidates) {
        if (Test-Path $f) {
            $fDir = Split-Path (Split-Path $f -Parent) -Parent
            $results.Flutter.Valid = $true
            $results.Flutter.Path = $fDir
            try {
                $fOut = & $f --version 2>&1 | Select-Object -First 1
                $results.Flutter.Version = $fOut
                if ($fOut -match 'channel\s+([^\s]+)') {
                    $results.Flutter.Channel = $matches[1]
                } else {
                    $results.Flutter.Channel = "stable"
                }
            } catch {
                $results.Flutter.Version = "ready"
                $results.Flutter.Channel = "stable"
            }
            break
        }
    }

    return $results
}

function Invoke-Doctor {
    param (
        [switch]$Fix
    )

    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host " Flutter-Kick Windows Toolchain Doctor & Diagnostic Analyzer" -ForegroundColor White
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host ""

    $passed = 0
    $warnings = 0
    $errors = 0
    $issues = @()
    $suggestions = @()

    # 1. OS & Architecture
    Write-Host "[1/6] Operating System & Environment" -ForegroundColor Cyan
    $os = Detect-WindowsOS
    Write-LogSuccess "OS: $($os.OsName) ($($os.Architecture))"
    $passed++

    $freeGb = [math]::Round((Get-PSDrive -Name C -ErrorAction SilentlyContinue).Free / 1GB, 1)
    if ($freeGb -ge 10) {
        Write-LogSuccess "Free Disk Space: $freeGb GB on C: (exceeds 10 GB requirement)"
        $passed++
    } else {
        Write-LogWarn "Free Disk Space: Only $freeGb GB free on C:"
        $warnings++
        $issues += "Low free disk space on drive C: (< 10 GB)."
        $suggestions += "Free up space on your primary drive."
    }

    # 2. Prerequisites
    Write-Host "`n[2/6] Core Prerequisites" -ForegroundColor Cyan
    $gitCmd = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($gitCmd) {
        Write-LogSuccess "Git for Windows: $($gitCmd.Source)"
        $passed++
    } else {
        Write-LogError "Git for Windows not found in PATH."
        $errors++
        $issues += "Git for Windows is missing."
        $suggestions += "Install Git from https://git-scm.com/download/win or 'winget install Git.Git'"
    }

    # Long path check
    try {
        $longPaths = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -ErrorAction SilentlyContinue).LongPathsEnabled
        if ($longPaths -eq 1) {
            Write-LogSuccess "Win32 Long Paths: Enabled"
            $passed++
        } else {
            Write-LogWarn "Win32 Long Paths: Disabled (recommended for deep Android SDK and Gradle paths)"
            $warnings++
            $issues += "Win32 Long Paths is not enabled."
            $suggestions += "Enable via elevated PowerShell: Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1"
        }
    } catch {
        Write-LogSuccess "Win32 Long Paths check complete."
        $passed++
    }

    # Detect Existing Tools
    $tools = Get-ExistingTools

    # 3. Java Development Kit (JDK)
    Write-Host "`n[3/6] Java Development Kit (JDK)" -ForegroundColor Cyan
    if ($tools.Jdk.Valid) {
        Write-LogSuccess "JDK Location: $($tools.Jdk.Path)"
        Write-LogSuccess "Java Version: $($tools.Jdk.Version)"
        $passed += 2

        if ($tools.Jdk.Major -ge 17) {
            Write-LogSuccess "Version Compatibility: Java $($tools.Jdk.Major) meets AGP 8.0+ requirements (>= 17)."
            $passed++
        } else {
            Write-LogWarn "Version Compatibility: Java $($tools.Jdk.Major) is older than recommended (Java 17+ required for AGP 8.0+)."
            $warnings++
            $issues += "Installed Java version ($($tools.Jdk.Major)) is too old."
            $suggestions += "Run '.\install.ps1 -Default' to install Eclipse Temurin OpenJDK 17 LTS."
        }
    } else {
        Write-LogError "Java Development Kit: No working Java Runtime found on system."
        $errors++
        $issues += "JDK is missing or not configured."
        $suggestions += "Run '.\install.ps1 -Default' to install Eclipse Temurin OpenJDK 17."
    }

    # 4. Android SDK
    Write-Host "`n[4/6] Android SDK & Command-Line Tools" -ForegroundColor Cyan
    if ($tools.Android.Valid) {
        Write-LogSuccess "ANDROID_HOME: $($tools.Android.SdkRoot)"
        $passed++

        if ($tools.Android.HasCmdline) {
            Write-LogSuccess "cmdline-tools: sdkmanager ready ($($tools.Android.CmdlinePath))"
            $passed++
        } else {
            Write-LogError "cmdline-tools: sdkmanager.bat missing in $($tools.Android.SdkRoot)\cmdline-tools\latest"
            $errors++
            $issues += "Android cmdline-tools is missing."
            $suggestions += "Run '.\install.ps1' to install canonical cmdline-tools."
        }

        if ($tools.Android.HasAdb) {
            Write-LogSuccess "platform-tools: adb ready ($($tools.Android.AdbVersion))"
            $passed++
        } else {
            Write-LogWarn "platform-tools: adb.exe missing in $($tools.Android.SdkRoot)\platform-tools"
            $warnings++
            $issues += "Android platform-tools (adb) is missing."
            $suggestions += "Install platform-tools via sdkmanager."
        }

        if ($tools.Android.Platforms.Count -gt 0) {
            Write-LogSuccess "Installed Platforms: $($tools.Android.Platforms -join ', ')"
            $passed++
        } else {
            Write-LogWarn "Installed Platforms: No Android platforms found."
            $warnings++
            $issues += "No Android platforms installed."
            $suggestions += "Install Android platform via sdkmanager."
        }

        if ($tools.Android.BuildTools.Count -gt 0) {
            Write-LogSuccess "Installed Build-Tools: $($tools.Android.BuildTools -join ', ')"
            $passed++
        } else {
            Write-LogWarn "Installed Build-Tools: No Android build-tools found."
            $warnings++
            $issues += "No Android build-tools installed."
            $suggestions += "Install build-tools via sdkmanager."
        }

        if ($tools.Android.LicensesAccepted) {
            Write-LogSuccess "Android SDK Licenses: Accepted"
            $passed++
        } else {
            Write-LogWarn "Android SDK Licenses: Not accepted"
            $warnings++
            $issues += "Android SDK licenses are not accepted."
            $suggestions += "Accept licenses via: & `"$($tools.Android.CmdlinePath)`" --licenses"
        }
    } else {
        Write-LogError "Android SDK: No Android SDK installation found."
        $errors++
        $issues += "Android SDK is missing."
        $suggestions += "Run '.\install.ps1 -Default' to install headless Android SDK."
    }

    # 5. Gradle & Flutter
    Write-Host "`n[5/6] Gradle & Flutter SDK" -ForegroundColor Cyan
    if ($tools.Gradle.Valid) {
        Write-LogSuccess "Gradle: $($tools.Gradle.Version) ($($tools.Gradle.Path))"
        $passed++
    } else {
        Write-LogInfo "Gradle: Standalone Gradle not found (wrapper gradlew will still work)."
    }

    if ($tools.Flutter.Valid) {
        Write-LogSuccess "Flutter SDK: $($tools.Flutter.Version) ($($tools.Flutter.Path))"
        $passed++
    } else {
        Write-LogWarn "Flutter SDK: Flutter not found in PATH."
        $warnings++
        $issues += "Flutter SDK is not installed or not in PATH."
        $suggestions += "Run '.\install.ps1 -Default' to install Flutter."
    }

    # 6. User Registry & Environment
    Write-Host "`n[6/6] Windows User Environment & PATH" -ForegroundColor Cyan
    $userEnv = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userEnv -match "flutter" -and $userEnv -match "platform-tools") {
        Write-LogSuccess "User PATH: Contains Flutter and Android platform-tools"
        $passed++
    } else {
        Write-LogWarn "User PATH: Incomplete toolchain entries in User environment."
        $warnings++
        $issues += "User PATH is missing toolchain directories."
        $suggestions += "Run '.\install.ps1' to update User environment variables."
    }

    # Summary
    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host " Doctor Summary: $passed passed, $warnings warning(s), $errors issue(s) found." -ForegroundColor White

    if ($issues.Count -gt 0) {
        Write-Host "`nActionable Recommendations:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $issues.Count; $i++) {
            Write-Host "  [$($i+1)] $($issues[$i])" -ForegroundColor Yellow
            Write-Host "      → Suggestion: $($suggestions[$i])" -ForegroundColor Cyan
        }
    } else {
        Write-Host " All checks passed! Your mobile development toolchain is healthy." -ForegroundColor Green
    }
    Write-Host "========================================================================`n" -ForegroundColor Cyan

    # Auto-Fix
    $canFix = $false
    if ($tools.Android.Valid -and -not $tools.Android.LicensesAccepted -and $tools.Android.CmdlinePath) {
        $canFix = $true
    }
    if ($tools.Flutter.Valid -and $tools.Android.Valid) {
        $canFix = $true
    }

    if ($canFix) {
        $shouldFix = $Fix
        if (-not $shouldFix -and [Environment]::UserInteractive) {
            $shouldFix = Prompt-Confirm "Would you like Flutter-Kick to attempt auto-fixing these issues?" $true
        }

        if ($shouldFix) {
            Write-LogStep "Running Automated Toolchain Fixes"

            if ($tools.Android.Valid -and -not $tools.Android.LicensesAccepted -and $tools.Android.CmdlinePath) {
                Write-LogInfo "Accepting Android SDK licenses..."
                1..30 | ForEach-Object { "y" } | & $tools.Android.CmdlinePath --licenses --sdk_root=$tools.Android.SdkRoot 2>$null
                Write-LogSuccess "Android SDK licenses accepted."
            }

            if ($tools.Flutter.Valid -and $tools.Android.Valid) {
                Write-LogInfo "Linking Android SDK to Flutter..."
                & (Join-Path $tools.Flutter.Path "bin\flutter.bat") config --android-sdk $tools.Android.SdkRoot 2>$null
                1..30 | ForEach-Object { "y" } | & (Join-Path $tools.Flutter.Path "bin\flutter.bat") doctor --android-licenses 2>$null
                Write-LogSuccess "Flutter Android SDK linked."
            }

            Write-LogSuccess "Auto-fix routine complete. Re-run '.\install.ps1 -Doctor' to re-verify."
        }
    }

    if ($errors -gt 0) {
        exit 1
    }
}

Export-ModuleMember -Function Get-ExistingTools, Invoke-Doctor
