#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_ID=0
UAD_LIST_URL="https://raw.githubusercontent.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation/main/resources/assets/uad_lists.json"
UAD_CACHE_FILE="$SCRIPT_DIR/uad_lists.json"
DEBLOAT_HISTORY_FILE="$SCRIPT_DIR/removed-packages.txt"
POWERKEEPER_OPS=("WRITE_SETTINGS" "GET_USAGE_STATS" "RUN_IN_BACKGROUND")
DOZE_PACKAGES=("com.facebook.services" "com.facebook.appmanager")
GMS_PACKAGES=("com.google.android.gms" "com.google.android.gsf")
TELEMETRY_PACKAGES=("com.miui.msa.global" "com.miui.daemon")
MULTICAST_PACKAGES=(
    "com.xiaomi.mi_connect_service"
    "com.milink.service"
    "com.miui.mishare.connectivity"
    "com.xiaomi.mirror"
    "com.xiaomi.continuity.sdkapp"
    "com.xiaomi.midrop"
    "com.microsoft.appmanager"
    "com.microsoft.deviceintegrationservice"
    "com.microsoftsdk.crossdeviceservicebroker"
)

print_usage() {
    cat <<'EOF'
HyperOS Optimizer ADB Script

Usage:
  ./hyperos3-optimizer.sh            Open the interactive menu
  ./hyperos3-optimizer.sh full       Apply the Full Optimization preset
  ./hyperos3-optimizer.sh full-debloat
                          Apply Full Optimization + Recommended Debloat
  ./hyperos3-optimizer.sh on         Apply the Performance preset
  ./hyperos3-optimizer.sh off        Restore stock/default settings
  ./hyperos3-optimizer.sh status     Print current managed setting values
  ./hyperos3-optimizer.sh explain    Show detailed feature descriptions
  ./hyperos3-optimizer.sh debloat    Open the Canta-style debloat menu
  ./hyperos3-optimizer.sh help       Show this help message

Requirements:
  - Android platform-tools / adb installed
  - python3 installed for Canta-style debloat list parsing
  - USB debugging enabled
  - One authorized device connected with adb

All actions use standard adb shell commands and can be reverted from the menu.
Canta-style debloat actions use the Universal Debloater Alliance package list.
EOF
}

