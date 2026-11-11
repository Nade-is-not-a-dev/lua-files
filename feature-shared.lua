----------------------------------------------------------------
-- feature-shared.lua -- infrastruktur bersama fitur
-- (dulu: kerangka initBallSpoof di vl-ball-spoof.lua monolit)
--
-- Berisi: akuisisi controller/service Knit + tunggu seed
-- profil, klasifikasi item, konstanta bersama, state S,
-- save/load vl-ball-spoof.json, patch aset, applyEquipped /
-- applyFavorites, injectInventory, dan pengawatan event
-- bersama (ProfileUpdated, penjaga drift, InventoryChanged).
--
-- File ini hanya MENYEDIAKAN alat: init-nya cuma menyiapkan
-- alat (akuisisi + seed) lalu selesai; perilaku (pengawatan
-- event, injeksi, penerapan lapisan) dilakukan modul fitur
-- memakai alatnya (installSuiteWiring, injectInventory,
-- applyEquipped, ...). Modul fitur berjalan SETELAH file
-- ini dan memakai local-local di sini. Panggilan
-- balik ke modul fitur lewat FeatureAPI (diisi modul fitur)
-- karena urutan deklarasi satu chunk.
----------------------------------------------------------------
local FeatureAPI = {}
local FeatureSharedReady = false
local function awaitFeatureShared(timeout)
	local deadline = os.clock() + (timeout or 90)
	while not FeatureSharedReady and os.clock() < deadline do
		task.wait(0.1)
	end
	return FeatureSharedReady
end

-- Fitur yang AKTIF di build ini: modul fitur mendaftarkan
-- dirinya di top level file-nya (suiteActivateFeature("Ball")
-- dst, memakai nama tipe Content). Alat bersama di file ini
-- (injectInventory, applyEquipped, applyFavorites) hanya
-- menyentuh kategori yang aktif, jadi build satu fitur
-- benar-benar berperilaku satu fitur.
local SuiteActive = {}
local function suiteActivateFeature(name)
	SuiteActive[name] = true
end

-- Controller & service bersama: dinyatakan di sini (chunk),
-- diisi initFeatureShared begitu Knit siap.
local InventoryController, InventoryService, DataService, CountService, JerseyService, JerseyPreviewController, EmoteController, PromptController, AnimationController, PlayerCardController, PlayerCardService, SettingsService, SettingsController, InterfaceController, EffectController, ScoreEffectPreviewController


local BALL_TYPE = ContentItem.Type.Ball
local ALL_BALL_IDS = ContentItem:GetAllIdsFromType(BALL_TYPE)

local function isBall(id)
	local item = id and ContentItem:Get(id)
	return item ~= nil and item.Type == BALL_TYPE
end

local JERSEY_TYPE = ContentItem.Type.Jersey
local ALL_JERSEY_IDS = ContentItem:GetAllIdsFromType(JERSEY_TYPE)

local function isJersey(id)
	local item = id and ContentItem:Get(id)
	return item ~= nil and item.Type == JERSEY_TYPE
end

local EMOTE_TYPE = ContentItem.Type.Emote
local ALL_EMOTE_IDS = ContentItem:GetAllIdsFromType(EMOTE_TYPE)

local function isEmote(id)
	local item = id and ContentItem:Get(id)
	return item ~= nil and item.Type == EMOTE_TYPE
end

local CARD_TYPE = ContentItem.Type.PlayerCard
local ALL_CARD_IDS = ContentItem:GetAllIdsFromType(CARD_TYPE)

local function isCard(id)
	local item = id and ContentItem:Get(id)
	return item ~= nil and item.Type == CARD_TYPE
end

local FX_TYPE = ContentItem.Type.ScoreEffect
local ALL_FX_IDS = ContentItem:GetAllIdsFromType(FX_TYPE)

local function isScoreFx(id)
	local item = id and ContentItem:Get(id)
	return item ~= nil and item.Type == FX_TYPE
end

-- Varian "acak dari favorit" milik Score FX (pola sama seperti kartu).
local RANDOM_FX_ID = "RandomFavoriteScoreEffect"

-- Kartu khusus "RANDOM FAVORITES": bila ter-equip, kartu yang tampil
-- dipilih acak dari daftar favorit. Diidentifikasi dari Id karena
-- flag Metadata.IsForRandomizing tidak terbaca dari data item.
local RANDOM_CARD_ID = "RandomFavoritePlayerCard"

