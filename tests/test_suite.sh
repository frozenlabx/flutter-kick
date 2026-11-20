#!/usr/bin/env bash
# ==============================================================================
# mobile-toolchain-setup: Test Suite (Phase 1 & Phase 2 Modules)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

assert_true() {
    local desc="$1"
    local condition="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if eval "$condition"; then
        printf "  ✓ PASS: %s\n" "$desc"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        printf "  ✗ FAIL: %s\n" "$desc" >&2
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_contains() {
    local desc="$1"
    local haystack="$2"
    local needle="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        printf "  ✓ PASS: %s\n" "$desc"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        printf "  ✗ FAIL: %s (Did not contain '%s')\n" "$desc" "$needle" >&2
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

printf "\n=======================================================\n"
printf "Running mobile-toolchain-setup Comprehensive Test Suite\n"
printf "=======================================================\n\n"

# ------------------------------------------------------------------------------
# Test 1: Configuration Source and Values
# ------------------------------------------------------------------------------
printf "[Test Group 1] defaults.env verification\n"
assert_true "defaults.env exists" "[[ -f '${PROJECT_ROOT}/config/defaults.env' ]]"

config_output="$(bash -c "source '${PROJECT_ROOT}/config/defaults.env' && echo \"\$JDK_VERSION|\$ANDROID_API|\$BUILD_TOOLS_VERSION|\$NDK_VERSION|\$CMAKE_VERSION|\$GRADLE_VERSION|\$FLUTTER_CHANNEL\"")"
assert_contains "defaults.env contains JDK 17" "$config_output" "17|"
assert_contains "defaults.env contains Android API 36" "$config_output" "|36|"
assert_contains "defaults.env contains Build-Tools 36.0.0" "$config_output" "|36.0.0|"
assert_contains "defaults.env contains CMake 3.22.1" "$config_output" "|3.22.1|"
assert_contains "defaults.env contains Gradle 8.11.1" "$config_output" "|8.11.1|"
assert_contains "defaults.env contains Flutter stable" "$config_output" "|stable"

# ------------------------------------------------------------------------------
# Test 2: OS, Arch, and Shell Detection
# ------------------------------------------------------------------------------
printf "\n[Test Group 2] os_detect.sh verification\n"
detect_res="$(bash -c "source '${PROJECT_ROOT}/unix/lib/os_detect.sh' && detect_all && echo \"OS_TYPE=\$OS_TYPE;CPU_ARCH=\$CPU_ARCH;ACTIVE_SHELL=\$ACTIVE_SHELL\"")"
assert_contains "detect_all sets OS_TYPE" "$detect_res" "OS_TYPE="
assert_contains "detect_all sets CPU_ARCH" "$detect_res" "CPU_ARCH="
assert_contains "detect_all sets ACTIVE_SHELL" "$detect_res" "ACTIVE_SHELL="

disk_check_res="$(bash -c "source '${PROJECT_ROOT}/unix/lib/os_detect.sh' && check_disk_space '$HOME' 1 && echo 'DISK_OK'")"
assert_contains "check_disk_space succeeds for 1 GB threshold" "$disk_check_res" "DISK_OK"

# ------------------------------------------------------------------------------
# Test 3: Idempotent Environment Injection & Removal
# ------------------------------------------------------------------------------
printf "\n[Test Group 3] env.sh idempotent injection and stripping\n"
tmp_rc="$(mktemp)"
printf "export USER_EXISTING_VAR=hello\n" > "$tmp_rc"

bash -c "
source '${PROJECT_ROOT}/unix/lib/env.sh'
block=\$(generate_env_block 'bash' '/test/jdk' '/test/android' '/test/gradle' '/test/flutter' '36.0.0')
inject_env_block '$tmp_rc' \"\$block\" false
"

