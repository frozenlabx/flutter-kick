# ==============================================================================
# mobile-toolchain-setup: Windows Environment & Registry Module
# Idempotently configures User environment variables and Path via .NET API
# ==============================================================================

Import-Module (Join-Path $PSScriptRoot "ui.psm1") -ErrorAction SilentlyContinue

function Set-ToolchainEnvironment {
    param (
        [string]$JavaHome,
        [string]$AndroidHome,
        [string]$GradleHome,
        [string]$FlutterHome,
        [string]$BuildToolsVer,
        [bool]$DryRun = $false
    )
    Write-LogStep "Configuring Windows Environment Variables and User PATH"

    $toolchainPaths = @(
        (Join-Path $JavaHome "bin"),
        (Join-Path $AndroidHome "cmdline-tools\latest\bin"),
        (Join-Path $AndroidHome "platform-tools"),
        (Join-Path $AndroidHome "emulator"),
        (Join-Path $AndroidHome "build-tools\$BuildToolsVer"),
        (Join-Path $GradleHome "bin"),
        (Join-Path $FlutterHome "bin")
    )

    if ($DryRun) {
        Write-LogDryRun "Would set User Environment Variable: JAVA_HOME = $JavaHome"
        Write-LogDryRun "Would set User Environment Variable: ANDROID_HOME = $AndroidHome"
        Write-LogDryRun "Would set User Environment Variable: ANDROID_SDK_ROOT = $AndroidHome"
        Write-LogDryRun "Would set User Environment Variable: GRADLE_HOME = $GradleHome"
        Write-LogDryRun "Would prepend the following paths to User PATH:"
        foreach ($p in $toolchainPaths) {
            Write-LogDryRun "  + $p"
        }

        # Update process environment for dry-run simulation checks
        $env:JAVA_HOME = $JavaHome
        $env:ANDROID_HOME = $AndroidHome
        $env:ANDROID_SDK_ROOT = $AndroidHome
        $env:GRADLE_HOME = $GradleHome
        $env:Path = ($toolchainPaths -join ";") + ";" + $env:Path
        return
    }

    # Set User-level environment variables
    [System.Environment]::SetEnvironmentVariable("JAVA_HOME", $JavaHome, "User")
    [System.Environment]::SetEnvironmentVariable("ANDROID_HOME", $AndroidHome, "User")
    [System.Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", $AndroidHome, "User")
    [System.Environment]::SetEnvironmentVariable("GRADLE_HOME", $GradleHome, "User")

    # Update process environment variables immediately
    $env:JAVA_HOME = $JavaHome
    $env:ANDROID_HOME = $AndroidHome
    $env:ANDROID_SDK_ROOT = $AndroidHome
    $env:GRADLE_HOME = $GradleHome

    # Update User PATH idempotently
    $currentUserPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $currentUserPath) { $currentUserPath = "" }

    $existingSegments = $currentUserPath.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)
    $cleanSegments = [System.Collections.Generic.List[string]]::new()

    # Exclude any existing matches of our paths to avoid duplicates
    foreach ($seg in $existingSegments) {
        $trimmed = $seg.Trim().TrimEnd('\')
        $isToolchain = $false
        foreach ($tp in $toolchainPaths) {
            if ($trimmed -ieq $tp.TrimEnd('\')) {
                $isToolchain = $true
                break
            }
        }
        if (-not $isToolchain) {
            $cleanSegments.Add($seg)
        }
    }

    # Prepend toolchain paths
    $newPathList = [System.Collections.Generic.List[string]]::new()
    foreach ($tp in $toolchainPaths) {
        $newPathList.Add($tp)
    }
    foreach ($cs in $cleanSegments) {
        $newPathList.Add($cs)
    }

    $newUserPath = $newPathList -join ";"
    [System.Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")

    # Update current session Path
    $env:Path = ($toolchainPaths -join ";") + ";" + $env:Path

    Write-LogSuccess "User environment variables (JAVA_HOME, ANDROID_HOME, GRADLE_HOME) updated in Windows Registry."
    Write-LogSuccess "Prepended mobile toolchain directories to User PATH."
}

function Remove-ToolchainEnvironment {
    param (
        [string]$AndroidHome = "",
        [string]$FlutterHome = "",
        [string]$GradleHome = "",
        [bool]$AutoConfirm = $false,
        [bool]$DryRun = $false
    )
    Write-LogStep "Starting Windows Uninstallation Routine"

    if ($DryRun) {
        Write-LogDryRun "Would remove User Environment Variables: JAVA_HOME, ANDROID_HOME, ANDROID_SDK_ROOT, GRADLE_HOME"
        Write-LogDryRun "Would clean toolchain directories from User PATH"
        if ($AndroidHome) { Write-LogDryRun "Would check/delete directory: $AndroidHome" }
        if ($FlutterHome) { Write-LogDryRun "Would check/delete directory: $FlutterHome" }
        Write-LogSuccess "Dry-run uninstall simulation complete. No files or registry entries modified."
        return
    }

    # Remove User-level environment variables
    [System.Environment]::SetEnvironmentVariable("JAVA_HOME", $null, "User")
    [System.Environment]::SetEnvironmentVariable("ANDROID_HOME", $null, "User")
    [System.Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", $null, "User")
    [System.Environment]::SetEnvironmentVariable("GRADLE_HOME", $null, "User")
    Write-LogSuccess "Cleared toolchain environment variables from User Registry."

    # Strip toolchain paths from User PATH
    $currentUserPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentUserPath) {
        $segments = $currentUserPath.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)
        $cleanSegments = @()
        foreach ($s in $segments) {
            $lower = $s.ToLower()
            if ($lower -like "*cmdline-tools*" -or `
                $lower -like "*platform-tools*" -or `
                $lower -like "*build-tools*" -or `
                $lower -like "*development\flutter*" -or `
                $lower -like "*share\gradle*" -or `
                $lower -like "*share\jdks*") {
                Write-LogInfo "Stripped from User PATH: $s"
            }
            else {
                $cleanSegments += $s
            }
        }
        $newUserPath = $cleanSegments -join ";"
        [System.Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
        Write-LogSuccess "Cleaned User PATH in Windows Registry."
    }

    # Clean SDK directories
    $dirs = @($AndroidHome, $FlutterHome)
    foreach ($d in $dirs) {
        if ($d -and (Test-Path $d)) {
            $remove = $AutoConfirm
            if (-not $remove -and [Environment]::UserInteractive) {
                $remove = Prompt-Confirm "Permanently remove directory '$d'?" $false
            }
            if ($remove) {
                Write-LogInfo "Removing directory: $d"
                Remove-Item -Path $d -Recurse -Force -ErrorAction SilentlyContinue
                Write-LogSuccess "Deleted: $d"
            }
        }
    }

    Write-LogSuccess "Uninstallation completed successfully."
    Write-LogInfo "Please restart your terminal or PowerShell console to reflect changes."
}

Export-ModuleMember -Function Set-ToolchainEnvironment, Remove-ToolchainEnvironment
