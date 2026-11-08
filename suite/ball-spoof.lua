----------------------------------------------------------------
-- suite/ball-spoof.lua -- Modul fitur 1: Ball Spoof (Bagian A)
--
-- Isi: spoof bola (serve/rally/replay/ghost), jersey, emote +
-- prop lokal, player card, Score FX (termasuk carrier), grup
-- VL Settings, dan baris Settings untuk Avatar Lite (tombol
-- Open-nya aktif hanya bila modul avatar terpasang).
--
-- Diekstrak apa adanya dari vl-ball-spoof.lua monolit
-- (Bagian A), dengan dua penyesuaian:
-- 1) baris progres overlay (setLoading/LoadingState) dibuang
--    karena overlay sudah dihapus dari core;
-- 2) peluncuran task.spawn(initBallSpoof) dipindah ke akhir
--    file ini (di monolit diluncurkan dari blok akhir file).
----------------------------------------------------------------
----------------------------------------------------------------
-- BAGIAN A: Ball Spoof
----------------------------------------------------------------
local function initBallSpoof()
	-- Tunggu controller & service siap (KnitStart selesai). GetController
	-- bisa error sebelum Knit hidup, jadi dibungkus pcall; timeout 90
	-- detik agar bagian lain tidak ikut tertahan selamanya.
	local InventoryController, InventoryService, DataService, CountService, JerseyService, JerseyPreviewController, EmoteController, PromptController, AnimationController, PlayerCardController, PlayerCardService, SettingsService, SettingsController, InterfaceController, EffectController, ScoreEffectPreviewController
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
		task.wait(0.25)
	until (InventoryController and InventoryController.Equipped and InventoryController.Inventory
		and InventoryService and DataService) or os.clock() > deadline
	if not (InventoryController and InventoryController.Equipped and InventoryController.Inventory
		and InventoryService and DataService) then
		warn("[VLBallSpoof] Controllers/services not ready after 90 seconds; ball spoof part skipped.")
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
		task.wait(0.25)
	end

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
		settings = { WorldAffectingScoreFX = true }, -- saklar bagian Settings tambahan
		settingsSectionBuilt = false,
		settingsGroupRegistered = false,
		avatarSettingsRowBuilt = false,
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

-- Segarkan kebenaran server dari DataService (bukan dari state UI).
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

local function loadLocal()
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

----------------------------------------------------------------
-- Bola serve di tangan (tag "WeldedBall", dibuat server)
----------------------------------------------------------------
local function weldedAnchor(ball)
	if ball:IsA("BasePart") then
		return ball
	end
	if ball:IsA("Model") then
		if ball.PrimaryPart then
			return ball.PrimaryPart
		end
		for _, desc in ipairs(ball:GetDescendants()) do
			if desc:IsA("BasePart") then
				return desc
			end
		end
	end
	return nil
end

local function weldedBelongsToLocal(ball)
	local character = player.Character
	if not character then
		return false
	end
	if ball:IsDescendantOf(character) then
		return true
	end
	-- Mungkin di Workspace tapi ter-weld ke tangan karakter.
	for _, desc in ipairs(ball:GetDescendants()) do
		if desc:IsA("WeldConstraint") or desc:IsA("Weld") or desc:IsA("Motor6D") then
			if (desc.Part0 and desc.Part0:IsDescendantOf(character))
				or (desc.Part1 and desc.Part1:IsDescendantOf(character)) then
				return true
			end
		end
	end
	return false
end

local function isEffectInstance(inst)
	return inst:IsA("Trail") or inst:IsA("ParticleEmitter") or inst:IsA("Beam")
		or inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles")
		or inst:IsA("Light") or inst:IsA("BillboardGui") or inst:IsA("SurfaceGui")
end