show_feature_help() {
    cat <<'EOF'
Feature Guide

Presets
  Full Optimization
    Applies all optimization settings managed by this tool: Performance-style
    multitasking, battery standby tweaks, telemetry disable, POCO/System
    stacked recents, and the Wi-Fi multicast battery fix.

  Full Optimization + Recommended Debloat
    Applies Full Optimization, then opens the Canta-style Recommended debloat
    flow. Package removal still requires an explicit YES confirmation.

  Performance
    Sets the phantom process limit to 512, forces 120Hz, restricts Xiaomi
    PowerKeeper, and disables common MIUI telemetry/ad services.

  Balanced
    Sets the phantom process limit to 128, restores dynamic/default refresh
    behavior, restores PowerKeeper permissions, and disables telemetry/ad
    services.

  Battery
    Removes Facebook service packages from the Doze whitelist, attempts to
    move Google Play Services and GSF to the Rare standby bucket, restores
    default refresh behavior, restores PowerKeeper permissions, and disables
    telemetry/ad services.

  Gaming
    Sets the phantom process limit to 1024, restricts Xiaomi PowerKeeper,
    forces 120Hz, and disables telemetry/ad services.

  Stock / Default
    Restores PowerKeeper permissions, removes the custom phantom process
    limit, restores Doze and GMS standby changes, restores default refresh
    behavior, re-enables telemetry packages, restores the System/POCO recents layout
    setting, and reinstalls the optional Wi-Fi multicast packages if possible.

Individual Options
  PowerKeeper
    Changes AppOps for com.miui.powerkeeper. Restricting it can reduce Xiaomi's
    aggressive background app killing, but may change battery management
    behavior.

  Phantom process limit
    Changes device_config activity_manager max_phantom_processes. Higher
    values can help multitasking, terminal sessions, emulators, and background
    processes stay alive longer.

  Doze whitelist optimization
    Removes or restores com.facebook.services and com.facebook.appmanager in
    the Doze whitelist. This can reduce screen-off battery drain on devices
    where these packages remain whitelisted even without the Facebook app.

  GMS standby
    Attempts to move com.google.android.gms and com.google.android.gsf between
    Rare and Active standby buckets. Android bucket values are:
      5=EXEMPTED, 10=ACTIVE, 20=WORKING_SET, 30=FREQUENT, 40=RARE,
      45=RESTRICTED.
    Some ROMs automatically promote Google Play Services back to EXEMPTED or
    ACTIVE. In that case, root may be required for persistent enforcement.

  Force 120Hz
    Writes system refresh-rate settings. It can improve perceived smoothness,
    but may increase battery usage.

  Telemetry packages
    Disables or re-enables common MIUI analytics/ad packages:
      com.miui.msa.global
      com.miui.daemon

  System/POCO Launcher stacked recents
    Sets global task_stack_view_layout_style to 2, enabling the stacked recent
    apps layout on supported System Launcher and POCO Launcher versions.
    An up-to-date launcher is recommended.

  Wi-Fi multicast battery fix
    Removes or restores Xiaomi/Microsoft cross-device connectivity packages
    that may cause Wi-Fi multicast wakelocks on some HyperOS builds. You may
    lose Xiaomi casting, Mi Share, cross-device clipboard, or similar ecosystem
    features while this fix is enabled.

  Hidden performance menu
    Attempts to open com.android.settings.fuelgauge.PowerModeSettings. This
    activity is not available on every ROM.

  Canta-style debloat
    Downloads the Universal Debloater Alliance package list, compares it with
    packages installed for the current Android user, and lets you list or
    remove packages by recommendation level. Recommended packages are the
    safest removal target. Advanced, Expert, and Unsafe categories can break
    device features and should only be used by people who understand the
    trade-off.
EOF
}

adb_shell() {
    adb shell "$@" < /dev/null
}

run_cmd() {
    echo "+ adb shell $*"
    adb_shell "$@"
    local code=$?
    if [ "$code" -ne 0 ]; then
        echo "  ! Command failed with exit code $code"
    fi
    return "$code"
}

pause() {
    printf "\nPress Enter to continue..."
    read -r _
}

check_device() {
    if ! command -v adb >/dev/null 2>&1; then
        echo "adb was not found. Install Android platform-tools first."
        exit 1
    fi

    local device_count
    device_count=$(adb devices | awk 'NR > 1 && $2 == "device" { count++ } END { print count + 0 }')
    if [ "$device_count" -eq 0 ]; then
        adb devices
        echo "No authorized adb device was found."
        exit 1
    fi
}

ensure_python3() {
    if ! command -v python3 >/dev/null 2>&1; then
        echo "python3 was not found. It is required for parsing the Universal Debloater Alliance list."
        exit 1
    fi
}

download_uad_list() {
    echo ">>> Updating Universal Debloater Alliance package list"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$UAD_LIST_URL" -o "$UAD_CACHE_FILE"
    else
        ensure_python3
        python3 - "$UAD_LIST_URL" "$UAD_CACHE_FILE" <<'PY'
import sys
import urllib.request

url, output = sys.argv[1], sys.argv[2]
with urllib.request.urlopen(url, timeout=30) as response:
    data = response.read()
with open(output, "wb") as file:
    file.write(data)
PY
    fi

    if [ ! -s "$UAD_CACHE_FILE" ]; then
        echo "Failed to download the package list."
        return 1
    fi

    echo "Saved: $UAD_CACHE_FILE"
}

ensure_uad_list() {
    ensure_python3
    if [ ! -s "$UAD_CACHE_FILE" ]; then
        download_uad_list
    fi
}

