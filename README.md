# HyperOS 3 Optimization ADB Tool

An interactive ADB shell tool for applying and reverting selected HyperOS 3 optimization tweaks on Xiaomi, Redmi, and POCO devices.

The script is designed for users who want a clear menu, reversible actions, and readable explanations instead of copying individual ADB commands by hand.

## Features

- Interactive terminal menu
- Performance, Balanced, Battery, Gaming, and Stock/Default presets
- PowerKeeper AppOps control
- Phantom process limit control for multitasking
- Doze whitelist optimization for selected packages
- Google Play Services standby bucket attempt with readable bucket labels
- 120Hz refresh-rate toggle
- MIUI telemetry/ad package disable and restore
- System/POCO Launcher stacked recent apps toggle
- Optional Wi-Fi multicast wakelock battery fix
- Status screen for all managed settings
- Detailed feature guide built into the script

## Requirements

- macOS, Linux, or another Unix-like shell environment
- Android platform-tools with `adb` available in `PATH`
- USB debugging enabled on the phone
- One authorized Android device connected over ADB

Check your device connection:

```bash
adb devices
```

## Usage

Clone the repository:

```bash
git clone https://github.com/Enki013/hyperos3-optimization-adb-tool.git
cd hyperos3-optimization-adb-tool
chmod +x hyperos3-optimizer.sh
```

Open the interactive menu:

```bash
./hyperos3-optimizer.sh
```

Apply the Performance preset directly:

```bash
./hyperos3-optimizer.sh on
```

Restore stock/default settings:

```bash
./hyperos3-optimizer.sh off
```

Print current managed setting values:

```bash
./hyperos3-optimizer.sh status
```

Show detailed feature explanations:

```bash
./hyperos3-optimizer.sh explain
```

## Presets

### Performance

- Sets phantom process limit to `512`
- Forces 120Hz refresh-rate settings
- Restricts Xiaomi PowerKeeper AppOps
- Disables common MIUI telemetry/ad packages

### Balanced

- Sets phantom process limit to `128`
- Restores default/dynamic refresh-rate behavior
- Restores PowerKeeper permissions
- Disables common MIUI telemetry/ad packages

### Battery

- Removes selected Facebook service packages from the Doze whitelist
- Attempts to move Google Play Services and GSF to the Rare standby bucket
- Restores default/dynamic refresh-rate behavior
- Restores PowerKeeper permissions
- Disables common MIUI telemetry/ad packages

### Gaming

- Sets phantom process limit to `1024`
- Restricts Xiaomi PowerKeeper AppOps
- Forces 120Hz refresh-rate settings
- Disables common MIUI telemetry/ad packages

### Stock / Default

Attempts to revert all settings managed by this script:

- Restores PowerKeeper permissions
- Removes custom phantom process limit
- Restores Doze and GMS standby changes
- Restores default/dynamic refresh-rate behavior
- Re-enables telemetry packages
- Restores System/POCO Launcher recent apps layout setting
- Reinstalls optional Wi-Fi multicast packages when available

## Important Notes

### Google Play Services standby bucket

Some ROMs automatically promote Google Play Services back to `EXEMPTED` or `ACTIVE`.

Android standby bucket values:

- `5` = `EXEMPTED`
- `10` = `ACTIVE`
- `20` = `WORKING_SET`
- `30` = `FREQUENT`
- `40` = `RARE`
- `45` = `RESTRICTED`

If GMS returns to `5` or `10` after applying the Battery preset, your ROM is likely enforcing a system policy. Persistent enforcement may require root.

### Wi-Fi multicast battery fix

The Wi-Fi multicast fix removes optional Xiaomi/Microsoft cross-device connectivity packages that may cause Wi-Fi multicast wakelocks on some HyperOS builds.

You may lose features such as:

- Xiaomi casting
- Mi Share
- Cross-device clipboard
- Continuity / interconnectivity features

Use this option only if you are troubleshooting battery drain and understand the trade-off.

### System/POCO Launcher stacked recents

The stacked recent apps layout can work on supported System Launcher and POCO Launcher builds. An up-to-date launcher is recommended. The script only writes:

```bash
settings put global task_stack_view_layout_style 2
```

If your launcher does not support the feature, the setting may have no visible effect.

## Safety

This project uses ADB shell commands that modify system settings for the current user. Most actions are reversible from the menu, but device behavior can vary by ROM, region, launcher version, and HyperOS build.

Review the script before running it. Use at your own risk.

## References

- [HyperOS battery drain community guide](https://www.reddit.com/r/Xiaomi/comments/1qxo8vi/guide_fixed_severe_battery_drain_after_hyperos_3/)
- [System/POCO Launcher stacked recents community guide](https://www.reddit.com/r/PocoPhones/comments/1r20p9i/poco_launcher_new_update_stacked_recent_menu_how/)

## Disclaimer

This project is not affiliated with Xiaomi, Redmi, POCO, Google, or Microsoft.

