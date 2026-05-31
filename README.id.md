[English](README.md) | [Bahasa Indonesia](README.id.md)

# NanoMount

**Modul OverlayFS berkinerja tinggi dan sangat ringan (ultra-lightweight) untuk menerapkan modifikasi sistem secara global pada perangkat Android modern.**

![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Android](https://img.shields.io/badge/Android-10.0%2B-green.svg)
![Version](https://img.shields.io/badge/Version-1.3-orange.svg)
![Root](https://img.shields.io/badge/Root-Magisk%20%7C%20KernelSU%20%7C%20APatch-red.svg)

## Deskripsi Umum

NanoMount adalah modul root yang sangat ringan (*ultra-lightweight*), menggantikan sistem *bind mount* tradisional yang lambat dengan OverlayFS yang ringkas dan cepat. Modul ini memuat seluruh file modifikasi ke dalam ruang penyimpanan sementara di RAM (`tmpfs`), lalu menumpuknya (overlay) secara bersih ke `/system`, `/vendor`, dan `/product` dalam satu langkah terpadu.

---

## Mengapa Memilih NanoMount?

- **Anti Deteksi**: Memasang file di folder tersembunyi (seperti `/dev/my_preload`), sukses melewati verifikasi m-banking dan deteksi root.
- **Murni di RAM**: Berjalan sepenuhnya di memori (`tmpfs`). Tanpa berkas citra ext4 loop, nol pemakaian memori internal, dan bebas korupsi data.
- **Booting Lebih Cepat**: Menghindari perulangan `chcon` file-per-file yang lambat saat booting dengan memverifikasi SELinux di awal.
- **Proteksi Instalasi**: Mendeteksi ketidakcocokan kernel dan SELinux saat instalasi, mencegah bootloop dengan membatalkan pemasangan secara aman.
- **Dukungan Universal**: Bekerja langsung dengan Magisk, KernelSU, dan APatch pada Android 10 ke atas.

---

## Persyaratan Sistem

| Persyaratan | Detail |
|-------------|--------|
| Android | 10.0+ (API 29+) |
| Kernel | `CONFIG_OVERLAY_FS=y`, `tmpfs` sebagai filesystem lower OverlayFS yang valid, & dukungan xattr `security.selinux` pada `tmpfs` |
| Root | Magisk, Magisk Alpha, KernelSU, atau APatch |

*(Catatan: Kompatibilitas KSU + susfs dengan MDM ketat (misal. Intune) belum diverifikasi).*

---

## Instalasi & Konfigurasi

1. Pasang berkas ZIP melalui tab **Modules** di manager root Anda.
2. **Reboot** (Mulai ulang) perangkat Anda untuk mengaktifkan.
3. Atur konfigurasi pada: `/data/adb/nanomount/config.sh`

---

## Resolusi Konflik

Jika beberapa modul memodifikasi file yang sama (misal `/system/etc/hosts`), file yang diproses terakhir akan menang di staging area `tmpfs`:
*   **Mode Otomatis**: Diproses secara **alfabetis** berdasarkan nama folder modul. Folder dengan alfabet terakhir yang menang.
*   **Mode Manual**: Diproses dari **atas ke bawah** sesuai daftar di `/data/adb/nanomount/modules.txt`. Baris paling bawah yang menang.

---

## Mengecualikan Modul

Untuk mencegah NanoMount memproses modul tertentu (misalnya jika tidak kompatibel atau memiliki sistem *mount* mandiri):
*   Buat file kosong bernama `skip_nanomount` di dalam folder modul tersebut:
    `/data/adb/modules/<module-id>/skip_nanomount`
*   NanoMount akan mengabaikan modul tersebut dan menyerahkan pemrosesan sepenuhnya ke manajer root Anda.

---

## Cara Kerja

```mermaid
flowchart TD
    FlashZip([Mulai: Flash ZIP Modul]) --> CheckOverlay{Cek CONFIG_OVERLAY_FS?}
    CheckOverlay -- Tidak --> AbortOverlay[Abort: OverlayFS Required]
    CheckOverlay -- Ya --> CheckTmpfsBackend{Cek Overlay di tmpfs?}
    
    CheckTmpfsBackend -- Tidak --> AbortTmpfsBackend[Abort: Kernel Tidak Kompatibel]
    CheckTmpfsBackend -- Ya --> CheckSELinux{Cek tmpfs SELinux?}
    
    CheckSELinux -- Tidak --> AbortSELinux[Abort: SELinux xattr Tidak Didukung]
    CheckSELinux -- Ya --> CheckTrusted{Cek tmpfs Trusted xattr?}
    
    CheckTrusted -- Ya --> FullMode[Instalasi Sukses: Fitur Lengkap]
    CheckTrusted -- No --> PureMode[Instalasi Sukses: Warning .replace Tidak Aktif]
    
    FullMode & PureMode --> ConfigSetup[Buat Folder Konfigurasi & Selesai]
    ConfigSetup --> BootStart[Perangkat Reboot & Booting Dimulai]
    
    BootStart --> WatchdogStart[Nyalakan Watchdog 60s & Cek Anti-Bootloop]
    WatchdogStart --> StagingCreate[Buat Staging Area tmpfs di /mnt atau /dev]
    StagingCreate --> ProcessModules[Proses Seluruh Modul Aktif]
    ProcessModules --> CopyFiles[Salin File + Terapkan SELinux Context]
    CopyFiles --> SkipMount[Beri Tanda skip_mount agar Magisk Tidak Double-Mount]
    SkipMount --> MountOverlay[Mount Overlay di Root Partisi]
    MountOverlay --> CleanStaging[Lazy Umount Staging Area agar Memori Bersih]
    CleanStaging --> WatchdogStop[Matikan Watchdog & Late Boot service.sh]
    
    WatchdogStop --> UILoaded[Sistem Utama Selesai Memuat]
    UILoaded --> UpdateProp[Baca Log & Perbarui Deskripsi di module.prop]
    UpdateProp --> WaitBoot[Tunggu Hingga sys.boot_completed=1]
    WaitBoot --> ResetAntiBoot[Reset Penghitung Anti-Bootloop & Hapus Log /dev/nanomount]
    ResetAntiBoot --> Finished([Selesai: Sistem Berjalan Stabil])

    %% Kustomisasi Tampilan dan Warna (Tema Gelap Ultra-Redup)
    classDef startEnd fill:#1b2c24,stroke:#34d399,stroke-width:1.5px,color:#e6f4ea;
    classDef fail fill:#2c1b1b,stroke:#f87171,stroke-width:1.5px,color:#fce8e6;
    classDef decision fill:#2d2216,stroke:#fbbf24,stroke-width:1.5px,color:#fef3c7;
    classDef process fill:#1e293b,stroke:#475569,stroke-width:1px,color:#f1f5f9;
    
    class FlashZip,Finished startEnd;
    class AbortOverlay,AbortTmpfsBackend,AbortSELinux fail;
    class CheckOverlay,CheckTmpfsBackend,CheckSELinux,CheckTrusted decision;
    class FullMode,PureMode,ConfigSetup,BootStart,WatchdogStart,StagingCreate,ProcessModules,CopyFiles,SkipMount,MountOverlay,CleanStaging,WatchdogStop,UILoaded,UpdateProp,WaitBoot,ResetAntiBoot process;
```

---

## Pengembang, Kontributor & Lisensi

- **Pengembang**: [dyokism](https://github.com/dyokism)
- **Terima Kasih Khusus**: [bnsmb](https://github.com/bnsmb) karena telah membantu menemukan celah ketidakcocokan kernel.
- **Lisensi**: MIT

