#!/system/bin/sh
# shellcheck disable=SC1091,SC2034
# nanomount - boot-completed.sh
# runs after sys.boot_completed signal (KernelSU / APatch)

PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH
MODDIR=${0%/*}
PERSISTENT="/data/adb/nanomount"
LOGDIR="/dev/nanomount"

# reset anti-bootloop markers
echo 0 > "$PERSISTENT/rapid_boots"
date +%s > "$PERSISTENT/last_boot_ts"

# cleanup single instance lock and logs
rm -f "/dev/nanomount_lock"
[ -d "$LOGDIR" ] && rm -rf "$LOGDIR"
