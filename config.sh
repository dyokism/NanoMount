#!/bin/sh
# shellcheck disable=SC2034
# nanomount configuration
# edit this file at /data/adb/nanomount/config.sh

# mode: 0=disabled, 1=manual (modules.txt), 2=auto (all modules with /system)
nano_mounts=2

# mount folder name (oem-like for stealth, samsung & oplus have this natively)
FAKE_MOUNT_NAME="my_preload"

# overlay device name shown in /proc/mounts
MOUNT_DEVICE_NAME="overlay"
