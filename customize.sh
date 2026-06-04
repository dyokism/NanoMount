#!/system/bin/sh
# shellcheck disable=SC3043
# nanomount - customize.sh
# installation script

PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH
PERSISTENT="/data/adb/nanomount"

ui_print "[+] NanoMount"
ui_print "[+] Lightweight OverlayFS for Modern Android Devices"
ui_print ""

# check overlayfs support
if grep -q "overlay" /proc/filesystems 2>/dev/null; then
    ui_print "[+] OverlayFS: supported"
else
    abort "[!] OverlayFS (CONFIG_OVERLAY_FS) is required!"
fi

# check tmpfs xattr support
check_tmpfs_selinux() {
    local testdir="$1"
    local testfile="$testdir/nanomount_selinux_test"
    rm -f "$testfile" 2>/dev/null
    touch "$testfile" 2>/dev/null || return 1
    
    local err=""
    if busybox setfattr -n security.selinux -v "u:object_r:device:s0" "$testfile" >/dev/null 2>&1; then
        rm -f "$testfile" 2>/dev/null
        return 0
    fi
    
    err=$(busybox setfattr -n security.selinux -v "u:object_r:device:s0" "$testfile" 2>&1)
    local ret=$?
    
    if [ $ret -ne 0 ] && { echo "$err" | grep -q "not found" || echo "$err" | grep -q "applet not found"; }; then
        err=$(toybox setfattr -n security.selinux -v "u:object_r:device:s0" "$testfile" 2>&1)
        ret=$?
    fi
    
    rm -f "$testfile" 2>/dev/null
    
    if [ $ret -eq 0 ]; then
        return 0
    fi
    
    case "$err" in
        *"not supported"*)
            return 1 # truly unsupported by kernel
            ;;
        *)
            return 0 # supported but restricted by recovery
            ;;
    esac
}

check_tmpfs_trusted() {
    local testdir="$1"
    local testfile="$testdir/nanomount_trusted_test"
    rm -f "$testfile" 2>/dev/null
    touch "$testfile" 2>/dev/null || return 1
    
    local err=""
    if busybox setfattr -n trusted.nanomount_test -v y "$testfile" >/dev/null 2>&1; then
        rm -f "$testfile" 2>/dev/null
        return 0
    fi
    
    err=$(busybox setfattr -n trusted.nanomount_test -v y "$testfile" 2>&1)
    local ret=$?
    
    if [ $ret -ne 0 ] && { echo "$err" | grep -q "not found" || echo "$err" | grep -q "applet not found"; }; then
        err=$(toybox setfattr -n trusted.nanomount_test -v y "$testfile" 2>&1)
        ret=$?
    fi
    
    rm -f "$testfile" 2>/dev/null
    
    if [ $ret -eq 0 ]; then
        return 0
    fi
    
    case "$err" in
        *"not supported"*)
            return 1 # truly unsupported
            ;;
        *)
            return 0 # supported but restricted
            ;;
    esac
}

# check overlay on tmpfs
check_overlay_on_tmpfs() {
    local testdir="/dev/nanomount_ovtest"
    local lower1="$testdir/lower1"
    local lower2="$testdir/lower2"
    local merged="$testdir/merged"
    mkdir -p "$lower1" "$lower2" "$merged"
    busybox mount -t tmpfs tmpfs "$lower1" 2>/dev/null || { rm -rf "$testdir"; return 1; }
    busybox mount -t tmpfs tmpfs "$lower2" 2>/dev/null || { busybox umount -l "$lower1" 2>/dev/null; rm -rf "$testdir"; return 1; }
    busybox mount -t overlay -o "lowerdir=$lower1:$lower2" overlay "$merged" 2>/dev/null
    local ret=$?
    busybox umount -l "$merged" 2>/dev/null
    busybox umount -l "$lower2" 2>/dev/null
    busybox umount -l "$lower1" 2>/dev/null
    rm -rf "$testdir"
    return $ret
}

TEST_DIR="/dev"
[ -w "$TEST_DIR" ] || abort "[!] /dev is not writable!"

if check_overlay_on_tmpfs; then
    ui_print "[+] OverlayFS on tmpfs backend: supported"
else
    ui_print "[-] OverlayFS on tmpfs backend: not supported"
    abort "[!] Aborting: OverlayFS on tmpfs backend is not supported by this kernel."
fi

# setup persistent config directory
mkdir -p "$PERSISTENT"

if check_tmpfs_selinux "$TEST_DIR"; then
    ui_print "[+] tmpfs SELinux context preservation: supported"
    if check_tmpfs_trusted "$TEST_DIR"; then
        ui_print "[+] tmpfs trusted xattrs (directory replace): supported"
        touch "$PERSISTENT/trusted_xattr_supported"
    else
        ui_print "[-] tmpfs trusted xattrs (directory replace): not supported by kernel"
        ui_print "[!] WARNING: Directory REPLACE (.replace) feature won't be available,"
        ui_print "[!] but the module will mount other files perfectly in pure tmpfs mode."
        rm -f "$PERSISTENT/trusted_xattr_supported"
    fi
else
    ui_print "[-] tmpfs SELinux context preservation: not supported"
    abort "[!] Aborting: security.selinux xattr on tmpfs is not supported by this kernel."
fi

# copy default configs if not present
for file in config.sh modules.txt; do
    if [ ! -f "$PERSISTENT/$file" ]; then
        ui_print "[+] Installing default $file"
        cat "$MODPATH/$file" > "$PERSISTENT/$file"
    fi
done

# cleanup template files
rm -f "$MODPATH/config.sh" "$MODPATH/modules.txt"

# reset anti-bootloop on fresh install
echo 0 > "$PERSISTENT/rapid_boots"
rm -f "$PERSISTENT/last_boot_ts"

# Install as metamodule if running KernelSU/APatch and supported
if grep -q "metamodule=true" "$MODPATH/module.prop" || grep -q "metamodule=1" "$MODPATH/module.prop"; then
    if { [ "$KSU" = "true" ] && [ ! "$KSU_MAGIC_MOUNT" = "true" ] && [ "$KSU_VER_CODE" -ge 22098 ]; } || \
       { [ "$APATCH" = "true" ] && [ "$APATCH_VER_CODE" -ge 11170 ]; }; then
        ui_print "[+] Installing in metamodule mode"
        mv "$MODPATH/post-fs-data.sh" "$MODPATH/metamount.sh"
    fi
fi

ui_print ""
ui_print "[+] Installation complete!"
ui_print "[+] Config: $PERSISTENT/config.sh"
ui_print "[+] Reboot to activate."
