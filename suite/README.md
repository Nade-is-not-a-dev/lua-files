# VL Suite (modular)

Sumber VL Suite dalam bentuk modul, digabungkan otomatis oleh
GitHub Actions menjadi satu file untuk loadstring.

## Loadstring

```lua
loadstring(game:HttpGet("https://nade-is-not-a-dev.github.io/vl-suite/vl-suite.lua"))()
```

## Layout

- `core.lua` — inti bersama: game guard, state, helper,
  persistensi.
- `feature-shared.lua` — PENYEDIA ALAT bersama (Bagian A):
  akuisisi controller Knit + seed, klasifikasi item, state
  spoof, dan fungsi alat (installSuiteWiring, injectInventory,
  applyEquipped, ...). Init-nya hanya menyiapkan alat; modul
  fitur memakai alatnya sendiri dan mendaftarkan kategorinya
  lewat suiteActivateFeature("Ball" / "Jersey" / ...), jadi
  alat bersama hanya menyentuh kategori yang aktif.
- `ball-spoof.lua` — modul fitur pertama: spoof bola saja.
- `auto-shiftlock.lua` — putar karakter menghadap kamera
  saat lompat + Redirection/Boom Jump (dulu "Face Camera");
  tidak menunggu feature-shared.

Untuk sekarang (2026-11-08) hanya ball-spoof yang aktif di
manifest; modul fitur lain (score-fx, settings, player-card,
emote, jersey, equip-router) dihapus sementara dari repo —
sumbernya tersimpan di riwayat git v0.5.1 dan dikembalikan
satu per satu.
Setiap init modul mencetak baris timing "ready in ...s"
untuk memburu sumber lag di awal jalan.
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
Baris `READY` dicetak real time oleh pelacak di `core.lua`:
hanya setelah semua modul terdaftar benar-benar selesai
init, jadi selalu jadi baris terakhir. Konvensi modul baru:
panggil `suiteExpectModule("nama")` di top level file dan
`suiteModuleLoaded("nama")` di akhir init-nya.
