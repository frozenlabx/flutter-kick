# ==============================================================================
# mobile-toolchain-setup (flutter-kick)
# Windows Universal Web & Local Installer Bootstrapper
#
# One-liner execution without cloning:
#   irm https://raw.githubusercontent.com/frozenlabx/flutter-kick/main/install.ps1 | iex
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/frozenlabx/flutter-kick/main/install.ps1))) -Default
# ==============================================================================
[CmdletBinding()]
param (
    [switch]$Default,
    [switch]$Doctor,
    [switch]$Fix,
    [switch]$Reinstall,
    [switch]$Fresh,
    [switch]$DryRun,
    [switch]$Uninstall,
    [switch]$Yes,
    [string]$Jdk,
    [string]$Api,
    [string]$BuildTools,
    [string]$Ndk,
    [string]$Cmake,
    [string]$Gradle,
    [string]$Flutter
)

$ErrorActionPreference = "Stop"

# 1. Local checkout check
$localInstall = Join-Path $PSScriptRoot "windows\install.ps1"
if ($PSScriptRoot -and (Test-Path $localInstall)) {
    & $localInstall @PSBoundParameters
    exit $LASTEXITCODE
}

# 2. Remote / Standalone mode: Download repository archive into a secure temp directory
$repoUrl = "https://github.com/frozenlabx/flutter-kick"
$branch = if ($env:FLUTTER_KICK_BRANCH) { $env:FLUTTER_KICK_BRANCH } else { "main" }
$zipUrl = "$repoUrl/archive/refs/heads/$branch.zip"

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host " Flutter-Kick: Headless Android SDK & Flutter Toolchain Bootstrapper" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "[i] Fetching latest toolchain scripts from $repoUrl ($branch)..." -ForegroundColor DarkCyan

$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("flutter-kick-" + [System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
$tmpZip = Join-Path $tmpDir "repo.zip"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $zipUrl -OutFile $tmpZip -UseBasicParsing -TimeoutSec 30
    Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force

    $unzippedFolder = Join-Path $tmpDir "flutter-kick-$branch"
    $scriptToRun = Join-Path $unzippedFolder "windows\install.ps1"

    if (-not (Test-Path $scriptToRun)) {
        # Fallback to any extracted directory
        $dirs = Get-ChildItem -Path $tmpDir -Directory | Where-Object { $_.Name -like "flutter-kick*" }
        if ($dirs.Count -gt 0) {
            $scriptToRun = Join-Path $dirs[0].FullName "windows\install.ps1"
        }
    }

    if (-not (Test-Path $scriptToRun)) {
        throw "Could not locate windows\install.ps1 in extracted archive."
    }

    & $scriptToRun @PSBoundParameters
}
finally {
    Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}
