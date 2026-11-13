# AGENTS.md — VL Suite

Panduan kerja untuk agent (dan manusia) yang mengedit repo ini.

## Apa ini

Suite script Roblox **client-side** untuk game **Volleyball Legends**.
Modul fitur digabung jadi satu file (`dist/vl-suite.lua`) dan
dipublish via GitHub Pages; dipakai lewat loadstring. Semua efek
hanya terlihat di layar sendiri.

```lua
loadstring(game:HttpGet("https://nade-is-not-a-dev.github.io/vl-suite/vl-suite.lua"))()
```

## Struktur

- `core.lua` — inti: game guard, state bersama `S`
  (persisten di `getgenv().VLBallSpoofState` + file
  `vl-ball-spoof.json`), helper, pelacak READY.
- `feature-shared.lua` — penyedia alat bersama: akuisisi controller
  Knit, `injectInventory`/`applyEquipped`/`applyFavorites`,
  `installSuiteWiring`, `showSpoofAlert` (dihapus v0.22.8),
  konstanta kategori item dan anggota Settings.
- `modules/*.lua` — modul fitur. Urutan concat di `manifest.txt`
  (inti dulu, lalu modul); `build.py` menggabungkan + stempel
  versi; CI: `.github/workflows/build-suite.yml` (build →
  `luau-compile` → deploy Pages) dan
  `luau-validate.yml` (manual, `luau-analyze`).

## Konvensi WAJIB

1. **Satu chunk.** Semua file digabung jadi SATU chunk Lua:
   - Top-level `local` di file A terlihat oleh file yang
     DITANGKIS lewat manifest.
   - Konsekuensi bug klasik: identifier dideklarasikan `local`
     di file TERAKHIR tapi dipakai di file LEBIH AWAL dikompilasi
     sebagai global (nil saat runtime). Pernah kejadian dua kali
     (`ALERT_*` v0.22.7, `spoofedWorldFx` v0.22.8). Aturan:
     konstanta/fungsi yang dipakai lintas modul harus
     didefinisikan di `core.lua`/`feature-shared.lua` (lebih awal)
     atau lewat registry `FeatureAPI`.
2. **Pelacak READY**: tiap modul memanggil
   `suiteExpectModule("nama")` di top level dan
   `suiteModuleLoaded("nama")` di akhir init-nya.
3. **Log** hanya memakai awalan `[VL Suite]`, termasuk warn.
4. **State**: semua persisten lewat `S` (getgenv) + field
   `S.settings`/skala di `saveLocal()`/`loadLocal()`
   (feature-shared). Bila menambah field yang dibaca loadLocal,
   tambahkan juga di saveLocal dan guard nil-nya di atas.
5. **Registry lintas modul**: pemanggilan fungsi modul-fitur dari
   file yang lebih awal lewat `FeatureAPI.nama(...)` dengan
   nil-guard (`if FeatureAPI.x then ... end`).
6. **Guard versi**: init modul idempoten — guard
   `getgenv().VL<Modul>Installed` + `S.installed<Modul>`, karena
   re-run di sesi yang sama tidak boleh double-wrap.
7. **Edit modul, bukan `dist/`** — `dist/` hasil build.
   Naikkan `VERSION` (semver kecil: fix patch, fitur minor).
8. Validasi: `python3 build.py` + CI. `luau-analyze` lokal
   bagus untuk menangkap global bocor; pola noise yang wajar:
   global Roblox/executor (task, getgenv, Instance, ...) — anggap
   temuan "Unknown global" di luar daftar itu sebagai bug nyata.

## Pengetahuan game (dari dump decompiled, root repo)

Dump: `ReplicatedFirst/`, `ReplicatedStorage/`, dst. (client-only —
tidak ada kode server; Knit *service* diverifikasi lewat callsite).

### Inventory & equip
- `InventoryController` (Fusion Value, TANPA `.Data`):
  `Inventory`, `Equipped`, `Favorited`, `Selected`
  (`Controllers/InventoryController/_source.lua:57–61`).
- `InventoryService:Equip(id[, slot])`,
  `InventoryService:ToggleFavorite(id)` — klien memanggil lewat
  proxy Knit; server tidak ada di dump.
- Favorite: UI hanya menampilkan FavBtn untuk **ScoreEffect**;
  **PlayerCard** punya FaveBtn sendiri
  (`Inventory/PlayerCard/Info.lua:96`).
- `Content.Item` (`ReplicatedStorage/Content/Item/_source.lua`):
  `Get(id)`, `GetAllIdsFromType(type)`, `Type` table
  (`Types.lua`: Ball/Emote/ScoreEffect/Jersey/PlayerCard/...).
  Field `Item.Asset` HANYA ada di entity PlayerCard
  (bukan bola). Prop emote via `Metadata.Handler.run`
  (mutator `Content/Item/Mutators/Emote.lua`).

### Bola & hit (penting untuk modul hitbox/bola)
- Pemilik bola: atribut **`ServedByPlayer` di INSTANSI bola**
  (nama pemain) — dibaca `BallController/_source.lua:40` pada
  instansi bertag `HeadBall`; mode Training = pemain lokal.
  BUKAN di ReplicatedStorage.
- Bola terbang: `Ball.new(model, cframe, velocity, itemData)`
  (`BallController/Ball.lua:21`); bola serve di tangan dibuat
  server dengan tag **`WeldedBall`**; bola replay:
  `GhostBall.new(clip, skinName, parent)`
  (`ReplayController/Stage/GhostBall.lua`).