-- Bagian Settings tambahan (grup GroupPages milik game) + saklar
-- untuk Score FX yang efeknya memengaruhi pemain secara fisik
-- (daftar disusun dari bukti kode: modul efeknya memasang gaya /
-- kecepatan ke karakter pemain -- tarik, pantul, dorong, selip).
local SETTINGS_GROUP = "VLSettings"
local SETTING_MEMBER_WORLD_FX = "WorldAffectingScoreFX"
local SETTINGS_KEY_WORLD_FX = SETTINGS_GROUP .. "_" .. SETTING_MEMBER_WORLD_FX
local SETTING_MEMBER_EXTREME = "ExtremeUltraFastMode"
local SETTINGS_KEY_EXTREME = SETTINGS_GROUP .. "_" .. SETTING_MEMBER_EXTREME
local SETTING_MEMBER_SHIFTLOCK = "AutoShiftlock"
local SETTINGS_KEY_SHIFTLOCK = SETTINGS_GROUP .. "_" .. SETTING_MEMBER_SHIFTLOCK
-- Username Spoofer: BUKAN kunci Settings game (tidak ada saklar
-- grupnya); nilainya hanya hidup di simpanan lokal S.settings.
local SETTING_MEMBER_USERNAME = "UsernameSpoof"
-- Stats Spoofer: sama, hanya hidup di simpanan lokal; isinya
-- tabel {namaField = angka} untuk field yang di-spoof saja.
local SETTING_MEMBER_STATS = "StatsSpoof"
-- Auto Farm (v15): sama, hanya hidup di simpanan lokal; boolean
-- saklar loop AUTO. Loop dijalankan modul farm; persistensi ini
-- yang membuatnya lanjut sendiri setelah rejoin (auto-attach).
local SETTING_MEMBER_FARM = "AutoFarm"
-- Auto Spin: hanya hidup di simpanan lokal juga; isinya
-- { Style = { Enabled = bool, Targets = {id=true,...} },
--   Ability = { Enabled = bool, Targets = {id=true,...} } }.
local SETTING_MEMBER_SPIN = "AutoSpin"
-- Avatar Lite TIDAK lagi jadi anggota grup: anggota grup selalu
-- dirender game sebagai saklar. Sebagai gantinya panel dibuka dari
-- baris tombol khusus di daftar utama Settings (pola yang sama
-- dengan baris "Buttons / Edit [Open]" milik ButtonEditController
-- game sendiri) -- lihat buildAvatarSettingsRow.
local WORLD_AFFECTING_FX = {
	SupernovaScoreEffect = true, -- black hole: AlignPosition menarik karakter
	TrampolineScoreEffect = true, -- memantulkan pemain yang menginjaknya
	TsunamiScoreEffect = true, -- gelombang mendorong karakter (AlignPosition)
	BallPortalScoreEffect = true, -- portal menggerakkan karakter (AlignPosition)
	BananaSlipScoreEffect = true, -- mengubah kecepatan karakter (tergelincir)
	GenieLampScoreEffect = true, -- melontarkan karakter (kecepatan)
	GreenEnergyScoreEffect = true, -- AlignPosition ke karakter
}

local StateModule
pcall(function()
	StateModule = require(RS:WaitForChild("Common"):WaitForChild("State"))
end)

local function isLocalInGame()
	if not StateModule then
		return false
	end
	local ok, result = pcall(StateModule.get, player, StateModule.Id.Gameplay, "InGame")
	return ok and result == true
end

local JerseyTool = require(RS:WaitForChild("Tools"):WaitForChild("Jersey"))

