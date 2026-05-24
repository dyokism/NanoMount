#!/bin/sh
# shellcheck disable=SC1091
# nanomount - service.sh
# late boot: update status, reset anti-bootloop

MODDIR="/data/adb/modules/nanomount"
PERSISTENT="/data/adb/nanomount"
LOGDIR="/dev/nanomount"
PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH

# load config
nano_mounts=2
[ -f "$PERSISTENT/config.sh" ] && . "$PERSISTENT/config.sh"

# update module description with status
case $nano_mounts in
    1) mode="manual" ;;
    2) mode="auto" ;;
    *) mode="disabled" ;;
esac

desc="description=mode: $mode | fstype: tmpfs"
if [ -f "$LOGDIR/modules" ]; then
    module_list=""
    while IFS= read -r mod; do
        module_list="$module_list $mod"
    done < "$LOGDIR/modules"
    desc="$desc | modules:$module_list"
else
    desc="$desc | no modules mounted"
fi
sed -i "s/^description=.*/$desc/" "$MODDIR/module.prop"

# wait for boot completion, then reset anti-bootloop
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 1
done

echo 0 > "$PERSISTENT/rapid_boots"
date +%s > "$PERSISTENT/last_boot_ts"

# cleanup
rm -f "/dev/nanomount_lock"
[ -d "$LOGDIR" ] && rm -rf "$LOGDIR"