- **Sistem hitbox pukulan**
  (`GameController/Actions/Move/DoMove/ClientHitbox.lua`):
  1. `Orchestrator.processHitboxCollision` memanggil
     `ClientHitbox.new{Hitbox, MovementName, Ball, Charge,
     Duration, HitboxSize?, HitboxOffset?, SpeedFactor,
     TiltFactor}`. `HitboxSize`/`HitboxOffset` hanya bila special
     Action aktif punya `Metadata.HitboxSize`
     (`StyleSpecial.computeSpecialHitboxParams`).
  2. Ukuran dasar = `params.HitboxSize or params.Hitbox.Size`;
     Hitbox per move dari `ReplicatedStorage/Tools/Hitbox.lua`
     (`get`/`register`: `Offset`, `Size`, `Custom`, `DebugColor`
     dari assembly `Assets/HitboxesNew/{Default,BySpecial}/...
     /Assemblies/<Move>`). `Custom.AdjustBoundsLocal(offset,
     size)` adalah hook per move (dipakai Encho).
  3. Saat move `CreateServerHitbox ~= nil` di `Configuration/
     Game/Ball.lua` (semua move pukulan) → klien juga memanggil
     `BallService:CreateHitbox{Key, Move, BallId, Charge,
     ClientTimestamp}`; Key = `<Move><os.clock()ms>`.
  4. `tryCollidingWithBall`: part hitbox diposisikan dari
     karakter + TiltJoint C0, diperluas oleh SpeedFactor
     (lerp 0..4 di Z + 3 di X saat bergerak cepat) dan TiltFactor
     (offset arah tilt), lalu `workspace:GetPartsInPart` dengan
     filter bertag `Ball`; part bola pertama yang lolos
     `Common.Physics.canInteract` dikembalikan.
  5. `canInteract(player, moveName, ballPos)`
     (`Common/Physics.lua:318`): bola harus di sisi tim sendiri
     (`isPointOnTeamSide`), `DistanceFromCharacter <= 20` (Dive
     30), debounce tim terakhir yang memukul (0.25 s / 10 stud),
     aturan serve/blok/spike. INI GERBANG JARAK — hitbox lebih
     besar dari itu di-clamp.
  6. Saat hit: klien memanggil `BallService:Interact{Move,
     BallId, Key, LookVector, MoveDirection, TiltDirection,
     Charge, SpecialCharge, ClientCanRunSpecial, Timestamp,
     CustomClient, From="Client"}`. Deteksi ADA DI KLIEN; validasi
     server (hitbox server + `MaxPingCompensation` 0.5 s di
     `Configuration/Game/Physics.lua`) tidak ada di dump — jaga
     perubahan tetap moderat.
- Debug visual hitbox milik game: `Configuration.Game._DebugHitboxes
  = true` (konsol ToggleHitboxes) → part hitbox digambar transparan
  neon (`IsDebugMode` hanya true di Studio). Modul hitbox-expander
  TIDAK memakainya (kotak di karakter tidak dinyalakan); visualnya
  cincin jangkauan sendiri: sphere semi-transparan radius 20 yang
  mengikuti tiap bola bertag `Ball`
  (warna dari `isPointOnTeamSide` + `DistanceFromCharacter`).
- Timer: `DefaultHitboxDuration = 0.3` s; Block/JumpSet juga
  berhenti saat `States.IsJumping` false.
- Gerbang lain: `isBallInNetBoundary` (bola harus di area net),
  `isHitboxSkipped` (blokir self-hit), `isMoveInvalidOnServe`.

### Spoof statistik/nama
- `DisplayFlashCard(controller, data)` — data punya
  `Player`, `PlayerCardItemId`, `Context.SingleStat`,
  `Context.Custom` (`PlayerCardController/_source.lua:56–76`).
- `CareerController.Career` = Fusion Value;
  `DataService.ProfileUpdated` key `"Career"`/`"Seasonal"/
  "Equipped"/"Favorited"/"Settings"`;
  `CareerService.DataUpdated(delta)` 1-arg;
  `RankedService.DataUpdated(typeKey, entry)` 2-arg;
  `InterfaceController.Ranked = Computed(Seasonal)` — spoof
  lewat mutasi `Seasonal.Ranked`.
- Field stat: `Configuration/Career.lua`; ranked:
  `{Elo, Wins, Games}` per tipe (`CareerController/RankedStats.lua`),
  Losses = Games - Wins. Elo → rank:
  `Configuration/Ranks.lua` (`getRankFromElo`, `isUnranked`).

### Settings (grup VL Settings)
- `SettingsController` (Knit controller) + `SettingsService`
  (Knit service, `ChangeSetting(key, value)`).
- Grup: `ReplicatedStorage/Configuration/SettingsGroups.lua`
  (`Order` array + `Data` map). Halaman dibangun game lewat
  `SettingsController/GroupPages.lua` (`_loadPage`, `_loadRows`,
  `_loadSettingsRow`).
- Kunci komposit suite: `VLSettings_<Member>` di Value
  `InterfaceController.Settings`; anggota saat ini:
  `WorldAffectingScoreFX`, `ExtremeUltraFastMode`,
  `AutoShiftlock`, `HitboxExpander`. `ChangeSetting` kunci milik
  suite ditangani lokal di wrapper `modules/settings.lua`
  (server tidak mengenal kunci komposit; bila bocor ke server
  jadi baris raw-key di halaman utama).
- Panel (Username/Stats/Avatar): baris tombol `[Open]` klon
  template `BB_TextLabel` + `B_Template` milik
  `ButtonEditController:LoadSettingsButton`.

## Rilis

1. Edit modul, naikkan `VERSION`.
2. `python3 build.py` (lokal) → push → CI build + `luau-compile`
   → Pages. `dist/vl-suite.lua` memuat versi+commit di header dan
   mencetaknya saat script jalan.

## Masih di monolit (belum dimodularkan)

- og-tag (Bagian C) dan avatar host (Bagian D) di `core.lua`.