local function hideInstance(inst)
	if inst:IsA("BasePart") then
		if not inst:GetAttribute("VLSpoofHidden") then
			inst:SetAttribute("VLSpoofOrigTransparency", inst.Transparency)
			inst:SetAttribute("VLSpoofHidden", true)
		end
		inst.Transparency = 1
	elseif isEffectInstance(inst) then
		if not inst:GetAttribute("VLSpoofHidden") then
			inst:SetAttribute("VLSpoofOrigEnabled", inst.Enabled)
			inst:SetAttribute("VLSpoofHidden", true)
		end
		inst.Enabled = false
	end
end

local function restoreInstance(inst)
	if not inst:GetAttribute("VLSpoofHidden") then
		return
	end
	if inst:IsA("BasePart") then
		inst.Transparency = inst:GetAttribute("VLSpoofOrigTransparency") or 0
		inst:SetAttribute("VLSpoofOrigTransparency", nil)
	elseif isEffectInstance(inst) then
		local orig = inst:GetAttribute("VLSpoofOrigEnabled")
		if orig ~= nil then
			inst.Enabled = orig
		end
		inst:SetAttribute("VLSpoofOrigEnabled", nil)
	end
	inst:SetAttribute("VLSpoofHidden", nil)
end

local function unspoofWelded(ball)
	restoreInstance(ball)
	for _, desc in ipairs(ball:GetDescendants()) do
		restoreInstance(desc)
	end
	for _, child in ipairs(ball:GetChildren()) do
		if child:GetAttribute("VLSpoofClone") then
			child:Destroy()
		end
	end
end

local function spoofWelded(ball)
	if not S.fakeEquipped then
		return
	end
	local anchor = weldedAnchor(ball)
	if not anchor then
		return
	end
	unspoofWelded(ball) -- mulai dari keadaan bersih
	local asset = RS.Assets.Ball:FindFirstChild(S.fakeEquipped)
	if not asset then
		return
	end
	-- Sembunyikan visual asli (struktur & weld server tidak disentuh):
	-- part transparan + semua efek (trail/partikel/dll) dimatikan.
	hideInstance(ball)
	for _, desc in ipairs(ball:GetDescendants()) do
		hideInstance(desc)
	end
	-- Clone skin palsu dan tempel ke jangkar yang sama.
	local clone = asset:Clone()
	clone:SetAttribute("VLSpoofClone", true)
	pcall(function()
		local State = require(RS.Common.State)
		local mult = State.get(player, State.Id.Modifier, "BallSizeMultiplier", 1)
		if type(mult) == "number" and mult ~= 1 then
			if clone:IsA("Model") then
				clone:ScaleTo(clone:GetScale() * mult)
			end
		end
	end)
	if clone:IsA("Model") then
		clone:PivotTo(anchor.CFrame)
	elseif clone:IsA("BasePart") then
		clone.CFrame = anchor.CFrame
	end
	clone.Parent = ball
	local root
	if clone:IsA("BasePart") then
		root = clone
	elseif clone.PrimaryPart then
		root = clone.PrimaryPart
	else
		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("BasePart") then
				root = desc
				break
			end
		end
	end
	if not root then
		clone:Destroy()
		unspoofWelded(ball)
		return
	end
	-- Semua part clone di-weld ke root, root di-weld ke jangkar:
	-- clone bergerak kaku mengikuti tangan.
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = false
			desc.CanCollide = false
			desc.CanQuery = false
			desc.CanTouch = false
			desc.Massless = true
			desc.CastShadow = false
			if desc ~= root then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = desc
				weld.Part1 = root
				weld.Parent = desc
			end
		end
	end
	if root ~= anchor then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = anchor
		weld.Parent = root
	end
end

