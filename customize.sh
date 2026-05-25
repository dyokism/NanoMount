#!/bin/sh
# nanomount - customize.sh
# installation script

PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH
PERSISTENT="/data/adb/nanomount"

echo "[+] NanoMount"
echo "[+] Lightweight OverlayFS for Modern Android Devices"
echo ""

# check overlayfs support
if grep -q "overlay" /proc/filesystems 2>/dev/null; then
    echo "[+] OverlayFS: supported"
else
    abort "[!] OverlayFS (CONFIG_OVERLAY_FS) is required!"
fi

# check tmpfs xattr support
TEST_DIR="/dev"
[ -w "$TEST_DIR" ] || abort "[!] /dev is not writable!"

testfile="$TEST_DIR/nanomount_xattr_test"
rm "$testfile" 2>/dev/null
busybox mknod "$testfile" c 0 0 2>/dev/null

if busybox setfattr -n trusted.overlay.whiteout -v y "$testfile" 2>/dev/null; then
    echo "[+] tmpfs xattr: supported"
    rm "$testfile" 2>/dev/null
else
    echo "[-] tmpfs xattr: not supported by kernel"
    echo "[!] WARNING: Directory REPLACE feature won't be available, but module will run in pure tmpfs mode (bootloop-safe)."
    rm "$testfile" 2>/dev/null
fi

# setup persistent config directory
mkdir -p "$PERSISTENT"

# copy default configs if not present
for file in config.sh modules.txt; do
    if [ ! -f "$PERSISTENT/$file" ]; then
        echo "[+] Installing default $file"
        cat "$MODPATH/$file" > "$PERSISTENT/$file"
    fi
done

# cleanup template files
rm -f "$MODPATH/config.sh" "$MODPATH/modules.txt"

# reset anti-bootloop state on fresh install
echo 0 > "$PERSISTENT/rapid_boots"
rm -f "$PERSISTENT/last_boot_ts"

echo ""
echo "[+] Installation complete!"
echo "[+] Config: $PERSISTENT/config.sh"
echo "[+] Reboot to activate."
