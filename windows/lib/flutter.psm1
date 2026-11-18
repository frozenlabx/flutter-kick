# ==============================================================================
# mobile-toolchain-setup: Windows Flutter Installation Module
# Clones / configures Flutter SDK, FVM, Android integration & license acceptance
# ==============================================================================

Import-Module (Join-Path $PSScriptRoot "ui.psm1") -ErrorAction SilentlyContinue

function Install-WindowsFlutter {
    param (
        [string]$Channel = "stable",
        [string]$FlutterRoot = (Join-Path $env:USERPROFILE "development\flutter"),
        [string]$AndroidSdk = "",
        [bool]$DryRun = $false
    )
    Write-LogStep "Configuring Flutter SDK ($Channel)"

    # --------------------------------------------------------------------------
    # FVM Mode
    # --------------------------------------------------------------------------
    if ($Channel -eq "fvm") {
        Write-LogInfo "Configuring Flutter Version Management (FVM)..."

        if ($DryRun) {
            Write-LogDryRun "Would install/verify FVM CLI (winget install --id LeoAfarias.FVM -e or dart pub)"
            Write-LogDryRun "Would run: fvm install stable && fvm global stable"
            Write-LogDryRun "Would configure: flutter config --android-sdk `"$AndroidSdk`""
            Write-LogDryRun "Would accept licenses: echo y | flutter doctor --android-licenses"
            return @{ FlutterHome = (Join-Path $env:USERPROFILE "fvm\default") }
        }

        # Check FVM
        if (-not (Get-Command fvm -ErrorAction SilentlyContinue)) {
            Write-LogInfo "Installing FVM via winget..."
            try {
                winget install --id LeoAfarias.FVM -e --accept-package-agreements --accept-source-agreements
            }
            catch {
                Write-LogWarn "winget install for FVM failed. Trying dart pub..."
                if (Get-Command dart -ErrorAction SilentlyContinue) {
                    dart pub global activate fvm
                }
            }
        }

        if (Get-Command fvm -ErrorAction SilentlyContinue) {
            Write-LogInfo "Installing and activating stable Flutter via FVM..."
            fvm install stable
            fvm global stable
            $fvmFlutter = Join-Path $env:USERPROFILE "fvm\default\bin"
            $env:Path = $fvmFlutter + ";" + $env:Path
        }

        if (Get-Command flutter -ErrorAction SilentlyContinue) {
            if ($AndroidSdk) {
                flutter config --android-sdk "$AndroidSdk" | Out-Null
            }
            for ($i = 0; $i -lt 30; $i++) { "y" } | flutter doctor --android-licenses 2>$null | Out-Null
            Write-LogSuccess "FVM Flutter environment configured."
        }

        return @{ FlutterHome = (Join-Path $env:USERPROFILE "fvm\default") }
    }

    # --------------------------------------------------------------------------
    # Standard Channel / Git Tag Mode
    # --------------------------------------------------------------------------
    $gitRepoUrl = "https://github.com/flutter/flutter.git"
    $flutterBat = Join-Path $FlutterRoot "bin\flutter.bat"

    if ($DryRun) {
        Write-LogDryRun "Target FLUTTER_HOME: $FlutterRoot"
        if (Test-Path (Join-Path $FlutterRoot ".git")) {
            Write-LogDryRun "Flutter repository already exists at $FlutterRoot. Would switch branch/tag to: $Channel"
        }
        else {
            Write-LogDryRun "Would clone Flutter repository:"
            Write-LogDryRun "  git clone --depth 1 -b $Channel $gitRepoUrl `"$FlutterRoot`""
        }
        Write-LogDryRun "Would prepend $FlutterRoot\bin to PATH"
        Write-LogDryRun "Would execute: flutter precache --android"
        Write-LogDryRun "Would execute: flutter config --android-sdk `"$AndroidSdk`""
        Write-LogDryRun "Would accept licenses: echo y | flutter doctor --android-licenses"
        $env:Path = (Join-Path $FlutterRoot "bin") + ";" + $env:Path
        return @{ FlutterHome = $FlutterRoot }
    }

    # Live Installation
    if (Test-Path (Join-Path $FlutterRoot ".git")) {
        Write-LogInfo "Flutter repository already exists at $FlutterRoot. Checking out $Channel..."
        try {
            git -C $FlutterRoot fetch --tags
            git -C $FlutterRoot checkout $Channel
        }
        catch {
            git -C $FlutterRoot checkout "tags/$Channel"
        }
    }
    else {
        Write-LogInfo "Cloning Flutter SDK ($Channel) into $FlutterRoot..."
        $parentDir = Split-Path -Parent $FlutterRoot
        if (-not (Test-Path $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }

        try {
            git clone --depth 1 -b $Channel $gitRepoUrl $FlutterRoot
        }
        catch {
            Write-LogWarn "Shallow branch clone failed. Attempting full repository clone to resolve channel/tag..."
            git clone $gitRepoUrl $FlutterRoot
            try {
                git -C $FlutterRoot checkout $Channel
            }
            catch {
                git -C $FlutterRoot checkout "tags/$Channel"
            }
        }
    }

    $flutterBin = Join-Path $FlutterRoot "bin"
    $env:Path = $flutterBin + ";" + $env:Path

    if (Test-Path $flutterBat) {
        Write-LogInfo "Pre-caching Android engine artifacts..."
        & $flutterBat precache --android | Out-Null

        if ($AndroidSdk) {
            Write-LogInfo "Associating Android SDK location with Flutter..."
            & $flutterBat config --android-sdk "$AndroidSdk" | Out-Null
        }

        Write-LogInfo "Accepting Flutter Android licenses..."
        try {
            for ($i = 0; $i -lt 30; $i++) { "y" } | & $flutterBat doctor --android-licenses 2>$null | Out-Null
        }
        catch {}

        Write-LogSuccess "Flutter SDK configured successfully."
        $fVer = try { (& $flutterBat --version 2>&1 | Select-Object -First 1) } catch { "" }
        if ($fVer) { Write-LogInfo $fVer }
        return @{ FlutterHome = $FlutterRoot }
    }
    else {
        Write-LogError "flutter.bat not found at $flutterBat."
        return $null
    }
}

Export-ModuleMember -Function Install-WindowsFlutter
