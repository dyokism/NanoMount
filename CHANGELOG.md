# Changelog

## 1.3
- **Optimized Boot Performance**: Added persistence for the trusted xattr capability check (`check_tmpfs_trusted`) to `$PERSISTENT/trusted_xattr_supported` during installation.
- **Opaque Scanning Bypass**: Automatically skip the directory opaque attribute restoration loop during early boot (`post-fs-data.sh`) on kernels lacking trusted xattr support, eliminating redundant overhead.

## 1.2
- **OverlayFS on tmpfs Kernel Check**: Added graceful kernel compatibility detection during installation (`customize.sh`), with special thanks to [bnsmb](https://github.com/bnsmb) for discovering the kernel-level incompatibility, strict check. The check mounts a temporary tmpfs and runs a dummy overlayfs stack using it to confirm kernel compatibility. If unsupported, the installation aborts cleanly with a detailed message suggesting Mountify as a working alternative.
- **Root-Level Overlay Mount**: Changed overlay mount strategy from per-subdirectory to per-root-partition, resolving mount conflicts with Magisk's internal tmpfs mounts on subdirectories like `/product/bin` and `/system/bin`.

## 1.1
- **Separated Kernel Detection**: Separated SELinux and trusted xattr checks on tmpfs, preventing false installation failures on devices.
- **Clear Installation Abort**: Added a clean abort screen during installation if SELinux xattr is completely unsupported, suggesting Mountify as a working alternative.
- **Extended Watchdog Timer**: Increased the boot watchdog timeout from 30 to 60 seconds to provide better startup stability on slower devices.

## 1.0
- **Initial Stable Release**: Reborn as a clean, highly optimized, and bug-free recreation of the OverlayFS global mount concept.
- **Zero-Bloat Architectural Rewrite**: Size reduced by **99%** (down to a tiny **~7.5 KB** footprint), stripping out legacy loadable kernel modules (`.ko` files) and heavy ext4 sparse image loop mounts in favor of pure, ultra-fast `tmpfs`.
- **High-Performance SELinux Sampling**: Replaced the expensive sequential file-by-file `chcon` loop with a smart single-file context preservation test on `tmpfs`, significantly speeding up device boot times.
- **Sandboxed Installation Guard**: Moved the installer's `tmpfs xattr` pen-test file creation to `/dev` (instead of `/mnt`), completely resolving false aborts during installation inside root manager app sandboxes.
- **Robust dev Boot Fallback**: Built an automated fallback to `/dev/nanomount` if `/mnt` is locked or read-only during the early `post-fs-data` boot stage, assuring 100% mounting success across customized ROMs.
- **Extended Root Manager Support**: Broadened the binary search path to automatically locate the native busybox environments of APatch and KernelSU:
  `PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH`
- **Xiaomi HyperOS Support**: Added the `mi_ext` dynamic system partition to the mount target list for complete compatibility with Xiaomi, Redmi, and Poco devices.
- **Timestamp-Based Anti-Bootloop**: Implemented an elegant anti-bootloop routine that automatically disables the module if two rapid reboots within 120 seconds are detected, preserving device accessibility.
- **Background Watchdog Guard**: Equipped with a 30-second background watchdog timer during boot to force-close hangs and prevent permanent bootloops.
- **Standardized Code Commenting**: Formatted all source code comments to be 100% lowercase, clean, concise, and completely free of decorative em-dashes (`──`) as per developer guidelines.
- **Full Brand Coherence**: Renamed all legacy internal system variables and skip flags (such as `mountify_mounts` -> `nano_mounts` and `skip_mountify` -> `skip_nanomount`) to achieve 100% project identity unification.
