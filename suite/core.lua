----------------------------------------------------------------
-- suite/core.lua -- inti bersama VL Suite (versi modular)
--
-- Berisi: game guard (hanya jalan di Volleyball Legends),
-- state bersama, helper, persistensi vl-ball-spoof.json, dan
-- loading overlay (Bagian 0). Modul fitur (ball-spoof,
-- face-camera, score-fx, ...) akan menyusul sebagai file
-- terpisah dan digabungkan SETELAH file ini oleh build.py.
--
-- Kode di bawah header ini diekstrak apa adanya dari
-- vl-ball-spoof.lua monolit (semua baris sebelum Bagian A).
----------------------------------------------------------------
--[[
    VL Ball Spoof + Face Camera -- Volleyball Legends (CLIENT-SIDE SAJA)

    SCRIPT GABUNGAN untuk AUTOEXEC:
    - Bagian A: Ball Spoof (di bawah).
    - Bagian B: Face Camera (lompat + Redirection/Boom Jump) --
      isi face-camera-jump-redirect.lua, digabung di berkas ini.
    Kedua bagian di-init di thread terpisah dengan cek kesiapan
    sendiri-sendiri (tunggu game selesai loading, LocalPlayer ada,
    Knit + controller/service siap, state awal server sudah ter-seed),
    jadi aman dijalankan executor sejak detik pertama masuk game,
    dan bila satu bagian gagal siap, bagian lain tetap jalan.

    === Bagian A: Ball Spoof ===

    Membuat SEMUA bola di game tampil di inventory dan bisa
    di-equip / unequip seolah-olah bola asli -- padahal semuanya lokal:

    (Soal favorite: game ini memang TIDAK punya favorite untuk bola.
    Dari kode UI-nya sendiri, tombol FavBtn hanya muncul bila item
    yang dipilih bertipe ScoreEffect. Jadi spoof ini tidak menyentuh
    sistem favorite sama sekali -- favorite ScoreEffect-mu bekerja
    100% asli.)

    1. INVENTORY: semua id bola (Content.Item tipe Ball) disuntikkan ke
       state Inventory milik InventoryController, jadi grid inventory
       menggambar semuanya.
    2. EQUIP PALSU: panggilan InventoryService:Equip untuk bola yang
       TIDAK dimiliki ditangani lokal (state Equipped controller
       ditimpa gabungan server + lokal). Bola yang beneran dimiliki
       tetap diteruskan ke server seperti biasa.
    3. RENDER: Ball.new (pabrik bola terbang) dibungkus -- saat ada bola
       palsu yang ter-equip, model + data Item yang dipakai adalah milik
       skin palsu itu sendiri. Ukuran model asli skin-nya, suara dan
       perilaku dari data Item aslinya -- persis seperti spawn resmi
       skin itu. Fisika/posisi tetap dari stream server, jadi bola
       tetap bisa dipukul seperti biasa.
       CAKUPAN: default-nya bola diganti HANYA bila pemiliknya kamu.
       Pemilik dibaca dari atribut "ServedByPlayer" milik game sendiri
       (nama pemain yang sedang serve saat bola muncul); mode Training
       selalu dianggap bolamu (sesuai logika game di HeadBall); bila
       atribut tidak tersedia, cadangan terakhir adalah mencocokkan
       skin stream dengan bola aslimu yang ter-equip. Ubah
       SPOOF_RALLY_ALL ke true bila ingin semua bola rally diganti.
    4. BOLA DISPLAY: Item.Asset milik bola asli yang ter-equip ditukar
       ke asset skin palsu, jadi display bola berbasis Item ikut tampil
       sebagai skin palsu.
    5. BOLA SERVE DI TANGAN: bola yang dipegang saat serve BUKAN dari
       jalur di atas -- server membuatnya sendiri, me-weld-nya ke
       tangan karakter, dan menandainya dengan tag "WeldedBall".
       Script mengawasi tag itu pada karakter lokal: visual asli
       disembunyikan (part dibuat transparan DAN efeknya dimatikan --
       Trail, ParticleEmitter, Beam, Fire, Smoke, Sparkles, Light,
       Billboard/SurfaceGui; nilai aslinya dicatat untuk dipulihkan),
       weld & struktur utuh, dan clone skin palsu ditempel dengan
       WeldConstraint ke part jangkar yang sama, jadi bola palsu
       mengikuti tangan persis seperti aslinya.
    6. REPLAY: bola di layar Replay TIDAK lewat Ball.new -- ia dibuat
       GhostBall dari nama skin yang direkam Recorder langsung dari
       paket stream (skin asli). GhostBall.new dibungkus: nama skin
       yang masuk ditukar ke skin palsu, dan GhostBall sendiri yang
       meng-clone model aslinya + memasang data Item-nya (termasuk
       suara kontak). CEK PEMILIK: arsip replay tidak menyimpan siapa
       pemilik bola, jadi script membuat log serve sendiri saat live
       (tiap bola muncul: jam + nama server dari ServedByPlayer). Saat
       replay diputar, clip dicocokkan ke entri Archive untuk membaca
       PointTime-nya, lalu log serve dicari mundur dari titik itu --
       ketemu serve yang memulai rally-nya. Hanya bila server-nya
       KAMU bola replay di-spoof; serve orang lain tidak. Bila log /
       arsip tidak ketemu, fallback ke pencocokan skin seperti bola
       rally.
    7. EFEK PERMUKAAN (mis. bekas slime): event SurfaceHit dari server
       ternyata TERGATE di sisi server -- server hanya mengirimnya
       untuk bola yang item aslinya lolos BallLib.hasSurfaceHit
       (punya Handler.SurfaceHit atau suara kontak). Bola polos yang
       di-spoof ke Slime Ball tidak pernah menerima event itu. Sebagai
       pemicu lokal dipakai OnHitBindable milik objek bola: fisika
       bola lokal game (Common.Physics, kode yang sama dengan server)
       menembakkannya setiap bola menyentuh permukaan. Dari situ
       posisi + normal dicari via spherecast, lalu
       BallController:SurfaceHit dipanggil -- render efeknya sesudah
       itu 100% jalur asli game.
    8. PERSISTENSI: equip palsu disimpan ke file lokal
       (vl-ball-spoof.json) bila executor mendukung writefile, dan
       dimuat lagi otomatis saat script dijalankan berikutnya.
    9. JERSEY (pola yang sama seperti bola): semua jersey tampil di
       inventory (tab Misc), equip/unequip jersey yang belum dimiliki
       dicegat lokal dan disimpan di file yang sama. Bedanya di
       render: jersey karakter dipasang oleh SERVER (JerseyService),
       jadi script memasang ulang jersey palsu secara lokal ke
       karakter sendiri memakai tool resmi game (Tools.Jersey.set)
       dengan props resmi (nama/nomor style + tim) dari
       JerseyService:GetPlayerJerseyPropsAsync -- hanya tampilan di
       layar ini yang berubah. Penjaga memasang ulang bila server
       menimpa (respawn / update), dan unequip palsu memasang kembali
       jersey asli secara lokal.
    10. EMOTE (pola yang sama): semua emote tampil di tab Emote.
        Equip emote = menaruhnya di slot RODA emote lewat
        InventoryService:Equip(id, indexSlot) -- panggilan untuk
        emote yang belum dimiliki dicegat lokal dan slotnya dicatat
        sebagai slot palsu (persisten, di file yang sama). Roda
        membaca Value Emotes milik EmoteController (biji dari
        Equipped.Emotes server), jadi peta slot server di-clone dan
        ditimpa slot palsu di sana; slot yang baru ditulis server
        (equip asli) mengalahkan slot palsu di indeks yang sama.
        Saat dimainkan, animasinya diputar klien sendiri
        (AnimationController:PlayAnimation) jadi emote tetap jalan
        dan terlihat pemain lain. Efek properti emote (yang normalnya
        dijalankan server lewat InventoryService:Use) dijalankan
        script secara LOKAL dari Handler.run item-nya: properti
        muncul di karakter, tapi hanya terlihat di layar ini.
    11. ALERT KEKURANGAN: item yang diketahui punya kekurangan
        (bola berefek permukaan seperti SlimeBall; emote berproperti)
        memunculkan dialog PromptController resmi game -- dialog
        yang sama dengan konfirmasi spin style/ability -- SEBELUM
        equip palsu diterapkan, berisi penjelasan kekurangannya.
        "Equip Anyway" melanjutkan, "Cancel" membatalkan equip.
    14. SCORE FX (ScoreEffect): semua efek (165) disuntikkan ke
        inventory. Equip palsu slot tunggal (persisten): efek yang
        dimainkan di poin sendiri adalah efek SPOOF itu sendiri
        (spesifik apa adanya; Random Favorite mengacak dari
        favorit PALSU lokal, dengan favorit asli server sebagai
        cadangan bila favorit palsu kosong). Penukaran di SATU corong
        (keputusan user): EffectController.PlayScoreEffect -- saat
        efek ASLI dimainkan untuk poin sendiri, Item-nya ditukar
        ke efek spoof sebelum dimainkan. Konsekuensinya efek asli
        tetap diperlukan sebagai "pembawa": server hanya
        memicu pemutaran efek bila profil server punya efek
        ter-equip; tanpa equip asli, tidak ada efek yang dimainkan
        dan tidak ada yang bisa ditukar. Pembawa dipastikan
        OTOMATIS: saat equip palsu diterapkan dan slot server
        kosong/Random, script meng-equip satu efek asli (yang
        pertama dimiliki) ke server di latar belakang lewat
        panggilan Equip asli; tampilan inventory tetap menunjukkan
        efek palsu. Pembawa bersifat NON-DESTRUKTIF: script tidak
        pernah melepas atau memulihkan equip server -- versi
        pulihkan-otomatis sebelumnya terbukti mengosongkan slot FX
        user (Equip adalah toggle; memasang ulang pembawa di slot
        yang sudah terisi = unequip), jadi pembawa yang terpasang
        dibiarkan sebagai equip asli user. Efek disiarkan server per
        poin, jadi penukaran hanya mengubah yang tampil di layar
        ini. Favorit efek yang belum dimiliki disimpan lokal
        (sistem yang sama dengan kartu, digabung ke Value
        Favorited yang sama). Efek berpengaruh fisik yang di-equip
        palsu memunculkan alert dulu (pengaruhnya hanya berlaku
        ke karakter sendiri). SUARA: suara poin yang diregistrasi
        game berasal dari efek server, jadi pembawa dipilih yang
        HENING (tanpa Id suara) bila ada, dan wrapper memainkan
        suara poin efek SPOOF dengan cara yang persis sama dengan
        HitGround.play (registrasi Metadata.Sound, Volume 4,
        PlaybackSpeed 0.9-1.1, diputar di titik skor); suara dari
        dalam modul efek memang selalu mengikuti efek spoof.
    13. BAGIAN SETTINGS TAMBAHAN ("VL Settings"): halaman Settings
        game bersifat data-driven (grup GroupPages dari tabel
        SettingsGroups), jadi script mendaftarkan satu grup baru dan
        membiarkan pembangun halaman game sendiri yang membuat
        halamannya. Isinya satu saklar: "World-Affecting Score
        Effects" -- untuk Score FX yang modulnya terbukti memasang
        gaya/kecepatan ke karakter pemain (Supernova, Trampoline,
        Tsunami, BallPortal, BananaSlip, GenieLamp, GreenEnergy).
        Grup WAJIB terdaftar sebelum kunci kompositnya digabung
        ke Value Settings: halaman utama menggambar saklar untuk
        setiap kunci boolean yang tidak dikenali parseKey, jadi
        penggabungan yang mendahului pendaftaran membuat baris
        berlabel kunci mentah bocor ke halaman utama (terbukti di
        pemakaian nyata). Avatar Lite TIDAK memakai grup ini --
        anggota grup selalu dirender sebagai saklar; ia memakai
        baris tombolnya sendiri (lihat bagian 16).
        Nilai saklar disimpan lokal (persisten) dan digabung ke
        Value Settings game sebagai kunci komposit; klik barisnya
        dicegat di SettingsService:ChangeSetting. Bila saklar MATI,
        EffectController.PlayScoreEffect digerbang: efek-efek itu
        tidak dimainkan sama sekali di client ini saat bermain
        langsung (Replay dan preview lobby tidak disentuh).
    12. KARTU PEMAIN (PlayerCard): semua kartu (118) disuntikkan ke
        inventory seperti kategori lain. Halaman kartu punya panel
        sendiri: equip-nya dibaca dengan :expect() dan nilai truthy
        dianggap pesan error, jadi jalur palsu mengembalikan promise
        KOSONG. FAVORIT KARTU: InventoryService.ToggleFavorite
        dibungkus -- kartu yang belum dimiliki disimpan lokal
        (persisten) dan digabung ke Value Favorited yang dibaca UI
        (bintang di sel + label FAVORITE/UNFAVORITE); favorit kartu
        ASLI tetap urusan server. RANDOM FAVORITES: momen tampil
        kartu (flash card saat mencetak poin + kartu MVP) datang dari
        event server berisi id kartu asli; DisplayFlashCard milik
        PlayerCardController dibungkus -- untuk event tentang pemain
        lokal, id-nya ditukar: kartu palsu bila ada, atau PILIHAN
        ACAK dari semua favorit (server + lokal) bila kartu efektif
        adalah RandomFavoritePlayerCard.

    KEAMANAN KATEGORI LAIN (ScoreEffect/Title/dll):
    - Injeksi inventory bersifat MENAMBAH saja: tabel state di-clone,
      hanya kunci item yang hilang yang ditambah; tidak ada kunci yang
      dihapus atau ditimpa.
    - Grid tiap kategori menyaring berdasarkan tipe item, jadi entri
      satu kategori tidak pernah muncul di kategori lain.
    - Merge Equipped juga clone + ubah kunci Ball/Jersey/PlayerCard
      saja; slot ChatBubble utuh. Merge Favorited clone + tambah
      favorit kartu lokal saja.
    - Kepemilikan asli dibaca dari DataService (data server), BUKAN
      dari state UI yang sudah disuntik -- jadi script aman dijalankan
      ulang dalam sesi yang sama.
    - State spoof disimpan di getgenv; menjalankan ulang script tidak
      menumpuk bungkus fungsi, cukup menerapkan ulang dari state yang
      sama.

    15. LOADING OVERLAY (Bagian 0): layar penuh menutupi game
        sejak script mulai; bar progresnya mengikuti milestone
        NYATA Bagian A (controller siap -> profil tersinkron ->
        hooks terpasang -> setup diterapkan -> Ready), bukan
        animasi acak. Grup tengah memudar masuk sekali, lalu
        memudar keluar + membesar sedikit saat selesai (tampil
        minimum 1,4 detik; failsafe keluar sendiri pada 60 detik;
        catatan "still working" muncul bila lewat 20 detik).
        Murni kosmetik dan dibungkus pcall -- kegagalannya tidak
        pernah menghalangi script utama.

    16. AVATAR LITE (Bagian D -- "Catalog Avatar Creator" versi
        ringan di dalam game): ganti avatar secara "gratis" dan
        CLIENT-SIDE saja. Panel (tombol melayang AVATAR, atau baris
        "VL Avatar / Avatar Lite [Open]" di halaman utama Settings
        -- klon template B milik game, meniru baris Buttons bawaan
        dari ButtonEditController:LoadSettingsButton) menerima ID
        item katalog. UI panelnya TIDAK lagi di file ini: ia
        di-fetch segar setiap run dari repo GitHub lua-files
        (avatar-lite/ui.lua, query anti-cache) dan meniru tata
        letak CatalogGUI game Catalog Avatar Creator secara
        fullscreen (Holder memenuhi layar, tidak bisa digeser;
        pratinjau 3D karakter di kiri atas, strip EquippedItems
        di kiri bawah, panel Catalog 65%x90% di kanan).
        apa pun; jenis dibaca dari MarketplaceService lalu dirutekan:
        aksesori (termasuk layered clothing) dimuat lewat GetObjects
        dan dipasang dengan Humanoid:AddAccessory; baju/celana ke
        template Shirt/Pants; wajah ke Decal face di Head. Daftar
        aksesori tambahan bisa dilepas satu per satu; Strip Real
        melepas aksesori asli secara lokal; Reset mengembalikan
        template + warna tubuh ke snapshot tampilan server (diambil
        tiap respawn sebelum outfit diterapkan). Outfit tersimpan
        di vl-avatar.json dan terpasang lagi ~2 detik setelah
        setiap CharacterAdded. Warna tubuh dari baris contoh warna.
        Bundle/bentuk badan dan animasi TIDAK termasuk. Modul yang
        sama juga hidup sebagai file mandiri vl-avatar-lite.lua --
        keduanya berbagi flag getgenv dan file simpan yang sama,
        jadi menjalankan dua-duanya tidak menggandakan apa pun.

    Yang TIDAK berubah: server dan pemain lain. Mereka tetap melihat
    skin aslimu, dan equip beneran tetap divalidasi server.
]]