injected_content="$(cat "$tmp_rc")"
assert_contains "Injected file retains existing content" "$injected_content" "USER_EXISTING_VAR=hello"
assert_contains "Injected file has start marker" "$injected_content" "# >>> MOBILE_TOOLCHAIN_SETUP_START >>>"
assert_contains "Injected file has end marker" "$injected_content" "# <<< MOBILE_TOOLCHAIN_SETUP_END <<<"
assert_contains "Injected file sets JAVA_HOME" "$injected_content" "export JAVA_HOME=\"/test/jdk\""
assert_contains "Injected file sets ANDROID_HOME" "$injected_content" "export ANDROID_HOME=\"/test/android\""
assert_contains "Injected file sets GRADLE_HOME" "$injected_content" "export GRADLE_HOME=\"/test/gradle\""
assert_contains "Injected file includes flutter in PATH" "$injected_content" "/test/flutter/bin"

# Test Idempotency: Re-inject updated block (e.g. JDK 21) into same file
bash -c "
source '${PROJECT_ROOT}/unix/lib/env.sh'
new_block=\$(generate_env_block 'bash' '/test/jdk21' '/test/android' '/test/gradle' '/test/flutter' '36.0.0')
inject_env_block '$tmp_rc' \"\$new_block\" false
"

re_injected="$(cat "$tmp_rc")"
assert_contains "Idempotent injection updated JAVA_HOME to jdk21" "$re_injected" "export JAVA_HOME=\"/test/jdk21\""
marker_count="$(grep -c "# >>> MOBILE_TOOLCHAIN_SETUP_START >>>" "$tmp_rc")"
assert_true "Exactly one start marker exists after re-injection" "[[ '$marker_count' -eq 1 ]]"

# Test Stripping block
bash -c "
source '${PROJECT_ROOT}/unix/lib/env.sh'
strip_env_block '$tmp_rc' false
"
stripped_content="$(cat "$tmp_rc")"
assert_contains "Stripped file retains user original variable" "$stripped_content" "USER_EXISTING_VAR=hello"
assert_true "Stripped file no longer contains marker block" "! grep -q '# >>> MOBILE_TOOLCHAIN_SETUP_START >>>' '$tmp_rc'"

rm -f "$tmp_rc"*

# ------------------------------------------------------------------------------
# Test 4: Fish Shell Block Generation
# ------------------------------------------------------------------------------
printf "\n[Test Group 4] env.sh fish shell support\n"
fish_block="$(bash -c "source '${PROJECT_ROOT}/unix/lib/env.sh' && generate_env_block 'fish' '/opt/jdk' '/opt/android' '/opt/gradle' '/opt/flutter' '36.0.0'")"
assert_contains "Fish block uses set -gx JAVA_HOME" "$fish_block" "set -gx JAVA_HOME \"/opt/jdk\""
assert_contains "Fish block uses fish_add_path" "$fish_block" "fish_add_path"

# ------------------------------------------------------------------------------
# Test 5: unix/lib/jdk.sh Module Verification
# ------------------------------------------------------------------------------
printf "\n[Test Group 5] unix/lib/jdk.sh module execution\n"
jdk17_dry="$("${PROJECT_ROOT}/unix/lib/jdk.sh" --version 17 --dry-run)"
assert_contains "jdk.sh recognizes version 17" "$jdk17_dry" "JDK 17"
if [[ "$jdk17_dry" == *"already installed"* || "$jdk17_dry" == *"already available"* ]]; then
    assert_contains "jdk.sh detects pre-installed JDK 17" "$jdk17_dry" "JDK 17"
else
    assert_contains "jdk.sh references Adoptium endpoint" "$jdk17_dry" "api.adoptium.net/v3/binary/latest/17"
    assert_contains "jdk.sh simulates JAVA_HOME export" "$jdk17_dry" "JAVA_HOME="
fi

jdk21_dry="$("${PROJECT_ROOT}/unix/lib/jdk.sh" --version 21 --dry-run)"
assert_contains "jdk.sh recognizes customizable version 21" "$jdk21_dry" "JDK 21"
if [[ "$jdk21_dry" == *"already installed"* || "$jdk21_dry" == *"already available"* ]]; then
    assert_contains "jdk.sh detects pre-installed JDK 21" "$jdk21_dry" "JDK 21"
else
    assert_contains "jdk.sh references Adoptium 21 endpoint" "$jdk21_dry" "api.adoptium.net/v3/binary/latest/21"
fi