write_installed_packages() {
    local output_file="$1"
    adb_shell pm list packages --user "$USER_ID" |
        sed 's/^package://' |
        tr -d '\r' |
        sort -u > "$output_file"
}

create_debloat_plan() {
    local recommendation="$1"
    local output_file="$2"
    local installed_file
    installed_file=$(mktemp)
    write_installed_packages "$installed_file"
    ensure_uad_list

    python3 - "$UAD_CACHE_FILE" "$installed_file" "$recommendation" > "$output_file" <<'PY'
import json
import sys

uad_path, installed_path, recommendation = sys.argv[1], sys.argv[2], sys.argv[3].lower()

with open(installed_path, "r", encoding="utf-8") as file:
    installed = {line.strip() for line in file if line.strip()}

with open(uad_path, "r", encoding="utf-8") as file:
    data = json.load(file)

rows = []
for package_name, info in data.items():
    if package_name not in installed:
        continue
    if str(info.get("removal", "")).lower() != recommendation:
        continue
    description = " ".join(str(info.get("description", "")).split())
    rows.append((package_name, description))

for package_name, description in sorted(rows):
    print(f"{package_name}\t{description}")
PY
    rm -f "$installed_file"
}

list_debloat_packages() {
    local recommendation="$1"
    local plan_file
    plan_file=$(mktemp)
    create_debloat_plan "$recommendation" "$plan_file"

    local count
    count=$(wc -l < "$plan_file" | tr -d ' ')
    echo ">>> Installed $recommendation packages found: $count"
    if [ "$count" -gt 0 ]; then
        awk -F '\t' '{ printf "- %s\n  %s\n", $1, $2 }' "$plan_file"
    fi
    rm -f "$plan_file"
}

remove_debloat_packages() {
    local recommendation="$1"
    local plan_file
    plan_file=$(mktemp)
    create_debloat_plan "$recommendation" "$plan_file"

    local count
    count=$(wc -l < "$plan_file" | tr -d ' ')
    if [ "$count" -eq 0 ]; then
        echo "No installed $recommendation packages were found."
        rm -f "$plan_file"
        return
    fi

    echo "Found $count installed $recommendation packages."
    awk -F '\t' '{ printf "- %s\n", $1 }' "$plan_file"
    echo
    if [ "$recommendation" != "recommended" ]; then
        echo "Warning: $recommendation packages can break device features."
    fi
    printf "Remove these packages for user %s? Type YES to continue: " "$USER_ID"
    read -r confirmation
    if [ "$confirmation" != "YES" ]; then
        echo "Cancelled."
        rm -f "$plan_file"
        return
    fi

    touch "$DEBLOAT_HISTORY_FILE"
    while IFS=$'\t' read -r package_name _description; do
        if run_cmd pm uninstall --user "$USER_ID" "$package_name"; then
            if ! grep -qx "$package_name" "$DEBLOAT_HISTORY_FILE"; then
                echo "$package_name" >> "$DEBLOAT_HISTORY_FILE"
            fi
        fi
    done < "$plan_file"
    sort -u "$DEBLOAT_HISTORY_FILE" -o "$DEBLOAT_HISTORY_FILE"
    rm -f "$plan_file"
}

restore_debloat_history() {
    if [ ! -s "$DEBLOAT_HISTORY_FILE" ]; then
        echo "No debloat history was found at $DEBLOAT_HISTORY_FILE."
        return
    fi

    echo "Packages recorded in debloat history:"
    sed 's/^/- /' "$DEBLOAT_HISTORY_FILE"
    echo
    printf "Restore these packages for user %s? Type YES to continue: " "$USER_ID"
    read -r confirmation
    if [ "$confirmation" != "YES" ]; then
        echo "Cancelled."
        return
    fi

    while IFS= read -r package_name; do
        [ -z "$package_name" ] && continue
        run_cmd cmd package install-existing --user "$USER_ID" "$package_name" ||
            run_cmd pm install-existing --user "$USER_ID" "$package_name"
    done < "$DEBLOAT_HISTORY_FILE"
}

