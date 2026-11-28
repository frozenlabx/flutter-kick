# ==============================================================================
# mobile-toolchain-setup: Windows PowerShell UI & Logging Module
# Provides ANSI formatting, status badges, log rotation, and interactive menus
# ==============================================================================

$global:LogFilePath = Join-Path $env:USERPROFILE ".mobile-toolchain-setup.log"
$global:LogFileWritable = $false
$global:IsVerboseMode = $false

function Initialize-Logging {
    param (
        [string]$Path = $global:LogFilePath
    )
    $global:LogFilePath = $Path
    try {
        $parent = Split-Path -Parent $global:LogFilePath
        if ($parent -and -not (Test-Path $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Add-Content -Path $global:LogFilePath -Value "`n=== Session Started: $timestamp ===" -ErrorAction Stop
        $global:LogFileWritable = $true
    }
    catch {
        $global:LogFileWritable = $false
    }
}
Set-Alias -Name Init-Logging -Value Initialize-Logging -Scope Global

function Write-LogMessage {
    param (
        [string]$Level,
        [string]$Message
    )
    if ($global:LogFileWritable) {
        try {
            $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            $cleanMsg = $Message -replace "`e\[[0-9;]*[a-zA-Z]", ""
            $line = "[$timestamp] [{0,-7}] $cleanMsg" -f $Level
            Add-Content -Path $global:LogFilePath -Value $line -ErrorAction SilentlyContinue
        }
        catch {}
    }
}

function Write-LogInfo {
    param ([string]$Message)
    Write-Host "[i] " -ForegroundColor Cyan -NoNewline
    Write-Host $Message
    Write-LogMessage "INFO" $Message
}

function Write-LogSuccess {
    param ([string]$Message)
    Write-Host "[✓] " -ForegroundColor Green -NoNewline
    Write-Host $Message
    Write-LogMessage "SUCCESS" $Message
}

function Write-LogWarn {
    param ([string]$Message)
    Write-Host "[!] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
    Write-LogMessage "WARN" $Message
}

function Write-LogError {
    param ([string]$Message)
    Write-Host "[✗] " -ForegroundColor Red -NoNewline
    Write-Host $Message
    Write-LogMessage "ERROR" $Message
}

function Write-LogStep {
    param (
        [string]$StepNum,
        [string]$TotalSteps,
        [string]$Message
    )
    Write-Host ""
    if ($TotalSteps) {
        Write-Host "[$StepNum/$TotalSteps] " -ForegroundColor Blue -NoNewline
        Write-Host $Message -ForegroundColor White
        Write-LogMessage "STEP" "[$StepNum/$TotalSteps] $Message"
    }
    else {
        Write-Host "[→] " -ForegroundColor Blue -NoNewline
        Write-Host $StepNum -ForegroundColor White
        Write-LogMessage "STEP" $StepNum
    }
}

function Write-LogDebug {
    param ([string]$Message)
    Write-LogMessage "DEBUG" $Message
    if ($global:IsVerboseMode) {
        Write-Host "[D] $Message" -ForegroundColor DarkGray
    }
}

function Write-LogDryRun {
    param ([string]$Message)
    Write-Host "[DRY-RUN] " -ForegroundColor Magenta -NoNewline
    Write-Host $Message -ForegroundColor Magenta
    Write-LogMessage "DRY-RUN" $Message
}

function Show-Banner {
    $banner = @"
================================================================================
  _____ _       _   _              _  ___      _    
 |  ___| |_   _| |_| |_ ___ _ __  | |/ (_) ___| | __
 | |_  | | | | | __| __/ _ \ '__| | ' /| |/ __| |/ /
 |  _| | | |_| | |_| ||  __/ |    | . \| | (__|   < 
 |_|   |_|\__,_|\__|\__\___|_|    |_|\_\_|\___|_|\_\
================================================================================
"@
    Write-Host $banner -ForegroundColor Cyan
    Write-Host " * Headless Flutter & Android SDK Environment Manager (Windows)" -ForegroundColor DarkGray
    if ($global:LogFileWritable) {
        Write-Host " * Log: $global:LogFilePath" -ForegroundColor DarkGray
    }
    Write-Host "================================================================================`n" -ForegroundColor Cyan
}

function Show-ToolchainOverview {
    param (
        [string]$OSName,
        [string]$Arch,
        [hashtable]$Existing,
        [hashtable]$Config
    )
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " Target System: $OSName ($Arch)  |  Environment: Windows Registry" -ForegroundColor White
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " Existing Toolchain Status:" -ForegroundColor White

    if ($Existing.Jdk.Valid) {
        Write-Host "   [✓] Java JDK       : " -ForegroundColor Green -NoNewline
        Write-Host "$($Existing.Jdk.Version) " -NoNewline
        Write-Host "(Reusing)" -ForegroundColor DarkGray
    } else {
        Write-Host "   [○] Java JDK       : " -ForegroundColor Cyan -NoNewline
        Write-Host "Not found " -NoNewline
        Write-Host "(Will install Eclipse Temurin $($Config['JDK_VERSION']))" -ForegroundColor DarkGray
    }

    if ($Existing.Android.Valid) {
        Write-Host "   [✓] Android SDK    : " -ForegroundColor Green -NoNewline
        Write-Host "$($Existing.Android.SdkRoot) " -NoNewline
        Write-Host "(Reusing)" -ForegroundColor DarkGray
    } else {
        Write-Host "   [○] Android SDK    : " -ForegroundColor Cyan -NoNewline
        Write-Host "Not found " -NoNewline
        Write-Host "(Will install cmdline-tools & API $($Config['ANDROID_API']))" -ForegroundColor DarkGray
    }

    if ($Existing.Gradle.Valid) {
        Write-Host "   [✓] Gradle         : " -ForegroundColor Green -NoNewline
        Write-Host "$($Existing.Gradle.Version) " -NoNewline
        Write-Host "(Reusing)" -ForegroundColor DarkGray
    } else {
        Write-Host "   [○] Gradle         : " -ForegroundColor Cyan -NoNewline
        Write-Host "Not installed " -NoNewline
        Write-Host "(Projects with 'gradlew.bat' don't require this)" -ForegroundColor DarkGray
    }

    if ($Existing.Flutter.Valid) {
        Write-Host "   [✓] Flutter SDK    : " -ForegroundColor Green -NoNewline
        Write-Host "$($Existing.Flutter.Version) " -NoNewline
        Write-Host "(Reusing)" -ForegroundColor DarkGray
    } else {
        Write-Host "   [○] Flutter SDK    : " -ForegroundColor Cyan -NoNewline
        Write-Host "Not found " -NoNewline
        Write-Host "(Will install $($Config['FLUTTER_CHANNEL']) channel)" -ForegroundColor DarkGray
    }
    Write-Host "--------------------------------------------------------------------------------`n" -ForegroundColor DarkCyan
}

function Read-PromptWithDefault {
    param (
        [string]$Label,
        [string]$DefaultValue
    )
    Write-Host "  ? " -ForegroundColor Cyan -NoNewline
    Write-Host "$Label " -NoNewline
    Write-Host "[$DefaultValue]" -ForegroundColor White -NoNewline
    Write-Host ": " -NoNewline

    $inputVal = Read-Host
    if ([string]::IsNullOrWhiteSpace($inputVal)) {
        return $DefaultValue
    }
    return $inputVal.Trim()
}
Set-Alias -Name Prompt-WithDefault -Value Read-PromptWithDefault -Scope Global

function Read-PromptConfirm {
    param (
        [string]$Label,
        [bool]$DefaultIsYes = $true
    )
    $suffix = if ($DefaultIsYes) { "[Y/n]" } else { "[y/N]" }
    Write-Host "  ? " -ForegroundColor Yellow -NoNewline
    Write-Host "$Label ${suffix}: " -NoNewline

    $ans = Read-Host
    if ([string]::IsNullOrWhiteSpace($ans)) {
        return $DefaultIsYes
    }
    $ans = $ans.Trim().ToLower()
    return ($ans -eq "y" -or $ans -eq "yes")
}
Set-Alias -Name Prompt-Confirm -Value Read-PromptConfirm -Scope Global

function Read-PromptModeSelection {
    param (
        [hashtable]$Config
    )
    Write-Host "What would you like to do?`n" -ForegroundColor White
    Write-Host "  [1] Quick Setup (Recommended)  - Setup Flutter & Android toolchain automatically" -ForegroundColor Green
    Write-Host "                                    (Reuses existing tools; installs only missing components)" -ForegroundColor DarkGray
    Write-Host "  [2] Custom Setup               - Choose custom JDK, Android API, NDK, CMake, Flutter" -ForegroundColor Cyan
    Write-Host "  [3] Run Doctor / Troubleshoot  - Analyze setup health, accept licenses & repair issues" -ForegroundColor Yellow
    Write-Host "  [4] Clean Uninstall            - Revert environment changes and remove managed SDKs" -ForegroundColor Red
    Write-Host "  [q] Exit`n" -ForegroundColor DarkGray

    Write-Host "  ? " -ForegroundColor Cyan -NoNewline
    Write-Host "Enter choice " -NoNewline
    Write-Host "[1]" -ForegroundColor White -NoNewline
    Write-Host ": " -NoNewline

    $choice = Read-Host
    if ([string]::IsNullOrWhiteSpace($choice)) {
        return "1"
    }
    $c = $choice.Trim().ToLower()
    if ($c -eq "2") {
        return "2"
    } elseif ($c -eq "3" -or $c -eq "doctor" -or $c -eq "d") {
        return "doctor"
    } elseif ($c -eq "4" -or $c -eq "uninstall" -or $c -eq "u") {
        return "uninstall"
    } elseif ($c -eq "q" -or $c -eq "quit" -or $c -eq "exit") {
        Write-Host "`nExiting Flutter-Kick."
        exit 0
    }
    return "1"
}
Set-Alias -Name Prompt-ModeSelection -Value Read-PromptModeSelection -Scope Global

function Show-SummaryBox {
    param (
        [string]$OSName,
        [string]$Arch,
        [string]$JdkVer,
        [string]$ApiVer,
        [string]$BuildToolsVer,
        [string]$NdkVer,
        [string]$CmakeVer,
        [string]$GradleVer,
        [string]$FlutterVer,
        [bool]$DryRun
    )
    Write-Host "`n--------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "Configuration Summary:" -ForegroundColor White
    Write-Host ("  {0,-22} : {1} ({2})" -f "Target OS / Arch", $OSName, $Arch)
    Write-Host ("  {0,-22} : User Registry Environment & User Path" -f "Environment Target")
    Write-Host ("  {0,-22} : {1}" -f "JDK Version", $JdkVer)
    Write-Host ("  {0,-22} : API {1} (Build-Tools: {2})" -f "Android SDK", $ApiVer, $BuildToolsVer)
    Write-Host ("  {0,-22} : {1}" -f "Android NDK", $NdkVer)
    Write-Host ("  {0,-22} : {1}" -f "CMake", $CmakeVer)
    Write-Host ("  {0,-22} : {1}" -f "Gradle", $GradleVer)
    Write-Host ("  {0,-22} : {1}" -f "Flutter Channel/SDK", $FlutterVer)
    if ($DryRun) {
        Write-Host "  Dry-Run Mode           : " -NoNewline
        Write-Host "YES (Simulation only, no files modified)" -ForegroundColor Magenta
    }
    else {
        Write-Host "  Dry-Run Mode           : " -NoNewline
        Write-Host "NO (Live installation)" -ForegroundColor Green
    }
    Write-Host "--------------------------------------------------------------------------------`n" -ForegroundColor DarkGray
}

function Get-DefaultsConfig {
    param (
        [string]$ConfigPath
    )
    $config = @{}
    if (Test-Path $ConfigPath) {
        $lines = Get-Content -Path $ConfigPath
        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            if ($trimmed -and -not $trimmed.StartsWith("#")) {
                if ($trimmed -match '^([A-Za-z0-9_]+)\s*=\s*["'']?(.*?)["'']?\s*(?:#.*)?$') {
                    $key = $matches[1]
                    $val = $matches[2]
                    $config[$key] = $val
                }
            }
        }
    }
    return $config
}

Export-ModuleMember -Function `
    Initialize-Logging, `
    Init-Logging, `
    Write-LogInfo, `
    Write-LogSuccess, `
    Write-LogWarn, `
    Write-LogError, `
    Write-LogStep, `
    Write-LogDebug, `
    Write-LogDryRun, `
    Show-Banner, `
    Show-ToolchainOverview, `
    Read-PromptWithDefault, `
    Prompt-WithDefault, `
    Read-PromptConfirm, `
    Prompt-Confirm, `
    Read-PromptModeSelection, `
    Prompt-ModeSelection, `
    Show-SummaryBox, `
    Get-DefaultsConfig -Alias Init-Logging, Prompt-WithDefault, Prompt-Confirm, Prompt-ModeSelection