local function scanWeldedBalls()
	for _, ball in ipairs(CollectionService:GetTagged("WeldedBall")) do
		if weldedBelongsToLocal(ball) then
			if S.fakeEquipped then
				spoofWelded(ball)
			else
				unspoofWelded(ball)
			end
		end
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
	if S.fakeEquipped then
		merged.Ball = S.fakeEquipped
	end
	if S.fakeJersey then
		merged.Jersey = S.fakeJersey
	end
	if S.fakeCard then
		merged.PlayerCard = S.fakeCard
	end
	if S.fakeScoreFx then
		merged.ScoreEffect = S.fakeScoreFx
	end
	if not shallowSame(InventoryController.Equipped:get(), merged) then
		InventoryController.Equipped:set(merged)
	end
	applyAssetPatch()
	scanWeldedBalls()
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
		for id in pairs(S.fakeCardFavorites) do
			merged[id] = true
		end
		for id in pairs(S.fakeFxFavorites) do
			merged[id] = true
		end
		if not shallowSame(InventoryController.Favorited:get(), merged) then
			InventoryController.Favorited:set(merged)
		end
	end)
end

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

local function injectInventory()
	-- Semua bola + jersey tampil di grid: buildEntries membaca
	-- Inventory Value. MENAMBAH saja: clone dulu, isi kunci yang
	-- belum ada. PENTING: Value hanya di-:set bila isinya BENAR-
	-- BENAR berubah -- :set dengan tabel baru (walau isinya sama)
	-- membuat Fusion membangun ulang semua halaman grid, sel-sel
	-- VirtualGrid terikat ulang, dan ikon tampak "loading" lagi
	-- setiap kali layar dibuka.
	local merged = table.clone(InventoryController.Inventory:get() or {})
	local changed = false
	for _, list in ipairs({ ALL_BALL_IDS, ALL_JERSEY_IDS, ALL_EMOTE_IDS, ALL_CARD_IDS, ALL_FX_IDS }) do
		for _, id in ipairs(list) do
			if not merged[id] or merged[id] <= 0 then
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
		for _, list in ipairs({ ALL_BALL_IDS, ALL_JERSEY_IDS, ALL_EMOTE_IDS, ALL_CARD_IDS, ALL_FX_IDS }) do
			for _, id in ipairs(list) do
				if not counts[id] then
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
	if JerseyPreviewController and JerseyPreviewController.Inventory
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
	if ScoreEffectPreviewController and ScoreEffectPreviewController.Inventory
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
-- Cek pemilik bola (siapa yang serve)
----------------------------------------------------------------
local function serverNameNow()
	-- Mode Training dicek PALING DULU: atribut ServedByPlayer bisa
	-- berisi nama basi / bukan pemilik bola latihan, dan game sendiri
	-- (kode HeadBall) menganggap server di Training = pemain lokal.
	local ok, current = pcall(function()
		return Gamemode.Current()
	end)
	if ok and current == Gamemode.Types.Training then
		return player.Name
	end
	local name = RS:GetAttribute("ServedByPlayer")
	if type(name) == "string" and name ~= "" then
		return name
	end
	return nil
end

local function skinIsMine(skinId)
	return skinId ~= nil and skinId == (S.serverEquipped.Ball or "ClassicBall")
end

local function recordServe(skinId)
	table.insert(S.serveLog, {
		t = os.clock(),
		server = serverNameNow(),
		skin = skinId,
	})
	while #S.serveLog > 16 do
		table.remove(S.serveLog, 1)
	end
end

local ArchiveModule
local function replayBelongsToMe(clip, skinName)
	-- Cocokkan clip ke entri Archive untuk mendapatkan PointTime.
	local pointTime
	if not ArchiveModule then
		pcall(function()
			ArchiveModule = require(ReplicatedFirst:WaitForChild("Controllers"):WaitForChild("ReplayController"):WaitForChild("Archive"))
		end)
	end
	if ArchiveModule and ArchiveModule._entries then
		pcall(function()
			for _, entry in pairs(ArchiveModule._entries) do
				if entry.Clip == clip then
					pointTime = entry.PointTime
					break
				end
			end
		end)
	end
	if pointTime then
		-- Serve terakhir pada / tepat sebelum titik poin = serve yang
		-- memulai rally yang sedang diputar ulang ini.
		local best
		for _, e in ipairs(S.serveLog) do
			if e.t <= pointTime + 1 and (not best or e.t > best.t) then
				best = e
			end
		end
		if best then
			if best.server then
				return best.server == player.Name
			end
			return skinIsMine(best.skin)
		end
	end
	-- Arsip / log tidak ketemu: fallback ke pencocokan skin.
	return skinIsMine(skinName)
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