set_powerkeeper() {
    local restricted="$1"
    local mode="allow"
    local label="Restoring PowerKeeper permissions"
    if [ "$restricted" = "on" ]; then
        mode="deny"
        label="Restricting PowerKeeper"
    fi

    echo ">>> $label"
    for op in "${POWERKEEPER_OPS[@]}"; do
        run_cmd appops set com.miui.powerkeeper "$op" "$mode"
    done
}

set_phantom_processes() {
    local enabled="$1"
    local limit="${2:-512}"
    if [ "$enabled" = "on" ]; then
        echo ">>> Setting phantom process limit to $limit"
        run_cmd device_config put activity_manager max_phantom_processes "$limit"
    else
        echo ">>> Removing custom phantom process limit"
        run_cmd device_config delete activity_manager max_phantom_processes
    fi
}

set_doze_optimization() {
    local optimized="$1"
    local prefix="+"
    local label="Restoring Doze whitelist entries"
    if [ "$optimized" = "on" ]; then
        prefix="-"
        label="Optimizing Doze whitelist"
    fi

    echo ">>> $label"
    for package_name in "${DOZE_PACKAGES[@]}"; do
        run_cmd cmd deviceidle whitelist "$prefix$package_name" ||
            run_cmd dumpsys deviceidle whitelist "$prefix$package_name"
    done
}

set_gms_standby() {
    local restricted="$1"
    local bucket="active"
    local label="Setting GMS standby bucket to Active"
    if [ "$restricted" = "on" ]; then
        bucket="40"
        label="Setting GMS standby bucket to Rare"
    fi

    echo ">>> $label"
    for package_name in "${GMS_PACKAGES[@]}"; do
        if [ "$restricted" = "on" ]; then
            run_cmd cmd deviceidle whitelist "-$package_name" ||
                run_cmd dumpsys deviceidle whitelist "-$package_name"
        fi

        run_cmd am set-standby-bucket --user "$USER_ID" "$package_name" "$bucket" ||
            run_cmd am set-standby-bucket "$package_name" "$bucket"

        if [ "$restricted" = "off" ]; then
            run_cmd cmd deviceidle whitelist "+$package_name" ||
                run_cmd dumpsys deviceidle whitelist "+$package_name"
        fi
    done

    echo
    echo "Result:"
    print_gms_bucket com.google.android.gms
    print_gms_bucket com.google.android.gsf
    if [ "$restricted" = "on" ]; then
        echo "Note: 5=EXEMPTED, 10=ACTIVE, 40=RARE. If the value returns to 5/10, your ROM is promoting GMS automatically."
    fi
}

set_force_120hz() {
    local forced="$1"
    if [ "$forced" = "on" ]; then
        echo ">>> Forcing 120Hz"
        run_cmd settings put system min_refresh_rate 0
        run_cmd settings put system peak_refresh_rate 120
        run_cmd settings put system user_refresh_rate 1
    else
        echo ">>> Restoring default/dynamic refresh behavior"
        run_cmd settings put system min_refresh_rate 60
        run_cmd settings put system peak_refresh_rate 120
        run_cmd settings delete system user_refresh_rate
    fi
}

set_telemetry() {
    local frozen="$1"
    if [ "$frozen" = "on" ]; then
        echo ">>> Disabling telemetry/ad packages"
        for package_name in "${TELEMETRY_PACKAGES[@]}"; do
            run_cmd pm disable-user --user "$USER_ID" "$package_name"
        done
    else
        echo ">>> Re-enabling telemetry/ad packages"
        for package_name in "${TELEMETRY_PACKAGES[@]}"; do
            run_cmd pm enable "$package_name"
        done
    fi
}