# ------------------------------------------------------------------------------
# Test 6: unix/lib/android.sh Module Verification (Smart NDK & Comma APIs)
# ------------------------------------------------------------------------------
printf "\n[Test Group 6] unix/lib/android.sh module execution\n"
android_dry="$("${PROJECT_ROOT}/unix/lib/android.sh" --api "34,35,36" --build-tools "36.0.0" --ndk "28.0" --cmake "3.22.1" --dry-run)"
assert_contains "android.sh extracts into cmdline-tools/latest" "$android_dry" "cmdline-tools/latest"
assert_contains "android.sh auto-accepts licenses" "$android_dry" "yes | sdkmanager --licenses"
assert_contains "android.sh parses API 34" "$android_dry" "platforms;android-34"
assert_contains "android.sh parses API 35" "$android_dry" "platforms;android-35"
assert_contains "android.sh parses API 36" "$android_dry" "platforms;android-36"
assert_contains "android.sh includes build-tools 36.0.0" "$android_dry" "build-tools;36.0.0"
assert_contains "android.sh smart NDK resolution resolves 28.0 to 28.0.13004108" "$android_dry" "ndk;28.0.13004108"
assert_contains "android.sh includes cmake 3.22.1" "$android_dry" "cmake;3.22.1"

# ------------------------------------------------------------------------------
# Test 7: unix/lib/gradle.sh Module Verification
# ------------------------------------------------------------------------------
printf "\n[Test Group 7] unix/lib/gradle.sh module execution\n"
gradle_dry="$("${PROJECT_ROOT}/unix/lib/gradle.sh" --version 8.11.1 --dry-run)"
assert_contains "gradle.sh targets .local/share/gradle" "$gradle_dry" ".local/share/gradle/gradle-8.11.1"
assert_contains "gradle.sh downloads official distribution" "$gradle_dry" "services.gradle.org/distributions/gradle-8.11.1-bin.zip"
assert_contains "gradle.sh sets GRADLE_HOME" "$gradle_dry" "GRADLE_HOME="

# ------------------------------------------------------------------------------
# Test 8: unix/lib/flutter.sh Module Verification
# ------------------------------------------------------------------------------
printf "\n[Test Group 8] unix/lib/flutter.sh module execution\n"
flutter_std_dry="$("${PROJECT_ROOT}/unix/lib/flutter.sh" --channel stable --dry-run)"
assert_contains "flutter.sh clones into development/flutter" "$flutter_std_dry" "development/flutter"
assert_contains "flutter.sh precaches android artifacts" "$flutter_std_dry" "flutter precache --android"
assert_contains "flutter.sh configures android-sdk" "$flutter_std_dry" "flutter config --android-sdk"
assert_contains "flutter.sh accepts doctor android licenses" "$flutter_std_dry" "flutter doctor --android-licenses"

flutter_fvm_dry="$("${PROJECT_ROOT}/unix/lib/flutter.sh" --channel fvm --dry-run)"
assert_contains "flutter.sh supports FVM mode" "$flutter_fvm_dry" "Flutter Version Management (FVM)"

# ------------------------------------------------------------------------------
# Test 9: install.sh Full CLI Flow & Dry-Run
# ------------------------------------------------------------------------------
printf "\n[Test Group 9] install.sh CLI execution, 7-step sequence & verification\n"

# --help
help_out="$("${PROJECT_ROOT}/unix/install.sh" --help)"
assert_contains "--help displays usage" "$help_out" "Usage:"
assert_contains "--help displays options" "$help_out" "--dry-run"

root_help_out="$("${PROJECT_ROOT}/install.sh" --help)"
assert_contains "Root install.sh wrapper delegates properly" "$root_help_out" "Usage:"

