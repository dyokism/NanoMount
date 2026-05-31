#!/bin/sh
# shellcheck disable=SC2034
# nanomount configuration
# edit this file at /data/adb/nanomount/config.sh

# mode: 0=disabled, 1=manual, 2=auto
nano_mounts=2

# mount folder name for stealth
FAKE_MOUNT_NAME="my_preload"

# overlay device name in mounts
MOUNT_DEVICE_NAME="overlay"
