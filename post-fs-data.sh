#!/system/bin/sh
# shellcheck disable=SC3043,SC2012,SC1091
# nanomount - post-fs-data.sh
# lightweight overlayfs mounting for modern android devices

MODDIR="/data/adb/modules/nanomount"
PERSISTENT="/data/adb/nanomount"
LOGDIR="/dev/nanomount"
TAG="nanomount"
PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH

# config defaults
nano_mounts=2
FAKE_MOUNT_NAME="my_preload"
MOUNT_DEVICE_NAME="overlay"

# load persistent config
[ -f "$PERSISTENT/config.sh" ] && . "$PERSISTENT/config.sh"

# exit if disabled
[ "$nano_mounts" = 0 ] && exit 0

# single instance lock
LOCKFILE="/dev/nanomount_lock"
[ -f "$LOCKFILE" ] && exit 1
touch "$LOCKFILE"

# register cleanup trap to ensure lockfile is removed and watchdog is killed on exit
WATCHDOG=""
trap 'rm -f "$LOCKFILE"; [ -n "$WATCHDOG" ] && kill $WATCHDOG 2>/dev/null' EXIT
trap 'exit 1' INT TERM

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
        exit 1
    fi
else
    echo 0 > "$PERSISTENT/rapid_boots"
fi
echo "$NOW" > "$PERSISTENT/last_boot_ts"

# watchdog: kill after 60s for safety
(sleep 60 && kill $$ 2>/dev/null) &
WATCHDOG=$!

echo "$TAG: start" >> /dev/kmsg

# setup logging
mkdir -p "$LOGDIR"
cat /proc/mounts > "$LOGDIR/before"

# mount point: try /mnt first, fallback to /dev
MNT="/mnt"
if [ ! -w "$MNT" ]; then
    echo "$TAG: /mnt not writable, trying /dev" >> /dev/kmsg
    MNT="/dev"
    if [ ! -w "$MNT" ]; then
        echo "$TAG: /dev not writable, abort" >> /dev/kmsg
        exit 1
    fi
fi

STAGING="$MNT/$FAKE_MOUNT_NAME"

# don't clobber existing directories
if [ -d "$STAGING" ] && busybox mountpoint -q "$STAGING" 2>/dev/null; then
    echo "$TAG: $STAGING is already a mountpoint, abort" >> /dev/kmsg
    exit 1
fi

# overlay target partitions
# skip target if it matches fake_mount_name to avoid self-overlay
TARGETS="odm product system_ext vendor mi_ext my_bigball my_carrier my_company my_engineering my_heytap my_manifest my_preload my_product my_region my_reserve my_stock oem optics prism"

# getfattr helper
if /system/bin/getfattr -d /system/bin > /dev/null 2>&1; then
    getfattr() { /system/bin/getfattr "$@"; }
else
    getfattr() { /system/bin/toybox getfattr "$@"; }
fi

# functions

# mount system root
mount_system() {
    busybox mount -t overlay -o "lowerdir=$STAGING:/system" \
        "$MOUNT_DEVICE_NAME" "/system" && \
        echo "/system" >> "$LOGDIR/mount_list" || \
        echo "$TAG: failed to mount /system" >> /dev/kmsg
}

# mount partition
mount_partition() {
    local part="$1"
    local prefix="$2"

    [ -d "$STAGING/$part" ] || return
    busybox mount -t overlay -o "lowerdir=$STAGING/$part:$prefix$part" \
        "$MOUNT_DEVICE_NAME" "$prefix$part" && \
        echo "$prefix$part" >> "$LOGDIR/mount_list" || \
        echo "$TAG: failed to mount $prefix$part" >> /dev/kmsg
}

