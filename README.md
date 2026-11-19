# `mobile-toolchain-setup`

[![CI](https://img.shields.io/badge/CI-Passing-brightgreen?logo=github-actions&logoColor=white)](#testing)
[![Shell Check](https://img.shields.io/badge/shell-POSIX%2FBash%203.2%2B-blue.svg)](https://www.gnu.org/software/bash/)
[![PowerShell](https://img.shields.io/badge/powershell-5.1%20%7C%207%2B-blue.svg)](https://microsoft.com/powershell)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg)](#supported-platforms)
[![Status](https://img.shields.io/badge/status-Production%20Ready-green.svg)](#)

A cross-platform, modular automation suite that sets up a **headless Android SDK and Flutter development environment** (without requiring Android Studio) on **Linux, macOS, and Windows**.

Designed for engineers, automated CI/CD runners, Docker containers, and lightweight environments who need a fully functional mobile development toolchain with zero unnecessary GUI overhead.

---

## Table of Contents

- [Features](#features)
- [Supported Platforms](#supported-platforms)
- [Directory Structure](#directory-structure)
- [Configuration Single Source of Truth](#configuration-single-source-of-truth)
- [Quick Start](#quick-start)
  - [Unix (Linux & macOS)](#unix-linux--macos)
  - [Windows (PowerShell)](#windows-powershell)
- [Installation Modes & Usage](#installation-modes--usage)
  - [1. Recommended (Default) Mode](#1-recommended-default-mode)
  - [2. Custom Setup Mode](#2-custom-setup-mode)
  - [3. Non-Interactive CLI Automation](#3-non-interactive-cli-automation)
  - [4. Dry-Run Simulation Mode](#4-dry-run-simulation-mode)
  - [5. Uninstallation](#5-uninstallation)
- [Modular Architecture Deep Dive](#modular-architecture-deep-dive)
  - [JDK Setup](#jdk-setup)
  - [Headless Android SDK & Smart NDK](#headless-android-sdk--smart-ndk)
  - [Gradle Setup](#gradle-setup)
  - [Flutter SDK & FVM](#flutter-sdk--fvm)
  - [Idempotent Environment Management](#idempotent-environment-management)
- [Post-Installation Verification](#post-installation-verification)
- [Troubleshooting & FAQs](#troubleshooting--faqs)

---

## Features

- **Headless & Ultra-Lightweight**: Installs command-line tools, platforms, build-tools, NDK, CMake, Gradle, and Flutter without downloading Android Studio (~4+ GB saved).
- **True Cross-Platform**: Dual-engine architecture with pure Bash for Unix (Linux/macOS) and PowerShell for Windows with 100% feature parity.
- **Dynamic Repository Resolution**: Fetches Google's `https://dl.google.com/android/repository/repository2-3.xml` to locate the latest `cmdline-tools` package, falling back seamlessly to `defaults.env` if offline.
- **Smart NDK Resolution**: Supports partial NDK versions (e.g. `28.0` or `27.2`), querying `sdkmanager --list` or built-in revision mappings to resolve the exact full LTS revision string (`28.0.13004108`).
- **Multi-API Support**: Accepts comma-separated API levels (e.g. `--api 34,35,36` / `-Api "34,35,36"`).
- **Interactive & Headless Modes**:
  - `[1] Recommended (Default)`: Zero prompts, verified LTS stack.
  - `[2] Custom Setup`: Granular component prompts with pre-filled defaults.
  - Comprehensive CLI flags for non-interactive automation in CI/CD pipelines.
- **Idempotent Environment Integration**:
  - **Unix**: Reversible marker blocks (`# >>> MOBILE_TOOLCHAIN_SETUP_START >>>`) in `.bashrc`, `.zshrc`, or `config.fish`.
  - **Windows**: User Registry environment variables (`JAVA_HOME`, `ANDROID_HOME`, `GRADLE_HOME`) and clean User `Path` updates via `.NET API`.
- **Pre-Flight Disk Checks**: Alerts if free disk space is under 15 GB before starting downloads.
- **Centralized Logging**: Logs all actions, step milestones, and debug events with ANSI stripping to `~/.mobile-toolchain-setup.log`.

---

## Supported Platforms

| Platform | Family / OS | Base Prerequisites | Architectures |
| :--- | :--- | :--- | :--- |
| **macOS** | Darwin (Sonoma, Sequoia, etc.) | Xcode CLI Tools (`xcode-select -p`), Homebrew | `arm64` (Apple Silicon), `x86_64` (Intel) |
| **Ubuntu / Debian** | Debian (`apt-get`) | `curl`, `git`, `unzip`, `xz-utils`, `clang`, `ninja-build`, `libgtk-3-dev` | `x86_64`, `arm64` |
| **Fedora / RHEL** | Fedora (`dnf`) | `curl`, `git`, `unzip`, `xz`, `clang`, `ninja-build`, `gtk3-devel` | `x86_64`, `arm64` |
| **Arch / Manjaro** | Arch (`pacman`) | `curl`, `git`, `unzip`, `xz`, `clang`, `ninja`, `gtk3` | `x86_64`, `arm64` |
| **Windows** | Windows 10 / 11 / Server | PowerShell 5.1+ or PowerShell 7+, Git for Windows | `x64`, `ARM64` |

---

## Directory Structure

```text
mobile-toolchain-setup/
├── config/
│   └── defaults.env             # Single source of truth for versions, URLs & paths
├── unix/
│   ├── install.sh               # Main Unix entrypoint (set -euo pipefail)
│   ├── lib/
│   │   ├── android.sh           # Android SDK, cmdline-tools, smart NDK & CMake
│   │   ├── env.sh               # Idempotent shell exports, markers & uninstall
│   │   ├── flutter.sh           # Flutter SDK, FVM, engine precache & iOS tools
│   │   ├── gradle.sh            # Gradle distribution extractor (~/.local/share/gradle)
│   │   ├── jdk.sh               # OpenJDK / Eclipse Temurin installer & JAVA_HOME
│   │   ├── os_detect.sh         # OS, arch, shell detection & prerequisites
│   │   └── ui.sh                # Colored terminal output, banners, prompts & logging
│   └── scripts/
│       ├── android.sh           # Android CLI wrapper
│       ├── flutter.sh           # Flutter CLI wrapper
│       ├── gradle.sh            # Gradle CLI wrapper
│       └── jdk.sh               # JDK CLI wrapper
├── windows/
│   ├── install.ps1              # Main Windows PowerShell entrypoint
│   └── lib/
│       ├── android.psm1         # Windows Android SDK & smart NDK installer
│       ├── env.psm1             # Windows User Registry & Path manager
│       ├── flutter.psm1         # Windows Flutter SDK & FVM installer
│       ├── gradle.psm1          # Windows Gradle standalone zip installer
│       ├── jdk.psm1             # Windows Temurin OpenJDK portable installer
│       ├── os_detect.psm1       # Windows OS, architecture, disk & Git check
│       └── ui.psm1              # Windows PowerShell UI, banners & logging
├── tests/
│   └── test_suite.sh            # Automated verification suite (70 tests)
├── install.sh                   # Root convenience wrapper for Unix
└── README.md                    # Project documentation
```

---

## Configuration Single Source of Truth

Recommended versions, fallback URLs, and default paths are centralized in [`config/defaults.env`](file:///Users/md.tanvirulislam/Desktop/flutter-kick/config/defaults.env):

| Setting | Default Value | Notes |
| :--- | :--- | :--- |
| `JDK_VERSION` | `17` | OpenJDK / Eclipse Temurin 17 LTS (Customizable to `21`) |
| `ANDROID_API` | `36` | Android 16 (API 36) SDK Platform (Comma-separated supported) |
| `BUILD_TOOLS_VERSION`| `36.0.0` | Android SDK Build-Tools 36.0.0 |
| `NDK_VERSION` | `27.2.12479018` | Android NDK r27c LTS (or partial version like `28.0`) |
| `CMAKE_VERSION` | `3.22.1` | Android Gradle Plugin compatible CMake |
| `GRADLE_VERSION` | `8.11.1` | Current stable Gradle release |
| `FLUTTER_CHANNEL` | `stable` | Flutter stable channel, Git tag, or `fvm` |
| `MIN_DISK_SPACE_GB` | `15` | Minimum free disk space threshold |

---

## Quick Start

### ⚡ 1. Zero-Clone Web One-Liner (Fastest & Recommended)

You do **not** need to install `git` or manually clone the repository! Run the one-liner for your operating system:

#### **macOS & Linux (bash / zsh)**
```bash
# Interactive setup (prompts for Recommended LTS vs Custom mode):
curl -fsSL https://raw.githubusercontent.com/frozenlabx/flutter-kick/main/install.sh | bash

# Non-interactive quick installation with verified LTS defaults:
curl -fsSL https://raw.githubusercontent.com/frozenlabx/flutter-kick/main/install.sh | bash -s -- --default

# Dry-run simulation (preview all actions without writing to disk):
curl -fsSL https://raw.githubusercontent.com/frozenlabx/flutter-kick/main/install.sh | bash -s -- --dry-run
```

#### **Windows (PowerShell)**
Open PowerShell as your user (Administrator not required):
```powershell
# Interactive setup (prompts for Recommended LTS vs Custom mode):
irm https://raw.githubusercontent.com/frozenlabx/flutter-kick/main/install.ps1 | iex

# Non-interactive quick installation with verified LTS defaults:
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/frozenlabx/flutter-kick/main/install.ps1))) -Default

# Dry-run simulation:
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/frozenlabx/flutter-kick/main/install.ps1))) -DryRun
```

> **Note for Windows**: If script execution is restricted on your machine, enable it for your current process session:
> ```powershell
> Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
> ```

---

### 📦 2. Standalone Tarball / Zip (No Git Required)

If you are inside an air-gapped network, enterprise proxy, or container without Git:

#### **Linux & macOS**:
```bash
curl -fsSL https://github.com/frozenlabx/flutter-kick/archive/refs/heads/main.tar.gz | tar -xz
cd flutter-kick-main
./install.sh --default
```

#### **Windows**:
```powershell
Invoke-WebRequest -Uri https://github.com/frozenlabx/flutter-kick/archive/refs/heads/main.zip -OutFile flutter-kick.zip
Expand-Archive -Path flutter-kick.zip -DestinationPath .
cd flutter-kick-main
.\install.ps1 -Default
```

---

### 💻 3. Local Clone (For Contributors & Offline Customization)

```bash
# Clone the repository
git clone https://github.com/frozenlabx/flutter-kick.git
cd flutter-kick

# Unix (macOS / Linux):
./install.sh

# Windows (PowerShell):
.\install.ps1
```

---

## Installation Modes & Usage

### 1. Recommended (Default) Mode
Uses the verified LTS stack from `config/defaults.env` with **zero extra prompts**:
- **Unix**: `./unix/install.sh --default`
- **Windows**: `.\windows\install.ps1 -Default`

### 2. Custom Setup Mode
Launches an interactive menu where you can configure each toolchain component. Pressing `[Enter]` on any prompt accepts the shown default in brackets:
- **Unix**: `./unix/install.sh`
- **Windows**: `.\windows\install.ps1`

Interactive prompts:
1. `JDK Version (17/21)` [default: `17`]
2. `Android API Level` [default: `36`, supports comma-separated e.g. `34,35,36`]
3. `Android Build-Tools` [default: `36.0.0`]
4. `Android NDK Version` [default: `27.2.12479018`, supports `28.0` or `skip`]
5. `CMake Version` [default: `3.22.1` or `skip`]
6. `Gradle Version` [default: `8.11.1` or `skip`]
7. `Flutter Channel/Tag or 'fvm'` [default: `stable`]
8. `Setup macOS iOS Tools (Xcode CLI/CocoaPods)` [default: `yes`] *(macOS only)*

### 3. Non-Interactive CLI Automation

Pass component flags directly to bypass all interactive prompts:

#### Unix
```bash
./unix/install.sh \
  --jdk 21 \
  --api "34,35" \
  --build-tools 35.0.0 \
  --ndk 28.0 \
  --cmake 3.22.1 \
  --gradle 8.10 \
  --flutter beta \
  --yes
```

#### Windows
```powershell
.\windows\install.ps1 `
  -Jdk 21 `
  -Api "34,35" `
  -BuildTools "35.0.0" `
  -Ndk "28.0" `
  -Cmake "3.22.1" `
  -Gradle "8.10" `
  -Flutter "beta" `
  -Yes
```

### 4. Dry-Run Simulation Mode

Simulate all actions, review environment variable exports, verify system paths, and inspect planned installations without modifying any files or registry settings:

#### Unix
```bash
# Preview default installation
./unix/install.sh --dry-run --default

# Preview custom configuration
./unix/install.sh --dry-run --jdk 21 --api "34,35" --ndk 28.0 --flutter fvm
```

#### Windows
```powershell
# Preview default installation
.\windows\install.ps1 -DryRun -Default

# Preview custom configuration
.\windows\install.ps1 -DryRun -Jdk 21 -Api "34,35" -Ndk "28.0" -Flutter "fvm"
```

### 5. Uninstallation

Cleanly strips environment variable injections, restores clean PATH settings, and optionally deletes installed toolchain directories:

#### Unix
```bash
# Interactive uninstallation
./unix/install.sh --uninstall

# Non-interactive uninstallation
./unix/install.sh --uninstall --yes

# Dry-run uninstallation preview
./unix/install.sh --uninstall --dry-run
```

#### Windows
```powershell
# Interactive uninstallation
.\windows\install.ps1 -Uninstall

# Non-interactive uninstallation
.\windows\install.ps1 -Uninstall -Yes

# Dry-run uninstallation preview
.\windows\install.ps1 -Uninstall -DryRun
```

---

## Modular Architecture Deep Dive

### JDK Setup
- **Unix**: [`unix/lib/jdk.sh`](file:///Users/md.tanvirulislam/Desktop/flutter-kick/unix/lib/jdk.sh)
- **Windows**: [`windows/lib/jdk.psm1`](file:///Users/md.tanvirulislam/Desktop/flutter-kick/windows/lib/jdk.psm1)
- Downloads official **Eclipse Temurin OpenJDK** portable archives directly from the Adoptium API (`api.adoptium.net/v3/binary/latest/...`).
- Installs into `~/.local/share/jdks/temurin-<ver>` (non-root, user-isolated).
- Configures `JAVA_HOME` and prepends `$JAVA_HOME/bin` to `PATH`.

### Headless Android SDK & Smart NDK
- **Unix**: [`unix/lib/android.sh`](file:///Users/md.tanvirulislam/Desktop/flutter-kick/unix/lib/android.sh)
- **Windows**: [`windows/lib/android.psm1`](file:///Users/md.tanvirulislam/Desktop/flutter-kick/windows/lib/android.psm1)
- **Dynamic XML Resolution**: Parses Google's official repository XML to fetch the latest `commandlinetools` archive.
- **Directory Hierarchy**: Extracts into `$ANDROID_HOME/cmdline-tools/latest` (ensuring `cmdline-tools/latest/bin/sdkmanager` structure).
- **Auto-Accept Licenses**: Automatically accepts all SDK licenses non-interactively.
- **Smart NDK Resolution**: Supports partial versions (e.g. `28.0`, `27.2`, `26.3`), querying `sdkmanager --list` or built-in LTS lookup tables to map `28.0` -> `28.0.13004108`.
- **Multi-API Installation**: Accepts comma-separated values (e.g. `34,35,36`), installing each target platform alongside `platform-tools`, `build-tools`, and `cmake`.

### Gradle Setup
- **Unix**: [`unix/lib/gradle.sh`](file:///Users/md.tanvirulislam/Desktop/flutter-kick/unix/lib/gradle.sh)
- **Windows**: [`windows/lib/gradle.psm1`](file:///Users/md.tanvirulislam/Desktop/flutter-kick/windows/lib/gradle.psm1)
- Downloads distribution zip from `https://services.gradle.org/distributions/gradle-${version}-bin.zip`.
- Extracts to `~/.local/share/gradle/gradle-${version}`.
- Sets `GRADLE_HOME` pointing to the binaries and prepends `$GRADLE_HOME/bin` to `PATH`.

### Flutter SDK & FVM
- **Unix**: [`unix/lib/flutter.sh`](file:///Users/md.tanvirulislam/Desktop/flutter-kick/unix/lib/flutter.sh)
- **Windows**: [`windows/lib/flutter.psm1`](file:///Users/md.tanvirulislam/Desktop/flutter-kick/windows/lib/flutter.psm1)
- Clones Flutter into `~/development/flutter` on the chosen channel (`stable`/`beta`/`master`) or checks out a specific tag.
- If `--flutter fvm` / `-Flutter fvm` is specified, installs FVM and activates the requested version.
- Executes `flutter precache --android`, configures `flutter config --android-sdk "$ANDROID_HOME"`, and runs `flutter doctor --android-licenses`.
- On macOS, checks Xcode Command Line Tools and CocoaPods (`pod`).

### Idempotent Environment Management
- **Unix**: [`unix/lib/env.sh`](file:///Users/md.tanvirulislam/Desktop/flutter-kick/unix/lib/env.sh)
  Uses structured marker blocks:
  ```bash
  # >>> MOBILE_TOOLCHAIN_SETUP_START >>>
  # Auto-generated by mobile-toolchain-setup. Do not edit between markers.
  export JAVA_HOME="/Users/user/.local/share/jdks/temurin-17/Contents/Home"
  export ANDROID_HOME="/Users/user/Library/Android/sdk"
  export ANDROID_SDK_ROOT="${ANDROID_HOME}"
  export GRADLE_HOME="/Users/user/.local/share/gradle/gradle-8.11.1"
  export PATH="${JAVA_HOME}/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/emulator:${ANDROID_HOME}/build-tools/36.0.0:${GRADLE_HOME}/bin:/Users/user/development/flutter/bin:${PATH}"
  # <<< MOBILE_TOOLCHAIN_SETUP_END <<<
  ```
- **Windows**: [`windows/lib/env.psm1`](file:///Users/md.tanvirulislam/Desktop/flutter-kick/windows/lib/env.psm1)
  Sets User Registry variables (`JAVA_HOME`, `ANDROID_HOME`, `GRADLE_HOME`) and User `Path` via `.NET` `[Environment]::SetEnvironmentVariable(..., "User")`.

---

## Post-Installation Verification

Every run includes automated validation of the configured toolchain:

```text
--- Toolchain Verification Summary ---
[✓] Java: openjdk version "17.0.12" 2024-07-16
[✓] Gradle: Gradle 8.11.1
[✓] Android Platform Tools: Android Debug Bridge version 1.0.41
[✓] Flutter Doctor check complete.
```

In `--dry-run` / `-DryRun` mode:
```text
[6/7] Post-Installation Verification
[DRY-RUN] Verification: Would execute 'java -version'
[DRY-RUN] Verification: Would execute 'gradle -v'
[DRY-RUN] Verification: Would execute 'adb --version'
[DRY-RUN] Verification: Would execute 'flutter doctor -v'
```

---

## Troubleshooting & FAQs

### 1. Windows: "cannot be loaded because running scripts is disabled on this system"
By default, Windows restricts unsigned PowerShell scripts. Enable execution for your current PowerShell session:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

### 2. Windows: Path Length Limitations (Error 260 Characters)
Android SDK and Gradle build caches can exceed the default Windows 260-character path limit. Enable Win32 Long Paths in an elevated PowerShell prompt:
```powershell
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" `
  -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force
```

### 3. Changes not appearing in your terminal session
Environment variable changes apply to new terminal processes:
- **Unix**: Reload your configuration with `source ~/.zshrc` (or `~/.bashrc`), or restart your terminal.
- **Windows**: Close and re-open PowerShell or Windows Terminal.

### 4. Android SDK Licenses Rejected or Not Accepted
If licenses were not accepted due to network or interactive timeouts, accept them manually:
- **Unix**:
  ```bash
  yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses
  flutter doctor --android-licenses
  ```
- **Windows**:
  ```powershell
  for ($i=0;$i -lt 30;$i++) { "y" } | & "$env:ANDROID_HOME\cmdline-tools\latest\bin\sdkmanager.bat" --licenses
  flutter doctor --android-licenses
  ```

### 5. Running behind a Corporate Proxy or Offline
If your network blocks dynamic Google repository fetching, the installer automatically falls back to pre-configured static URLs in `config/defaults.env`. You can edit `config/defaults.env` to point to internal artifactory mirrors if required.

---

## Distribution & Deployment Strategies

### 1. Zero-Clone Web Bootstrapper Architecture
`flutter-kick` includes universal web bootstrappers ([`install.sh`](file:///Users/md.tanvirulislam/Desktop/flutter-kick/install.sh) and [`install.ps1`](file:///Users/md.tanvirulislam/Desktop/flutter-kick/install.ps1)) that enable one-line installations without `git clone`:
- **Dual-Mode Operation**: When run locally within a cloned directory, it delegates directly to `unix/install.sh` or `windows/install.ps1`. When run standalone (e.g. via `curl | bash` or `irm | iex`), it downloads the repository archive directly into a secure temporary directory (`/tmp` or `$env:TEMP`).
- **Interactive TTY Reconnection**: On Unix, piped execution (`curl ... | bash`) automatically reconnects standard input to `/dev/tty`, allowing full colored interactive menus (`[1] Recommended, [2] Custom`) to work seamlessly without skipping prompts.
- **Automatic Self-Cleanup**: Temporary archives are trapped and removed immediately upon exit or interruption.

### 2. Docker & Container Pipelines
Add this single line to your `Dockerfile` for headless CI builds:
```dockerfile
RUN curl -fsSL https://raw.githubusercontent.com/frozenlabx/flutter-kick/main/install.sh | bash -s -- --default
ENV PATH="/root/.local/share/jdks/temurin-17/bin:/root/Android/Sdk/cmdline-tools/latest/bin:/root/Android/Sdk/platform-tools:/root/.local/share/gradle/gradle-8.11.1/bin:/root/development/flutter/bin:${PATH}"
ENV JAVA_HOME="/root/.local/share/jdks/temurin-17"
ENV ANDROID_HOME="/root/Android/Sdk"
```

### 3. GitHub Pages Vanity URL (Optional Setup)
By enabling GitHub Pages for `frozenlabx/flutter-kick` on the `main` branch (root), users can run even shorter commands:
```bash
# Unix (Linux & macOS):
curl -fsSL https://frozenlabx.github.io/flutter-kick/install.sh | bash

# Windows:
irm https://frozenlabx.github.io/flutter-kick/install.ps1 | iex
```

### 4. Package Managers Roadmap

#### **Homebrew (macOS & Linux)**
You can host a Homebrew Tap by creating repository `frozenlabx/homebrew-tap` with formula `flutter-kick.rb`:
```ruby
class FlutterKick < Formula
  desc "Headless Android SDK & Flutter development environment setup"
  homepage "https://github.com/frozenlabx/flutter-kick"
  url "https://github.com/frozenlabx/flutter-kick/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "<checksum>"
  license "MIT"

  def install
    bin.install "install.sh" => "flutter-kick"
    prefix.install "unix", "config"
  end
end
```
Users then install via:
```bash
brew tap frozenlabx/tap
brew install flutter-kick
flutter-kick --default
```

#### **Scoop (Windows)**
Create a Scoop bucket manifest `flutter-kick.json`:
```json
{
  "version": "1.0.0",
  "description": "Headless Android SDK & Flutter Toolchain Automation",
  "homepage": "https://github.com/frozenlabx/flutter-kick",
  "license": "MIT",
  "url": "https://github.com/frozenlabx/flutter-kick/archive/refs/tags/v1.0.0.zip",
  "bin": "install.ps1"
}
```

---

## Testing

A comprehensive automated test suite is provided in [`tests/test_suite.sh`](file:///Users/md.tanvirulislam/Desktop/flutter-kick/tests/test_suite.sh):

```bash
./tests/test_suite.sh
```

**70/70 tests passing**, verifying:
- Defaults configuration parsing
- OS, architecture, active shell, and disk space detection
- Idempotent marker block injection, re-injection, and removal
- Native fish shell syntax generation
- Modular execution of `jdk.sh`, `android.sh`, `gradle.sh`, `flutter.sh`
- Smart NDK resolution (`28.0` -> `28.0.13004108`) and comma-separated API parsing
- Full 7-step sequence in `install.sh` and post-install verification checks
- Interactive piped stdin simulation for custom setups