local ALERT_BALL_SURFACE = "This ball's surface effect is normally sent by the server. The script recreates it locally: only you see it, and only on hard impacts. Equip anyway?"

local ALERT_EMOTE_PROP = "This emote's prop is normally run by the server. The script runs it locally: only you see the prop; others only see the animation. Equip anyway?"

local ALERT_FX_WORLD = "This score effect physically affects players. The spoof shows only on your screen and only affects your own character. Equip anyway?"

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

if not S.installed then
	S.installed = true

	-- Sintesis SurfaceHit lokal untuk bola spoof (pemicu OnHitBindable).
	-- Fisika bola lokal game (Common.Physics.calculateBallPhysics --
	-- kode yang sama dengan yang jalan di server) mendeteksi tiap
	-- sentuhan bola ke permukaan dan menembakkannya lewat
	-- ball.OnHitBindable, sinyal yang tidak didengarkan siapa pun di
	-- client. Untuk bola asli, server mengirim event SurfaceHit-nya
	-- sendiri (tergate BallLib.hasSurfaceHit atas item asli); untuk
	-- bola spoof event itu tidak pernah datang. Jadi OnHitBindable
	-- dipakai sebagai pemicu lokal: posisi + normal permukaan dicari
	-- dengan spherecast pendek, lalu BallController:SurfaceHit
	-- dipanggil -- render efeknya sesudah itu 100% jalur asli game.
	local BallControllerLazy
	local function getBallController()
		if not BallControllerLazy then
			pcall(function()
				BallControllerLazy = Knit.GetController("BallController")
			end)
		end
		return BallControllerLazy
	end

	local RunService = game:GetService("RunService")
	local GameConfig = require(RS:WaitForChild("Configuration"):WaitForChild("Game"))
	local StateModule = require(RS:WaitForChild("Common"):WaitForChild("State"))

	local function armSplatSynth(ballObj)
		if not (ballObj and ballObj.OnHitBindable) then
			return
		end
		-- Kecepatan MASUK (sebelum fisika frame ini memantulkannya):
		-- disampel tiap akhir frame; saat OnHit menembak di frame
		-- berikutnya, inilah arah datang bola yang sebenarnya.
		local prevVel = nil
		ballObj.maid:GiveTask(RunService.RenderStepped:Connect(function()
			prevVel = ballObj.Velocity
		end))
		local lastSplat = 0
		local lastSplatPos = nil
		ballObj.OnHitBindable:Connect(function(hitInstance)
			if not S.fakeEquipped or not ballObj.__vlSpoofed then
				return
			end
			local item = ballObj.Item
			local handler = item and item.Metadata and item.Metadata.Handler
			if not (handler and handler.SurfaceHit) then
				return
			end
			local now = os.clock()
			if now - lastSplat < 0.08 then
				return
			end
			lastSplat = now
			-- Gerbang benturan: bola yang menggelinding / diam di
			-- tanah menembakkan kontak fisika terus-menerus (log tes
			-- 2026-11-07: sampai ~12x/detik) — itu bukan "bekas
			-- jatuh" yang dimaksud efeknya, dan jadi spam.
			local inVel = prevVel or ballObj.Velocity or Vector3.zero
			if inVel.Magnitude < SPLAT_MIN_IMPACT then
				return
			end
			local bc = getBallController()
			if not bc then
				return
			end
			local serverId = ballObj.Ball and ballObj.Ball:GetAttribute("ServerId")
			if serverId == nil then
				for k, v in pairs(bc.ActiveBalls or {}) do
					if v == ballObj then
						serverId = k
						break
					end
				end
			end
			if serverId == nil then
				return
			end
			-- Tiru spherecast fisika game sendiri: asal di posisi
			-- PrimaryPart, radius = radius fisika konfigurasi (BUKAN
			-- ukuran visual model), arah = kecepatan masuk, jarak =
			-- tempuh satu-dua frame. Hasil Position + Normal-nya
			-- persis jenis data yang dikirim server untuk bola asli.
			local model = ballObj.Ball
			local origin = (model.PrimaryPart and model.PrimaryPart.Position)
				or model:GetPivot().Position
			local mult = 1
			pcall(function()
				mult = StateModule.get(player, StateModule.Id.Modifier, "BallSizeMultiplier", 1)
			end)
			local radius = GameConfig.Physics.Radius * mult
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			local exclude = { model }
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr.Character then
					table.insert(exclude, plr.Character)
				end
			end
			for _, tagged in ipairs(CollectionService:GetTagged("Ball")) do
				table.insert(exclude, tagged)
			end
			params.FilterDescendantsInstances = exclude
			local hit
			if inVel.Magnitude > 1 then
				local dir = inVel.Unit
				-- Mundur cukup jauh sebelum permukaan: di frame OnHit,
				-- model bola bisa sudah menembus permukaan (penetration
				-- makin dalam makin kencang bolanya) dan cast yang mulai
				-- dari dalam part selalu meleset.
				local backoff = radius + inVel.Magnitude * 0.05 + 0.75
				local reach = backoff + radius * 2 + inVel.Magnitude * 0.06 + 1
				hit = workspace:Spherecast(origin - dir * backoff, radius, dir * reach, params)
			end
			if not hit then
				hit = workspace:Raycast(
					origin + Vector3.new(0, radius, 0),
					Vector3.new(0, -(radius * 2 + 4), 0),
					params)
			end
			if not hit and hitInstance and hitInstance:IsA("BasePart")
				and math.abs(hitInstance.CFrame.UpVector.Y) > 0.7 then
				-- Cadangan terakhir khusus lantai datar: permukaan atas
				-- part yang ditabrak fisika game sendiri, di XZ bola.
				local topY = hitInstance.Position.Y + hitInstance.Size.Y / 2
				local floorPos = Vector3.new(origin.X, topY + 0.02, origin.Z)
				if lastSplatPos and (floorPos - lastSplatPos).Magnitude < SPLAT_MIN_SPACING then
					return
				end
				lastSplatPos = floorPos
				local okF, errF = pcall(function()
					bc:SurfaceHit(serverId, floorPos, Vector3.yAxis)
				end)
				return
			end
			if not hit then
				return
			end
			if lastSplatPos and (hit.Position - lastSplatPos).Magnitude < SPLAT_MIN_SPACING then
				return
			end
			lastSplatPos = hit.Position
			local okS, errS = pcall(function()
				bc:SurfaceHit(serverId, hit.Position, hit.Normal)
			end)
		end)
	end

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

	-- Ball.new: ganti model + Item dengan skin palsu saat spawn.
	local BallModule = require(ReplicatedFirst:WaitForChild("Controllers"):WaitForChild("BallController"):WaitForChild("Ball"))
	local AssetsBall = RS:WaitForChild("Assets"):WaitForChild("Ball")
	local originalNew = BallModule.new
	BallModule.new = function(model, cframe, velocity, itemData)
		-- Catat serve ini dulu (untuk cek pemilik di Replay nanti).
		local skinId = itemData and itemData.Id
		recordServe(skinId)
		-- Cakupan: kecuali SPOOF_RALLY_ALL, hanya ganti bola milikku --
		-- pemilik dari ServedByPlayer; bila atribut kosong, cadangan
		-- pencocokan skin.
		local server = serverNameNow()
		local inScope = SPOOF_RALLY_ALL
			or (server ~= nil and server == player.Name)
			or (server == nil and skinIsMine(skinId))
		if S.fakeEquipped and inScope then
			local asset = AssetsBall:FindFirstChild(S.fakeEquipped)
			local fakeItem = ContentItem:Get(S.fakeEquipped)
			if asset and fakeItem then
				local clone = asset:Clone()
				for _, desc in ipairs(clone:GetDescendants()) do
					if desc:IsA("BasePart") then
						desc.CastShadow = false
					end
				end
				if model then
					model:Destroy()
				end
				local result = originalNew(clone, cframe, velocity, fakeItem)
				if result then
					-- Penanda + pasang sintesis SurfaceHit (bekas slime dll).
					result.__vlSpoofed = true
					armSplatSynth(result)
				end
				return result
			end
		end
		return originalNew(model, cframe, velocity, itemData)
	end

	-- GhostBall.new: bola layar Replay, dibuat dari nama skin rekaman.
	local GhostBallModule = require(ReplicatedFirst:WaitForChild("Controllers"):WaitForChild("ReplayController"):WaitForChild("Stage"):WaitForChild("GhostBall"))
	local originalGhostNew = GhostBallModule.new
	GhostBallModule.new = function(clip, skinName, parent)
		-- Hanya spoof bila rally di replay ini dimulai dari serve-ku.
		local inScope = SPOOF_RALLY_ALL or replayBelongsToMe(clip, skinName)
		if S.fakeEquipped and inScope then
			return originalGhostNew(clip, S.fakeEquipped, parent)
		end
		return originalGhostNew(clip, skinName, parent)
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
				task.defer(ensureFxCarrier)
			end
		elseif key == "Favorited" and type(value) == "table" then
			S.serverFavorited = value
			applyFavorites()
		elseif key == "Settings" then
			-- Sinkron Settings dari server menimpa Value milik
			-- InterfaceController: gabung ulang kunci saklar kita.
			applyVLSettings()
		end
		-- Lapisan equip lokal diterapkan ulang pada SETIAP kunci
		-- ProfileUpdated, bukan hanya "Equipped": sinkron profil
		-- dari server bisa menimpa Value Equipped milik controller
		-- dengan tabel mentah lewat jalur mana pun, dan label
		-- EQUIPPED di inventory membaca Value itu. Kedua fungsi ini
		-- menjaga dirinya sendiri (murah bila tidak ada perubahan).
		applyEquipped()
		applyEmotes()
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

	-- Bola serve baru yang di-weld server ke tangan karakter.
	CollectionService:GetInstanceAddedSignal("WeldedBall"):Connect(function(ball)
		task.spawn(function()
			-- Beri waktu replikasi selesai (parent & part-partnya).
			for _ = 1, 20 do
				if not ball.Parent then
					break
				end
				if weldedAnchor(ball) and weldedBelongsToLocal(ball) then
					if S.fakeEquipped then
						spoofWelded(ball)
					end
					return
				end
				task.wait(0.1)
			end
		end)
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

	if CountService and CountService.ItemCount and CountService.ItemCount.Observe then
		pcall(function()
			CountService.ItemCount:Observe(function()
				task.defer(injectInventory)
			end)
		end)
	end

end

----------------------------------------------------------------
-- Terapkan semuanya
----------------------------------------------------------------
	loadLocal()
	injectInventory()
	applyEquipped()
	applyEmotes()
	applyFavorites()
	applyVLSettings()
	-- Pembawa Score FX: lapis palsu aktif dari sesi sebelumnya ->
	-- pastikan ada efek asli ter-equip di latar belakang. Script
	-- tidak pernah memulihkan/melepas equip server.
	if S.fakeScoreFx then
		task.defer(ensureFxCarrier)
	end
	task.spawn(buildSettingsSection)
	task.spawn(buildAvatarSettingsRow)
	-- Preview awal panel inventory mengikuti bola spoof: game
	-- menginisialisasi Selected ke bola yang ter-equip di server,
	-- jadi arahkan ke bola palsu yang aktif.
	if S.fakeEquipped and InventoryController.Selected then
		InventoryController.Selected:set(S.fakeEquipped)
	end
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
-- Peluncuran modul (lihat catatan header nomor 2).
task.spawn(initBallSpoof)
