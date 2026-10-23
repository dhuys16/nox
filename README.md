# Nox Panel untuk Windows 11

Widget Flutter di tengah atas monitor utama. Window OS tetap **600×200 logical pixel**; `AnimatedContainer` hitam berubah antara idle **200×30**, media **400×30**, dan expanded **400×150**. Ukuran fisik mengikuti DPI Windows.

## Menjalankan

Prasyarat:

- Flutter stable (Dart ≥3.8), dengan Windows Desktop aktif.
- Visual Studio 2022, workload **Desktop development with C++**, CMake dan Windows SDK yang menyertakan C++/WinRT (10.0.19041 atau lebih baru).
- Rust stable MSVC melalui rustup, dibutuhkan oleh `smtc_windows`.
- Windows Developer Mode aktif agar Flutter dapat membuat symlink plugin. Buka Settings → System → Advanced → For developers, atau jalankan `start ms-settings:developers`.

```powershell
flutter config --enable-windows-desktop
flutter doctor -v
rustup default stable-x86_64-pc-windows-msvc
flutter pub get
flutter run -d windows
```

Build distribusi:

```powershell
flutter build windows --release
```

Distribusikan **seluruh folder** `build/windows/x64/runner/Release`, termasuk DLL dan `data`, bukan hanya EXE. Mesin tujuan memerlukan Microsoft Visual C++ Redistributable x64. `sqlite3` yang di-resolve melalui lockfile menggunakan native assets; tidak perlu mengunduh SQLite DLL secara manual.

Untuk membangun paket portabel dan membuat shortcut Desktop sekaligus:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build-portable.ps1 -DesktopShortcut
```

Hasilnya berada di `dist/NoxPanel`, dengan ZIP `dist/NoxPanel-portable.zip` dan shortcut `dist/Nox Panel.lnk`. Skrip menyertakan runtime C++ dari Build Tools bila tersedia dan menggunakan junction plugin tanpa mengubah pengaturan Developer Mode. `smtc_windows` menggunakan runtime `flutter_rust_bridge` versi 2.11.1 yang sesuai kode generator paket tersebut.

## Penggunaan

- Hover membuka panel; keluar dari area widget menutupnya setelah 350 ms. Klik panel ringkas atau tombol pin untuk menyematkan/melepas panel. Navigasi horizontal di kiri atas memakai ikon musik, timer, dan jadwal dengan tooltip. Tombol pin dan keluar berada di kanan atas. Memilih tab menyematkan panel agar form tidak menutup saat diketik.
- **Media** menampilkan judul satu baris maksimal 220 px (elipsis untuk judul panjang) dan artis di atas sampul album 46 px yang berada di tengah, dengan previous di kiri dan next di kanan. Klik sampul untuk play/pause. Panel membaca sesi yang dipilih Windows, metadata, album art, dan kemampuan tombol. Pemutar harus mendukung SMTC (misalnya Spotify atau browser yang menyediakan sesi media).
- **Timer** menyediakan preset 5/15/25 menit dan durasi khusus 1–1440 menit. Countdown dihitung dari deadline absolut, sehingga tidak bergeser akibat frame terlambat atau sleep. Deadline dipulihkan saat restart; timer yang sudah habis menjadi pengingat.
- **Jadwal** menerima judul dan waktu lokal `HH:mm`. Waktu yang sudah terlewat berarti besok. Centang pengulangan untuk pengingat minum setiap 60 menit setelah pengingat sebelumnya diselesaikan.
- Pengingat membuka panel otomatis dan tetap tersimpan sampai diselesaikan. Pengingat yang jatuh tempo ketika aplikasi tertutup muncul saat aplikasi dibuka lagi. Pemeriksaan background berjalan di dalam proses aplikasi, bukan Windows Service; tidak ada notifikasi saat proses dimatikan.
- Tombol × di panel menutup aplikasi. Aplikasi tidak tampil di taskbar.

## Arsitektur

| File | Tanggung jawab |
| --- | --- |
| `lib/main.dart` | Bootstrap SQLite/SMTC, HWND, window transparan, top center, always-on-top dan skip taskbar |
| `lib/island_view.dart` | AnimatedContainer dengan kurva SpringSimulation, jam, form dan kontrol media |
| `lib/island_controller.dart` | ChangeNotifier, state hover/pin, pemeriksaan deadline dan pengingat, polling GSMTC |
| `lib/services/window_region.dart` | Hit region Win32 berdasarkan ukuran dan radius aktual setiap frame, dengan konversi DPI |
| `lib/services/local_store.dart` | SQLite versi 1, pengingat, pengulangan dan deadline timer; expiry atomik dalam transaksi |
| `lib/services/media_service.dart` | MethodChannel bertipe untuk metadata dan kontrol global |
| `windows/runner/media_bridge.*` | GSMTC C++/WinRT pada worker MTA; hasil dikembalikan di platform thread melalui PostMessage |

### Area transparan dan klik

`SetWindowRgn` membatasi bentuk native window ke kontur widget yang terlihat, termasuk sudut membulat. Area lain dari window 600×200 tidak termasuk hit region, sehingga klik langsung diterima aplikasi di belakangnya. Region dihitung dari layout dan dekorasi yang sedang dianimasikan, bukan target ukuran akhir. `win32` menyediakan `SetWindowRgn` dan pengelolaan handle; binding FFI `CreateRoundRectRgn` ditambahkan karena fungsi ini belum diekspor oleh win32 5.x.

Tidak ada polling posisi mouse, pergantian `WS_EX_TRANSPARENT`, atau `HTTRANSPARENT` yang hanya meneruskan pesan ke window di thread sama. Seluruh widget hitam tetap interaktif dan menerima input keyboard. Tidak ada perubahan ukuran native window selama transisi UI.

### SMTC dan GSMTC

`smtc_windows` merupakan **publisher** sesi media aplikasi sendiri; API tersebut tidak menyediakan pembacaan sesi global milik aplikasi lain. Runtime diinisialisasi sesuai stack yang diminta, tanpa membuat pemutar palsu. Bridge menggunakan `GlobalSystemMediaTransportControlsSessionManager` untuk menemukan sesi global dan memanggil `TryPlayAsync`, `TryPauseAsync`, `TrySkipNextAsync`, serta `TrySkipPreviousAsync`.

Metadata diperiksa setiap dua detik. Semua penantian WinRT berlangsung pada worker MTA, bukan UI thread. Album art dibatasi 8 MiB dan disimpan di cache untuk lagu/sesi yang sama. Sesi kosong menampilkan keadaan idle; kegagalan sesi ditampilkan di panel dan polling berikutnya mencoba kembali. Indikator waveform bersifat dekoratif: GSMTC tidak menyediakan sampel audio mentah.

Referensi: [smtc_windows](https://pub.dev/packages/smtc_windows), [GSMTC Microsoft](https://learn.microsoft.com/en-us/uwp/api/windows.media.control.globalsystemmediatransportcontrolssessionmanager), [SetWindowRgn Microsoft](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowrgn).

## Validasi

```powershell
dart analyze
flutter test
```

Tes mencakup persistensi pengingat setelah restart, reschedule pengingat berulang, expiry timer atomik, serta geometri widget/region selama transisi idle → media → expanded. Tes widget merekam region tanpa memodifikasi window mesin pengujian.

Sesudah membuat paket portabel, pemeriksaan native dapat dijalankan dengan:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-portable.ps1
```