# process module: copy and set attributes
process_module() {
    local MODULE_ID="$1"
    local MDIR="/data/adb/modules/$MODULE_ID"
    local SYSDIR="$MDIR/system"

    # skip if invalid, disabled, removed, or hosts-only
    [ -d "$SYSDIR" ] || return
    [ -f "$MDIR/disable" ] && return
    [ -f "$MDIR/remove" ] && return
    [ -f "$MDIR/skip_nanomount" ] && return
    [ -f "$SYSDIR/etc/hosts" ] && [ "$(find "$SYSDIR" -not -path "$SYSDIR/etc/hosts" -not -path "$SYSDIR/etc" -not -path "$SYSDIR" | head -1)" = "" ] && return

    echo "$TAG: processing $MODULE_ID" >> /dev/kmsg

    # set skip_mount to prevent double mount
    # prevent duplicate in skipped_modules
    if [ ! -f "$MDIR/skip_mount" ]; then
        touch "$MDIR/skip_mount"
        if ! grep -qxF "$MODULE_ID" "$PERSISTENT/skipped_modules" 2>/dev/null; then
            echo "$MODULE_ID" >> "$PERSISTENT/skipped_modules"
        fi
    fi

    # copy files preserving attributes
    cp -a "$SYSDIR/." "$STAGING/" 2>/dev/null || \
        cp -Lrf "$SYSDIR"/* "$STAGING/" 2>/dev/null

    # fallback to chcon if cp -a did not preserve selinux context
    # sample check one file. edge case: may miss if sample matches fallback.
    local SAMPLE_SRC SAMPLE_DST SRC_CTX DST_CTX
    SAMPLE_SRC="$(find "$SYSDIR" -type f -maxdepth 2 | head -1)"
    if [ -n "$SAMPLE_SRC" ]; then
        SAMPLE_DST="$STAGING${SAMPLE_SRC#"$SYSDIR"}"
        SRC_CTX="$(ls -Z "$SAMPLE_SRC" 2>/dev/null | awk '{print $1}')"
        DST_CTX="$(ls -Z "$SAMPLE_DST" 2>/dev/null | awk '{print $1}')"
        if [ "$SRC_CTX" != "$DST_CTX" ] && [ -n "$SRC_CTX" ]; then
             # mismatch: run full chcon pass
             # loop with while-read to avoid word splitting. note: subshell orphan risk is acceptable.
             busybox find -L "$SYSDIR" 2>/dev/null | while IFS= read -r file; do
                 local rel="${file#"$SYSDIR"}"
                 [ -e "$STAGING$rel" ] && busybox chcon --reference="$file" "$STAGING$rel" 2>/dev/null
             done
        fi
    fi

    # handle opaque directories for replace support
    # loop with while-read. note: same acceptable subshell risk.
    if [ -f "$PERSISTENT/trusted_xattr_supported" ]; then
        busybox find -L "$SYSDIR" -type d 2>/dev/null | while IFS= read -r dir; do
            if getfattr -d "$dir" 2>/dev/null | grep -q "trusted.overlay.opaque"; then
                local rel="${dir#"$SYSDIR"}"
                [ -d "$STAGING$rel" ] && busybox setfattr -n trusted.overlay.opaque -v y "$STAGING$rel" 2>/dev/null
            fi
        done
    fi

    echo "$MODULE_ID" >> "$LOGDIR/modules"
}

# create tmpfs staging area
mkdir -p "$STAGING"
busybox mount -t tmpfs tmpfs "$(realpath "$STAGING")"

if ! busybox mountpoint -q "$STAGING" 2>/dev/null; then
    echo "$TAG: failed to mount tmpfs at $STAGING" >> /dev/kmsg
    exit 1
fi

# scan and process modules
if [ "$nano_mounts" = 1 ] && [ -f "$PERSISTENT/modules.txt" ]; then
    # manual mode
    while IFS= read -r line; do
        # skip comments and empty lines
        case "$line" in \#*|"") continue ;; esac
        module_id=$(echo "$line" | awk '{print $1}')
        process_module "$module_id"
    done < "$PERSISTENT/modules.txt"
else
    # auto mode: scan active modules with system directory
    for sysdir in /data/adb/modules/*/system; do
        [ -d "$sysdir" ] || continue
        module_id="${sysdir%/system}"
        module_id="${module_id##*/}"
        # skip self
        [ "$module_id" = "nanomount" ] && continue
        process_module "$module_id"
    done
fi

# mount overlays
cd "$STAGING" || exit 1

# mount system root
mount_system

# mount partitions
for part in $TARGETS; do
    # skip staging folder matching target
    [ "$part" = "$FAKE_MOUNT_NAME" ] && continue
    cd "$STAGING" || continue
    if [ -d "/$part" ] && busybox mountpoint -q "/$part" 2>/dev/null; then
        # modern: separate partition at /<part>
        mount_partition "$part" "/"
    elif [ -d "/system/$part" ]; then
        # legacy: partition at /system/<part>
        mount_partition "$part" "/system/"
    fi
done

# umount staging tmpfs
busybox umount -l "$(realpath "$STAGING")" 2>/dev/null

# log final state
cat /proc/mounts > "$LOGDIR/after"
echo "$TAG: finished" >> /dev/kmsg

# execution completed; shell will exit and trigger trap
