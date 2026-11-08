# VL Suite (modular)

Sumber VL Suite dalam bentuk modul, digabungkan otomatis oleh
GitHub Actions menjadi satu file untuk loadstring.

## Loadstring

```lua
loadstring(game:HttpGet("https://nade-is-not-a-dev.github.io/lua-files/vl-suite.lua"))()
```

## Layout

- `core.lua` — inti bersama: game guard, state, helper,
  persistensi.
- Modul fitur (menyusul): satu file per fitur di folder ini,
  didaftarkan di `manifest.txt` sesuai urutan jalan.
- `manifest.txt` — urutan penggabungan.
- `VERSION` — versi suite (naikkan saat rilis berarti).
- `build.py` — penggabung; berjalan lokal maupun di Actions.

## Alur

Push ke `suite/**` -> workflow build -> cek sintaks luau ->
terbit ke GitHub Pages (`dist/vl-suite.lua`). Header file hasil
build memuat versi + commit + tanggal, dan tercetak ke konsol
saat script jalan, jadi versi yang aktif selalu bisa diverifikasi.
File hasil build diakhiri baris penanda `READY` yang hanya
tercetak bila semua modul selesai dimuat tanpa error.