----------------------------------------------------------------
-- State spoof (satu-satunya, disimpan di getgenv agar aman
-- dijalankan ulang)
----------------------------------------------------------------
local S = getgenv().VLBallSpoofState
if not S then
	S = {
		realOwned = {}, -- [id] = true, kepemilikan asli dari server
		serverEquipped = {},
		fakeEquipped = nil, -- id bola palsu yang ter-equip (lokal)
		fakeJersey = nil, -- id jersey palsu yang dipakai (lokal)
		fakeEmotes = {}, -- [indexSlot] = id emote palsu di roda emote
		fakeCard = nil, -- id kartu pemain palsu yang ter-equip (lokal)
		fakeCardFavorites = {}, -- [idKartu] = true, favorit kartu lokal
		fakeScoreFx = nil, -- id Score FX palsu yang ter-equip (lokal)
		fakeFxFavorites = {}, -- [idFx] = true, favorit Score FX lokal
		fxCarrier = nil, -- id Score FX asli yang terakhir dipasang script sebagai pembawa (info saja)
		serverFavorited = {}, -- favorit asli dari server
		settings = { WorldAffectingScoreFX = true, ExtremeUltraFastMode = false, AutoShiftlock = false, UsernameSpoof = "", StatsSpoof = {}, AutoFarm = false, AutoSpin = { Style = { Enabled = false, Targets = {} }, Ability = { Enabled = false, Targets = {} } } }, -- saklar bagian Settings tambahan + spoof nama/statistik + farm/spin
		settingsSectionBuilt = false,
		settingsGroupRegistered = false,
		avatarSettingsRowBuilt = false,
		usernameSettingsRowBuilt = false,
		statsSettingsRowBuilt = false,
		farmSettingsRowBuilt = false,
		spinSettingsRowBuilt = false,
		installed = false,
		patchedAssetId = nil,
		patchedAssetOriginal = nil,
	}
	getgenv().VLBallSpoofState = S
end
if S.serveLog == nil then
	S.serveLog = {} -- [{t=os.clock(), server=nama|nil, skin=id|nil}]
end
if S.fakeEmotes == nil then
	S.fakeEmotes = {}
end
if S.fakeCardFavorites == nil then
	S.fakeCardFavorites = {}
end
if S.fakeFxFavorites == nil then
	S.fakeFxFavorites = {}
end
if S.serverFavorited == nil then
	S.serverFavorited = {}
end
if S.settings == nil then
	S.settings = { WorldAffectingScoreFX = true }
end

-- Segarkan kebenaran server dari DataService (bukan dari
-- state UI): S.realOwned + S.serverEquipped +
-- S.serverFavorited. Dulu blok ini duduk di top level
-- file dan tidak pernah berhasil jalan -- DataService
-- baru terisi di initFeatureShared, jadi pcall-nya
-- selalu menelan error dan realOwned selalu kosong
-- (carrier Score FX tidak pernah ketemu). Sekarang ia
-- fungsi alat; init memanggilnya setelah seed selesai.
local function refreshServerTruth()
	pcall(function()
		local inv = DataService:Get("Inventory"):expect()
		if type(inv) == "table" then
			table.clear(S.realOwned)
			for id, count in pairs(inv) do
				if count and count > 0 then
					S.realOwned[id] = true
				end
			end
		end
		local eq = DataService:Get("Equipped"):expect()
		if type(eq) == "table" then
			S.serverEquipped = eq
		end
		local fav = DataService:Get("Favorited"):expect()
		if type(fav) == "table" then
			S.serverFavorited = fav
		end
	end)
end

----------------------------------------------------------------
-- Persistensi lokal
----------------------------------------------------------------
local hasFS = (typeof(writefile) == "function" and typeof(readfile) == "function"
	and typeof(isfile) == "function")

local function saveLocal()
	if not hasFS then
		return
	end
	pcall(function()
		local cardFavorites = {}
		for id in pairs(S.fakeCardFavorites) do
			table.insert(cardFavorites, id)
		end
		local fxFavorites = {}
		for id in pairs(S.fakeFxFavorites) do
			table.insert(fxFavorites, id)
		end
		writefile(SAVE_FILE, HttpService:JSONEncode({
			equipped = S.fakeEquipped,
			jersey = S.fakeJersey,
			emotes = S.fakeEmotes,
			card = S.fakeCard,
			cardFavorites = cardFavorites,
			fx = S.fakeScoreFx,
			fxFavorites = fxFavorites,
			fxCarrier = S.fxCarrier,
			settings = S.settings,
		}))
	end)
end

