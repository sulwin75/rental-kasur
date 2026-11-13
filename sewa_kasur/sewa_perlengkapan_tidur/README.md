# Sewa Perlengkapan Tidur — Supabase

## Konfigurasi
Aplikasi sudah dikonfigurasi memakai Supabase project URL dan publishable key yang diberikan pemilik project di `index.html`.

- `index.html`: PWA dengan login Supabase, data barang online, transaksi sewa per malam, DP, pelunasan, dan riwayat transaksi.
- `supabase_schema.sql`: skema database dan RPC transaksi.
- `manifest.webmanifest`, `sw.js`, `icon.svg`: aset PWA.

## Pembaruan: banyak barang dalam satu transaksi
1. Jalankan `supabase_multi_item.sql` di Supabase SQL Editor LEBIH DULU.
2. Setelah itu baru ganti file aplikasi di GitHub/Netlify dengan isi folder ini.
3. `sw.js` diperbarui (selalu ambil halaman terbaru), jadi pembaruan berikutnya langsung sampai ke HP.

## Stok otomatis
Stok yang tampil dihitung dari transaksi yang tercatat: "tersedia" = total stok dikurangi barang yang sedang disewa/dipesan pada tanggal tersebut. Total stok tetap diubah lewat "Ubah harga/stok". Barang kembali tersedia otomatis setelah tanggal kembali, atau bila status transaksi "Dibatalkan".

## Cara deploy / memperbarui Netlify
1. Ekstrak ZIP ini.
2. Unggah isi folder `sewa_perlengkapan_tidur` ke repository GitHub yang terhubung ke Netlify (gantikan file lama).
3. Commit dan push perubahan.
4. Tunggu Netlify selesai deploy, lalu buka alamat website melalui HTTPS.
5. Login memakai akun yang telah dibuat di Supabase Authentication.

## Catatan
- Gunakan Project URL dasar `https://...supabase.co`, bukan URL REST `/rest/v1/`.
- Publishable/anon key boleh ada di frontend; jangan pernah memasukkan `service_role` atau secret key.
- Pastikan tabel dan fungsi pada `supabase_schema.sql` sudah dibuat di project Supabase.
- RLS di skema awal memberi akses data operasional kepada semua pengguna yang berhasil login. Perketat kebijakan per role sebelum pemakaian produksi.
- Pengujian login, baca/tulis data, dan deploy harus dilakukan pada project/website milik pengguna; ZIP ini belum membuktikan bahwa website Netlify sudah diperbarui.