Skrip membuka EXE, memeriksa ukuran client 600×200 dengan skala DPI, always-on-top, serta region Win32 pada area transparan/sudut/pusat widget, lalu menutup proses pengujian. Hasilnya disimpan di `.tools/smoke-result.json`. Opsi `-LeaveRunning` selanjutnya meluncurkan aplikasi melalui Windows Shell, terpisah dari proses pengujian; bila aplikasi sudah berjalan, instance tersebut dipertahankan. Untuk pemakaian biasa, buka shortcut Desktop **Nox Panel**. Aplikasi tidak memiliki waktu kedaluwarsa atau auto-hide ketika idle; panel hanya menyusut menjadi jam 200×30.

Pengujian manual pada Windows 11 diperlukan untuk jalur native:

1. Jalankan bersama Spotify/browser; cek metadata dan artwork, pause/play, next/previous, lalu tutup pemutar.
2. Letakkan aplikasi lain di belakang island; klik area transparan, sudut membulat dan kontrol hitam, termasuk selama ekspansi/collapse.
3. Ulangi dengan display scaling 100%, 150%, 200%. Pastikan window tetap 600×200 logical pixel dan posisi top center benar.
4. Atur jadwal satu menit mendatang dan timer; tutup/buka aplikasi melewati deadline, lalu cek satu notifikasi dan data tersimpan.
5. Sleep/resume Windows; cek deadline diproses setelah resume dan kontrol media tersambung kembali.

Posisi awal memakai monitor utama. Pemilihan monitor, startup otomatis, tray menu dan Windows toast berada di luar implementasi ini.

