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
- `modules/init.lua` — sistem yang dimuat AWAL, bukan
  fitur tampilan: pengawatan event bersama, sistem equip
  (bungkus InventoryService.Equip), dan sistem favorite
  (bungkus InventoryService.ToggleFavorite). Modul fitur
  tidak memasangnya sendiri.
- `modules/ball-spoof.lua` — modul fitur: spoof bola.
- `modules/score-fx.lua` — modul fitur: spoof Score FX
  (resolver efek palsu / Random Favorites, carrier, suara
  poin, bungkus PlayScoreEffect, scrub gembok preview).
- `modules/settings.lua` — modul fitur: grup VL Settings
  (saklar World-Affecting Score FX + halaman grup) dan baris
  Settings Avatar Lite (tombol Open-nya nil-guarded sampai
  modul avatar kembali) + baris Settings Username Spoofer
  (pola baris yang sama, membuka panel modul username-spoof).
- `modules/player-card.lua` — modul fitur: spoof kartu
  pemain (resolver kartu tampil + DisplayFlashCard).
- `modules/jersey.lua` — modul fitur: spoof jersey
  (render lokal di karakter sendiri + penjaga timpaan
  server + bungkus Jersey Preview).
- `modules/emote.lua` — modul fitur: spoof emote (slot
  roda palsu + prop lokal untuk emote berproperti).
- `modules/extreme-ultra-fast.lua` — modul fitur: Extreme
  Ultra Fast Mode (saklar di grup VL Settings). Visual game
  dicabut sampai tinggal yang penting (tekstur dunia,
  SurfaceAppearance, Sky/Atmosfer, partikel + cahaya dinamis,
  bayangan, PostEffect, kualitas Level 1; karakter, bola, dan
  net tidak disentuh) DAN semua fitur spoof digerbang mati
  lewat flag S.extremeFast yang dibaca alat bersama + bungkus
  tiap modul. Mati = semua dipulihkan, fitur diterapkan lagi.
- `modules/auto-shiftlock.lua` — putar karakter menghadap
  kamera saat lompat + Redirection/Boom Jump (dulu
  "Face Camera"); tidak menunggu feature-shared.
- `modules/username-spoof.lua` — modul fitur: Username
  Spoofer. Panel (dibuka dari Settings > VL Username > Open)
  berisi TextBox + tombol Apply yang merupakan klon kotak
  redeem code bawaan game (Shop > Codes > EnterBox /
  EnterButton). Nama yang ditulis menggantikan username +
  display name lokal di seluruh permukaan GUI (leaderboard,
  kartu, statistik, spectate, lobi, skor, chat) lewat sapuan
  teks: teks asli dicatat dan ditimpa, objek baru diawasi
  lewat DescendantAdded + penjaga perubahan Text + sapuan
  berkala; Reset memulihkan semua teks persis. Client-side
  saja; nametag di atas kepala (digambar engine) tidak
  berubah. Nama tersimpan di simpanan lokal dan diterapkan
  lagi otomatis saat masuk game.
- `manifest.txt` — urutan penggabungan (inti dulu, lalu modul
  fitur sesuai urutan jalan).
- `VERSION` — versi suite (naikkan saat rilis berarti).
- `build.py` — penggabung; berjalan lokal maupun di Actions.

Semua modul dari v0.5.1 sudah kembali. Yang masih tinggal di
monolit: og-tag (Bagian C) dan avatar host (Bagian D).

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