set_poco_stacked_recents() {
    local enabled="$1"
    if [ "$enabled" = "on" ]; then
        echo ">>> Enabling System/POCO Launcher stacked recents"
        echo "An up-to-date System Launcher or POCO Launcher is recommended. Known POCO guide version: RELEASE-6.01.05.1993-02021709"
        run_cmd settings put global task_stack_view_layout_style 2
    else
        echo ">>> Restoring default System/POCO Launcher recents layout"
        run_cmd settings delete global task_stack_view_layout_style
    fi
}

set_wifi_multicast_fix() {
    local enabled="$1"
    if [ "$enabled" = "on" ]; then
        echo ">>> Removing optional cross-device connectivity packages"
        echo "This may disable Xiaomi casting, Mi Share, continuity, and related ecosystem features."
        for package_name in "${MULTICAST_PACKAGES[@]}"; do
            run_cmd pm uninstall --user "$USER_ID" "$package_name" ||
                run_cmd pm disable-user --user "$USER_ID" "$package_name"
        done
    else
        echo ">>> Restoring optional cross-device connectivity packages when available"
        for package_name in "${MULTICAST_PACKAGES[@]}"; do
            run_cmd cmd package install-existing --user "$USER_ID" "$package_name" ||
                run_cmd pm enable "$package_name"
        done
    fi
}

open_hidden_performance_menu() {
    echo ">>> Opening hidden performance menu"
    run_cmd am start -n com.android.settings/com.android.settings.fuelgauge.PowerModeSettings
}

apply_performance_preset() {
    echo ">>> Applying Performance preset"
    set_phantom_processes on 512
    set_force_120hz on
    set_powerkeeper on
    set_telemetry on
    echo ">>> Done. Rebooting may be required for some changes."
}

apply_full_optimization_preset() {
    echo ">>> Applying Full Optimization preset"
    set_phantom_processes on 512
    set_force_120hz on
    set_powerkeeper on
    set_doze_optimization on
    set_gms_standby on
    set_telemetry on
    set_poco_stacked_recents on
    set_wifi_multicast_fix on
    echo ">>> Done. Rebooting is recommended."
}

apply_full_optimization_with_recommended_debloat_preset() {
    echo ">>> Applying Full Optimization + Recommended Debloat preset"
    apply_full_optimization_preset
    echo
    echo ">>> Starting Recommended debloat flow"
    remove_debloat_packages recommended
    echo ">>> Done. Rebooting is recommended."
}

apply_balanced_preset() {
    echo ">>> Applying Balanced preset"
    set_phantom_processes on 128
    set_force_120hz off
    set_powerkeeper off
    set_telemetry on
    echo ">>> Done. Rebooting may be required for some changes."
}

apply_battery_preset() {
    echo ">>> Applying Battery preset"
    set_doze_optimization on
    set_gms_standby on
    set_force_120hz off
    set_powerkeeper off
    set_telemetry on
    echo ">>> Done. Rebooting may be required for some changes."
}

apply_gaming_preset() {
    echo ">>> Applying Gaming preset"
    set_phantom_processes on 1024
    set_powerkeeper on
    set_force_120hz on
    set_telemetry on
    echo ">>> Done. Rebooting may be required for some changes."
}

apply_stock_preset() {
    echo ">>> Restoring stock/default settings"
    set_powerkeeper off
    set_phantom_processes off
    set_doze_optimization off
    set_gms_standby off
    set_force_120hz off
    set_telemetry off
    set_poco_stacked_recents off
    set_wifi_multicast_fix off
    echo ">>> Done. A reboot is recommended."
}

bucket_label() {
    case "$1" in
        5) echo "EXEMPTED" ;;
        10) echo "ACTIVE" ;;
        20) echo "WORKING_SET" ;;
        30) echo "FREQUENT" ;;
        40) echo "RARE" ;;
        45) echo "RESTRICTED" ;;
        50) echo "NEVER" ;;
        *) echo "UNKNOWN" ;;
    esac
}

print_gms_bucket() {
    local package_name="$1"
    local value
    value=$(adb_shell am get-standby-bucket --user "$USER_ID" "$package_name" 2>/dev/null ||
        adb_shell am get-standby-bucket "$package_name" 2>/dev/null)
    value=$(echo "$value" | tr -d '\r' | tail -n 1)
    echo "$package_name: $value ($(bucket_label "$value"))"
}

