[English](README.md) | [Bahasa Indonesia](README.id.md)

# NanoMount

**A professional, ultra-lightweight OverlayFS module to globally mount system modifications on modern Android devices.**

![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Android](https://img.shields.io/badge/Android-10.0%2B-green.svg)
![Version](https://img.shields.io/badge/Version-1.1-orange.svg)
![Root](https://img.shields.io/badge/Root-Magisk%20%7C%20KernelSU%20%7C%20APatch-red.svg)

## Overview

NanoMount is a high-performance root module designed to replace traditional bind mounts with a unified, lightweight OverlayFS system. It aggregates all active module modifications into a memory-backed staging area (`tmpfs`) and overlays them cleanly onto `/system`, `/vendor`, `/product`, and other dynamic partitions in a single unified step.

---

## Why Use NanoMount?

- **Stealth & Bypass**: Stages modifications under stock OEM-like paths (e.g., `/mnt/my_preload` or `/dev/my_preload`) to hide active mounts, making it highly effective **to open mobile banking apps and bypass other root detection mechanisms**.
- **Zero Disk Overhead**: Operates purely in-memory (`tmpfs`), eliminating heavy ext4 loop-mount images and potential filesystem corruption.
- **Instant Boot Times**: Avoids slow, file-by-file `chcon` loops during boot using smart, single-file SELinux context preservation sampling.
- **Universal Compatibility**: Works seamlessly across Magisk, KernelSU, and APatch on modern Android 10+ devices.

---

## Requirements

| Requirement | Details |
|-------------|---------|
| Android | 10.0+ (API 29+) |
| Kernel | `CONFIG_OVERLAY_FS=y` & `tmpfs` `security.selinux` xattr support |
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
        A[Flash Module ZIP] --> B{Check CONFIG_OVERLAY_FS?}
        B -- No --> ABORT1[Abort: OverlayFS Required]
        B -- Yes --> C{Check tmpfs SELinux?}
        C -- No --> ABORT2[Abort: Kernel Incompatible]
        C -- Yes --> D{Check tmpfs Trusted xattr?}
        D -- Yes --> E[Install: Full Feature Mode]
        D -- No --> F[Install: Pure tmpfs Mode]
        E & F --> G[Setup Config & Complete]
    end

    %% Early Boot Phase
    subgraph Early_Boot ["2. Early Boot (post-fs-data.sh)"]
        G --> H[Device Reboots]
        H --> I[Start 60s Watchdog & Check Anti-Bootloop]
        I --> M[Create tmpfs Staging Area]
        M --> N[Process Active Modules]
        N --> O[Copy Files & Apply SELinux Contexts]
        O --> P[Touch skip_mount for Modules]
        P --> Q[Execute mount -t overlay]
        Q --> R[Lazy Umount Staging Area]
        R --> S[Stop Watchdog]
    end

    %% Late Boot Phase
    subgraph Late_Boot ["3. Late Boot (service.sh)"]
        S --> T[Android UI Loaded]
        T --> U[Update module.prop Description]
        U --> V[Wait for sys.boot_completed=1]
        V --> W[Reset Anti-Bootloop Counters & Cleanup Logs]
        W --> X[Finished & Running Smoothly]
    end

    %% Custom Styles (Transparent background & borderless design)
    style Installation fill:none,stroke:none
    style Early_Boot fill:none,stroke:none
    style Late_Boot fill:none,stroke:none

    classDef default fill:none,stroke:#9ca3af,stroke-width:1px;
    classDef abort fill:#fee2e2,stroke:#ef4444,stroke-width:1.5px,color:#991b1b;
    classDef success fill:#d1fae5,stroke:#10b981,stroke-width:1.5px,color:#065f46;
    classDef check fill:none,stroke:#f59e0b,stroke-width:1.5px;

    class ABORT1,ABORT2 abort;
    class E,F,X success;
    class B,C,D check;
```

---

## Developer & License

- **Developer**: [dyokism](https://github.com/dyokism)
- **License**: MIT

