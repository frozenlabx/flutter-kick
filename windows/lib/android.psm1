# ==============================================================================
# mobile-toolchain-setup: Windows Android SDK Installation Module
# Manages cmdline-tools, platform-tools, platforms, build-tools, NDK, and CMake
# ==============================================================================

Import-Module (Join-Path $PSScriptRoot "ui.psm1") -ErrorAction SilentlyContinue

function Resolve-WindowsCmdlineToolsUrl {
    param (
        [string]$FallbackUrl = "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
    )
    $repoUrl = "https://dl.google.com/android/repository/repository2-3.xml"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $response = Invoke-WebRequest -Uri $repoUrl -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        if ($response -and $response.Content) {
            [xml]$xml = $response.Content
            $latestUrl = ""

            # Priority 1: Canonical 'cmdline-tools;latest' package
            foreach ($pkg in $xml.repository.remotePackage) {
                if ($pkg.path -eq "cmdline-tools;latest") {
                    foreach ($archive in $pkg.archives.archive) {
                        if ($archive."host-os" -eq "windows") {
                            $latestUrl = $archive.complete.url
                            break
                        }
                    }
                    if ($latestUrl) { break }
                }
            }

            # Priority 2: Fallback to highest numbered version if latest not found
            if (-not $latestUrl) {
                foreach ($pkg in $xml.repository.remotePackage) {
                    if ($pkg.path -like "cmdline-tools;[0-9]*") {
                        foreach ($archive in $pkg.archives.archive) {
                            if ($archive."host-os" -eq "windows") {
                                $latestUrl = $archive.complete.url
                                break
                            }
                        }
                        if ($latestUrl) { break }
                    }
                }
            }

            if ($latestUrl) {
                if (-not $latestUrl.StartsWith("http")) {
                    $latestUrl = "https://dl.google.com/android/repository/" + $latestUrl
                }
                Write-LogInfo "Dynamically resolved latest Windows cmdline-tools: $latestUrl"
                return $latestUrl
            }
        }
    }
    catch {
        Write-LogDebug "Dynamic XML fetch failed, using fallback URL."
    }
    return $FallbackUrl
}

function Resolve-WindowsNDKVersion {
    param (
        [string]$RawNdk,
        [string]$SdkRoot,
        [bool]$DryRun = $false
    )
    if ($RawNdk -eq "skip" -or [string]::IsNullOrWhiteSpace($RawNdk)) {
        return "skip"
    }
    if ($RawNdk -match '^[0-9]+\.[0-9]+\.[0-9]+$') {
        return $RawNdk
    }

    $sdkmanagerBat = Join-Path $SdkRoot "cmdline-tools\latest\bin\sdkmanager.bat"
    if ((Test-Path $sdkmanagerBat) -and -not $DryRun) {
        try {
            Write-LogInfo "Querying sdkmanager for available NDK revisions matching '$RawNdk'..."
            $listOutput = & $sdkmanagerBat --list "--sdk_root=$SdkRoot" 2>$null
            $matched = $listOutput | Where-Object { $_ -match "ndk;$([regex]::Escape($RawNdk))" } | ForEach-Object {
                if ($_ -match "ndk;([0-9.]+)") { $matches[1] }
            } | Sort-Object | Select-Object -Last 1
            if ($matched) {
                Write-LogSuccess "Smart NDK resolution: '$RawNdk' -> '$matched' (via sdkmanager.bat)"
                return $matched
            }
        }
        catch {}
    }

    # Built-in lookup map for common partial versions
    $mapped = switch ($RawNdk) {
        "28.0" { "28.0.13004108" }
        "28"   { "28.0.13004108" }
        "27.2" { "27.2.12479018" }
        "27"   { "27.2.12479018" }
        "27.1" { "27.1.12297006" }
        "26.3" { "26.3.11579264" }
        "26"   { "26.3.11579264" }
        "25.2" { "25.2.9519653" }
        "25"   { "25.2.9519653" }
        "23.2" { "23.2.8568313" }
        "21.4" { "21.4.7075529" }
        default { $RawNdk }
    }

    if ($mapped -ne $RawNdk) {
        Write-LogInfo "Smart NDK resolution: mapped partial '$RawNdk' -> '$mapped'"
    }

    return $mapped
}

