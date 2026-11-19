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
 __  __       _     _ _        _____           _      _           _     
|  \/  |     | |   (_) |      |_   _|         | |    | |         (_)    
| \  / | ___ | |__  _| | ___    | | ___   ___ | | ___| |__   __ _ _ _ __
| |\/| |/ _ \| '_ \| | |/ _ \   | |/ _ \ / _ \| |/ __| '_ \ / _` | | '_ \
| |  | | (_) | |_) | | |  __/   | | (_) | (_) | | (__| | | | (_| | | | | |
|_|  |_|\___/|_.__/|_|_|\___|   \_/\___/ \___/|_|\___|_| |_|\__,_|_|_| |_|
================================================================================
"@
    Write-Host $banner -ForegroundColor Cyan
    Write-Host " * Headless Android SDK & Flutter Toolchain Automation (Windows)" -ForegroundColor DarkGray
    if ($global:LogFileWritable) {
        Write-Host " * Log: $global:LogFilePath" -ForegroundColor DarkGray
    }
    Write-Host "================================================================================`n" -ForegroundColor Cyan
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
    Write-Host "Select Installation Mode:" -ForegroundColor White
    Write-Host "  [1] Recommended (Default)  - Quick setup with verified LTS toolchain" -ForegroundColor Green
    Write-Host "                                (JDK $($Config['JDK_VERSION']), Android API $($Config['ANDROID_API']), Build-Tools $($Config['BUILD_TOOLS_VERSION']), Flutter $($Config['FLUTTER_CHANNEL']))" -ForegroundColor DarkGray
    Write-Host "  [2] Custom Setup           - Configure JDK, Android APIs, NDK, CMake, Gradle, Flutter`n" -ForegroundColor Cyan

    Write-Host "  ? " -ForegroundColor Cyan -NoNewline
    Write-Host "Enter choice " -NoNewline
    Write-Host "[1]" -ForegroundColor White -NoNewline
    Write-Host ": " -NoNewline

    $choice = Read-Host
    if ([string]::IsNullOrWhiteSpace($choice) -or $choice.Trim() -ne "2") {
        return "1"
    }
    return "2"
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
    Read-PromptWithDefault, `
    Prompt-WithDefault, `
    Read-PromptConfirm, `
    Prompt-Confirm, `
    Read-PromptModeSelection, `
    Prompt-ModeSelection, `
    Show-SummaryBox, `
    Get-DefaultsConfig -Alias Init-Logging, Prompt-WithDefault, Prompt-Confirm, Prompt-ModeSelection
