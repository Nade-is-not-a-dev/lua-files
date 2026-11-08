# VL Suite

Modular client-side spoof suite for **Volleyball Legends** (Roblox).
Feature modules are concatenated into one script and published via
GitHub Pages. Everything is client-side only: effects are visible on
your own screen, nothing is sent to the server.

Loadstring:

```lua
loadstring(game:HttpGet("https://nade-is-not-a-dev.github.io/vl-suite/vl-suite.lua"))()
```

## Layout

Inti suite di root repo, modul fitur di `modules/`:

- `core.lua` — inti bersama: game guard, state, helper,
  persistensi, dan pelacak READY.
- `feature-shared.lua` — PENYEDIA ALAT bersama: akuisisi
  controller Knit + seed profil, klasifikasi item, state spoof,
  dan fungsi alat (installSuiteWiring, injectInventory,
  applyEquipped, ...). Init-nya hanya menyiapkan alat; modul
  fitur memakai alatnya sendiri dan mendaftarkan kategorinya
  lewat suiteActivateFeature("Ball" / "Jersey" / ...), jadi
  alat bersama hanya menyentuh kategori yang aktif.
- `modules/ball-spoof.lua` — modul fitur: spoof bola.
- `modules/score-fx.lua` — modul fitur: spoof Score FX
  (resolver efek palsu / Random Favorites, carrier, suara
  poin, bungkus PlayScoreEffect, scrub gembok preview).
- `modules/player-card.lua` — modul fitur: spoof kartu
  pemain (resolver kartu tampil + bungkus ToggleFavorite
  untuk favorit kartu/Score FX palsu + DisplayFlashCard).
- `modules/equip-router.lua` — intersepsi
  InventoryService:Equip: klik equip item palsu dirutekan
  ke lapis lokal, item asli diteruskan ke server. Paling
  akhir di manifest; hanya merutekan kategori yang
  modulnya aktif.
- `modules/auto-shiftlock.lua` — putar karakter menghadap
  kamera saat lompat + Redirection/Boom Jump (dulu
  "Face Camera"); tidak menunggu feature-shared.
- `manifest.txt` — urutan penggabungan (inti dulu, lalu modul
  fitur sesuai urutan jalan).
- `VERSION` — versi suite (naikkan saat rilis berarti).
- `build.py` — penggabung; berjalan lokal maupun di Actions.

Modul fitur lain (settings, emote, jersey) sedang
dihapus sementara dari repo —
sumbernya tersimpan di riwayat git v0.5.1 dan dikembalikan
satu per satu.

## Alur

Push yang menyentuh inti/modul -> workflow build -> cek
sintaks luau -> terbit ke GitHub Pages (`dist/vl-suite.lua`).
Header file hasil build memuat versi + commit + tanggal, dan
tercetak ke konsol saat script jalan, jadi versi yang aktif
selalu bisa diverifikasi.

## Konvensi

- Baris `READY` dicetak real time oleh pelacak di `core.lua`:
  hanya setelah semua modul terdaftar benar-benar selesai
  init, jadi selalu jadi baris terakhir di console. Modul
  baru: panggil `suiteExpectModule("nama")` di top level file
  dan `suiteModuleLoaded("nama")` di akhir init-nya.
- Setiap init modul mencetak baris timing "ready in ...s"
  untuk memburu sumber lag di awal jalan.
- Console hanya memuat log [VL Suite]: modul tidak mencetak
  log bermerek sendiri; warn kegagalan pun memakai awalan
  [VL Suite].
