# MemWatch

**English** | [Русский](README.ru.md)

A small macOS menu bar app that warns you before memory pressure freezes your Mac.

<!-- screenshot: docs/screenshot.png -->

## Why

When memory runs out, macOS slows down and can freeze. Activity Monitor shows you
the problem only after it happened. MemWatch sits in the menu bar, turns yellow and
red early, sends a notification, and shows which apps use the most memory.

## Features

- Menu bar text `MEM NN%`. NN is `100 - kern.memorystatus_level`. It is the kernel's own view of how full memory is. It is not the same as "Memory Used" in Activity Monitor.
- Two warning levels: yellow (warning) and red (critical).
- A notification when the level goes up.
- A menu with memory numbers, the top 10 apps (helper processes are added to their app) and the top 5 single processes.
- Launch at login.
- A JSON log of level changes and top memory users.
- No Dock icon. No extra packages.

## Requirements

- macOS 14 (Sonoma) or newer.
- Swift 6 toolchain (Xcode 16 or newer, or matching Command Line Tools).

## Download

MemWatch is not in an app store. You can download a ready app from GitHub Releases:

1. Open [Releases](https://github.com/Toloymak/MemWatch/releases) and download `MemWatch-<version>.zip`.
2. Unzip it.
3. Move `MemWatch.app` to `/Applications` (or `~/Applications`).

The app is signed ad-hoc and is not notarized, so macOS Gatekeeper blocks the first
launch. To open it, right-click `MemWatch.app` and choose Open, then click Open again.
Or remove the quarantine flag in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/MemWatch.app
```

The app is universal: it runs on Apple silicon and Intel Macs.

## Install

To build it yourself from source:

```bash
git clone https://github.com/Toloymak/MemWatch.git
cd MemWatch
Scripts/bundle.sh
open ~/Applications/MemWatch.app
```

`Scripts/bundle.sh` builds the release binary, makes `build/MemWatch.app`, signs it
ad-hoc, and copies it to `~/Applications/MemWatch.app`. If MemWatch is already running,
the script asks it to quit first.

To build only, without an app bundle: `swift build -c release`.

To make `build/MemWatch.app` without quitting or replacing the installed app, run
`Scripts/bundle.sh --no-install` (or set `MEMWATCH_NO_INSTALL=1`). To set the app
version, set `MEMWATCH_VERSION`, for example `MEMWATCH_VERSION=0.2.0 Scripts/bundle.sh`.
The default is `0.1.0`.

First run:

- macOS asks for notification permission. Click Allow. You can change it later in
  System Settings > Notifications > MemWatch.
- To start MemWatch at login, open its menu and turn on "Launch at Login".

## Usage

### Menu bar

| State | What you see |
|---|---|
| Normal | `MEM 52%` in the normal menu bar color |
| Warning | a yellow dot before the text: `● MEM 72%` |
| Critical | the whole text is red and bold |

### Menu

- Level, with the reason when it is not normal.
- Kernel pressure, free level, App / Wired / Compressed / Cached files, Used of total RAM.
- Swap used and total, swap growth, swapouts and compressed growth.
- Top apps and top processes. Click one to open Activity Monitor.
- Open Activity Monitor, Notifications on/off, Launch at Login, Send Test Notification, Quit.

### Command line flags

Run these from the binary: `.build/release/MemWatch` or
`~/Applications/MemWatch.app/Contents/MacOS/MemWatch`.

| Flag | What it does |
|---|---|
| `--status` | Takes two samples 2 seconds apart, prints the numbers, level and top apps, then exits. |
| `--test-notify` | Sends one test notification and waits up to 20 seconds for the result. |
| `--login-item status\|on\|off` | Shows, enables or disables launch at login. Default is `status`. |

Run `--test-notify` and `--login-item` from the binary inside the `.app`, because they
need the bundle id `local.memwatch`.

Example `--status` output (made-up numbers):

```
MemWatch status  2026-01-15T10:30:00Z
Level:         NORMAL  (raw, no hysteresis)
Pressure:      1 (normal)   kern.memorystatus_vm_pressure_level
Free level:    48%   kern.memorystatus_level
RAM:           16.0 GB, page size 16384
App memory:    6.1 GB
Wired:         2.3 GB
Compressed:    1.4 GB  (holds 3.2 GB of data)
Cached files:  4.0 GB
Memory used:   9.8 GB  (App + Wired + Compressed)
Swap:          used 1.2 GB / total 3.0 GB, free 1.8 GB
Processes:     612 pids, 540 read, 72 not allowed (root, EPERM)
Top apps:
   1. Google Chrome                              3.1 GB  (24 procs)
   2. Xcode                                      2.4 GB  (6 procs)
   3. Docker                                     1.8 GB  (4 procs)
   4. Slack                                      0.9 GB  (7 procs)
Top processes:
   1. Google Chrome Helper (Renderer)            0.8 GB  pid 4121
   2. Xcode                                      0.7 GB  pid 3010
```

Some lines are shortened here.

## How levels work

The level follows the number in the menu bar, `NN = 100 - kern.memorystatus_level`.

- **Critical** (red): `NN >= 80`, or the kernel pressure level is 4.
- **Warning** (yellow): `NN >= 70`.
- **Normal**: everything else.

Swap, swapouts and compressed memory rates are shown in the menu and in `--status`.
They do not change the level.

Going up is instant. Going down needs 2 lower samples in a row (at least 5 seconds).

Notifications are sent when the level goes up:

- Warning: at most once per 15 minutes.
- Critical: at most once per 3 minutes. It repeats every 3 minutes while memory stays critical, and it plays a sound.
- You can turn notifications off in the menu.

To change the limits, edit `Thresholds.warningUsedPercent` and
`Thresholds.criticalUsedPercent` in `Sources/MemWatch/LevelEvaluator.swift`
(the cooldowns are in the same place). Then run `Scripts/bundle.sh` again.

### How notifications are sent

1. `UNUserNotificationCenter`, when you allowed it in System Settings > Notifications > MemWatch.
2. If not allowed, or if it fails, MemWatch uses `osascript display notification`. macOS shows these as coming from "Script Editor". If you turned off notifications for Script Editor, you will not see them.

### Launch at login

The menu item uses `SMAppService.mainApp`. If that fails, MemWatch writes a LaunchAgent
(`~/Library/LaunchAgents/local.memwatch.plist`) that opens the app.

## How memory numbers are computed

MemWatch samples every 3 seconds, and right away on a kernel memory pressure event.

- Pressure level and free level: `sysctl kern.memorystatus_vm_pressure_level` and `kern.memorystatus_level`.
- App, Wired, Compressed and Cached files: `host_statistics64` (`internal_page_count - purgeable_count`, `wire_count`, `compressor_page_count`, `external_page_count + purgeable_count`).
- Swap: `sysctl vm.swapusage`.
- Top consumers: `proc_pid_rusage`, field `ri_phys_footprint`, for each process. This is the "Memory" column in Activity Monitor.
- Grouping: processes are grouped by the first `.app` in the executable path, so "Google Chrome Helper (Renderer)" counts as "Google Chrome". Other processes use their file name.

## Limits / known issues

- Processes owned by root (and `kernel_task`, `WindowServer`) are not readable without sudo (`EPERM`). They are skipped and counted as "not allowed". `sudo .build/release/MemWatch --status` can read them.
- `phys_footprint` is not RSS. It includes compressed and swapped pages, so it matches Activity Monitor, not `ps`. The sum can be larger than RAM.
- Docker's VM shows as `com.apple.Virtualization.VirtualMachine`, because it runs from a system framework path, not from `Docker.app`.
- macOS adds swap files when needed, so "swap free" can drop and come back.
- The app is signed ad-hoc, not notarized.

Log file: `~/Library/Logs/MemWatch.log`. It has JSON lines and rotates at 5 MB.

## Uninstall

1. Quit MemWatch from its menu.
2. Turn off "Launch at Login" in the menu first (or run `MemWatch --login-item off`).
3. Delete `~/Applications/MemWatch.app`.
4. Delete `~/Library/Logs/MemWatch.log`.
5. If it exists, delete `~/Library/LaunchAgents/local.memwatch.plist`.

## Releasing

Releases are made by GitHub Actions (`.github/workflows/release.yml`). To cut a release,
push a version tag:

```bash
git tag v0.2.0 && git push origin v0.2.0
```

The workflow builds the app, zips it, and creates a GitHub Release with the zip and
its `.sha256` file. A tag with `-` in it, like `v0.2.0-beta.1`, makes a prerelease.
You can also start the workflow by hand from the Actions tab. That only builds the zip
and keeps it as a workflow artifact. It does not make a release.

## License

MIT. See [LICENSE](LICENSE).
