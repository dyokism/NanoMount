[English](README.md) | [Bahasa Indonesia](README.id.md)

# NanoMount

**Modul OverlayFS profesional yang sangat ringan (ultra-lightweight) untuk menerapkan modifikasi sistem secara global pada perangkat Android modern.**

![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Android](https://img.shields.io/badge/Android-10.0%2B-green.svg)
![Version](https://img.shields.io/badge/Version-1.1-orange.svg)
![Root](https://img.shields.io/badge/Root-Magisk%20%7C%20KernelSU%20%7C%20APatch-red.svg)

## Deskripsi Umum

NanoMount adalah modul root berkinerja tinggi yang dirancang untuk menggantikan sistem *bind mount* tradisional dengan sistem OverlayFS yang terpadu dan ringan. Modul ini menyatukan semua file modifikasi sistem ke dalam ruang memori sementara (`tmpfs`) dan menerapkannya secara bersih ke `/system`, `/vendor`, `/product`, serta partisi dinamis lainnya dalam satu langkah terpadu.

---

## Mengapa Memilih NanoMount?

- **Penyamaran & Bypass**: Menaruh file modifikasi di bawah folder staging mirip partisi bawaan pabrik (seperti `/mnt/my_preload` atau `/dev/my_preload`) untuk menyembunyikan mount aktif, sehingga sangat efektif **untuk membuka aplikasi mbanking dan deteksi root lainnya**.
- **Tanpa Beban Penyimpanan**: Berjalan murni di dalam memori (`tmpfs`), menghindari penggunaan berkas citra disk ext4 sparse yang berat dan rawan kerusakan berkas sistem.
- **Booting Sangat Cepat**: Menghindari proses pemindaian `chcon` file-per-file yang lambat saat booting menggunakan metode pengetesan preservasi SELinux satu file secara cerdas.
- **Kompatibilitas Universal**: Bekerja sempurna pada Magisk, Magisk Alpha, KernelSU, dan APatch di perangkat Android 10+.

---

## Persyaratan Sistem

| Persyaratan | Detail |
|-------------|--------|
| Android | 10.0+ (API 29+) |
| Kernel | `CONFIG_OVERLAY_FS=y` & dukungan xattr `security.selinux` pada `tmpfs` |
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
        A[Mulai Flash ZIP] --> B{Cek CONFIG_OVERLAY_FS?}
        B -- Tidak --> ABORT1[Abort: OverlayFS Required]
        B -- Ya --> C{Cek tmpfs SELinux?}
        C -- Tidak --> ABORT2[Abort: Kernel Tidak Kompatibel]
        C -- Ya --> D{Cek tmpfs Trusted xattr?}
        D -- Ya --> E[Instalasi Sukses: Fitur Lengkap]
        D -- Tidak --> F[Instalasi Sukses: Warning .replace Tidak Aktif]
        E & F --> G[Buat Folder Konfigurasi & Selesai]
    end

    %% Fase Boot Awal
    subgraph Fase_Boot_Awal ["2. Fase Boot Awal (post-fs-data.sh)"]
        G --> H[Perangkat Reboot & Booting Dimulai]
        H --> I[Nyalakan Watchdog 60s & Cek Anti-Bootloop]
        I --> M[Buat Staging Area tmpfs di /mnt atau /dev]
        M --> N[Proses Seluruh Modul Aktif]
        N --> O[Salin File + Terapkan SELinux Context]
        O --> P[Beri Tanda skip_mount agar Magisk Tidak Double-Mount]
        P --> Q[Jalankan mount -t overlay untuk Menggabungkan Sistem]
        Q --> R[Lazy Umount Staging Area agar Memori Bersih]
        R --> S[Matikan Watchdog]
    end

    %% Fase Boot Akhir
    subgraph Fase_Boot_Akhir ["3. Fase Boot Akhir (service.sh)"]
        S --> T[Sistem Utama Selesai Memuat]
        T --> U[Baca Log & Perbarui Deskripsi di module.prop]
        U --> V[Tunggu Hingga sys.boot_completed=1]
        V --> W[Reset Penghitung Anti-Bootloop & Hapus Log /dev/nanomount]
        W --> X[Selesai & Sistem Berjalan Stabil]
    end

    %% Custom Styles (Transparent background & borderless design)
    style Fase_Instalasi fill:none,stroke:none
    style Fase_Boot_Awal fill:none,stroke:none
    style Fase_Boot_Akhir fill:none,stroke:none

    classDef default fill:none,stroke:#9ca3af,stroke-width:1px;
    classDef abort fill:#fee2e2,stroke:#ef4444,stroke-width:1.5px,color:#991b1b;
    classDef success fill:#d1fae5,stroke:#10b981,stroke-width:1.5px,color:#065f46;
    classDef check fill:none,stroke:#f59e0b,stroke-width:1.5px;

    class ABORT1,ABORT2 abort;
    class E,F,X success;
    class B,C,D check;
```

---

## Pengembang & Lisensi

- **Pengembang**: [dyokism](https://github.com/dyokism)
- **Lisensi**: MIT