show_status() {
    echo ">>> Current status"
    echo
    echo "[PowerKeeper AppOps]"
    for op in "${POWERKEEPER_OPS[@]}"; do
        adb_shell appops get com.miui.powerkeeper "$op"
    done
    echo
    echo "[Phantom process limit]"
    adb_shell device_config get activity_manager max_phantom_processes
    echo
    echo "[Doze whitelist]"
    adb_shell cmd deviceidle whitelist | grep -E 'com.facebook.services|com.facebook.appmanager|com.google.android.gms|com.google.android.gsf' || true
    echo
    echo "[GMS standby]"
    print_gms_bucket com.google.android.gms
    print_gms_bucket com.google.android.gsf
    echo
    echo "[Refresh rate]"
    echo "min_refresh_rate=$(adb_shell settings get system min_refresh_rate)"
    echo "peak_refresh_rate=$(adb_shell settings get system peak_refresh_rate)"
    echo "user_refresh_rate=$(adb_shell settings get system user_refresh_rate)"
    echo
    echo "[System/POCO Launcher stacked recents]"
    echo "task_stack_view_layout_style=$(adb_shell settings get global task_stack_view_layout_style)"
    echo
    echo "[Disabled telemetry packages]"
    adb_shell pm list packages -d --user "$USER_ID" | grep -E 'com.miui.msa.global|com.miui.daemon' || true
    echo
    echo "[Wi-Fi multicast fix packages]"
    for package_name in "${MULTICAST_PACKAGES[@]}"; do
        if adb_shell pm list packages --user "$USER_ID" "$package_name" | grep -q "$package_name"; then
            echo "$package_name: installed"
        else
            echo "$package_name: removed or unavailable"
        fi
    done
}

ask_on_off() {
    local title="$1"
    local callback="$2"
    echo
    echo "$title"
    echo "1) Enable"
    echo "2) Disable / restore"
    echo "0) Back"
    printf "Select: "
    read -r choice
    case "$choice" in
        1) "$callback" on ;;
        2) "$callback" off ;;
        0) return ;;
        *) echo "Invalid selection." ;;
    esac
}

show_canta_debloat_menu() {
    while true; do
        clear
        cat <<'EOF'
Canta-style Debloat Menu

This menu uses the Universal Debloater Alliance list, similar to Canta.
Only packages installed for the current Android user are shown or removed.

1) Update package recommendation list
2) List installed Recommended packages
3) Remove installed Recommended packages
4) List installed Advanced packages
5) Remove installed Advanced packages
6) List installed Expert packages
7) Remove installed Expert packages
8) List installed Unsafe packages
9) Remove installed Unsafe packages
10) Restore packages removed by this tool
0) Back

Recommendation levels:
  Recommended: safest target; usually pointless or replaceable packages.
  Advanced: can break minor or device-specific features.
  Expert: can break important features.
  Unsafe: can break vital OS functionality. Avoid unless you know exactly why.
EOF
        printf "Select: "
        read -r choice
        case "$choice" in
            1) download_uad_list; pause ;;
            2) list_debloat_packages recommended; pause ;;
            3) remove_debloat_packages recommended; pause ;;
            4) list_debloat_packages advanced; pause ;;
            5) remove_debloat_packages advanced; pause ;;
            6) list_debloat_packages expert; pause ;;
            7) remove_debloat_packages expert; pause ;;
            8) list_debloat_packages unsafe; pause ;;
            9) remove_debloat_packages unsafe; pause ;;
            10) restore_debloat_history; pause ;;
            0) return ;;
            *) echo "Invalid selection."; pause ;;
        esac
    done
}

show_menu() {
    while true; do
        clear
        cat <<'EOF'
HyperOS Optimizer ADB Script

Presets
1) Full Optimization preset
   All optimization settings managed by this tool, without app debloat.
