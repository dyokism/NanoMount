[English](README.md) | [Bahasa Indonesia](README.id.md)

# NanoMount

**A high-performance, ultra-lightweight OverlayFS module to globally mount system modifications on modern Android devices.**

![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Android](https://img.shields.io/badge/Android-10.0%2B-green.svg)
![Version](https://img.shields.io/badge/Version-1.2-orange.svg)
![Root](https://img.shields.io/badge/Root-Magisk%20%7C%20KernelSU%20%7C%20APatch-red.svg)

## Overview

NanoMount is an ultra-lightweight root module that replaces heavy, traditional bind mounts with a unified, high-performance OverlayFS system. It loads active module files into a temporary RAM staging area (`tmpfs`) and mounts them cleanly over partitions like `/system`, `/vendor`, and `/product` in a single, seamless step.

---

## Why Use NanoMount?

- **Stealth by Design**: Mounts files under hidden paths (like `/dev/my_preload`), easily bypassing banking apps and root detection.
- **Pure RAM Staging**: Operates entirely in memory (`tmpfs`). Zero disk overhead, no heavy ext4 loop images, and no storage wear.
- **Faster Boot**: Skips slow file-by-file SELinux (`chcon`) loops during startup by validating compatibility at install time.
- **Installation Guard**: Verifies kernel OverlayFS-on-tmpfs and SELinux support during installation, aborting safely to prevent bootloops.
- **Universal Compatibility**: Works out-of-the-box with Magisk, KernelSU, and APatch on Android 10+.

---

## Requirements

| Requirement | Details |
|-------------|---------|
| Android | 10.0+ (API 29+) |
| Kernel | `CONFIG_OVERLAY_FS=y`, `tmpfs` as valid OverlayFS lower filesystem, & `tmpfs` `security.selinux` xattr support |
| Root | Magisk, Magisk Alpha, KernelSU, or APatch |

---

## Installation & Configuration

1. Install the ZIP file via your root manager's **Modules** tab.
2. **Reboot** your device to activate.
3. Configure settings at: `/data/adb/nanomount/config.sh`

---

## How It Works

```mermaid
flowchart TD
    %% Installation Phase
    subgraph Installation ["1. Installation (customize.sh)"]
        FlashZip[Flash Module ZIP] --> CheckOverlay{Check CONFIG_OVERLAY_FS?}
        CheckOverlay -- No --> AbortOverlay[Abort: OverlayFS Required]
        CheckOverlay -- Yes --> CheckTmpfsBackend{Check Overlay on tmpfs?}
        CheckTmpfsBackend -- No --> AbortTmpfsBackend[Abort: tmpfs Backend Unsupported]
        CheckTmpfsBackend -- Yes --> CheckSELinux{Check tmpfs SELinux?}
        CheckSELinux -- No --> AbortSELinux[Abort: SELinux xattr Unsupported]
        CheckSELinux -- Yes --> CheckTrusted{Check tmpfs Trusted xattr?}
        CheckTrusted -- Yes --> FullMode[Install: Full Feature Mode]
        CheckTrusted -- No --> PureMode[Install: Pure tmpfs Mode]
        FullMode & PureMode --> ConfigSetup[Setup Config & Complete]
    end

    %% Early Boot Phase
    subgraph Early_Boot ["2. Early Boot (post-fs-data.sh)"]
        ConfigSetup --> BootStart[Device Reboots]
        BootStart --> WatchdogStart[Start 60s Watchdog & Check Anti-Bootloop]
        WatchdogStart --> StagingCreate[Create tmpfs Staging Area]
        StagingCreate --> ProcessModules[Process Active Modules]
        ProcessModules --> CopyFiles[Copy Files & Apply SELinux Contexts]
        CopyFiles --> SkipMount[Touch skip_mount for Modules]
        SkipMount --> MountOverlay[Mount Overlay at Partition Root Level]
        MountOverlay --> CleanStaging[Lazy Umount Staging Area]
        CleanStaging --> WatchdogStop[Stop Watchdog]
    end

    %% Late Boot Phase
    subgraph Late_Boot ["3. Late Boot (service.sh)"]
        WatchdogStop --> UILoaded[Android UI Loaded]
        UILoaded --> UpdateProp[Update module.prop Description]
        UpdateProp --> WaitBoot[Wait for sys.boot_completed=1]
        WaitBoot --> ResetAntiBoot[Reset Anti-Bootloop Counters & Cleanup Logs]
        ResetAntiBoot --> Finished[Finished & Running Smoothly]
    end

    %% Custom Styles
    style Installation fill:none,stroke:none
    style Early_Boot fill:none,stroke:none
    style Late_Boot fill:none,stroke:none

    classDef default fill:none,stroke:#9ca3af,stroke-width:1px;
    classDef abort fill:#fee2e2,stroke:#ef4444,stroke-width:1.5px,color:#991b1b;
    classDef success fill:#d1fae5,stroke:#10b981,stroke-width:1.5px,color:#065f46;
    classDef check fill:none,stroke:#f59e0b,stroke-width:1.5px;

    class AbortOverlay,AbortTmpfsBackend,AbortSELinux abort;
    class FullMode,PureMode,Finished success;
    class CheckOverlay,CheckTmpfsBackend,CheckSELinux,CheckTrusted check;
```

---

## Developer, Credits & License

- **Developer**: [dyokism](https://github.com/dyokism)
- **Special Thanks**: [bnsmb](https://github.com/bnsmb) for finding the kernel compatibility gap and helping structure the module installation check to be much stricter and cleaner.
- **License**: MIT