-- === Cek game: hanya jalan di Volleyball Legends ===
-- Memakai GameId (ID universe), BUKAN PlaceId: semua mode VL
-- (lobby, match, training, ranked, dan place lain) berbagi satu
-- GameId yang sama walaupun PlaceId-nya berbeda-beda. Nilai ini
-- terverifikasi untuk place 73956553001240 (root) dan
-- 74691681039273 -- keduanya GameId 6931042565.
-- Cadangan: bila GameId tidak cocok (misalnya place uji), script
-- mengonfirmasi dulu lewat struktur khas VL sebelum berhenti.
local VL_GAME_ID = 6931042565
if game.GameId ~= VL_GAME_ID then
	local rs = game:GetService("ReplicatedStorage")
	local rf = game:GetService("ReplicatedFirst")
	local content = rs:WaitForChild("Content", 20)
	local looksLikeVL = content and content:FindFirstChild("Item") and rf:FindFirstChild("Controllers")
	if not looksLikeVL then
		warn("[VLSpoof] Not Volleyball Legends (GameId " .. tostring(game.GameId) .. ") -- script stopped.")
		return
	end
end

local SAVE_FILE = "vl-ball-spoof.json"

-- false = hanya bola berskin sama dengan bola aslimu yang ter-equip
--         yang diganti (serve-mu sendiri).
-- true  = semua bola rally diganti, termasuk serve pemain lain.
local SPOOF_RALLY_ALL = false