# --dry-run --default
default_dry_out="$("${PROJECT_ROOT}/unix/install.sh" --dry-run --default)"
assert_contains "Recommended mode sets JDK 17" "$default_dry_out" "JDK Version            : 17"
assert_contains "Recommended mode sets Android API 36" "$default_dry_out" "API 36 (Build-Tools: 36.0.0)"
assert_contains "Executes Step 1" "$default_dry_out" "[1/7] Detecting Host Operating System & Shell"
assert_contains "Executes Step 2" "$default_dry_out" "[2/7] Pre-Flight Checks"
assert_contains "Executes Step 3" "$default_dry_out" "[3/7] Installing Base Prerequisites"
assert_contains "Executes Step 4" "$default_dry_out" "[4/7] Installing Toolchain Components"
assert_contains "Executes Step 5" "$default_dry_out" "[5/7] Injecting Environment Variables and PATH"
assert_contains "Executes Step 6 Post-Install Verification" "$default_dry_out" "[6/7] Post-Installation Verification"
assert_contains "Verification checks java" "$default_dry_out" "Would execute 'java -version'"
assert_contains "Verification checks gradle" "$default_dry_out" "Would execute 'gradle -v'"
assert_contains "Verification checks adb" "$default_dry_out" "Would execute 'adb --version'"
assert_contains "Verification checks flutter doctor" "$default_dry_out" "Would execute 'flutter doctor -v'"
assert_contains "Executes Step 7" "$default_dry_out" "[7/7] Installation Completed"

# --dry-run with component flag overrides
custom_dry_out="$("${PROJECT_ROOT}/unix/install.sh" --dry-run --jdk 21 --api 35 --build-tools 35.0.0 --ndk 28.0 --cmake 3.22.1 --gradle 8.10 --flutter beta)"
assert_contains "CLI flags override JDK to 21" "$custom_dry_out" "JDK Version            : 21"
assert_contains "CLI flags override API to 35" "$custom_dry_out" "API 35 (Build-Tools: 35.0.0)"
assert_contains "CLI flags resolve NDK 28.0 to 28.0.13004108" "$custom_dry_out" "ndk;28.0.13004108"
assert_contains "CLI flags override Gradle to 8.10" "$custom_dry_out" "gradle-8.10"
assert_contains "CLI flags override Flutter to beta" "$custom_dry_out" "Flutter Channel/SDK    : beta"

# --uninstall --dry-run
uninstall_dry_out="$("${PROJECT_ROOT}/unix/install.sh" --uninstall --dry-run)"
assert_contains "Uninstall mode identifies uninstallation" "$uninstall_dry_out" "Starting mobile-toolchain-setup Uninstallation"
assert_contains "Uninstall dry-run finishes successfully" "$uninstall_dry_out" "Dry-run uninstall simulation complete"

# Parallel vs Sequential mode checks
parallel_dry_out="$("${PROJECT_ROOT}/unix/install.sh" --dry-run --default --parallel)"
assert_contains "Parallel mode reports 4 concurrent workers" "$parallel_dry_out" "Parallel Toolchain Ingestion enabled (4 concurrent download workers)"
assert_contains "Parallel mode logs Worker 1" "$parallel_dry_out" "Parallel Worker 1: Fetch Eclipse Temurin JDK"

seq_dry_out="$("${PROJECT_ROOT}/unix/install.sh" --dry-run --default --sequential)"
assert_contains "Sequential mode performs standard JDK installation" "$seq_dry_out" "Installing / Verifying JDK 17"

# ------------------------------------------------------------------------------
# Test 10: Interactive Simulation via Piped Input
# ------------------------------------------------------------------------------
printf "\n[Test Group 10] Interactive simulation via piped inputs\n"
piped_custom_out="$(printf "2\n21\n34\n34.0.0\nskip\nskip\n8.10\nbeta\nno\n" | "${PROJECT_ROOT}/unix/install.sh" --dry-run)"
assert_contains "Piped custom mode prompts and sets JDK 21" "$piped_custom_out" "JDK Version            : 21"
assert_contains "Piped custom mode prompts and sets API 34" "$piped_custom_out" "API 34 (Build-Tools: 34.0.0)"
assert_contains "Piped custom mode prompts and sets Flutter beta" "$piped_custom_out" "Flutter Channel/SDK    : beta"

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
printf "\n=======================================================\n"
printf "Test Summary: Total=%d, Passed=%d, Failed=%d\n" "$TESTS_RUN" "$TESTS_PASSED" "$TESTS_FAILED"
printf "=======================================================\n\n"

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