function Install-WindowsAndroidSDK {
    param (
        [string]$ApiArg = "36",
        [string]$BuildToolsArg = "36.0.0",
        [string]$NdkArg = "27.2.12479018",
        [string]$CmakeArg = "3.22.1",
        [string]$SdkRoot = (Join-Path $env:USERPROFILE "AppData\Local\Android\Sdk"),
        [string]$FallbackCmdlineUrl = "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip",
        [bool]$DryRun = $false,
        [string]$PredownloadedArchive = ""
    )
    Write-LogStep "Configuring Headless Android SDK (Windows)"

    $cmdlineUrl = Resolve-WindowsCmdlineToolsUrl -FallbackUrl $FallbackCmdlineUrl
    $resolvedNdk = Resolve-WindowsNDKVersion -RawNdk $NdkArg -SdkRoot $SdkRoot -DryRun $DryRun

    # Prepare package list supporting comma-separated APIs
    $packages = [System.Collections.Generic.List[string]]::new()
    $packages.Add("platform-tools")

    $apiItems = $ApiArg.Split(',', [System.StringSplitOptions]::RemoveEmptyEntries)
    foreach ($item in $apiItems) {
        $clean = $item.Trim()
        if ($clean) {
            $packages.Add("platforms;android-$clean")
        }
    }

    if ($BuildToolsArg -and $BuildToolsArg -ne "skip") {
        $packages.Add("build-tools;$BuildToolsArg")
    }
    if ($resolvedNdk -and $resolvedNdk -ne "skip") {
        $packages.Add("ndk;$resolvedNdk")
    }
    if ($CmakeArg -and $CmakeArg -ne "skip") {
        $packages.Add("cmake;$CmakeArg")
    }

    $sdkmanagerBat = Join-Path $SdkRoot "cmdline-tools\latest\bin\sdkmanager.bat"

    if ($DryRun) {
        Write-LogDryRun "Target ANDROID_HOME: $SdkRoot"
        Write-LogDryRun "cmdline-tools source: $cmdlineUrl"
        Write-LogDryRun "Would extract into: $(Join-Path $SdkRoot 'cmdline-tools\latest')"
        Write-LogDryRun "Would accept licenses: echo y | sdkmanager.bat --licenses"
        Write-LogDryRun "Would install packages:"
        foreach ($pkg in $packages) {
            Write-LogDryRun "  - $pkg"
        }
        Write-LogDryRun "Would prepend cmdline-tools\latest\bin and platform-tools to PATH"
        $env:ANDROID_HOME = $SdkRoot
        $env:ANDROID_SDK_ROOT = $SdkRoot
        return @{ AndroidHome = $SdkRoot }
    }

    # Live Installation
    if (-not (Test-Path $sdkmanagerBat)) {
        Write-LogInfo "Installing Android SDK Command-line Tools into $SdkRoot\cmdline-tools\latest..."
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $tmpZip = Join-Path $tmpDir "cmdline-tools.zip"

        try {
            if ($PredownloadedArchive -and (Test-Path $PredownloadedArchive)) {
                Copy-Item -Path $PredownloadedArchive -Destination $tmpZip -Force
            }
            else {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -Uri $cmdlineUrl -OutFile $tmpZip -UseBasicParsing -TimeoutSec 120
            }
            $extractTmp = Join-Path $tmpDir "extracted"
            Expand-Archive -Path $tmpZip -DestinationPath $extractTmp -Force

            $latestDir = Join-Path $SdkRoot "cmdline-tools\latest"
            $parentLatest = Split-Path -Parent $latestDir
            if (-not (Test-Path $parentLatest)) {
                New-Item -ItemType Directory -Path $parentLatest -Force | Out-Null
            }
            if (Test-Path $latestDir) {
                Remove-Item -Path $latestDir -Recurse -Force -ErrorAction SilentlyContinue
            }

            # Resilient directory handling: Google zip usually contains 'cmdline-tools'
            $innerCmdline = Join-Path $extractTmp "cmdline-tools"
            $innerTools = Join-Path $extractTmp "tools"
            if (Test-Path $innerCmdline) {
                Move-Item -Path $innerCmdline -Destination $latestDir -Force
            }
            elseif (Test-Path $innerTools) {
                Move-Item -Path $innerTools -Destination $latestDir -Force
            }
            else {
                Move-Item -Path $extractTmp -Destination $latestDir -Force
            }

            Write-LogSuccess "cmdline-tools installed at $latestDir"
        }
        catch {
            Write-LogError "Failed to download/extract Android command-line tools: $($_.Exception.Message)"
            return $null
        }
        finally {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-LogSuccess "Android cmdline-tools already present at $SdkRoot\cmdline-tools\latest"
    }

    $env:ANDROID_HOME = $SdkRoot
    $env:ANDROID_SDK_ROOT = $SdkRoot
    $env:Path = (Join-Path $SdkRoot "cmdline-tools\latest\bin") + ";" + (Join-Path $SdkRoot "platform-tools") + ";" + $env:Path

    # Auto-accept SDK licenses
    Write-LogInfo "Auto-accepting Android SDK licenses..."
    try {
        1..30 | ForEach-Object { "y" } | & $sdkmanagerBat --licenses "--sdk_root=$SdkRoot" 2>$null | Out-Null
        Write-LogSuccess "Android SDK licenses accepted."
    }
    catch {
        Write-LogWarn "License acceptance script exited with warnings."
    }

    # Install packages
    Write-LogInfo "Installing Android SDK packages: $($packages -join ', ')..."
    try {
        1..30 | ForEach-Object { "y" } | & $sdkmanagerBat "--sdk_root=$SdkRoot" $packages
        Write-LogSuccess "Android SDK package installation completed."
    }
    catch {
        Write-LogWarn "Package installation encountered non-zero return code."
    }

    $adbPath = Join-Path $SdkRoot "platform-tools\adb.exe"
    if (Test-Path $adbPath) {
        $adbVer = (& $adbPath --version 2>&1 | Select-Object -First 1)
        Write-LogSuccess "Android platform-tools ready: $adbVer"
    }

    return @{ AndroidHome = $SdkRoot }
}

Export-ModuleMember -Function Resolve-WindowsCmdlineToolsUrl, Resolve-WindowsNDKVersion, Install-WindowsAndroidSDK
