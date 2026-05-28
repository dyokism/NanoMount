#!/system/bin/sh
# shellcheck disable=SC3043,SC2012,SC1091
# nanomount - post-fs-data.sh
# lightweight overlayfs mounting for modern android devices

MODDIR="/data/adb/modules/nanomount"
PERSISTENT="/data/adb/nanomount"
LOGDIR="/dev/nanomount"
TAG="nanomount"
PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH

# config defaults (overridden by config.sh)
nano_mounts=2
FAKE_MOUNT_NAME="my_preload"
MOUNT_DEVICE_NAME="overlay"

# load persistent config
[ -f "$PERSISTENT/config.sh" ] && . "$PERSISTENT/config.sh"

# exit immediately if disabled
[ "$nano_mounts" = 0 ] && exit 0

# single instance lock
LOCKFILE="/dev/nanomount_lock"
[ -f "$LOCKFILE" ] && exit 1
touch "$LOCKFILE"

# anti-bootloop: timestamp-based
LAST_BOOT=$(cat "$PERSISTENT/last_boot_ts" 2>/dev/null || echo 0)
NOW=$(date +%s)
DELTA=$((NOW - LAST_BOOT))

if [ "$DELTA" -lt 120 ] && [ "$LAST_BOOT" -ne 0 ]; then
    RAPID_BOOTS=$(($(cat "$PERSISTENT/rapid_boots" 2>/dev/null || echo 0) + 1))
    echo "$RAPID_BOOTS" > "$PERSISTENT/rapid_boots"
    if [ "$RAPID_BOOTS" -ge 2 ]; then
        touch "$MODDIR/disable"
        sed -i 's/^description=.*/description=Anti-bootloop triggered. Module disabled. Re-enable to activate./' "$MODDIR/module.prop"
        echo "$TAG: anti-bootloop triggered (rapid_boots=$RAPID_BOOTS)" >> /dev/kmsg
        rm -f "$LOCKFILE"
        exit 1
    fi
else
    echo 0 > "$PERSISTENT/rapid_boots"
fi
echo "$NOW" > "$PERSISTENT/last_boot_ts"

# watchdog: kill ourselves after 60s (safer for slow entry-level devices)
(sleep 60 && kill -9 $$ 2>/dev/null) &
WATCHDOG=$!

echo "$TAG: start" >> /dev/kmsg

# setup logging
mkdir -p "$LOGDIR"
cat /proc/mounts > "$LOGDIR/before"

# mount point: try /mnt first, fallback to /dev if not writable
MNT="/mnt"
if [ ! -w "$MNT" ]; then
    echo "$TAG: /mnt not writable, trying /dev" >> /dev/kmsg
    MNT="/dev"
    if [ ! -w "$MNT" ]; then
        echo "$TAG: /dev not writable, abort" >> /dev/kmsg
        kill $WATCHDOG 2>/dev/null
        rm -f "$LOCKFILE"
        exit 1
    fi
fi

STAGING="$MNT/$FAKE_MOUNT_NAME"

# safety: don't clobber existing real directories
if [ -d "$STAGING" ] && busybox mountpoint -q "$STAGING" 2>/dev/null; then
    echo "$TAG: $STAGING is already a mountpoint, abort" >> /dev/kmsg
    kill $WATCHDOG 2>/dev/null
    rm -f "$LOCKFILE"
    exit 1
fi

# overlay target partitions
# note: if fake_mount_name matches a target name, that target is skipped
# to avoid overlaying our own staging area
TARGETS="odm product system_ext vendor mi_ext my_bigball my_carrier my_company my_engineering my_heytap my_manifest my_preload my_product my_region my_reserve my_stock oem optics prism"

# getfattr helper
if /system/bin/getfattr -d /system/bin > /dev/null 2>&1; then
    getfattr() { /system/bin/getfattr "$@"; }
else
    getfattr() { /system/bin/toybox getfattr "$@"; }
fi

# functions

# mount overlay at /system root
mount_system() {
    busybox mount -t overlay -o "lowerdir=$STAGING:/system" \
        "$MOUNT_DEVICE_NAME" "/system" && \
        echo "/system" >> "$LOGDIR/mount_list" || \
        echo "$TAG: failed to mount /system" >> /dev/kmsg
}

# mount overlay at partition root
mount_partition() {
    local part="$1"
    local prefix="$2"

    [ -d "$STAGING/$part" ] || return
    busybox mount -t overlay -o "lowerdir=$STAGING/$part:$prefix$part" \
        "$MOUNT_DEVICE_NAME" "$prefix$part" && \
        echo "$prefix$part" >> "$LOGDIR/mount_list" || \
        echo "$TAG: failed to mount $prefix$part" >> /dev/kmsg
}

