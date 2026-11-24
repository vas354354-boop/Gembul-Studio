# Aplikasi Android dan iOS

Aplikasi native menggunakan Capacitor dan memuat halaman pelanggan serta area staf dari website. Booking, akun/member, POS, CRM, inventori, pemasaran, dan autentikasi memakai Supabase; bundle aplikasi hanya berisi konfigurasi publik untuk browser. Jangan pernah menambahkan Supabase service-role key ke aplikasi.

## Sinkronisasi aplikasi

```powershell
npm ci
npm run mobile:sync
```

`mobile:sync` membangun ulang `mobile/www` dari halaman dan gambar situs, lalu menyinkronkannya ke proyek Android dan iOS. Folder `mobile/www` serta salinan aset native merupakan hasil build, bukan sumber yang diedit langsung. Area staf berisi Kasir POS, CRM, inventori/penerimaan pembelian, riwayat transaksi/refund, laporan keuangan, voucher, dan persiapan pesan WhatsApp. Modul keuangan, refund, promosi, dan kampanye dibatasi untuk Super Admin; aplikasi tidak mengirim pesan WhatsApp otomatis.

## Android

Pasang Android Studio dan JDK yang didukung oleh versi Android Gradle Plugin proyek. Buka folder `android` melalui Android Studio, pilih emulator atau perangkat, lalu jalankan konfigurasi aplikasi. Untuk menghasilkan APK/AAB rilis, konfigurasi signing key privat di Android Studio; jangan commit key atau password signing.

Perintah untuk membuka proyek dari komputer yang memiliki Android Studio:

```powershell
npm run mobile:open:android
```

## iOS

Build dan signing iOS harus dilakukan di macOS dengan Xcode. Buka workspace/proyek `ios/App` melalui Xcode, pilih team signing dan target perangkat, lalu arsipkan aplikasi melalui Organizer.

Perintah untuk membuka proyek pada Mac yang memiliki Xcode:

```sh
npm run mobile:open:ios
```

Pengiriman ke Google Play atau Apple App Store memerlukan akun developer, signing, serta proses review masing-masing toko. APK/IPA rilis belum dibuat oleh sinkronisasi Capacitor.

## Auth dan backend

Tautan reset password dari aplikasi native diarahkan ke `https://gembul-studio.vercel.app/account.html`. Pastikan halaman pemulihan password versi terbaru sudah dipublikasikan di URL tersebut sebelum menguji reset dari aplikasi. Proses booking, login, dan metrik admin memerlukan koneksi internet serta RPC/migrasi Supabase yang sesuai sudah diterapkan.

Untuk memakai seluruh fungsi admin, jalankan migrasi berikut secara berurutan di Supabase SQL Editor setelah migrasi dasar lainnya:

1. `supabase/migrations/20261124010000_admin_dashboard_metrics.sql`
2. `supabase/migrations/20261124020000_admin_booking_operations.sql`
3. `supabase/migrations/20261124030000_business_operations.sql`

Migrasi bisnis menambahkan RPC transaksi idempotent, stok dan HPP, refund penuh, CRM/izin pemasaran, pemasok/pembelian, pengeluaran, laporan, voucher, dan segmentasi kampanye. Perubahan repository ini tetap lokal; migrasi belum diterapkan ke Supabase live. Sebelum dipakai, uji migrasi di proyek Supabase staging dan pastikan konfigurasi Auth/redirect URL sesuai.
