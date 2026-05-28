[English](README.md) | [Bahasa Indonesia](README.id.md)

# NanoMount

**Modul OverlayFS berkinerja tinggi dan sangat ringan (ultra-lightweight) untuk menerapkan modifikasi sistem secara global pada perangkat Android modern.**

![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Android](https://img.shields.io/badge/Android-10.0%2B-green.svg)
![Version](https://img.shields.io/badge/Version-1.2-orange.svg)
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

---

## Instalasi & Konfigurasi

1. Pasang berkas ZIP melalui tab **Modules** di manager root Anda.
2. **Reboot** (Mulai ulang) perangkat Anda untuk mengaktifkan.
3. Atur konfigurasi pada: `/data/adb/nanomount/config.sh`

---

## Cara Kerja

```mermaid
flowchart TD
    %% Fase Instalasi
    subgraph Fase_Instalasi ["1. Fase Instalasi (customize.sh)"]
        FlashZip[Mulai Flash ZIP] --> CheckOverlay{Cek CONFIG_OVERLAY_FS?}
        CheckOverlay -- Tidak --> AbortOverlay[Abort: OverlayFS Required]
        CheckOverlay -- Ya --> CheckTmpfsBackend{Cek Overlay di tmpfs?}
        CheckTmpfsBackend -- Tidak --> AbortTmpfsBackend[Abort: Kernel Tidak Kompatibel]
        CheckTmpfsBackend -- Ya --> CheckSELinux{Cek tmpfs SELinux?}
        CheckSELinux -- Tidak --> AbortSELinux[Abort: SELinux xattr Tidak Didukung]
        CheckSELinux -- Ya --> CheckTrusted{Cek tmpfs Trusted xattr?}
        CheckTrusted -- Ya --> FullMode[Instalasi Sukses: Fitur Lengkap]
        CheckTrusted -- Tidak --> PureMode[Instalasi Sukses: Warning .replace Tidak Aktif]
        FullMode & PureMode --> ConfigSetup[Buat Folder Konfigurasi & Selesai]
    end

    %% Fase Boot Awal
    subgraph Fase_Boot_Awal ["2. Fase Boot Awal (post-fs-data.sh)"]
        ConfigSetup --> BootStart[Perangkat Reboot & Booting Dimulai]
        BootStart --> WatchdogStart[Nyalakan Watchdog 60s & Cek Anti-Bootloop]
        WatchdogStart --> StagingCreate[Buat Staging Area tmpfs di /mnt atau /dev]
        StagingCreate --> ProcessModules[Proses Seluruh Modul Aktif]
        ProcessModules --> CopyFiles[Salin File + Terapkan SELinux Context]
        CopyFiles --> SkipMount[Beri Tanda skip_mount agar Magisk Tidak Double-Mount]
        SkipMount --> MountOverlay[Mount Overlay di Root Partisi]
        MountOverlay --> CleanStaging[Lazy Umount Staging Area agar Memori Bersih]
        CleanStaging --> WatchdogStop[Matikan Watchdog]
    end

    %% Fase Boot Akhir
    subgraph Fase_Boot_Akhir ["3. Fase Boot Akhir (service.sh)"]
        WatchdogStop --> UILoaded[Sistem Utama Selesai Memuat]
        UILoaded --> UpdateProp[Baca Log & Perbarui Deskripsi di module.prop]
        UpdateProp --> WaitBoot[Tunggu Hingga sys.boot_completed=1]
        WaitBoot --> ResetAntiBoot[Reset Penghitung Anti-Bootloop & Hapus Log /dev/nanomount]
        ResetAntiBoot --> Finished[Selesai & Sistem Berjalan Stabil]
    end

    %% Custom Styles
    style Fase_Instalasi fill:none,stroke:none
    style Fase_Boot_Awal fill:none,stroke:none
    style Fase_Boot_Akhir fill:none,stroke:none

    classDef default fill:none,stroke:#9ca3af,stroke-width:1px;
    classDef abort fill:#fee2e2,stroke:#ef4444,stroke-width:1.5px,color:#991b1b;
    classDef success fill:#d1fae5,stroke:#10b981,stroke-width:1.5px,color:#065f46;
    classDef check fill:none,stroke:#f59e0b,stroke-width:1.5px;

    class AbortOverlay,AbortTmpfsBackend,AbortSELinux abort;
    class FullMode,PureMode,Finished success;
    class CheckOverlay,CheckTmpfsBackend,CheckSELinux,CheckTrusted check;
```

---

## Pengembang, Kontributor & Lisensi

- **Pengembang**: [dyokism](https://github.com/dyokism)
- **Terima Kasih Khusus**: [bnsmb](https://github.com/bnsmb) karena telah membantu menemukan celah ketidakcocokan kernel dan membantu merancang pemeriksaan instalasi modul agar lebih ketat dan terstruktur.
- **Lisensi**: MIT