# process a single module: validate, copy, preserve selinux + opaques
process_module() {
    local MODULE_ID="$1"
    local MDIR="/data/adb/modules/$MODULE_ID"
    local SYSDIR="$MDIR/system"

    # skip: no /system, disabled, pending removal, skip flag, hosts-only
    [ -d "$SYSDIR" ] || return
    [ -f "$MDIR/disable" ] && return
    [ -f "$MDIR/remove" ] && return
    [ -f "$MDIR/skip_nanomount" ] && return
    [ -f "$SYSDIR/etc/hosts" ] && [ "$(find "$SYSDIR" -not -path "$SYSDIR/etc/hosts" -not -path "$SYSDIR/etc" -not -path "$SYSDIR" | head -1)" = "" ] && return

    echo "$TAG: processing $MODULE_ID" >> /dev/kmsg

    # set skip_mount so magisk doesn't also bind-mount
    if [ ! -f "$MDIR/skip_mount" ]; then
        touch "$MDIR/skip_mount"
        echo "$MODULE_ID" >> "$PERSISTENT/skipped_modules"
    fi

    # copy with preserved ownership, permissions, timestamps, and selinux context
    # this replaces the sequential cp + chcon loop
    cp -a "$SYSDIR/." "$STAGING/" 2>/dev/null || \
        cp -Lrf "$SYSDIR"/* "$STAGING/" 2>/dev/null

    # if cp -a did not preserve context (tmpfs may not), fallback to chcon
    # but check only one file to decide, not all
    local SAMPLE_SRC SAMPLE_DST SRC_CTX DST_CTX
    SAMPLE_SRC="$(find "$SYSDIR" -type f -maxdepth 2 | head -1)"
    if [ -n "$SAMPLE_SRC" ]; then
        SAMPLE_DST="$STAGING${SAMPLE_SRC#"$SYSDIR"}"
        SRC_CTX="$(ls -Z "$SAMPLE_SRC" 2>/dev/null | awk '{print $1}')"
        DST_CTX="$(ls -Z "$SAMPLE_DST" 2>/dev/null | awk '{print $1}')"
        if [ "$SRC_CTX" != "$DST_CTX" ] && [ -n "$SRC_CTX" ]; then
            # context mismatch: need full chcon pass
            for file in $(busybox find -L "$SYSDIR" 2>/dev/null); do
                local rel="${file#"$SYSDIR"}"
                [ -e "$STAGING$rel" ] && busybox chcon --reference="$file" "$STAGING$rel" 2>/dev/null
            done
        fi
    fi

    # catch opaque dirs (module replace= support)
    for dir in $(busybox find -L "$SYSDIR" -type d 2>/dev/null); do
        if getfattr -d "$dir" 2>/dev/null | grep -q "trusted.overlay.opaque"; then
            local rel="${dir#"$SYSDIR"}"
            [ -d "$STAGING$rel" ] && busybox setfattr -n trusted.overlay.opaque -v y "$STAGING$rel" 2>/dev/null
        fi
    done

    echo "$MODULE_ID" >> "$LOGDIR/modules"
}

# create staging area (tmpfs)
mkdir -p "$STAGING"
busybox mount -t tmpfs tmpfs "$(realpath "$STAGING")"

if ! busybox mountpoint -q "$STAGING" 2>/dev/null; then
    echo "$TAG: failed to mount tmpfs at $STAGING" >> /dev/kmsg
    kill $WATCHDOG 2>/dev/null
    rm -f "$LOCKFILE"
    exit 1
fi

# enumerate and process modules
if [ "$nano_mounts" = 1 ] && [ -f "$PERSISTENT/modules.txt" ]; then
    # manual mode
    while IFS= read -r line; do
        # skip comments and empty lines
        case "$line" in \#*|"") continue ;; esac
        module_id=$(echo "$line" | awk '{print $1}')
        process_module "$module_id"
    done < "$PERSISTENT/modules.txt"
else
    # auto mode: scan all modules with /system
    for sysdir in /data/adb/modules/*/system; do
        [ -d "$sysdir" ] || continue
        module_id="${sysdir%/system}"
        module_id="${module_id##*/}"
        # never mount ourselves
        [ "$module_id" = "nanomount" ] && continue
        process_module "$module_id"
    done
fi

# mount overlays
cd "$STAGING" || exit 1

# system root overlay
mount_system

# then partition-level dirs
for part in $TARGETS; do
    # skip if partition name matches our staging folder
    [ "$part" = "$FAKE_MOUNT_NAME" ] && continue
    cd "$STAGING" || continue
    if [ -d "/$part" ] && busybox mountpoint -q "/$part" 2>/dev/null; then
        # modern: separate partition mounted at /<part>
        mount_partition "$part" "/"
    elif [ -d "/system/$part" ]; then
        # legacy: partition lives under /system/<part>
        mount_partition "$part" "/system/"
    fi
done

# cleanup staging tmpfs
busybox umount -l "$(realpath "$STAGING")" 2>/dev/null

# log final state
cat /proc/mounts > "$LOGDIR/after"
echo "$TAG: finished" >> /dev/kmsg

# cancel watchdog
kill $WATCHDOG 2>/dev/null
rm -f "$LOCKFILE"