2) Full Optimization + Recommended Debloat preset
   Full Optimization, then Canta-style Recommended package removal.
3) Performance preset
   Phantom 512 + Force 120Hz + restrict PowerKeeper + disable telemetry.
4) Balanced preset
   Phantom 128 + default refresh + restore PowerKeeper + disable telemetry.
5) Battery preset
   Optimize Doze + attempt GMS Rare + default refresh + disable telemetry.
6) Gaming preset
   Phantom 1024 + restrict PowerKeeper + Force 120Hz + disable telemetry.
7) Restore stock/default settings
   Reverts all settings managed by this script where possible.

Individual options
8) PowerKeeper
   Reduces Xiaomi background app killing by changing PowerKeeper AppOps.
9) Phantom process limit
   Raises/removes Android's background process limit for multitasking.
10) Doze whitelist optimization
   Removes/restores Facebook service packages in the Doze whitelist.
11) GMS standby bucket
   Attempts to move Google Play Services/GSF between Rare and Active.
12) Force 120Hz
   Forces or restores system refresh-rate settings.
13) Telemetry packages
   Disables or re-enables common MIUI analytics/ad packages.
14) System/POCO Launcher stacked recents
   Enables/restores the stacked recent apps layout on supported launchers.
15) Wi-Fi multicast battery fix
   Removes/restores connectivity packages that may cause multicast wakelocks.
16) Open hidden performance menu
   Opens the ROM's hidden battery/performance activity when available.
17) Show current status
   Prints the values managed by this script.
18) Canta-style debloat
   Lists/removes installed packages by UAD recommendation level.
19) Feature guide
   Shows detailed explanations and trade-offs.
0) Exit
EOF
        printf "Select: "
        read -r choice
        case "$choice" in
            1) apply_full_optimization_preset; pause ;;
            2) apply_full_optimization_with_recommended_debloat_preset; pause ;;
            3) apply_performance_preset; pause ;;
            4) apply_balanced_preset; pause ;;
            5) apply_battery_preset; pause ;;
            6) apply_gaming_preset; pause ;;
            7) apply_stock_preset; pause ;;
            8) ask_on_off "PowerKeeper" set_powerkeeper; pause ;;
            9) ask_on_off "Phantom process limit" set_phantom_processes; pause ;;
            10) ask_on_off "Doze whitelist optimization" set_doze_optimization; pause ;;
            11) ask_on_off "GMS standby bucket" set_gms_standby; pause ;;
            12) ask_on_off "Force 120Hz" set_force_120hz; pause ;;
            13) ask_on_off "Telemetry packages" set_telemetry; pause ;;
            14) ask_on_off "System/POCO Launcher stacked recents" set_poco_stacked_recents; pause ;;
            15) ask_on_off "Wi-Fi multicast battery fix" set_wifi_multicast_fix; pause ;;
            16) open_hidden_performance_menu; pause ;;
            17) show_status; pause ;;
            18) show_canta_debloat_menu ;;
            19) show_feature_help; pause ;;
            0) exit 0 ;;
            *) echo "Invalid selection."; pause ;;
        esac
    done
}

case "${1:-menu}" in
    -h|--help|help)
        print_usage
        ;;
    explain)
        show_feature_help
        ;;
    update-list)
        download_uad_list
        ;;
    *)
        check_device
        case "${1:-menu}" in
            menu) show_menu ;;
            full) apply_full_optimization_preset ;;
            full-debloat) apply_full_optimization_with_recommended_debloat_preset ;;
            on) apply_performance_preset ;;
            off) apply_stock_preset ;;
            status) show_status ;;
            debloat) show_canta_debloat_menu ;;
            list-recommended) list_debloat_packages recommended ;;
            remove-recommended) remove_debloat_packages recommended ;;
            restore-debloat) restore_debloat_history ;;
            *)
                echo "Invalid argument: $1"
                print_usage
                exit 1
                ;;
        esac
        ;;
esac
