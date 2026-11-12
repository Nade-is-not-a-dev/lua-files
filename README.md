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
  modul avatar kembali)
  + baris Settings Stats Spoofer (pola yang sama lagi,
  membuka panel modul stats-spoof) + baris Settings Auto
  Farm (pola yang sama lagi, membuka panel bundle
  otomatisasi) + pemuat bundle otomatisasi: fetch
  `vl-automation.lua` dari Pages saat runtime (anti-cache,
  nil-guarded; gagal fetch tidak fatal).
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
- `modules/stats-spoof.lua` — modul fitur: Stats Spoofer.
  Panel (dibuka dari Settings > VL Stats > Open) berisi 10
  kotak angka: Wins, Losses, MVPs, Games, Points, Spikes,
  Blocks, Aces, Saves, Elo (kotak kosong = tidak di-spoof).
  Tiga permukaan ditimpa, semua client-side: (1) flash card
  — bungkus DisplayFlashCard kedua setelah player-card,
  menimpa Context.Custom (Wins/Losses/SeasonRank dari Elo
  via Configuration.Ranks game sendiri) dan Context.
  SingleStat sesuai Metadata.Stat kartu; (2) halaman Career
  — Fusion Value CareerController.Career ditimpa klon
  berangka spoof, sinkron server (ProfileUpdated "Career" +
  CareerService.DataUpdated) dicerminkan ke snapshot asli
  lalu ditimpa lagi; (3) tab Ranked — InterfaceController.
  Ranked adalah Computed dari Seasonal, jadi Seasonal
  ditimpa klon dengan .Ranked spoof (tipe Seasonal membawa
  target; tipe lain di-nol-kan agar agregat pas), cermin
  RankedService.DataUpdated juga dijaga. Reset memulihkan
  snapshot asli. Digembok Extreme Ultra Fast Mode lewat
  reconcile berkala (statistik = spoof, bukan alat bantu).
  Nilai tersimpan di simpanan lokal (StatsSpoof) dan
  diterapkan lagi otomatis saat masuk game.
- `automation/` — bundle otomatisasi, SENGAJA di luar
  penggabungan suite: fitur berat yang berjalan sendiri,
  diterbitkan sebagai file terpisah `dist/vl-automation.lua`
  yang DI-OBFUSCATE (Prometheus, config light:
  `automation/obfuscate-config.lua`; langkah build:
  `automation/build-automation.sh`) dan dimuat suite saat
  runtime. Karena di-obfuscate terpisah, semua kebutuhan
  bersamanya diambil dari bridge `getgenv().VLBridge` yang
  diterbitkan `feature-shared.lua` (state S, saveLocal,
  loadLocal, Knit, FeatureAPI, konstanta settings) — bukan
  dari local chunk suite. Modul suite lain TIDAK ikut
  di-obfuscate.
  - `automation/auto-farm.lua` — Auto Farm: porting utuh
    farm v15 extreme (loop join -> farm Block-only ->
    post-match -> reset/respawn -> ulang, handler serve,
    klaim reward level + redeem kode otomatis dengan alur
    respawn-first, error logger ke file, mode Fast/Ultra
    game). TANPA HUD di layar: semua kontrol di panel
    Settings > VL Farm > Open — saklar AUTO persisten
    (sekali ON, suite mengantrekan dirinya lewat
    queue_on_teleport gaya Infinite Yield, jadi farm
    lanjut sendiri setelah rejoin/pindah server tanpa
    autoexec), toggle manual TP/BALL/SPIKE/JUMP, kotak
    interval Block, status, dan progres level 15 sebagai
    teks.
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
selalu bisa diverifikasi. Push yang menyentuh `automation/`
ikut memicu workflow: bundle otomatisasi di-obfuscate dengan
Prometheus lalu diterbitkan di sampingnya sebagai
`dist/vl-automation.lua` (cek sintaks luau berlaku juga).

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
