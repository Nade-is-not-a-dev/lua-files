----------------------------------------------------------------
-- modules/score-fx.lua -- Modul fitur: Score FX Spoof
--
-- Resolver efek palsu / RANDOM FAVORITES, pembawa (carrier),
-- suara poin, bungkus EffectController.PlayScoreEffect, dan
-- scrub gembok layar Score FX Preview. Kode dari Bagian A
-- monolit apa adanya; kerangkanya mengikuti arsitektur suite:
-- menunggu feature-shared, memakai alatnya sendiri, dan
-- mendaftarkan kategori "ScoreEffect" agar alat bersama
-- hanya menyentuh kategori ini atas namanya.
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
	if S.extremeFast then
		return
	end
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
		warn("[VL Suite] No owned Score FX available as carrier -- the spoof cannot trigger without one genuine effect owned.")
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
		-- Sapuan DIBAGI per bingkai: versi sinkron penuhnya
		-- membekukan game beberapa detik (pohon daftar ini
		-- besar) -- itulah freeze di tengah playback preview
		-- yang dilaporkan user 2026-11-08 (awalan efek muncul,
		-- freeze, lalu lanjut). 20 baris per napas.
		local scrubbed = 0
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
				scrubbed += 1
				if scrubbed % 20 == 0 then
					task.wait()
				end
			end
		end
	end)
end

local function initScoreFx()
	local t0 = os.clock()
	if not awaitFeatureShared(90) then
		warn("[VL Suite] score-fx skipped: feature-shared not ready.")
		return
	end
	local tShared = os.clock()
	FeatureAPI.ensureFxCarrier = ensureFxCarrier
	-- Pakai alat feature-shared sendiri: muat state lokal
	-- (fakeScoreFx + favorit FX dari simpanan), suntikkan
	-- kategori
	-- ScoreEffect ke inventory, terapkan lapisan equip FX
	-- dan gabungan favorit FX.
	loadLocal()
	injectInventory()
	applyEquipped()
	applyFavorites()
	if not S.installedFx then
		S.installedFx = true
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
			if S.extremeFast then
				return originalPlayScoreEffect(self, data)
			end
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
	-- Hal yang sama untuk layar Score FX Preview.
	if ScoreEffectPreviewController and ScoreEffectPreviewController.Open then
		local originalFxPreviewOpen = ScoreEffectPreviewController.Open
		ScoreEffectPreviewController.Open = function(self, id, ...)
			injectInventory()
			local result = originalFxPreviewOpen(self, id, ...)
			-- Scrub gembok TIDAK lagi dipanggil dari sini:
			-- versi sinkronnya membekukan preview di tengah
			-- efek, versi per-bingkainya (v0.13.2) malah
			-- membuat preview patah-patah sejak awal --
			-- keduanya dilaporkan user 2026-11-08. Playback
			-- preview sekarang bersih; apakah gembok di
			-- daftar preview muncul lagi tanpa scrub, dicek
			-- dari laporan user (fungsi scrubFxPreviewLocks
			-- dipertahankan untuk pemicu lain bila perlu).
			return result
		end
	end
	end
	if S.fakeScoreFx then
		task.defer(ensureFxCarrier)
	end
	-- DULU di sini ada task.delay(3, scrubFxPreviewLocks):
	-- scrub itu menyapu seluruh pohon daftar EffectPreview
	-- secara sinkron ~3 detik setelah load dan diduga kuat
	-- penyebab freeze ~5 detik setelah suite selesai dimuat
	-- (dilaporkan user 2026-11-08). Dihapus: membuka layar
	-- preview sendiri sudah memicu scrub yang sama lewat
	-- bungkus Open di atas, jadi scrub terjadwal ini mubazir.
	print(("[VL Suite] score-fx ready in %.2fs (shared wait %.2fs)"):format(os.clock() - t0, tShared - t0))
	suiteModuleLoaded("score-fx")
end

suiteActivateFeature("ScoreEffect")
suiteExpectModule("score-fx")
task.spawn(initScoreFx)
