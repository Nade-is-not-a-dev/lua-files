----------------------------------------------------------------
-- modules/init.lua -- Modul init: sistem yang dimuat AWAL
--
-- Isinya bukan fitur tampilan, melainkan sistem lintas
-- fitur yang harus terpasang sebelum modul lain berjalan
-- dan tidak dipasang oleh modul fitur secara langsung:
--   1) pengawatan event bersama (installSuiteWiring),
--   2) sistem equip -- bungkus InventoryService.Equip
--      (router hybrid asli/palsu; juga menangkap
--      S.originalEquip untuk carrier Score FX),
--   3) sistem favorite -- bungkus
--      InventoryService.ToggleFavorite (favorit kartu /
--      Score FX palsu disimpan lokal; asli diteruskan).
-- Karena file ini dimuat SEBELUM modul fitur, panggilan ke
-- fungsi milik modul lain wajib lewat FeatureAPI (registry
-- feature-shared), bukan local file lain.
----------------------------------------------------------------

-- Sistem equip (dulu: modul equip-router).
local function installEquipSystem()
	if not S.installedRouter then
		S.installedRouter = true
	-- InventoryService:Equip -- hybrid asli/palsu.
	local originalEquip = InventoryService.Equip
	S.originalEquip = originalEquip
	InventoryService.Equip = function(_, id, ...)
		if SuiteActive.Ball and isBall(id) and not S.realOwned[id]  and not S.extremeFast then
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
		if SuiteActive.Jersey and isJersey(id) and not S.realOwned[id]  and not S.extremeFast then
			if S.fakeJersey == id then
				S.fakeJersey = nil -- klik lagi = unequip
				applyEquipped()
				saveLocal()
				-- Server tidak tahu apa-apa: pasang kembali yang
				-- asli secara lokal.
				if FeatureAPI.restoreJerseyRender then FeatureAPI.restoreJerseyRender() end
			else
				S.fakeJersey = id
				applyEquipped()
				saveLocal()
				if FeatureAPI.applyJerseyRender then FeatureAPI.applyJerseyRender() end
			end
			return resolvedPromise(true)
		end
		if SuiteActive.Emote and isEmote(id) and not S.realOwned[id]  and not S.extremeFast then
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
				if FeatureAPI.applyEmotes then FeatureAPI.applyEmotes() end
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
					if FeatureAPI.applyEmotes then FeatureAPI.applyEmotes() end
					saveLocal()
				end
				-- Emote berproperti: efeknya server-driven -> alert.
				if FeatureAPI.propEmotes and FeatureAPI.propEmotes[id] then
					local item = ContentItem:Get(id)
					showSpoofAlert((item and item.DisplayName) or id, ALERT_EMOTE_PROP, doEquip)
				else
					doEquip()
				end
			end
			return resolvedPromise(true)
		end
		if SuiteActive.PlayerCard and isCard(id) and not S.realOwned[id]  and not S.extremeFast then
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
		if SuiteActive.ScoreEffect and isScoreFx(id) and not S.realOwned[id]  and not S.extremeFast then
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
					if FeatureAPI.ensureFxCarrier then task.defer(FeatureAPI.ensureFxCarrier) end
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
		if SuiteActive.ScoreEffect and isScoreFx(id)  and not S.extremeFast then
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
				task.delay(6, function() if FeatureAPI.ensureFxCarrier then FeatureAPI.ensureFxCarrier() end end)
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
	end
end

-- Sistem favorite (dulu: bagian dari modul player-card).
local function installFavoriteSystem()
	if S.installedFavorite then
		return
	end
	S.installedFavorite = true
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
end

local function initEarlySystems()
	local t0 = os.clock()
	if not awaitFeatureShared(90) then
		warn("[VL Suite] init skipped: feature-shared not ready.")
		return
	end
	local tShared = os.clock()
	loadLocal()
	installSuiteWiring()
	installEquipSystem()
	installFavoriteSystem()
	print(("[VL Suite] init ready in %.2fs (shared wait %.2fs)"):format(os.clock() - t0, tShared - t0))
	suiteModuleLoaded("init")
end

suiteExpectModule("init")
task.spawn(initEarlySystems)
