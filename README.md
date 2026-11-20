<p align="center">
  <img src="assets/logo.svg" width="128" height="128" alt="Flutter-Kick Logo" />
</p>

<h1 align="center">Flutter-Kick</h1>

<p align="center">
  <a href="https://github.com/frozenlabx/flutter-kick/actions/workflows/ci.yml"><img src="https://github.com/frozenlabx/flutter-kick/actions/workflows/ci.yml/badge.svg" alt="CI" /></a>
  <a href="https://www.gnu.org/software/bash/"><img src="https://img.shields.io/badge/shell-POSIX%2FBash%203.2%2B-blue.svg" alt="Shell" /></a>
  <a href="https://microsoft.com/powershell"><img src="https://img.shields.io/badge/powershell-5.1%20%7C%207%2B-blue.svg" alt="PowerShell" /></a>
  <a href="#supported-platforms"><img src="https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg" alt="Platform" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT" /></a>
</p>

A lightweight, automated bootstrapper that configures a complete **headless Android SDK and Flutter toolchain** without Android Studio (~4+ GB disk saved).

---

## ⚡ Quick Start (No Git Clone Required)

Run the one-liner in your terminal to start the interactive setup:

### macOS & Linux
```bash
curl -fsSL https://raw.githubusercontent.com/frozenlabx/flutter-kick/main/install.sh | bash
```
> **Non-Interactive LTS Installation**:
> ```bash
> curl -fsSL https://raw.githubusercontent.com/frozenlabx/flutter-kick/main/install.sh | bash -s -- --default
> ```

### Windows (PowerShell)
```powershell
irm https://raw.githubusercontent.com/frozenlabx/flutter-kick/main/install.ps1 | iex
```
> **Non-Interactive LTS Installation**:
> ```powershell
> & ([scriptblock]::Create((irm https://raw.githubusercontent.com/frozenlabx/flutter-kick/main/install.ps1))) -Default
> ```

---

## ✨ Features

- **Headless & Fast**: Downloads only command-line tools, platforms, build-tools, NDK, CMake, Gradle, and Flutter. Zero Android Studio GUI overhead.
- **Concurrent Ingestion & Live Progress**: Downloads JDK, Android cmdline-tools, Gradle, and Flutter simultaneously with real-time percentage indicators.
- **Smart NDK Resolution**: Supports partial versions (e.g. `28.0`, `27.2`), auto-mapping to the full LTS revision (e.g. `28.0.13004108`).
- **Multi-API Support**: Install multiple Android SDK platforms at once (e.g. `--api 34,35,36`).
- **Idempotent Shell Configuration**: Safely manages `JAVA_HOME`, `ANDROID_HOME`, `GRADLE_HOME`, and `PATH` via clean, reversible marker blocks (`.zshrc`, `.bashrc`, `config.fish`, or Windows User Environment).
- **Automated Verification**: Automatically validates `java`, `gradle`, `adb`, and verifies Flutter licenses via `flutter doctor`.
- **Clean Uninstallation**: Reverts environment variable blocks and cleanly removes installed SDK directories.

---

## ⚙️ Components & Default Versions

Accepted via `[1] Recommended LTS` or customized in `[2] Custom Setup`:

| Component | Default | Popular Options | Notes |
| :--- | :--- | :--- | :--- |
| **JDK** | `17` | `17`, `21` | Eclipse Temurin OpenJDK |
| **Android API** | `36` | `36` (Android 16), `35`, `34` | Comma-separated supported (e.g. `34,35,36`) |
| **Build-Tools** | `36.0.0` | `36.0.0`, `35.0.0`, `34.0.0` | Matches target Android API |
| **Android NDK** | `27.2.12479018` | `28.0`, `27.2`, `26.3`, `skip` | Auto-resolves partial version strings |
| **CMake** | `3.22.1` | `3.22.1`, `3.28.0`, `skip` | AGP compatible C/C++ build tool |
| **Gradle** | `8.11.1` | `8.11.1`, `8.10.2`, `skip` | Official Gradle release |
| **Flutter SDK** | `stable` | `stable`, `beta`, `master`, `fvm` | FVM mode supported |

---

## 🚀 CLI Flags & Automation

Automate CI/CD pipelines or bypass prompts with command-line flags:

### Unix (macOS / Linux)
```bash
# Non-interactive default setup
./install.sh --default

# Custom toolchain configuration
./install.sh --jdk 21 --api "34,35" --ndk 28.0 --gradle 8.11.1 --flutter beta --yes

# Dry-run simulation (preview actions without writing to disk)
./install.sh --dry-run --default

# Clean uninstallation
./install.sh --uninstall --yes
```

### Windows (PowerShell)
```powershell
# Non-interactive default setup
.\install.ps1 -Default

# Custom toolchain configuration
.\install.ps1 -Jdk 21 -Api "34,35" -Ndk "28.0" -Gradle "8.11.1" -Flutter "beta" -Yes

# Dry-run simulation
.\install.ps1 -DryRun -Default

# Clean uninstallation
.\install.ps1 -Uninstall -Yes
```

---

## 🖥️ Supported Platforms

| Platform | Family | Package Manager | Architectures |
| :--- | :--- | :--- | :--- |
| **macOS** | Darwin | Homebrew | `arm64` (Apple Silicon), `x86_64` (Intel) |
| **Ubuntu / Debian** | Debian | `apt-get` | `x86_64`, `arm64` |
| **Fedora / RHEL** | Fedora | `dnf` | `x86_64`, `arm64` |
| **Arch / Manjaro** | Arch | `pacman` | `x86_64`, `arm64` |
| **Windows** | Windows 10/11 | PowerShell 5.1+ / 7+ | `x64`, `ARM64` |

---

## 🧪 Testing

Run the automated test suite locally:

```bash
./tests/test_suite.sh
```

Validates configuration defaults, OS detection, idempotent environment injections, smart NDK mapping, interactive menus, and post-installation verification across 75 test cases.

---

## 📄 License

MIT © [FrozenLabX](https://github.com/frozenlabx)
