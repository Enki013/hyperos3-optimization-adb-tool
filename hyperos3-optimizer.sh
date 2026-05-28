#!/usr/bin/env bash

set -u

USER_ID=0
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
  ./hyperos3-optimizer.sh on         Apply the Performance preset
  ./hyperos3-optimizer.sh off        Restore stock/default settings
  ./hyperos3-optimizer.sh status     Print current managed setting values
  ./hyperos3-optimizer.sh explain    Show detailed feature descriptions
  ./hyperos3-optimizer.sh help       Show this help message

Requirements:
  - Android platform-tools / adb installed
  - USB debugging enabled
  - One authorized device connected with adb

All actions use standard adb shell commands and can be reverted from the menu.
EOF
}

show_feature_help() {
    cat <<'EOF'
Feature Guide

Presets
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
EOF
}

adb_shell() {
    adb shell "$@"
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
            run_cmd cmd package install-existing "$package_name" ||
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

show_menu() {
    while true; do
        clear
        cat <<'EOF'
HyperOS Optimizer ADB Script

Presets
1) Performance preset
   Phantom 512 + Force 120Hz + restrict PowerKeeper + disable telemetry.
2) Balanced preset
   Phantom 128 + default refresh + restore PowerKeeper + disable telemetry.
3) Battery preset
   Optimize Doze + attempt GMS Rare + default refresh + disable telemetry.
4) Gaming preset
   Phantom 1024 + restrict PowerKeeper + Force 120Hz + disable telemetry.
5) Restore stock/default settings
   Reverts all settings managed by this script where possible.

Individual options
6) PowerKeeper
   Reduces Xiaomi background app killing by changing PowerKeeper AppOps.
7) Phantom process limit
   Raises/removes Android's background process limit for multitasking.
8) Doze whitelist optimization
   Removes/restores Facebook service packages in the Doze whitelist.
9) GMS standby bucket
   Attempts to move Google Play Services/GSF between Rare and Active.
10) Force 120Hz
   Forces or restores system refresh-rate settings.
11) Telemetry packages
   Disables or re-enables common MIUI analytics/ad packages.
12) System/POCO Launcher stacked recents
   Enables/restores the stacked recent apps layout on supported launchers.
13) Wi-Fi multicast battery fix
   Removes/restores connectivity packages that may cause multicast wakelocks.
14) Open hidden performance menu
   Opens the ROM's hidden battery/performance activity when available.
15) Show current status
   Prints the values managed by this script.
16) Feature guide
   Shows detailed explanations and trade-offs.
0) Exit
EOF
        printf "Select: "
        read -r choice
        case "$choice" in
            1) apply_performance_preset; pause ;;
            2) apply_balanced_preset; pause ;;
            3) apply_battery_preset; pause ;;
            4) apply_gaming_preset; pause ;;
            5) apply_stock_preset; pause ;;
            6) ask_on_off "PowerKeeper" set_powerkeeper; pause ;;
            7) ask_on_off "Phantom process limit" set_phantom_processes; pause ;;
            8) ask_on_off "Doze whitelist optimization" set_doze_optimization; pause ;;
            9) ask_on_off "GMS standby bucket" set_gms_standby; pause ;;
            10) ask_on_off "Force 120Hz" set_force_120hz; pause ;;
            11) ask_on_off "Telemetry packages" set_telemetry; pause ;;
            12) ask_on_off "System/POCO Launcher stacked recents" set_poco_stacked_recents; pause ;;
            13) ask_on_off "Wi-Fi multicast battery fix" set_wifi_multicast_fix; pause ;;
            14) open_hidden_performance_menu; pause ;;
            15) show_status; pause ;;
            16) show_feature_help; pause ;;
            0) exit 0 ;;
            *) echo "Invalid selection."; pause ;;
        esac
    done
}

case "${1:-menu}" in
    -h|--help|help)
        print_usage
        ;;
    *)
        check_device
        case "${1:-menu}" in
            menu) show_menu ;;
            on) apply_performance_preset ;;
            off) apply_stock_preset ;;
            status) show_status ;;
            explain) show_feature_help ;;
            *)
                echo "Invalid argument: $1"
                print_usage
                exit 1
                ;;
        esac
        ;;
esac