-- Face Camera: kunci arah hadap selama di udara setelah putaran
-- lompat (AutoRotate dimatikan, dipulihkan saat mendarat).
local LOCK_DIRECTION = true

-- Sintesis efek permukaan (bekas slime): splat hanya digambar untuk
-- benturan NYATA (bola datang dengan kecepatan minimal ini, studs/s)
-- dan berjarak minimal sekian studs dari splat sebelumnya. Tanpa dua
-- gerbang ini, bola yang menggelinding / diam di tanah menembakkan
-- kontak fisika terus-menerus dan splat-nya jadi spam.
local SPLAT_MIN_IMPACT = 9
local SPLAT_MIN_SPACING = 1.5

-- === Cek kesiapan global (autoexec bisa jalan sebelum loading) ===
if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
if not player then
	player = Players.PlayerAdded:Wait()
end
local RS = ReplicatedStorage

local Knit = require(RS:WaitForChild("Packages"):WaitForChild("Knit"))
local ContentItem = require(RS:WaitForChild("Content"):WaitForChild("Item"))
local Gamemode = require(RS:WaitForChild("Configuration"):WaitForChild("Gamemode"))
local TweenService = game:GetService("TweenService")

----------------------------------------------------------------
-- BAGIAN 0: Loading Overlay
-- Layar penuh yang menutupi game sejak script mulai, menampilkan
-- progres NYATA dari milestone Bagian A, lalu memudar keluar
-- begitu semuanya siap. Murni kosmetik: kegagalan membangun
-- overlay tidak boleh mengganggu script utama (semua pcall).
----------------------------------------------------------------
local LoadingState = { frac = 0.04, status = "Waiting for the game", done = false }
getgenv().VLLoadingState = LoadingState

