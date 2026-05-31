#!/bin/sh
# nanomount - uninstall.sh
# cleanup on module removal

PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH
PERSISTENT="/data/adb/nanomount"

# remove skip_mount flags on other modules
if [ -f "$PERSISTENT/skipped_modules" ]; then
    while IFS= read -r module; do
        [ -n "$module" ] && rm -f "/data/adb/modules/$module/skip_mount"
    done < "$PERSISTENT/skipped_modules"
fi

# delete persistent config
[ -d "$PERSISTENT" ] && rm -rf "$PERSISTENT"
