#!/system/bin/sh
# shellcheck disable=SC3043,SC2012,SC1091,SC2086
# nanomount - post-fs-data.sh
# lightweight overlayfs mounting for modern android devices

# Check if sourced
(return 0 2>/dev/null) && SOURCED=1 || SOURCED=0

MODDIR=${0%/*}
PERSISTENT="/data/adb/nanomount"
LOGDIR="/dev/nanomount"
TAG="nanomount"
PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH

# config defaults
nano_mounts=2
FAKE_MOUNT_NAME="my_preload"
MOUNT_DEVICE_NAME="overlay"

# Determine manager-specific properties early
IS_KSU=false
if [ "$KSU" = "true" ] || [ -d "/data/adb/ksu" ]; then
    IS_KSU=true
fi

if [ "$IS_KSU" = "true" ]; then
    MOUNT_DEVICE_NAME="KSU"
else
    MOUNT_DEVICE_NAME="overlay"
fi

# getfattr helper
if /system/bin/getfattr -d /system/bin > /dev/null 2>&1; then
    getfattr() { /system/bin/getfattr "$@"; }
else
    getfattr() { /system/bin/toybox getfattr "$@"; }
fi

# mount subdirectory overlay
mount_subdir() {
    local staging_path="$1"
    local target_path="$2"

    [ -d "$staging_path" ] || return
    [ -d "$target_path" ] || return

    # skip if target_path is already a mountpoint to prevent duplicate mounts
    if busybox mountpoint -q "$target_path" 2>/dev/null; then
        echo "$TAG: $target_path is already a mountpoint, skipping" >> /dev/kmsg
        return
    fi

    busybox mount -t overlay -o "lowerdir=$staging_path:$target_path" \
        "$MOUNT_DEVICE_NAME" "$target_path" && \
        echo "$target_path" >> "$LOGDIR/mount_list" || \
        echo "$TAG: failed to mount overlay at $target_path" >> /dev/kmsg
}

# process module: copy and set attributes
process_module() {
    local MODULE_ID="$1"
    local MDIR="/data/adb/m""odules/$MODULE_ID"
    local SYSDIR="$MDIR/system"
    local SAMPLE_SRC SAMPLE_DST SRC_CTX DST_CTX file dir rel first_file

    # skip if invalid, disabled, removed, or hosts-only
    [ -d "$SYSDIR" ] || return
    [ -f "$MDIR/disable" ] && return
    [ -f "$MDIR/remove" ] && return
    [ -f "$MDIR/skip_nanomount" ] && return
    
    # Check if this is hosts-only module without spawning a subshell pipe
    if [ -f "$SYSDIR/etc/hosts" ]; then
        find "$SYSDIR" -not -path "$SYSDIR/etc/hosts" -not -path "$SYSDIR/etc" -not -path "$SYSDIR" > "$LOGDIR/hosts_check"
        read -r first_file < "$LOGDIR/hosts_check"
        rm -f "$LOGDIR/hosts_check"
        [ -z "$first_file" ] && return
    fi

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
    SAMPLE_SRC="$(find "$SYSDIR" -type f -maxdepth 2 | head -1)"
    if [ -n "$SAMPLE_SRC" ]; then
        SAMPLE_DST="$STAGING${SAMPLE_SRC#"$SYSDIR"}"
        SRC_CTX="$(ls -Z "$SAMPLE_SRC" 2>/dev/null | awk '{print $1}')"
        DST_CTX="$(ls -Z "$SAMPLE_DST" 2>/dev/null | awk '{print $1}')"
        if [ "$SRC_CTX" != "$DST_CTX" ] && [ -n "$SRC_CTX" ]; then
             # mismatch: run full chcon pass
             # avoid pipes to while-read to prevent subshells
             busybox find -L "$SYSDIR" 2>/dev/null > "$LOGDIR/find_temp"
             while IFS= read -r file; do
                 rel="${file#"$SYSDIR"}"
                 [ -e "$STAGING$rel" ] && busybox chcon --reference="$file" "$STAGING$rel" 2>/dev/null
             done < "$LOGDIR/find_temp"
             rm -f "$LOGDIR/find_temp"
        fi
    fi

    # handle opaque directories for replace support
    if [ -f "$PERSISTENT/trusted_xattr_supported" ]; then
         busybox find -L "$SYSDIR" -type d 2>/dev/null > "$LOGDIR/find_dir_temp"
         while IFS= read -r dir; do
            if getfattr -d "$dir" 2>/dev/null | grep -q "trusted.overlay.opaque"; then
                rel="${dir#"$SYSDIR"}"
                [ -d "$STAGING$rel" ] && busybox setfattr -n trusted.overlay.opaque -v y "$STAGING$rel" 2>/dev/null
            fi
         done < "$LOGDIR/find_dir_temp"
         rm -f "$LOGDIR/find_dir_temp"
    fi

    echo "$MODULE_ID" >> "$LOGDIR/modules"
}

nanomount_main() {
    # load persistent config
    [ -f "$PERSISTENT/config.sh" ] && . "$PERSISTENT/config.sh"

    # return if disabled
    [ "$nano_mounts" = 0 ] && return 0

    # check metamodule conflicts (for KernelSU / APatch)
    if [ "$KSU" = "true" ] || [ "$APATCH" = "true" ]; then
        if [ -e "/data/adb/metamodule" ]; then
            ACTIVE_META=$(readlink -f /data/adb/metamodule)
            ACTIVE_META_ID=$(basename "$ACTIVE_META")
            if [ "$ACTIVE_META_ID" != "nanomount" ]; then
                echo "$TAG: another metamodule ($ACTIVE_META_ID) is active. Backing off to prevent conflicts." >> /dev/kmsg
                # Clean up any skip_mount flags that nanomount previously set
                if [ -f "$PERSISTENT/skipped_modules" ]; then
                    while IFS= read -r module; do
                        if [ -n "$module" ] && [ "$module" != "nanomount" ]; then
                            rm -f "/data/adb/m""odules/$module/skip_mount"
                        fi
                    done < "$PERSISTENT/skipped_modules"
                    rm -f "$PERSISTENT/skipped_modules"
                fi
                return 0
            fi
        fi
    fi

    # single instance lock
    LOCKFILE="/dev/nanomount_lock"
    [ -f "$LOCKFILE" ] && return 0
    touch "$LOCKFILE"

    # Setup watchdog and traps if NOT sourced (only relevant/safe for standalone process)
    local watchdog_pid=""
    if [ "$SOURCED" = "0" ]; then
        local self_pid=$$
        trap '[ -n "$watchdog_pid" ] && kill "$watchdog_pid" 2>/dev/null' EXIT
        trap 'return 1' INT TERM

        # Timeout: KSU/APatch (8s), Magisk (35s)
        local timeout=35
        if [ "$IS_KSU" = "true" ] || [ "$APATCH" = "true" ]; then
            timeout=8
        fi
        (sleep $timeout && kill $self_pid 2>/dev/null) &
        watchdog_pid=$!
    fi

    # anti-bootloop: timestamp-based
    local last_boot now delta rapid_boots
    last_boot=$(cat "$PERSISTENT/last_boot_ts" 2>/dev/null || echo 0)
    now=$(date +%s)
    delta=$((now - last_boot))

    if [ "$delta" -lt 120 ] && [ "$last_boot" -ne 0 ]; then
        rapid_boots=$(($(cat "$PERSISTENT/rapid_boots" 2>/dev/null || echo 0) + 1))
        echo "$rapid_boots" > "$PERSISTENT/rapid_boots"
        if [ "$rapid_boots" -ge 2 ]; then
            touch "$MODDIR/disable"
            if [ -f "$MODDIR/module.prop" ]; then
                (
                    grep -v '^description=' "$MODDIR/module.prop"
                    echo "description=Anti-bootloop triggered. Module disabled. Re-enable to activate."
                ) > "$MODDIR/module.prop.tmp" && mv "$MODDIR/module.prop.tmp" "$MODDIR/module.prop"
            fi
            echo "$TAG: anti-bootloop triggered (rapid_boots=$rapid_boots)" >> /dev/kmsg
            return 1
        fi
    else
        echo 0 > "$PERSISTENT/rapid_boots"
    fi
    echo "$now" > "$PERSISTENT/last_boot_ts"

    echo "$TAG: start (MOUNT_DEVICE_NAME=$MOUNT_DEVICE_NAME)" >> /dev/kmsg

    # setup logging
    mkdir -p "$LOGDIR"
    cat /proc/mounts > "$LOGDIR/before"

    # mount point: try /mnt first, fallback to /dev
    local mnt="/mnt"
    if [ ! -w "$mnt" ]; then
        echo "$TAG: /mnt not writable, trying /dev" >> /dev/kmsg
        mnt="/dev"
        if [ ! -w "$mnt" ]; then
            echo "$TAG: /dev not writable, abort" >> /dev/kmsg
            return 1
        fi
    fi

    STAGING="$mnt/$FAKE_MOUNT_NAME"

    # don't clobber existing directories
    if [ -d "$STAGING" ] && busybox mountpoint -q "$STAGING" 2>/dev/null; then
        echo "$TAG: $STAGING is already a mountpoint, abort" >> /dev/kmsg
        return 1
    fi

    # overlay target partitions
    # skip target if it matches fake_mount_name to avoid self-overlay
    TARGETS="odm product system_ext vendor mi_ext my_bigball my_carrier my_company my_engineering my_heytap my_manifest my_preload my_product my_region my_reserve my_stock oem optics prism"

    # create tmpfs staging area
    mkdir -p "$STAGING"
    busybox mount -t tmpfs tmpfs "$(realpath "$STAGING")"

    if ! busybox mountpoint -q "$STAGING" 2>/dev/null; then
        echo "$TAG: failed to mount tmpfs at $STAGING" >> /dev/kmsg
        return 1
    fi

    # scan and process modules
    local line module_id sysdir subdir_path name part prefix
    if [ "$nano_mounts" = 1 ] && [ -f "$PERSISTENT/modules.txt" ]; then
        # manual mode
        while IFS= read -r line; do
            # skip comments and empty lines
            case "$line" in \#*|"") continue ;; esac
            # Extract first word without spawning awk/echo
            module_id="${line%% *}"
            module_id="${module_id%%	*}"
            process_module "$module_id"
        done < "$PERSISTENT/modules.txt"
    else
        # auto mode: scan active modules with system directory (including modules_update for safety)
        for sysdir in /data/adb/m""odules/*/system /data/adb/m""odules_update/*/system; do
            [ -d "$sysdir" ] || continue
            module_id="${sysdir%/system}"
            module_id="${module_id##*/}"
            # skip self
            [ "$module_id" = "nanomount" ] && continue
            process_module "$module_id"
        done
    fi

    # mount overlays in subdirectory granularity

    # 1. mount /system subdirectories (scanning directly under staging root, excluding target partition directories)
    for subdir_path in "$STAGING"/*; do
        [ -d "$subdir_path" ] || continue
        name="${subdir_path##*/}"
        
        # skip target partitions to prevent mounting them as /system subdirectories
        case " $TARGETS " in
            *" $name "*) continue ;;
        esac
        
        mount_subdir "$subdir_path" "/system/$name"
    done

    # 2. mount other partitions subdirectories (legacy and modern handling)
    for part in $TARGETS; do
        # skip staging folder matching target
        [ "$part" = "$FAKE_MOUNT_NAME" ] && continue
        [ -d "$STAGING/$part" ] || continue

        prefix=""
        if [ -L "/$part" ] && [ ! -L "/system/$part" ]; then
            # legacy: partition at /system/<part>
            prefix="/system/"
        elif [ -d "/$part" ] && busybox mountpoint -q "/$part" 2>/dev/null; then
            # modern: partition at /<part>
            prefix="/"
        elif [ -d "/system/$part" ]; then
            # fallback legacy
            prefix="/system/"
        else
            # target not present on device
            continue
        fi

        # mount each subdirectory inside the target partition staging area
        for subdir_path in "$STAGING/$part"/*; do
            [ -d "$subdir_path" ] || continue
            name="${subdir_path##*/}"
            mount_subdir "$subdir_path" "${prefix}${part}/${name}"
        done
    done

    # umount staging tmpfs
    busybox umount -l "$(realpath "$STAGING")" 2>/dev/null

    # log final state
    cat /proc/mounts > "$LOGDIR/after"
    echo "$TAG: finished" >> /dev/kmsg
    return 0
}

nanomount_main
RET_VAL=$?
if [ "$SOURCED" = "1" ]; then
    return $RET_VAL
else
    exit $RET_VAL
fi