local function setLoading(frac, status)
	if frac and frac > LoadingState.frac then
		LoadingState.frac = frac
	end
	if status then
		LoadingState.status = status
	end
end

local function initLoadingOverlay()
	local playerGui = player:WaitForChild("PlayerGui", 10)
	if not playerGui then
		return
	end
	local existing = playerGui:FindFirstChild("VLLoadingOverlay")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "VLLoadingOverlay"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 999
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Akar CanvasGroup: seluruh overlay (latar gradasi + cahaya +
	-- konten) bisa memudar sebagai satu kesatuan saat keluar --
	-- UIGradient tidak mengikuti BackgroundTransparency frame.
	local root = Instance.new("CanvasGroup")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.GroupTransparency = 0
	root.Parent = gui

	-- Latar: gradasi vertikal biru-malam, plus dua cahaya violet
	-- redup yang bergerak lambat (satu momen gerak ambient).
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(10, 10, 18)
	backdrop.BorderSizePixel = 0
	backdrop.Parent = root
	local bgGrad = Instance.new("UIGradient")
	bgGrad.Rotation = 90
	bgGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 10, 18)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(23, 17, 38)),
	})
	bgGrad.Parent = backdrop

	local function makeGlow(color, size, pos, transparency)
		local glow = Instance.new("Frame")
		glow.Size = UDim2.fromOffset(size, size)
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = pos
		glow.BackgroundColor3 = color
		glow.BackgroundTransparency = transparency
		glow.BorderSizePixel = 0
		glow.Parent = backdrop
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = glow
		return glow
	end
	local glowA = makeGlow(Color3.fromRGB(91, 63, 214), 640, UDim2.new(0.36, 0, 0.34, 0), 0.9)
	local glowB = makeGlow(Color3.fromRGB(43, 27, 105), 520, UDim2.new(0.66, 0, 0.68, 0), 0.92)
	local swayInfo = TweenInfo.new(7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(glowA, swayInfo, { Position = UDim2.new(0.4, 0, 0.3, 0) }):Play()
	TweenService:Create(glowB, TweenInfo.new(9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.new(0.62, 0, 0.72, 0) }):Play()

	-- Grup tengah (CanvasGroup agar bisa memudar sebagai satu
	-- kesatuan saat keluar).
	local group = Instance.new("CanvasGroup")
	group.Name = "Group"
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.new(0.5, 0, 0.5, 16)
	group.Size = UDim2.fromOffset(460, 380)
	group.BackgroundTransparency = 1
	group.GroupTransparency = 1
	group.Parent = root
	local groupScale = Instance.new("UIScale")
	groupScale.Scale = 1
	groupScale.Parent = group

	-- Marka: ubin violet dengan bayangan lembut bergeser.
	local markShadow = Instance.new("Frame")
	markShadow.AnchorPoint = Vector2.new(0.5, 0)
	markShadow.Position = UDim2.new(0.5, 0, 0, 10)
	markShadow.Size = UDim2.fromOffset(88, 88)
	markShadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	markShadow.BackgroundTransparency = 0.55
	markShadow.BorderSizePixel = 0
	markShadow.Parent = group
	local shadowCorner = Instance.new("UICorner")
	shadowCorner.CornerRadius = UDim.new(0, 22)
	shadowCorner.Parent = markShadow

	local mark = Instance.new("Frame")
	mark.AnchorPoint = Vector2.new(0.5, 0)
	mark.Position = UDim2.new(0.5, 0, 0, 0)
	mark.Size = UDim2.fromOffset(88, 88)
	mark.BackgroundColor3 = Color3.fromRGB(106, 75, 224)
	mark.BorderSizePixel = 0
	mark.Parent = group
	local markCorner = Instance.new("UICorner")
	markCorner.CornerRadius = UDim.new(0, 22)
	markCorner.Parent = mark
	local markGrad = Instance.new("UIGradient")
	markGrad.Rotation = 135
	markGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(122, 92, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(74, 47, 184)),
	})
	markGrad.Parent = mark
	local markScale = Instance.new("UIScale")
	markScale.Scale = 0.85
	markScale.Parent = mark
	local markText = Instance.new("TextLabel")
	markText.Size = UDim2.fromScale(1, 1)
	markText.BackgroundTransparency = 1
	markText.Text = "VL"
	markText.Font = Enum.Font.MontserratBold
	markText.TextSize = 38
	markText.TextColor3 = Color3.fromRGB(255, 255, 255)
	markText.Parent = mark

	local title = Instance.new("TextLabel")
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.new(0.5, 0, 0, 116)
	title.Size = UDim2.new(1, 0, 0, 40)
	title.BackgroundTransparency = 1
	title.Text = "VL Spoof Suite"
	title.Font = Enum.Font.MontserratBold
	title.TextSize = 32
	title.TextColor3 = Color3.fromRGB(237, 237, 242)
	title.Parent = group

	local subtitle = Instance.new("TextLabel")
	subtitle.AnchorPoint = Vector2.new(0.5, 0)
	subtitle.Position = UDim2.new(0.5, 0, 0, 158)
	subtitle.Size = UDim2.new(1, 0, 0, 20)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Ball · Jersey · Emote · Player Cards · Score FX"
	subtitle.Font = Enum.Font.Montserrat
	subtitle.TextSize = 14
	subtitle.TextColor3 = Color3.fromRGB(167, 155, 219)
	subtitle.Parent = group

	-- Bar progres: ramping, isian mengikuti milestone nyata,
	-- dengan kilau (sheen) yang melintas selama memuat.
	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.Position = UDim2.new(0.5, 0, 0, 216)
	track.Size = UDim2.fromOffset(320, 5)
	track.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	track.BackgroundTransparency = 0.88
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = group
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(LoadingState.frac, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(122, 92, 255)
	fill.BorderSizePixel = 0
	fill.ClipsDescendants = true
	fill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill
	local fillGrad = Instance.new("UIGradient")
	fillGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(139, 108, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(91, 63, 214)),
	})
	fillGrad.Parent = fill
	local sheen = Instance.new("Frame")
	sheen.Size = UDim2.fromOffset(56, 5)
	sheen.Position = UDim2.new(-0.2, 0, 0, 0)
	sheen.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	sheen.BackgroundTransparency = 0.72
	sheen.BorderSizePixel = 0
	sheen.Rotation = 18
	sheen.Parent = fill
	local sheenTween = TweenService:Create(sheen, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, -1), { Position = UDim2.new(1.15, 0, 0, 0) })
	sheenTween:Play()

	local statusLabel = Instance.new("TextLabel")
	statusLabel.AnchorPoint = Vector2.new(0, 0)
	statusLabel.Position = UDim2.new(0.5, -160, 0, 234)
	statusLabel.Size = UDim2.fromOffset(240, 18)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = LoadingState.status
	statusLabel.Font = Enum.Font.Montserrat
	statusLabel.TextSize = 14
	statusLabel.TextColor3 = Color3.fromRGB(207, 200, 236)
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Parent = group

	local percentLabel = Instance.new("TextLabel")
	percentLabel.AnchorPoint = Vector2.new(0, 0)
	percentLabel.Position = UDim2.new(0.5, 80, 0, 234)
	percentLabel.Size = UDim2.fromOffset(80, 18)
	percentLabel.BackgroundTransparency = 1
	percentLabel.Text = "4%"
	percentLabel.Font = Enum.Font.Montserrat
	percentLabel.TextSize = 14
	percentLabel.TextColor3 = Color3.fromRGB(207, 200, 236)
	percentLabel.TextXAlignment = Enum.TextXAlignment.Right
	percentLabel.Parent = group

	local slowLabel = Instance.new("TextLabel")
	slowLabel.AnchorPoint = Vector2.new(0.5, 0)
	slowLabel.Position = UDim2.new(0.5, 0, 0, 266)
	slowLabel.Size = UDim2.new(1, 0, 0, 18)
	slowLabel.BackgroundTransparency = 1
	slowLabel.Text = "Still working — the game is taking a while to respond."
	slowLabel.Font = Enum.Font.Montserrat
	slowLabel.TextSize = 12
	slowLabel.TextColor3 = Color3.fromRGB(154, 147, 184)
	slowLabel.TextTransparency = 1
	slowLabel.Parent = group

	local footnote = Instance.new("TextLabel")
	footnote.AnchorPoint = Vector2.new(0.5, 1)
	footnote.Position = UDim2.new(0.5, 0, 1, -18)
	footnote.Size = UDim2.new(1, 0, 0, 16)
	footnote.BackgroundTransparency = 1
	footnote.Text = "vl-ball-spoof · client-side only"
	footnote.Font = Enum.Font.Montserrat
	footnote.TextSize = 11
	footnote.TextColor3 = Color3.fromRGB(154, 147, 184)
	footnote.TextTransparency = 0.35
	footnote.Parent = root

	gui.Parent = playerGui

	-- Koreografi masuk: satu momen — grup memudar + naik ke
	-- posisi, marka membesar ke ukuran penuh.
	local easeOut = TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	TweenService:Create(group, easeOut, { GroupTransparency = 0, Position = UDim2.new(0.5, 0, 0.5, 0) }):Play()
	TweenService:Create(markScale, TweenInfo.new(0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	-- Loop pemantau: bar mengikuti milestone (tidak pernah
	-- mundur), teks status mengikuti Bagian A, keluar begitu
	-- selesai (dengan waktu tampil minimum) atau failsafe 60 dtk.
	local startedAt = os.clock()
	local currentShown = LoadingState.frac
	local finished = false
	local function finish()
		if finished then
			return
		end
		finished = true
		sheenTween:Cancel()
		setLoading(1, "Ready")
		TweenService:Create(fill, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = UDim2.new(1, 0, 1, 0) }):Play()
		statusLabel.Text = "Ready"
		percentLabel.Text = "100%"
		task.wait(0.35)
		local outInfo = TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		TweenService:Create(root, outInfo, { GroupTransparency = 1 }):Play()
		TweenService:Create(groupScale, outInfo, { Scale = 1.04 }):Play()
		task.wait(0.7)
		gui:Destroy()
	end

	while not finished do
		local elapsed = os.clock() - startedAt
		if LoadingState.frac > currentShown then
			currentShown = LoadingState.frac
			TweenService:Create(fill, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = UDim2.new(currentShown, 0, 1, 0) }):Play()
		end
		percentLabel.Text = ("%d%%"):format(math.floor(currentShown * 100))
		if statusLabel.Text ~= LoadingState.status then
			statusLabel.Text = LoadingState.status
		end
		if elapsed > 20 and not LoadingState.done and slowLabel.TextTransparency > 0 then
			TweenService:Create(slowLabel, TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()
		end
		if (LoadingState.done and elapsed >= 1.4) or elapsed > 60 then
			finish()
			break
		end
		task.wait(0.08)
	end
end

task.spawn(function()
	pcall(initLoadingOverlay)
end)