local LocalStateLoaded = false
local function loadLocal()
	if LocalStateLoaded then
		return
	end
	LocalStateLoaded = true
	S.localStateLoaded = true
	if not hasFS then
		return
	end
	pcall(function()
		if isfile(SAVE_FILE) then
			local data = HttpService:JSONDecode(readfile(SAVE_FILE))
			if type(data) == "table" then
				if isBall(data.equipped) and not S.realOwned[data.equipped] then
					S.fakeEquipped = data.equipped
				end
				if isJersey(data.jersey) and not S.realOwned[data.jersey] then
					S.fakeJersey = data.jersey
				end
				if type(data.emotes) == "table" then
					-- Kunci JSON selalu string; kembalikan ke angka.
					for key, emoteId in pairs(data.emotes) do
						local index = tonumber(key)
						if index and isEmote(emoteId) and not S.realOwned[emoteId] then
							S.fakeEmotes[index] = emoteId
						end
					end
				end
				if isCard(data.card) and not S.realOwned[data.card] then
					S.fakeCard = data.card
				end
				if type(data.cardFavorites) == "table" then
					for _, cardId in ipairs(data.cardFavorites) do
						if isCard(cardId) and not S.realOwned[cardId] then
							S.fakeCardFavorites[cardId] = true
						end
					end
				end
				if type(data.settings) == "table"
					and type(data.settings[SETTING_MEMBER_WORLD_FX]) == "boolean" then
					S.settings[SETTING_MEMBER_WORLD_FX] = data.settings[SETTING_MEMBER_WORLD_FX]
				end
				if type(data.settings) == "table"
					and type(data.settings[SETTING_MEMBER_EXTREME]) == "boolean" then
					S.settings[SETTING_MEMBER_EXTREME] = data.settings[SETTING_MEMBER_EXTREME]
				end
				S.extremeFast = S.settings[SETTING_MEMBER_EXTREME] == true
				if type(data.settings) == "table"
					and type(data.settings[SETTING_MEMBER_SHIFTLOCK]) == "boolean" then
					S.settings[SETTING_MEMBER_SHIFTLOCK] = data.settings[SETTING_MEMBER_SHIFTLOCK]
				end
				if type(data.settings) == "table"
					and type(data.settings[SETTING_MEMBER_USERNAME]) == "string" then
					S.settings[SETTING_MEMBER_USERNAME] = data.settings[SETTING_MEMBER_USERNAME]
				end
				if type(data.settings) == "table"
					and type(data.settings[SETTING_MEMBER_STATS]) == "table" then
					local cleanStats = {}
					for _, field in ipairs({ "Wins", "Losses", "MVPs", "Games", "Points", "Spikes", "Blocks", "Aces", "Saves", "Elo" }) do
						local v = data.settings[SETTING_MEMBER_STATS][field]
						if type(v) == "number" and v >= 0 then
							cleanStats[field] = math.floor(v)
						end
					end
					S.settings[SETTING_MEMBER_STATS] = cleanStats
				end
				if type(data.settings) == "table"
					and type(data.settings[SETTING_MEMBER_FARM]) == "boolean" then
					S.settings[SETTING_MEMBER_FARM] = data.settings[SETTING_MEMBER_FARM]
				end
				if type(data.settings) == "table"
					and type(data.settings[SETTING_MEMBER_SPIN]) == "table" then
					-- Sanitasi AutoSpin: hanya Enabled boolean +
					-- Targets berisi kunci string bernilai true.
					local cleanSpin = { Style = { Enabled = false, Targets = {} }, Ability = { Enabled = false, Targets = {} } }
					for _, kind in ipairs({ "Style", "Ability" }) do
						local src = data.settings[SETTING_MEMBER_SPIN][kind]
						if type(src) == "table" then
							cleanSpin[kind].Enabled = src.Enabled == true
							if type(src.Targets) == "table" then
								for id, on in pairs(src.Targets) do
									if type(id) == "string" and on == true then
										cleanSpin[kind].Targets[id] = true
									end
								end
							end
						end
					end
					S.settings[SETTING_MEMBER_SPIN] = cleanSpin
				end
				if isScoreFx(data.fx)
					and (not S.realOwned[data.fx] or data.fx == RANDOM_FX_ID) then
					-- Random Favorite boleh memuat lapis lokal walau
					-- dimiliki asli (keduanya hidup berdampingan).
					S.fakeScoreFx = data.fx
				end
				if isScoreFx(data.fxCarrier) then
					S.fxCarrier = data.fxCarrier
				end
				-- Field fxCarrierOriginal/fxCarrierActive dari versi
				-- lama SENGAJA tidak dibaca lagi: sistem pulihkan-
				-- otomatisnya terbukti mengosongkan slot FX user.
				if type(data.fxFavorites) == "table" then
					for _, fxId in ipairs(data.fxFavorites) do
						if isScoreFx(fxId) and not S.realOwned[fxId] then
							S.fakeFxFavorites[fxId] = true
						end
					end
				end
			end
		end
	end)
end

