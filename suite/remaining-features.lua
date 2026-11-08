----------------------------------------------------------------
-- suite/remaining-features.lua -- SEMENTARA: fitur-fitur
-- Bagian A yang belum punya modul sendiri (Score FX, grup
-- VL Settings + baris Avatar, kartu, emote + prop, jersey,
-- router equip InventoryService:Equip, bungkus preview).
-- Akan dipecah satu per satu ke modulnya masing-masing;
-- ball-spoof sudah lebih dulu pisah sebagai modul fitur
-- pertama. Kode diekstrak apa adanya dari Bagian A monolit;
-- penyesuaian hanya di kerangka peluncuran (menunggu
-- feature-shared + guard S.installedRemaining) dan
-- registrasi FeatureAPI untuk feature-shared.
----------------------------------------------------------------

-- Model penggantian Score FX (sesuai rancangan user):
--   DEPAN (inventory): user memilih efek palsu -- satu efek
--   spesifik (mis. Supernova) atau Random Favorite.
--   BELAKANG (server): script memastikan SATU efek yang benar-
--   benar dimiliki ter-equip sebagai pembawa (ensureFxCarrier),
--   karena server hanya menyiarkan efek untuk poin bila profil
--   punya equip asli; tanpa itu tidak ada momen penukaran.
--   PENUKARAN (PlayScoreEffect): efek pembawa yang dimainkan
--   server diganti -- efek spesifik mengganti dengan dirinya;
--   Random Favorite memilih acak dari semua Score FX PALSU yang
--   tersimpan di favorit lokal (S.fakeFxFavorites). Bila favorit
--   palsu kosong, jatuh ke favorit asli server; bila keduanya
--   kosong, tidak ada penukaran (efek pembawa tampil apa adanya).
-- RandomFavoriteScoreEffect tidak pernah masuk pool (modul
-- asetnya hanya stub peringatan, memang tidak untuk dimainkan).
local function randomFxFromFakeFavorites(excludeSet)
	local pool = {}
	for id in pairs(S.fakeFxFavorites) do
		if id ~= RANDOM_FX_ID and not (excludeSet and excludeSet[id]) then
			table.insert(pool, id)
		end
	end
	if #pool > 0 then
		return pool[math.random(1, #pool)]
	end
	return nil
end

local function randomFxFromServerFavorites(excludeSet)
	local pool = {}
	for id, fav in pairs(S.serverFavorited) do
		if fav and isScoreFx(id) and id ~= RANDOM_FX_ID
			and not (excludeSet and excludeSet[id]) then
			table.insert(pool, id)
		end
	end
	if #pool > 0 then
		return pool[math.random(1, #pool)]
	end
	return nil
end

local function resolveScoreFxItemId()
	-- Yang dimainkan adalah efek SPOOF itu sendiri. Penukaran
	-- terjadi di PlayScoreEffect (saat efek asli dimainkan), jadi
	-- resolver ini hanya menjawab: efek palsu apa yang mengganti
	-- efek asli yang sedang dimainkan untuk poin sendiri.
	if S.fakeScoreFx then
		if S.fakeScoreFx ~= RANDOM_FX_ID then
			-- Spesifik palsu: efek itu sendiri yang main.
			return S.fakeScoreFx
		end
		-- Random Favorite palsu: acak dari favorit palsu lokal;
		-- favorit asli server sebagai cadangan terakhir.
		return randomFxFromFakeFavorites()
			or randomFxFromServerFavorites()
	end
	return nil
end

-- Suara poin sebuah item Score FX "hening" bila item tidak punya
-- Metadata.Sound atau konfigurasinya tidak membawa Id suara.
local function fxSoundIsSilent(item)
	local meta = item and item.Metadata
	if not meta or not meta.Sound then
		return true
	end
	return meta.Sound.Id == nil
end

-- Varian resolver saat saklar World-Affecting MATI: pool Random
-- tidak boleh menghasilkan efek berpengaruh fisik, supaya poin
-- tetap menampilkan sesuatu (bukan kosong total). Efek spesifik
-- yang dipilih sendiri tetap dikembalikan apa adanya (gerbang di
-- wrapper yang menilainya).
local function resolveScoreFxItemIdExcludingWorld()
	if S.fakeScoreFx and S.fakeScoreFx == RANDOM_FX_ID then
		return randomFxFromFakeFavorites(WORLD_AFFECTING_FX)
			or randomFxFromServerFavorites(WORLD_AFFECTING_FX)
	end
	return resolveScoreFxItemId()
end

-- Suara poin efek spoof, dimainkan persis seperti game
-- memainkannya untuk efek asli di HitGround.play: registrasi
-- konfigurasi Metadata.Sound (Volume dipaksa 4, PlaybackSpeed
-- acak 0.9-1.1) lalu putar di titik skor. SoundTool diisi saat
-- wrapper PlayScoreEffect dipasang.
local SoundTool
local function playFxPointSound(item, origin)
	if not (SoundTool and item and item.Metadata and item.Metadata.Sound) then
		return
	end
	pcall(function()
		if not SoundTool.isRegistered(item.Id) then
			local cfg = table.clone(item.Metadata.Sound)
			cfg.Volume = 4
			cfg.PlaybackSpeed = NumberRange.new(0.9, 1.1)
			SoundTool.register(item.Id, cfg)
		end
		local originCFrame
		if typeof(origin) == "Vector3" then
			originCFrame = CFrame.new(origin)
		elseif typeof(origin) == "CFrame" then
			originCFrame = origin
		else
			originCFrame = CFrame.new()
		end
		SoundTool.fromName(item.Id)({ Origin = originCFrame })
	end)
end

-- Pembawa Score FX: penukaran di PlayScoreEffect hanya terjadi
-- bila server benar-benar memainkan efek untuk poin sendiri, dan
-- server hanya memicu pemutaran bila profil punya efek ter-equip
-- konkret. Fungsi ini memastikan selalu ada efek ASLI ter-equip
-- di server selama lapis palsu aktif -- dipasang lewat panggilan
-- Equip ASLI (S.originalEquip, melewati wrapper). Pembawa dipilih
-- yang HENING bila ada (lihat playFxPointSound: suara poin yang
-- didengar harus suara efek spoof, bukan suara pembawa).
local function pickFxCarrier()
	-- Utamakan pembawa HENING (tanpa suara poin): game meregistrasi
	-- suara poin dari efek SERVER, sementara wrapper memainkan
	-- suara efek spoof secara terpisah -- pembawa bersuara membuat
	-- dua suara poin bertumpuk.
	local anyOwned
	for _, id in ipairs(ALL_FX_IDS) do
		if id ~= RANDOM_FX_ID and S.realOwned[id] then
			anyOwned = anyOwned or id
			if fxSoundIsSilent(ContentItem:Get(id)) then
				return id
			end
		end
	end
	return anyOwned
end

-- Pembawa Score FX, versi NON-DESTRUKTIF. Pelajaran dari versi
-- sebelumnya: Equip bersifat toggle dan equip server berjalan
-- async, jadi sistem "pasang pembawa lalu pulihkan equip semula"
-- balapan dengan klik user sendiri dan pada akhirnya malah
-- MENGOSONGKAN slot FX (equip ulang pembawa = unequip). Aturan
-- sekarang: script hanya PERNAH memasang satu efek asli saat slot
-- server kosong/Random dan lapis palsu aktif; script TIDAK PERNAH
-- melepas atau memulihkan equip server apa pun. Pembawa yang
-- sudah terpasang adalah efek asli milik user -- dibiarkan saja.
local function ensureFxCarrier()
	if not S.fakeScoreFx or S.fxCarrierInFlight then
		return
	end
	-- Equip asli yang BARU dipilih user sendiri selalu menang:
	-- jangan timpa kliknya dengan pembawa.
	if S.fxUserEquipAt and os.clock() - S.fxUserEquipAt < 5 then
		return
	end
	local current = S.serverEquipped.ScoreEffect
	-- CATATAN: slot berisi Random Favorite ASLI pun tetap diganti
	-- pembawa di sini. Server menyelesaikan Random dari favorit
	-- ASLI profil; bila favorit asli kosong (terbukti dari log
	-- diagnostik 2026-11-07: favorit server 0, semua HitGround
	-- poin sendiri berisi ScoreEffect=nil), server menyiarkan
	-- NIHIL dan tidak ada efek apa pun yang bisa ditukar. Sesuai
	-- model user: Random di depan, satu efek milik sendiri yang
	-- dipilih script di belakang.
	if current and current ~= RANDOM_FX_ID then
		-- Sudah ada efek asli konkret ter-equip: itu sendiri
		-- pembawanya, tidak perlu diubah apa pun. Satu pengecualian:
		-- pembawa yang KITA pasang sendiri tapi BERSUARA ditukar ke
		-- pembawa hening bila ada, supaya suara poinnya tidak
		-- bertumpuk dengan suara efek spoof dari wrapper.
		if current == S.fxCarrier and S.originalEquip
			and not fxSoundIsSilent(ContentItem:Get(current)) then
			local silent = pickFxCarrier()
			if silent and silent ~= current then
				S.fxCarrierInFlight = true
				S.fxCarrier = silent
				pcall(function()
					S.originalEquip(InventoryService, silent)
				end)
			end
		end
		return
	end
	local carrier = pickFxCarrier()
	if not carrier then
		warn("[VLBallSpoof] No owned Score FX available as carrier -- the spoof cannot trigger without one genuine effect owned.")
		return
	end
	if not S.originalEquip then
		return
	end
	-- Tandai in-flight SEBELUM memanggil: gema ProfileUpdated yang
	-- membersihkan tanda ini adalah bukti equip-nya sudah diproses;
	-- tanpa tanda, pemicu berulang bisa meng-equip pembawa dua kali
	-- (equip kedua = unequip).
	S.fxCarrierInFlight = true
	S.fxCarrier = carrier
	pcall(function()
		S.originalEquip(InventoryService, carrier)
	end)
end

-- Daftarkan grup VL Settings ke tabel SettingsGroups game. Ini
-- MURNI mutasi tabel modul (tidak butuh controller), jadi aman
-- dipanggil sedini mungkin -- dan WAJIB mendahului penggabungan
-- kunci kita ke Value Settings: halaman utama Settings menggambar
-- saklar untuk setiap kunci boolean yang tidak dikenali
-- SettingsGroups.parseKey, jadi kunci yang tergabung sebelum grup
-- terdaftar bocor ke halaman utama sebagai baris berlabel kunci
-- mentah (dan Fusion ForPairs tidak menggambar ulang kunci yang
-- nilainya tidak berubah, jadi kebocorannya tidak sembuh sendiri).
local function registerSettingsGroup()
	if S.settingsGroupRegistered then
		return
	end
	local ok = pcall(function()
		local groups = require(RS:WaitForChild("Configuration"):WaitForChild("SettingsGroups"))
		if not groups.Data[SETTINGS_GROUP] then
			groups.Data[SETTINGS_GROUP] = {
				DisplayName = "VL Settings",
				Members = { SETTING_MEMBER_WORLD_FX },
			}
			table.insert(groups.Order, SETTINGS_GROUP)
		end
		pcall(function()
			-- Label baris di halaman grup (peta milik KeybindController).
			local nameMap = require(ReplicatedFirst:WaitForChild("Controllers"):WaitForChild("KeybindController"):WaitForChild("DisplayNameMap"))
			if type(nameMap) == "table" and nameMap[SETTING_MEMBER_WORLD_FX] == nil then
				nameMap[SETTING_MEMBER_WORLD_FX] = "World-Affecting Score Effects"
			end
		end)
		pcall(function()
			-- Asuransi label di halaman utama (peta milik
			-- SettingsController sendiri): bila baris kita entah
			-- bagaimana tetap tergambar di sana, labelnya benar.
			local mainMap = require(ReplicatedFirst:WaitForChild("Controllers"):WaitForChild("SettingsController"):WaitForChild("DisplayNameMap"))
			if type(mainMap) == "table" and mainMap[SETTINGS_KEY_WORLD_FX] == nil then
				mainMap[SETTINGS_KEY_WORLD_FX] = "World-Affecting Score Effects"
			end
		end)
	end)
	if ok then
		S.settingsGroupRegistered = true
	end
end

-- Saklar bagian Settings tambahan hidup sebagai kunci komposit
-- "VLSettings_<Anggota>" di dalam Value Settings milik
-- InterfaceController (yang dibaca baris-baris Settings) -- gabung
-- nilai lokal kita ke sana, dan gabung ulang setiap server
-- menyinkronkan Settings (sinkron server menimpa seluruh tabel).
local function applyVLSettings()
	if not (InterfaceController and InterfaceController.Settings) then
		return
	end
	registerSettingsGroup()
	pcall(function()
		local current = InterfaceController.Settings:get() or {}
		if current[SETTINGS_KEY_WORLD_FX] == S.settings[SETTING_MEMBER_WORLD_FX] then
			return
		end
		local merged = table.clone(current)
		merged[SETTINGS_KEY_WORLD_FX] = S.settings[SETTING_MEMBER_WORLD_FX]
		InterfaceController.Settings:set(merged)
	end)
end

-- Bangun halaman bagian kita memakai mekanisme grup milik game
-- (GroupPages): daftarkan grup ke tabel SettingsGroups, lalu panggil
-- pembangun halaman game sendiri. Dikerjakan setelah Settings
-- selesai dimuat (bootstrap grup asli berjalan di KnitStart).
local function buildSettingsSection()
	if S.settingsSectionBuilt then
		return
	end
	local deadline = os.clock() + 30
	while os.clock() < deadline do
		if SettingsController and SettingsController.Loaded then
			break
		end
		task.wait(0.5)
	end
	if not (SettingsController and SettingsController.Loaded) then
		return
	end
	pcall(function()
		registerSettingsGroup()
		local groups = require(RS:WaitForChild("Configuration"):WaitForChild("SettingsGroups"))
		local groupPages = require(ReplicatedFirst:WaitForChild("Controllers"):WaitForChild("SettingsController"):WaitForChild("GroupPages"))
		if groupPages.Components[SETTINGS_GROUP] then
			S.settingsSectionBuilt = true
			return
		end
		local index = #groups.Order
		groupPages._loadPage(SETTINGS_GROUP)
		groupPages._loadRows(SETTINGS_GROUP)
		groupPages._loadSettingsRow(SETTINGS_GROUP, index)
		S.settingsSectionBuilt = true
	end)
end

-- Baris tombol Avatar Lite di daftar utama Settings, meniru
-- ButtonEditController:LoadSettingsButton milik game sendiri
-- (baris "Buttons / Edit [Open]"): header BB_TextLabel + baris
-- B_Template dengan tombol Open. Nama baris dipilih agar urutan
-- nama UIListLayout menaruhnya setelah baris Buttons bawaan.
local function buildAvatarSettingsRow()
	if S.avatarSettingsRowBuilt then
		return
	end
	local function findList()
		local ok, found = pcall(function()
			return InterfaceController.App.Lobby.Settings.BGFrame.Body.List
		end)
		if ok and found then
			return found
		end
		local ok, found = pcall(function()
			local app = player.PlayerGui:FindFirstChild("App")
			local lobby = app and app:FindFirstChild("Lobby")
			local settings = lobby and lobby:FindFirstChild("Settings")
			local bg = settings and settings:FindFirstChild("BGFrame")
			local body = bg and bg:FindFirstChild("Body")
			return body and body:FindFirstChild("List")
		end)
		if ok and found then
			return found
		end
		return nil
	end
	local deadline = os.clock() + 120
	local list
	while os.clock() < deadline do
		list = findList()
		if list then
			break
		end
		task.wait(0.5)
	end
	if not list then
		warn("[VLAvatar] Settings list not found; the Settings row was not built.")
		return
	end
	if list:FindFirstChild("B_VLAvatarRow") then
		S.avatarSettingsRowBuilt = true
		return
	end
	local okBuild, err = pcall(function()
		local Fusion = require(RS:WaitForChild("Packages"):WaitForChild("Fusion"))
		local Button = require(ReplicatedFirst:WaitForChild("Components"):WaitForChild("Button"))
		-- Visible WAJIB diset eksplisit: template baris game
		-- tersembunyi (Visible=false), klonnya mewarisi itu.
		Fusion.Hydrate(list.BB_TextLabel:Clone())({
			["Name"] = "B_VLAvatarLabel",
			["Text"] = "VL Avatar",
			["Visible"] = true,
			["Parent"] = list,
		})
		local row = Fusion.Hydrate(list.B_Template:Clone())({
			["Name"] = "B_VLAvatarRow",
			["Visible"] = true,
			["Parent"] = list,
		})
		row.Setting.Text = "Avatar Lite"
		row.ImageButton.KeyCode.Text = "Open"
		Button(row.ImageButton)({
			["OnActivated"] = function()
				local opener = getgenv().VLAvatarOpenPanel
				if opener then
					pcall(opener)
				end
			end,
		})
	end)
	if okBuild then
		S.avatarSettingsRowBuilt = true
		print("[VLAvatar] Settings row built (Settings > VL Avatar > Open).")
	else
		warn("[VLAvatar] Settings row failed: " .. tostring(err))
	end
end

-- Kartu yang dipakai untuk momen tampil (flash card / MVP):
-- kartu palsu bila ada; bila kartu efektif adalah RANDOM FAVORITES,
-- pilih acak dari SEMUA favorit (server + lokal). Nil = biarkan
-- pilihan server apa adanya.
local function resolveDisplayCardId()
	if S.fakeCard and S.fakeCard ~= RANDOM_CARD_ID then
		return S.fakeCard
	end
	local effective = S.fakeCard or S.serverEquipped.PlayerCard
	if effective == RANDOM_CARD_ID then
		local pool, seen = {}, {}
		local function addToPool(id)
			if isCard(id) and id ~= RANDOM_CARD_ID and not seen[id] then
				seen[id] = true
				table.insert(pool, id)
			end
		end
		for id, fav in pairs(S.serverFavorited) do
			if fav then
				addToPool(id)
			end
		end
		for id in pairs(S.fakeCardFavorites) do
			addToPool(id)
		end
		if #pool > 0 then
			return pool[math.random(1, #pool)]
		end
	end
	return nil
end

-- Roda emote membaca Value Emotes milik EmoteController sendiri
-- (biji dari DataService Equipped.Emotes), bukan Equipped milik
-- InventoryController -- jadi slot palsu diterapkan ke sana:
-- clone peta slot server, timpa dengan slot palsu kita.
local function applyEmotes()
	if not (EmoteController and EmoteController.Emotes) then
		return
	end
	pcall(function()
		local merged = table.clone(S.serverEquipped.Emotes or {})
		for index, emoteId in pairs(S.fakeEmotes) do
			merged[index] = emoteId
		end
		EmoteController.Emotes:set(merged)
	end)
end

local function fetchJerseyProps()
	if JerseyService and JerseyService.GetPlayerJerseyPropsAsync then
		local ok, props = pcall(function()
			local raw = JerseyService:GetPlayerJerseyPropsAsync(player, player.Character)
			-- Tahan dua bentuk hasil: promise Knit (perlu :expect())
			-- atau tabel props langsung.
			if type(raw) == "table" and type(raw.expect) == "function" then
				return raw:expect()
			end
			return raw
		end)
		if ok and type(props) == "table"
			and (props.Name ~= nil or props.Number ~= nil or props.TeamName ~= nil) then
			jerseyPropsCache = {
				Name = props.Name,
				Number = props.Number,
				TeamName = props.TeamName,
			}
		end
	end
	return jerseyPropsCache
end

local lastTeamName = nil

local function resolveTeamName()
	-- Warna jersey ditentukan oleh FOLDER VARIAN TIM di dalam aset
	-- (bukan pewarnaan runtime): Tools.Jersey memakai folder bernama
	-- TeamName bila diberikan, dan memilih ACAK bila tidak. Urutan
	-- sumber kami: props resmi server -> tim terakhir yang terpakai
	-- -> baca-balik dari jersey asli yang sedang dipakai karakter
	-- (template kaos/celana yang terpasang hanya cocok dengan satu
	-- folder tim di aset jersey asli).
	if jerseyPropsCache and jerseyPropsCache.TeamName then
		lastTeamName = jerseyPropsCache.TeamName
		return lastTeamName
	end
	if lastTeamName then
		return lastTeamName
	end
	local char = player.Character
	if not char then
		return nil
	end
	local wornShirt, wornPants
	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Shirt") and child.ShirtTemplate ~= "" then
			wornShirt = child.ShirtTemplate
		elseif child:IsA("Pants") and child.PantsTemplate ~= "" then
			wornPants = child.PantsTemplate
		end
	end
	if not wornShirt and not wornPants then
		return nil
	end
	local realItem = ContentItem:Get(S.serverEquipped.Jersey or "ClassicJersey")
	if not realItem then
		return nil
	end
	local asset = JerseyTool.getAsset(JerseyTool.getItemRenderId(realItem))
	if not asset then
		return nil
	end
	for _, folder in ipairs(asset:GetChildren()) do
		if folder.Name:find("Team") then
			for _, desc in ipairs(folder:GetDescendants()) do
				if (desc:IsA("Shirt") and wornShirt and desc.ShirtTemplate == wornShirt)
					or (desc:IsA("Pants") and wornPants and desc.PantsTemplate == wornPants) then
					lastTeamName = folder.Name
					return lastTeamName
				end
			end
		end
	end
	return nil
end

local function setJerseyLocal(id)
	local char = player.Character
	if not char then
		return
	end
	local props = jerseyPropsCache
	local teamName = resolveTeamName() -- baca SEBELUM set() membersihkan karakter
	pcall(function()
		JerseyTool.set({
			Character = char,
			Id = id,
			Player = player,
			Name = props and props.Name or nil,
			Number = props and props.Number or nil,
			TeamName = teamName,
		})
	end)
	lastJerseyApply = os.clock()
end

local function applyJerseyRender()
	if not S.fakeJersey then
		return
	end
	jerseySeq += 1
	local mySeq = jerseySeq
	task.spawn(function()
		fetchJerseyProps()
		if mySeq == jerseySeq and S.fakeJersey then
			setJerseyLocal(S.fakeJersey)
		end
	end)
end

local function restoreJerseyRender()
	-- Unequip palsu: pasang kembali jersey ASLI secara lokal (persis
	-- tampilan dari server) tanpa perlu respawn.
	jerseySeq += 1
	local mySeq = jerseySeq
	task.spawn(function()
		fetchJerseyProps()
		if mySeq == jerseySeq and not S.fakeJersey then
			setJerseyLocal(S.serverEquipped.Jersey or "ClassicJersey")
		end
	end)
end

local function watchCharacterJersey(char)
	-- Server menimpa jersey karakter pada momen-momen tertentu
	-- (spawn, update style). Pemasangan server menambahkan anak
	-- jersey ke karakter; bila itu terjadi di luar pemasangan lokal
	-- kita, pasang ulang yang palsu.
	char.ChildAdded:Connect(function(child)
		if not S.fakeJersey then
			return
		end
		if os.clock() - lastJerseyApply < 2 then
			return
		end
		if child.Name == "JerseyBack" or child.Name == "JerseyFront"
			or child.Name == "_jerseyInstances" or child:IsA("Clothing")
			or child:IsA("ShirtGraphic") then
			task.delay(0.3, applyJerseyRender)
		end
	end)
end

local function scrubJerseyPreviewLocks()
	-- Sentuhan akhir kosmetik: paksa sembunyikan gembok + kembalikan
	-- warna penuh gambar di daftar layar Jersey Preview yang sudah
	-- terlanjur dibuat (sumber datanya tetap Value hasil injeksi,
	-- jadi hitungan ulang Fusion berikutnya pun konsisten).
	pcall(function()
		local interfaceController = Knit.GetController("InterfaceController")
		local lobby = interfaceController and interfaceController.App
			and interfaceController.App:FindFirstChild("Lobby")
		local menu = lobby and lobby:FindFirstChild("JerseyPreview")
		local list = menu and menu:FindFirstChild("Dropdown", true)
		if not list then
			return
		end
		for _, row in ipairs(list:GetChildren()) do
			if isJersey(row.Name) then
				local lock = row:FindFirstChild("Lock", true)
				if lock then
					lock.Visible = false
				end
				local img = row:FindFirstChild("ImageLabel", true)
				if img then
					img.ImageColor3 = Color3.new(1, 1, 1)
				end
			end
		end
	end)
end

local function scrubFxPreviewLocks()
	-- Sama seperti scrub jersey, untuk daftar di layar Score FX
	-- Preview (App.Lobby.EffectPreview): baris bernama id efek di
	-- dalam dropdown per grup; gembok + gambar abu ada di anak
	-- "Button"-nya.
	pcall(function()
		local lobby = InterfaceController and InterfaceController.App
			and InterfaceController.App:FindFirstChild("Lobby")
		local menu = lobby and lobby:FindFirstChild("EffectPreview")
		local list = menu and menu:FindFirstChild("List", true)
		if not list then
			return
		end
		for _, row in ipairs(list:GetDescendants()) do
			if row:IsA("GuiObject") and isScoreFx(row.Name) then
				local button = row:FindFirstChild("Button")
				if button then
					local lock = button:FindFirstChild("Lock", true)
					if lock then
						lock.Visible = false
					end
					local img = button:FindFirstChild("ImageLabel", true)
					if img then
						img.ImageColor3 = Color3.new(1, 1, 1)
					end
				end
			end
		end
	end)
end

----------------------------------------------------------------
-- Alert kekurangan (PromptController resmi game -- dialog yang
-- sama dengan konfirmasi spin style/ability). Ditampilkan SEBELUM
-- equip palsu untuk item yang diketahui punya kekurangan, agar
-- tidak kaget belakangan. Batal = equip tidak terjadi.
----------------------------------------------------------------
-- Emote yang Metadata.Callback-nya menelurkan properti di karakter
-- (dari definisi item di Content/Item/Entities). Untuk equip
-- palsu propertinya hanya jalan lokal (lihat bungkus Use di
-- bawah), tidak terlihat pemain lain.
local PROP_EMOTES = {
	BeachBallEmote = true, BecomeSpiderEmote = true,
	BroomEmote = true, CarrotEmote = true, CleanSweepEmote = true,
	CopySkateboardEmote = true, CrabRaveEmote = true,
	DiamondEmote = true, DigInEmote = true, EatTurkeyEmote = true,
	EggThrowEmote = true, FlamethrowerEmote = true,
	GlowStickDanceEmote = true, GuitarEmote = true,
	HakkaSkateboardEmote = true, IWinEmote = true,
	LayEggEmote = true, PopcornEmote = true,
	PumpkinDribbleEmote = true, SadTromboneEmote = true,
	SadViolinEmote = true, ShieldBashEmote = true,
	SingerEmote = true, SkateboardEmote = true,
	SleepingEmote = true, TenOutOfTenEmote = true,
	TikiDrumEmote = true, TongueEmote = true,
	TrickOrTreatEmote = true, TurkeyExplodingEmote = true,
	TurkeyRideEmote = true, TurkeySquishEmote = true,
	VolcanoEmote = true, VomitEmote = true, WandEmote = true,
	WitchesBrewEmote = true,
}

	local function stopEmoteProp(id)
		local cleanup = activeEmoteProps[id]
		activeEmoteProps[id] = nil
		if cleanup then
			pcall(cleanup)
		end
	end

	local function stopAllEmoteProps()
		for id in pairs(activeEmoteProps) do
			stopEmoteProp(id)
		end
	end

	local function runEmoteProp(id)
		local item = ContentItem:Get(id)
		local handler = item and item.Metadata and item.Metadata.Handler
		if not (handler and handler.run) then
			return
		end
		stopEmoteProp(id)
		local ok, cleanup = pcall(function()
			return handler.run({ Character = player.Character })
		end)
		if ok and type(cleanup) == "function" then
			activeEmoteProps[id] = cleanup
			if not (item.Metadata and item.Metadata.Looped) then
				local length = 0
				pcall(function()
					length = AnimationController:GetAnimationLength(id)
				end)
				if length and length > 0 then
					task.delay(length, function()
						stopEmoteProp(id)
					end)
				end
			end
		end
	end

	local function isFakeEmoteEquipped(id)
		for _, emoteId in pairs(S.fakeEmotes) do
			if emoteId == id then
				return true
			end
		end
		return false
	end

local function initRemainingFeatures()
	if not awaitFeatureShared(90) then
		warn("[VLRemaining] feature-shared tidak siap; modul sisa dilewati.")
		return
	end
	FeatureAPI.ensureFxCarrier = ensureFxCarrier
	FeatureAPI.applyVLSettings = applyVLSettings
	FeatureAPI.applyEmotes = applyEmotes
	if not S.installedRemaining then
		S.installedRemaining = true
	-- Favorit kartu palsu: server menolak memfavoritkan item yang
	-- tidak dimiliki, jadi untuk kartu yang belum dimiliki toggle
	-- disimpan lokal (S.fakeCardFavorites) dan diterapkan ke Value
	-- Favorited yang dibaca UI.
	if InventoryService.ToggleFavorite then
		local originalToggleFavorite = InventoryService.ToggleFavorite
		InventoryService.ToggleFavorite = function(_, id, ...)
			if isCard(id) and not S.realOwned[id] then
				local added = not S.fakeCardFavorites[id]
				if added then
					S.fakeCardFavorites[id] = true
				else
					S.fakeCardFavorites[id] = nil
				end
				applyFavorites()
				saveLocal()
				-- TryToggleFavorite meneruskan nilai KEDUA hasil
				-- ToggleFavorite sebagai teks notifikasi; nil membuat
				-- komponen Notify error -- selalu sertakan pesan.
				return resolvedPromise(true, added and "Added to favorites." or "Removed from favorites.")
			end
			if isScoreFx(id) and not S.realOwned[id] then
				local added = not S.fakeFxFavorites[id]
				if added then
					S.fakeFxFavorites[id] = true
				else
					S.fakeFxFavorites[id] = nil
				end
				applyFavorites()
				saveLocal()
				return resolvedPromise(true, added and "Added to favorites." or "Removed from favorites.")
			end
			local promise = originalToggleFavorite(_, id, ...)
			-- Server tidak selalu mengirim pesan (saat melepas
			-- favorit pesannya nil) dan TryToggleFavorite milik game
			-- tidak menjaganya, sehingga komponen Notify error
			-- "Unable to assign property Text ... got nil". Isi
			-- pesan bawaan bila server tidak mengirimnya.
			if promise and type(promise.andThen) == "function" then
				return promise:andThen(function(success, message)
					if message == nil then
						message = success and "Favorites updated." or "Failed to update favorites."
					end
					return success, message
				end)
			end
			return promise
		end
	end
	-- Momen tampil kartu (flash card saat mencetak poin + kartu MVP)
	-- digerakkan event server yang membawa id kartu ASLI. Untuk
	-- event tentang pemain lokal, tukar id-nya dengan kartu palsu /
	-- hasil acak RANDOM FAVORITES sebelum dirender. Controller
	-- membaca DisplayFlashCard dari tabelnya setiap event, jadi
	-- membungkus method-nya efektif.
	if PlayerCardController and PlayerCardController.DisplayFlashCard then
		local originalDisplayFlashCard = PlayerCardController.DisplayFlashCard
		PlayerCardController.DisplayFlashCard = function(self, data)
			if type(data) == "table" and data.Player == player then
				local resolved = resolveDisplayCardId()
				if resolved and resolved ~= data.PlayerCardItemId then
					data = table.clone(data)
					data.PlayerCardItemId = resolved
				end
			end
			return originalDisplayFlashCard(self, data)
		end
	end
	-- Saklar bagian Settings tambahan: ChangeSetting untuk kunci
	-- komposit milik kita ditangani lokal (server tidak mengenal
	-- kuncinya); kunci asli diteruskan ke server seperti biasa.
	if SettingsService and SettingsService.ChangeSetting then
		local originalChangeSetting = SettingsService.ChangeSetting
		SettingsService.ChangeSetting = function(_, key, value, ...)
			if key == SETTINGS_KEY_WORLD_FX then
				S.settings[SETTING_MEMBER_WORLD_FX] = value == true
				applyVLSettings()
				saveLocal()
				return resolvedPromise(true)
			end
			return originalChangeSetting(_, key, value, ...)
		end
	end
	-- Score FX dibungkus di satu corong yang sama (semua pemutaran
	-- efek skor lewat EffectController.PlayScoreEffect):
	-- 1) SPOOF: untuk poin milik pemain lokal sendiri saat bermain
	--    langsung, Item ditukar dengan efek palsu / hasil acak
	--    RANDOM FAVORITES sebelum dimainkan.
	-- 2) GERBANG FISIK: bila saklar World-Affecting mati, efek dari
	--    daftar WORLD_AFFECTING_FX (dinilai dari item FINAL setelah
	--    penukaran) tidak dimainkan sama sekali di client ini.
	-- Replay tidak disentuh oleh keduanya.
	if EffectController and EffectController.PlayScoreEffect then
		pcall(function()
			SoundTool = require(RS:WaitForChild("Tools"):WaitForChild("Sound"))
		end)
		local originalPlayScoreEffect = EffectController.PlayScoreEffect
		EffectController.PlayScoreEffect = function(self, data)
			if type(data) == "table" and not data.IsReplay and data.Item then
				if data.Character == player.Character and isLocalInGame() then
					local gateOff = S.settings[SETTING_MEMBER_WORLD_FX] == false
					-- Saklar mati: pool Random menyingkirkan efek
					-- berpengaruh fisik agar poin tetap menampilkan
					-- sesuatu; efek spesifik dinilai gerbang di bawah.
					local resolvedId = gateOff
						and resolveScoreFxItemIdExcludingWorld()
						or resolveScoreFxItemId()
					if resolvedId and resolvedId ~= data.Item.Id then
						local item = ContentItem:Get(resolvedId)
						if item and not (gateOff and WORLD_AFFECTING_FX[resolvedId]) then
							data = table.clone(data)
							data.Item = item
							-- Suara poin mengikuti efek spoof (suara
							-- terdaftar game berasal dari efek server/
							-- pembawa, yang dipilih hening).
							playFxPointSound(item, data.Origin)
						end
					end
				end
				if S.settings[SETTING_MEMBER_WORLD_FX] == false
					and WORLD_AFFECTING_FX[data.Item.Id]
					and isLocalInGame() then
					return function() end
				end
			end
			return originalPlayScoreEffect(self, data)
		end
	end
	-- InventoryService:Equip -- hybrid asli/palsu.
	local originalEquip = InventoryService.Equip
	S.originalEquip = originalEquip
	InventoryService.Equip = function(_, id, ...)
		if isBall(id) and not S.realOwned[id] then
			if S.fakeEquipped == id then
				S.fakeEquipped = nil -- klik lagi = unequip
				applyEquipped()
				saveLocal()
			else
				local function doEquip()
					S.fakeEquipped = id
					applyEquipped()
					saveLocal()
				end
				-- Bola berefek permukaan (Handler.SurfaceHit, mis.
				-- SlimeBall): efeknya tergate server -> alert dulu.
				local item = ContentItem:Get(id)
				local handler = item and item.Metadata and item.Metadata.Handler
				if handler and handler.SurfaceHit then
					showSpoofAlert(item.DisplayName or id, ALERT_BALL_SURFACE, doEquip)
				else
					doEquip()
				end
			end
			return resolvedPromise(true)
		end
		if isJersey(id) and not S.realOwned[id] then
			if S.fakeJersey == id then
				S.fakeJersey = nil -- klik lagi = unequip
				applyEquipped()
				saveLocal()
				-- Server tidak tahu apa-apa: pasang kembali yang
				-- asli secara lokal.
				restoreJerseyRender()
			else
				S.fakeJersey = id
				applyEquipped()
				saveLocal()
				applyJerseyRender()
			end
			return resolvedPromise(true)
		end
		if isEmote(id) and not S.realOwned[id] then
			-- Equip emote = menaruhnya di slot roda:
			-- InventoryService:Equip(id, indexSlot) dari mode pilih
			-- slot (Components/Wheel). Tanpa indeks, pakai slot
			-- pertama yang kosong (gabungan server + palsu).
			local index = select(1, ...)
			if type(index) ~= "number" then
				index = 1
				while S.fakeEmotes[index]
					or (S.serverEquipped.Emotes and S.serverEquipped.Emotes[index]) do
					index += 1
				end
			end
			if S.fakeEmotes[index] == id then
				S.fakeEmotes[index] = nil -- slot yang sama = lepas
				applyEmotes()
				saveLocal()
			else
				local function doEquip()
					-- Satu emote hanya di satu slot: pindahkan bila
					-- sudah menempati slot palsu lain.
					for slot, emoteId in pairs(S.fakeEmotes) do
						if emoteId == id then
							S.fakeEmotes[slot] = nil
						end
					end
					S.fakeEmotes[index] = id
					applyEmotes()
					saveLocal()
				end
				-- Emote berproperti: efeknya server-driven -> alert.
				if PROP_EMOTES[id] then
					local item = ContentItem:Get(id)
					showSpoofAlert((item and item.DisplayName) or id, ALERT_EMOTE_PROP, doEquip)
				else
					doEquip()
				end
			end
			return resolvedPromise(true)
		end
		if isCard(id) and not S.realOwned[id] then
			-- Kartu palsu: toggle lokal seperti bola. Halaman kartu
			-- membaca hasil Equip dengan :expect() dan menganggap
			-- nilai truthy sebagai PESAN ERROR -- jadi kembalikan
			-- promise kosong (sukses = tanpa nilai).
			if S.fakeCard == id then
				S.fakeCard = nil
			else
				S.fakeCard = id
			end
			applyEquipped()
			saveLocal()
			return resolvedPromise()
		end
		if isScoreFx(id) and not S.realOwned[id] then
			-- Score FX palsu: toggle lokal seperti kartu.
			if S.fakeScoreFx == id then
				-- Lapis palsu dilepas: slot server TIDAK disentuh
				-- (pembawa yang terpasang adalah efek asli; biarkan).
				S.fakeScoreFx = nil
				applyEquipped()
				saveLocal()
			else
				local function doEquip()
					S.fakeScoreFx = id
					applyEquipped()
					saveLocal()
					task.defer(ensureFxCarrier)
				end
				-- Efek berpengaruh fisik: pengaruhnya hanya berlaku
				-- lokal untuk versi spoof -> alert dulu.
				if WORLD_AFFECTING_FX[id] then
					local item = ContentItem:Get(id)
					showSpoofAlert((item and item.DisplayName) or id, ALERT_FX_WORLD, doEquip)
				else
					doEquip()
				end
			end
			return resolvedPromise(true)
		end
		-- Item asli: bersihkan lapisan palsu kategorinya, teruskan.
		if isScoreFx(id) then
			-- Catat waktu klik equip asli user: ensureFxCarrier
			-- tidak boleh menimpa pilihan ini dengan pembawa.
			S.fxUserEquipAt = os.clock()
			if id == RANDOM_FX_ID then
				-- Random Favorite ASLI di-equip: lapis acak lokal
				-- menyala bersamanya (tampilan inventory tetap
				-- Random, pool penukaran = favorit lokal). Klik
				-- saat Random sedang ter-equip = unequip.
				if S.serverEquipped.ScoreEffect == RANDOM_FX_ID then
					if S.fakeScoreFx == RANDOM_FX_ID then
						S.fakeScoreFx = nil
						applyEquipped()
						saveLocal()
					end
				elseif S.fakeScoreFx ~= RANDOM_FX_ID then
					S.fakeScoreFx = RANDOM_FX_ID
					applyEquipped()
					saveLocal()
				end
				-- Equip Random asli menaruh Random di slot server;
				-- server tidak menyiarkan apa pun untuk Random bila
				-- favorit asli kosong, jadi pembawa harus dipasang
				-- MENGGANTIKAN Random di belakang layar. Tertunda 6
				-- detik agar melewati jendela fxUserEquipAt yang
				-- baru saja diset klik ini; ensureFxCarrier menjaga
				-- dirinya sendiri bila lapis ternyata dimatikan.
				task.delay(6, ensureFxCarrier)
			elseif S.fakeScoreFx then
				S.fakeScoreFx = nil
				applyEquipped()
				saveLocal()
			end
		end
		if isCard(id) and S.fakeCard then
			S.fakeCard = nil
			applyEquipped()
			saveLocal()
		end
		if isBall(id) and S.fakeEquipped then
			S.fakeEquipped = nil
			applyEquipped()
			saveLocal()
		end
		if isJersey(id) and S.fakeJersey then
			S.fakeJersey = nil
			applyEquipped()
			saveLocal()
			-- Render tidak perlu dipulihkan lokal: server memasang
			-- jersey asli yang baru di-equip ini ke karakter.
		end
		return originalEquip(_, id, ...)
	end

	-- Properti emote palsu: Handler.run milik item tersedia utuh di
	-- klien, tapi TIDAK ada kode klien yang memanggilnya -- normalnya
	-- server yang menjalankannya saat menerima InventoryService:Use.
	-- Untuk emote palsu yang sedang ter-equip, jalankan secara lokal
	-- saat emote dimainkan (bungkus Use di bawah): properti muncul
	-- menempel di karakter, hanya terlihat di layar ini. Cleanup
	-- mengikuti pola roda resmi: emote non-loop dibersihkan setelah
	-- panjang animasinya, StopEmotes membersihkan semuanya.
	local activeEmoteProps = {} -- [id emote] = fungsi cleanup
	local originalUse = InventoryService.Use
	InventoryService.Use = function(_, id, ...)
		local result = originalUse(_, id, ...)
		if type(id) == "string" and PROP_EMOTES[id] and isFakeEmoteEquipped(id) then
			task.spawn(runEmoteProp, id)
		end
		return result
	end
	if InventoryService.StopEmotes then
		local originalStopEmotes = InventoryService.StopEmotes
		InventoryService.StopEmotes = function(_, ...)
			stopAllEmoteProps()
			return originalStopEmotes(_, ...)
		end
	end
	player.CharacterAdded:Connect(function()
		stopAllEmoteProps()
	end)
	-- Layar Jersey Preview: pastikan injeksi segar + gembok hilang
	-- setiap kali layar dibuka.
	if JerseyPreviewController and JerseyPreviewController.Open then
		local originalPreviewOpen = JerseyPreviewController.Open
		JerseyPreviewController.Open = function(self, id, ...)
			injectInventory()
			local result = originalPreviewOpen(self, id, ...)
			task.delay(0.5, scrubJerseyPreviewLocks)
			return result
		end
	end
	-- Hal yang sama untuk layar Score FX Preview.
	if ScoreEffectPreviewController and ScoreEffectPreviewController.Open then
		local originalFxPreviewOpen = ScoreEffectPreviewController.Open
		ScoreEffectPreviewController.Open = function(self, id, ...)
			injectInventory()
			local result = originalFxPreviewOpen(self, id, ...)
			task.delay(0.5, scrubFxPreviewLocks)
			return result
		end
	end
	-- Jersey: karakter baru (respawn) dipasangi yang asli oleh
	-- server; pasang ulang yang palsu + pasang penjaga timpaan.
	player.CharacterAdded:Connect(function(char)
		watchCharacterJersey(char)
		task.delay(1, function()
			if S.fakeJersey then
				applyJerseyRender()
			end
		end)
	end)
	if player.Character then
		watchCharacterJersey(player.Character)
	end
	end
	applyEmotes()
	applyVLSettings()
	if S.fakeScoreFx then
		task.defer(ensureFxCarrier)
	end
	task.spawn(buildSettingsSection)
	task.spawn(buildAvatarSettingsRow)
	if S.fakeJersey then
		applyJerseyRender()
	end
	task.delay(3, scrubJerseyPreviewLocks)
	task.delay(3, scrubFxPreviewLocks)
	local fakeEmoteCount = 0
	for _ in pairs(S.fakeEmotes) do
		fakeEmoteCount += 1
	end
	local fakeCardFavCount = 0
	for _ in pairs(S.fakeCardFavorites) do
		fakeCardFavCount += 1
	end
	local fakeFxFavCount = 0
	for _ in pairs(S.fakeFxFavorites) do
		fakeFxFavCount += 1
	end
	print(("[VLBallSpoof] active: %d balls + %d jerseys + %d emotes + %d cards + %d fx shown in inventory. Fake ball: %s | Fake jersey: %s | Fake emotes: %d slots | Fake card: %s | Fake card favorites: %d | Fake FX: %s | Fake FX favorites: %d | FX carrier: %s"):format(
		#ALL_BALL_IDS, #ALL_JERSEY_IDS, #ALL_EMOTE_IDS, #ALL_CARD_IDS, #ALL_FX_IDS,
		tostring(S.fakeEquipped), tostring(S.fakeJersey), fakeEmoteCount,
		tostring(S.fakeCard), fakeCardFavCount,
		tostring(S.fakeScoreFx), fakeFxFavCount,
		tostring(S.serverEquipped.ScoreEffect)))
end

task.spawn(initRemainingFeatures)
