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
		-- MODE TARIK VISUAL (permintaan user 2026-11-12): untuk
		-- efek skor PALSU berpengaruh fisik (mis. Supernova) pada
		-- poin sendiri, tarikan dibuat visual murni. Karakter asli
		-- TIDAK bergerak: constraint penggerak yang dipasang modul
		-- efek ke HRP langsung dihancurkan saat muncul, jadi data
		-- fisika yang terkirim ke server tetap diam di tempat.
		-- Yang terlihat tertarik di layar sendiri adalah KLON
		-- lokal karakter (instance lokal, tidak pernah
		-- tereplikasi) yang digeser ke titik skor meniru
		-- MaxVelocity efek asli; karakter asli disembunyikan
		-- khusus di layar sendiri lewat LocalTransparencyModifier
		-- (tidak tereplikasi). Pemain lain melihat karakter asli
		-- diam, persis seperti data server.
		local VisualPull = { active = false }
		local RunServiceVP = game:GetService("RunService")
		local MOVER_CLASSES = {
			AlignPosition = true, AlignOrientation = true,
			LinearVelocity = true, VectorForce = true,
			BodyPosition = true, BodyVelocity = true,
			BodyForce = true, BodyGyro = true,
		}
		function VisualPull.finish()
			if not VisualPull.active then
				return
			end
			VisualPull.active = false
			for _, conn in ipairs(VisualPull.conns or {}) do
				pcall(function()
					conn:Disconnect()
				end)
			end
			VisualPull.conns = nil
			if VisualPull.clone then
				pcall(function()
					VisualPull.clone:Destroy()
				end)
				VisualPull.clone = nil
			end
			for part, v in pairs(VisualPull.ltm or {}) do
				pcall(function()
					part.LocalTransparencyModifier = v
				end)
			end
			VisualPull.ltm = nil
			for gui, v in pairs(VisualPull.guis or {}) do
				pcall(function()
					gui.Enabled = v
				end)
			end
			VisualPull.guis = nil
			for em, v in pairs(VisualPull.emitters or {}) do
				pcall(function()
					em.Enabled = v
				end)
			end
			VisualPull.emitters = nil
		end
		function VisualPull.begin(origin)
			if VisualPull.active then
				return
			end
			local target
			if typeof(origin) == "Vector3" then
				target = origin
			elseif typeof(origin) == "CFrame" then
				target = origin.Position
			else
				return
			end
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if not (char and hrp and hum) then
				return
			end
			VisualPull.active = true
			VisualPull.conns = {}
			VisualPull.char = char
			VisualPull.startPos = hrp.Position
			VisualPull.target = target
			local ok = pcall(function()
				-- Klon lokal karakter pada pose saat ini.
				char.Archivable = true
				for _, d in ipairs(char:GetDescendants()) do
					pcall(function()
						d.Archivable = true
					end)
				end
				local clone = char:Clone()
				clone.Name = char.Name .. "_VisualPull"
				for _, d in ipairs(clone:GetDescendants()) do
					if d:IsA("Script") or d:IsA("LocalScript") then
						d:Destroy()
					elseif d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = false
						d.CanQuery = false
						d.CanTouch = false
					end
				end
				local cloneHum = clone:FindFirstChildOfClass("Humanoid")
				if cloneHum then
					cloneHum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
					cloneHum.HealthDisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				end
				clone.Parent = workspace
				VisualPull.clone = clone
				-- Sembunyikan karakter asli di layar sendiri saja.
				VisualPull.ltm = {}
				VisualPull.guis = {}
				VisualPull.emitters = {}
				for _, d in ipairs(char:GetDescendants()) do
					if d:IsA("BasePart") then
						VisualPull.ltm[d] = d.LocalTransparencyModifier
						d.LocalTransparencyModifier = 1
					elseif d:IsA("BillboardGui") then
						VisualPull.guis[d] = d.Enabled
						d.Enabled = false
					elseif d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") then
						VisualPull.emitters[d] = d.Enabled
						d.Enabled = false
					end
				end
				-- Penjaga: hancurkan penggerak apa pun yang modul
				-- efek pasang ke karakter asli selama jendela ini.
				table.insert(VisualPull.conns, hrp.DescendantAdded:Connect(function(inst)
					if MOVER_CLASSES[inst.ClassName] then
						local att = inst.Attachment0
						inst:Destroy()
						if att and att:IsA("Attachment") and att.Parent == hrp then
							att:Destroy()
						end
					end
				end))
				-- Geser klon ke titik skor, maks 20 studs/detik
				-- (meniru MaxVelocity AlignPosition efek asli).
				table.insert(VisualPull.conns, RunServiceVP.Heartbeat:Connect(function(dt)
					if not (VisualPull.active and VisualPull.clone and VisualPull.clone.Parent) then
						return
					end
					local pivot = VisualPull.clone:GetPivot()
					local delta = VisualPull.target - pivot.Position
					local dist = delta.Magnitude
					if dist > 0.05 then
						local step = math.min(dist, 20 * dt)
						local newPos = pivot.Position + delta.Unit * step
						local rot = pivot - pivot.Position
						VisualPull.clone:PivotTo(CFrame.new(newPos) * rot)
					end
				end))
			end)
			if not ok then
				VisualPull.finish()
				return
			end
			-- Pengawas: akhiri lebih awal bila game memindahkan
			-- karakter asli (reset serve/respawn); jendela maks 2,8 d.
			task.spawn(function()
				local t0 = os.clock()
				while VisualPull.active and os.clock() - t0 < 2.8 do
					if player.Character ~= char then
						break
					end
					local h = char:FindFirstChild("HumanoidRootPart")
					if not h or (h.Position - VisualPull.startPos).Magnitude > 12 then
						break
					end
					task.wait(0.2)
				end
				VisualPull.finish()
			end)
		end
	-- Score FX dibungkus di satu corong yang sama (semua pemutaran
	-- efek skor lewat EffectController.PlayScoreEffect):
	-- 1) SPOOF: untuk poin milik pemain lokal sendiri saat bermain
	--    langsung, Item ditukar dengan efek palsu / hasil acak
	--    RANDOM FAVORITES sebelum dimainkan.
	-- 2) GERBANG FISIK: bila saklar World-Affecting mati, efek dari
	--    daftar WORLD_AFFECTING_FX (dinilai dari item FINAL setelah
	--    penukaran) tidak dimainkan sama sekali di client ini.
	--    Bila saklar MENYALA dan efeknya hasil penukaran (palsu),
	--    efek dimainkan penuh tetapi tarikannya visual murni
	--    lewat VisualPull di atas: karakter asli tidak bergerak.
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
					local spoofedWorldFx = false
					local resolvedId = gateOff
						and resolveScoreFxItemIdExcludingWorld()
						or resolveScoreFxItemId()
					if resolvedId and resolvedId ~= data.Item.Id then
						local item = ContentItem:Get(resolvedId)
						if item and not (gateOff and WORLD_AFFECTING_FX[resolvedId]) then
							data = table.clone(data)
							data.Item = item
							if WORLD_AFFECTING_FX[resolvedId] then
								spoofedWorldFx = true
							end
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
			if spoofedWorldFx then
				VisualPull.begin(data.Origin)
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