----------------------------------------------------------------
-- Terapkan state lokal ke controller (yang dibaca UI)
----------------------------------------------------------------
local function restoreAssetPatch()
	if S.patchedAssetId then
		local item = ContentItem:Get(S.patchedAssetId)
		if item and S.patchedAssetOriginal ~= nil then
			item.Asset = S.patchedAssetOriginal
		end
		S.patchedAssetId = nil
		S.patchedAssetOriginal = nil
	end
end

local function applyAssetPatch()
	restoreAssetPatch()
	if not S.fakeEquipped then
		return
	end
	local realId = S.serverEquipped.Ball or "ClassicBall"
	if realId == S.fakeEquipped then
		return
	end
	local realItem = ContentItem:Get(realId)
	local fakeItem = ContentItem:Get(S.fakeEquipped)
	if realItem and fakeItem and fakeItem.Asset then
		S.patchedAssetOriginal = realItem.Asset
		S.patchedAssetId = realId
		realItem.Asset = fakeItem.Asset
	end
end

-- Perbandingan dangkal untuk menjaga Value Fusion: :set hanya
-- bila isi benar-benar berubah, supaya UI tidak membangun ulang
-- (dan ikon tidak tampak memuat ulang) tanpa perlu.
local function shallowSame(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in pairs(a) do
		if b[k] ~= v then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function applyEquipped()
	local merged = table.clone(S.serverEquipped)
	if SuiteActive.Ball and not S.extremeFast and S.fakeEquipped then
		merged.Ball = S.fakeEquipped
	end
	if SuiteActive.Jersey and not S.extremeFast and S.fakeJersey then
		merged.Jersey = S.fakeJersey
	end
	if SuiteActive.PlayerCard and not S.extremeFast and S.fakeCard then
		merged.PlayerCard = S.fakeCard
	end
	if SuiteActive.ScoreEffect and not S.extremeFast and S.fakeScoreFx then
		merged.ScoreEffect = S.fakeScoreFx
	end
	if not shallowSame(InventoryController.Equipped:get(), merged) then
		InventoryController.Equipped:set(merged)
	end
	if SuiteActive.Ball then
		if S.extremeFast then
			restoreAssetPatch()
		else
			applyAssetPatch()
		end
		if FeatureAPI.scanWeldedBalls then FeatureAPI.scanWeldedBalls() end
	end
end

-- Favorit yang dibaca UI (bintang di sel kartu + label tombol
-- FAVORITE/UNFAVORITE) berasal dari Value Favorited milik
-- InventoryController -- gabungan favorit server + favorit kartu
-- lokal kita:
local function applyFavorites()
	if not InventoryController.Favorited then
		return
	end
	pcall(function()
		local merged = table.clone(S.serverFavorited)
		if SuiteActive.PlayerCard and not S.extremeFast then
			for id in pairs(S.fakeCardFavorites) do
				merged[id] = true
			end
		end
		if SuiteActive.ScoreEffect and not S.extremeFast then
			for id in pairs(S.fakeFxFavorites) do
				merged[id] = true
			end
		end
		if not shallowSame(InventoryController.Favorited:get(), merged) then
			InventoryController.Favorited:set(merged)
		end
	end)
end

local function injectInventory()
	-- Item kategori AKTIF tampil di grid: buildEntries membaca
	-- Inventory Value. MENAMBAH saja: clone dulu, isi kunci yang
	-- belum ada. PENTING: Value hanya di-:set bila isinya BENAR-
	-- BENAR berubah -- :set dengan tabel baru (walau isinya sama)
	-- membuat Fusion membangun ulang semua halaman grid, sel-sel
	-- VirtualGrid terikat ulang, dan ikon tampak "loading" lagi
	-- setiap kali layar dibuka.
	local activeLists = {}
	if SuiteActive.Ball then table.insert(activeLists, ALL_BALL_IDS) end
	if SuiteActive.Jersey then table.insert(activeLists, ALL_JERSEY_IDS) end
	if SuiteActive.Emote then table.insert(activeLists, ALL_EMOTE_IDS) end
	if SuiteActive.PlayerCard then table.insert(activeLists, ALL_CARD_IDS) end
	if SuiteActive.ScoreEffect then table.insert(activeLists, ALL_FX_IDS) end
	local merged = table.clone(InventoryController.Inventory:get() or {})
	local changed = false
	for _, list in ipairs(activeLists) do
		for _, id in ipairs(list) do
			if S.extremeFast then
				-- Mode Extreme AKTIF: item palsu DICABUT dari
				-- Value inventaris (yang asli dari server --
				-- ada di realOwned -- tidak disentuh).
				if merged[id] and not S.realOwned[id] then
					merged[id] = nil
					changed = true
				end
			elseif not merged[id] or merged[id] <= 0 then
				merged[id] = 1
				changed = true
			end
		end
	end
	if changed then
		InventoryController.Inventory:set(merged)
	end
	-- Panel info membaca ItemCount untuk jumlah kepemilikan.
	if InventoryController.ItemCount then
		local counts = table.clone(InventoryController.ItemCount:get() or {})
		local countsChanged = false
		for _, list in ipairs(activeLists) do
			for _, id in ipairs(list) do
				if S.extremeFast then
					if counts[id] and not S.realOwned[id] then
						counts[id] = nil
						countsChanged = true
					end
				elseif not counts[id] then
					counts[id] = 1
					countsChanged = true
				end
			end
		end
		if countsChanged then
			InventoryController.ItemCount:set(counts)
		end
	end
	-- Daftar di layar Jersey Preview membaca Value Inventory milik
	-- JerseyPreviewController. Normalnya itu objek yang SAMA dengan
	-- milik InventoryController; bila ternyata beda, suntik juga ke
	-- sana supaya gembok "tidak dimiliki" di daftar preview hilang.
	if not S.extremeFast and SuiteActive.Jersey and JerseyPreviewController and JerseyPreviewController.Inventory
		and JerseyPreviewController.Inventory ~= InventoryController.Inventory then
		local pMerged = table.clone(JerseyPreviewController.Inventory:get() or {})
		local pChanged = false
		for _, id in ipairs(ALL_JERSEY_IDS) do
			if not pMerged[id] or pMerged[id] <= 0 then
				pMerged[id] = 1
				pChanged = true
			end
		end
		if pChanged then
			JerseyPreviewController.Inventory:set(pMerged)
		end
	end
	-- Sama untuk layar Score FX Preview: baris-barisnya membaca
	-- Value Inventory milik ScoreEffectPreviewController (gembok
	-- tampil bila id tidak ada di sana). Suntik juga bila objeknya
	-- ternyata berbeda.
	if not S.extremeFast and SuiteActive.ScoreEffect and ScoreEffectPreviewController and ScoreEffectPreviewController.Inventory
		and ScoreEffectPreviewController.Inventory ~= InventoryController.Inventory then
		local fMerged = table.clone(ScoreEffectPreviewController.Inventory:get() or {})
		local fChanged = false
		for _, id in ipairs(ALL_FX_IDS) do
			if not fMerged[id] or fMerged[id] <= 0 then
				fMerged[id] = 1
				fChanged = true
			end
		end
		if fChanged then
			ScoreEffectPreviewController.Inventory:set(fMerged)
		end
	end
end

----------------------------------------------------------------
-- Jersey palsu di karakter sendiri. Server yang memasang jersey
-- asli ke karakter (JerseyService); di layar ini kita pasang ulang
-- secara lokal memakai tool resmi game dengan props RESMI (nama /
-- nomor style + varian tim) yang diambil dari JerseyService --
-- hanya Id-nya yang diganti ke jersey palsu.
----------------------------------------------------------------
local jerseyPropsCache = nil -- {Name=, Number=, TeamName=}
local jerseySeq = 0 -- nomor urut permintaan pasang; yang terbaru menang
local lastJerseyApply = 0

local function showSpoofAlert(displayName, body, onConfirm)
	if PromptController and PromptController.Open then
		local ok = pcall(function()
			PromptController:Open({
				Header = "Warning -- " .. displayName,
				Body = body,
				Option1 = "Equip Anyway",
				Option2 = "Cancel",
				Callback1 = onConfirm,
			})
		end)
		if ok then
			return
		end
	end
	-- PromptController tidak tersedia: jangan menghalangi equip.
	onConfirm()
end

----------------------------------------------------------------
-- Bungkus fungsi (hanya sekali; jalan ulang cukup menerapkan ulang)
----------------------------------------------------------------
local function resolvedPromise(...)
	local values = table.pack(...)
	local p = {}
	function p:expect()
		return table.unpack(values, 1, values.n)
	end
	function p:andThen(fn)
		if fn then
			fn(table.unpack(values, 1, values.n))
		end
		return p
	end
	function p:catch()
		return p
	end
	return p
end

-- Pengawatan event bersama: alat yang DISEDIAKAN file ini,
-- dipasang oleh modul fitur dari init-nya (guard di dalamnya
-- membuatnya terpasang sekali saja walau dipanggil banyak
-- modul). Dulu dipasang langsung oleh initFeatureShared.
local function installSuiteWiring()
	if not S.installedShared then
		S.installedShared = true
	-- Ikuti perubahan server: terapkan ulang lapisan lokal di atasnya.
	DataService.ProfileUpdated:Connect(function(key, value)
		if key == "Equipped" and type(value) == "table" then
			-- Slot emote yang baru saja ditulis server (equip asli)
			-- mengalahkan slot palsu di indeks yang sama.
			if type(value.Emotes) == "table" then
				local prevEmotes = S.serverEquipped.Emotes or {}
				local cleared = false
				for index, emoteId in pairs(value.Emotes) do
					if prevEmotes[index] ~= emoteId and S.fakeEmotes[index] then
						S.fakeEmotes[index] = nil
						cleared = true
					end
				end
				if cleared then
					saveLocal()
				end
			end
			S.serverEquipped = value
			-- Gema equip dari server sudah tiba: pemasangan pembawa
			-- yang sedang berjalan dianggap selesai.
			S.fxCarrierInFlight = false
			if S.fakeEquipped and value.Ball == S.fakeEquipped and S.realOwned[S.fakeEquipped] then
				S.fakeEquipped = nil
				saveLocal()
			end
			if S.fakeJersey and value.Jersey == S.fakeJersey and S.realOwned[S.fakeJersey] then
				S.fakeJersey = nil
				saveLocal()
			end
			if S.fakeCard and value.PlayerCard == S.fakeCard and S.realOwned[S.fakeCard] then
				S.fakeCard = nil
				saveLocal()
			end
			if S.fakeScoreFx and value.ScoreEffect == S.fakeScoreFx and S.realOwned[S.fakeScoreFx]
				and S.fakeScoreFx ~= RANDOM_FX_ID then
				-- Random Favorite dikecualikan: lapis lokalnya
				-- memang hidup berdampingan dengan equip asli.
				S.fakeScoreFx = nil
				saveLocal()
			end
			-- Lapis palsu aktif tapi slot server kosong / Random:
			-- pasang pembawa (ensureFxCarrier menjaga dirinya
			-- sendiri dari klik user dan pemasangan ganda). Slot
			-- Random Favorite ASLI pun termasuk: server tidak
			-- menyiarkan apa pun untuknya bila favorit asli kosong.
			if S.fakeScoreFx
				and (not value.ScoreEffect or value.ScoreEffect == RANDOM_FX_ID) then
				if FeatureAPI.ensureFxCarrier then task.defer(FeatureAPI.ensureFxCarrier) end
			end
		elseif key == "Favorited" and type(value) == "table" then
			S.serverFavorited = value
			applyFavorites()
		elseif key == "Settings" then
			-- Sinkron Settings dari server menimpa Value milik
			-- InterfaceController: gabung ulang kunci saklar kita.
			if FeatureAPI.applyVLSettings then FeatureAPI.applyVLSettings() end
		end
		-- Lapisan equip lokal diterapkan ulang pada SETIAP kunci
		-- ProfileUpdated, bukan hanya "Equipped": sinkron profil
		-- dari server bisa menimpa Value Equipped milik controller
		-- dengan tabel mentah lewat jalur mana pun, dan label
		-- EQUIPPED di inventory membaca Value itu. Kedua fungsi ini
		-- menjaga dirinya sendiri (murah bila tidak ada perubahan).
		applyEquipped()
		if FeatureAPI.applyEmotes then FeatureAPI.applyEmotes() end
	end)
	-- Penjaga tampilan equip: periksa berkala apakah Value
	-- Equipped yang dibaca UI masih mencerminkan lapisan palsu;
	-- bila menyimpang (ditimpa binding game di luar jalur yang
	-- terpantau), terapkan ulang. Ini yang menjaga teks EQUIPPED
	-- tidak "terlepas" sendiri di inventory.
	task.spawn(function()
		while true do
			task.wait(0.5)
			pcall(function()
				local current = InventoryController.Equipped
					and InventoryController.Equipped:get()
				if type(current) == "table" then
					local drifted = (S.fakeEquipped and current.Ball ~= S.fakeEquipped)
						or (S.fakeJersey and current.Jersey ~= S.fakeJersey)
						or (S.fakeCard and current.PlayerCard ~= S.fakeCard)
						or (S.fakeScoreFx and current.ScoreEffect ~= S.fakeScoreFx)
					if drifted then
						applyEquipped()
					end
				end
			end)
		end
	end)
	InventoryService.InventoryChanged:Connect(function(id, count)
		if count and count > 0 then
			S.realOwned[id] = true
		else
			S.realOwned[id] = nil
		end
	end)
	if CountService and CountService.ItemCount and CountService.ItemCount.Observe then
		pcall(function()
			CountService.ItemCount:Observe(function()
				task.defer(injectInventory)
			end)
		end)
	end
	end
end

local function initFeatureShared()
	local t0 = os.clock()
	-- Tunggu controller & service siap (KnitStart selesai). GetController
	-- bisa error sebelum Knit hidup, jadi dibungkus pcall; timeout 90
	-- detik agar bagian lain tidak ikut tertahan selamanya.
	local deadline = os.clock() + 90
	repeat
		pcall(function()
			InventoryController = Knit.GetController("InventoryController")
			InventoryService = Knit.GetService("InventoryService")
			DataService = Knit.GetService("DataService")
			CountService = Knit.GetService("CountService")
			JerseyService = Knit.GetService("JerseyService")
			JerseyPreviewController = Knit.GetController("JerseyPreviewController")
			EmoteController = Knit.GetController("EmoteController")
			PromptController = Knit.GetController("PromptController")
			AnimationController = Knit.GetController("AnimationController")
			PlayerCardController = Knit.GetController("PlayerCardController")
			PlayerCardService = Knit.GetService("PlayerCardService")
			SettingsService = Knit.GetService("SettingsService")
			SettingsController = Knit.GetController("SettingsController")
			InterfaceController = Knit.GetController("InterfaceController")
			EffectController = Knit.GetController("EffectController")
			ScoreEffectPreviewController = Knit.GetController("ScoreEffectPreviewController")
		end)
		task.wait(0.1)
	until (InventoryController and InventoryController.Equipped and InventoryController.Inventory
		and InventoryService and DataService) or os.clock() > deadline
	if not (InventoryController and InventoryController.Equipped and InventoryController.Inventory
		and InventoryService and DataService) then
		warn("[VL Suite] feature-shared not ready after 90 seconds; dependent modules skipped.")
		return
	end
	-- Tunggu state awal dari server benar-benar ter-seed ke controller.
	-- Field controller terisi satu-satu secara async (Favorited bisa
	-- masih nil saat Equipped/Inventory sudah ada), jadi ceknya wajib
	-- nil-safe -- versi sebelumnya crash di sini ("index nil 'get'").
	local function valueIsTable(v)
		if v == nil then
			return false
		end
		local ok, val = pcall(function()
			return v:get()
		end)
		return ok and typeof(val) == "table"
	end
	local seedDeadline = os.clock() + 30
	while os.clock() < seedDeadline do
		local seeded = valueIsTable(InventoryController.Equipped)
			and valueIsTable(InventoryController.Inventory)
			and valueIsTable(InventoryController.Favorited)
		if seeded then
			break
		end
		task.wait(0.1)
	end
	refreshServerTruth()
	-- Bridge untuk bundle otomatisasi (auto farm + auto spin):
	-- file terpisah yang di-obfuscate dan dimuat saat runtime,
	-- jadi ia tidak bisa memakai local chunk suite. Semua yang
	-- ia butuhkan diterbitkan di sini, sekali, lewat getgenv.
	getgenv().VLBridge = {
		S = S,
		saveLocal = saveLocal,
		loadLocal = loadLocal,
		awaitFeatureShared = awaitFeatureShared,
		FeatureAPI = FeatureAPI,
		Knit = Knit,
		ContentItem = ContentItem,
		player = player,
		RS = RS,
		ReplicatedFirst = ReplicatedFirst,
		CollectionService = CollectionService,
		SETTING_MEMBER_FARM = SETTING_MEMBER_FARM,
		SETTING_MEMBER_SPIN = SETTING_MEMBER_SPIN,
	}
	FeatureSharedReady = true
	print(("[VL Suite] feature-shared ready in %.2fs"):format(os.clock() - t0))
	suiteModuleLoaded("feature-shared")
end

suiteExpectModule("feature-shared")
task.spawn(initFeatureShared)
