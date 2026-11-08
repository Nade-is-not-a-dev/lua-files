----------------------------------------------------------------
-- modules/equip-router.lua -- Modul fitur: Router Equip
--
-- Intersepsi InventoryService:Equip -- router hybrid
-- asli/palsu. PALING AKHIR di manifest karena menyebut
-- fungsi modul fitur lain (mis. ensureFxCarrier milik
-- score-fx). Hanya kategori yang modulnya AKTIF yang
-- dirutekan ke lapis palsu (SuiteActive); kategori lain
-- diteruskan ke equip asli apa adanya. Router ini juga
-- yang menangkap S.originalEquip -- tanpa dia,
-- ensureFxCarrier tidak bisa memasang carrier.
----------------------------------------------------------------

local function initEquipRouter()
	local t0 = os.clock()
	if not awaitFeatureShared(90) then
		warn("[VL Suite] equip-router skipped: feature-shared not ready.")
		return
	end
	local tShared = os.clock()
	loadLocal()
	installSuiteWiring()
	if not S.installedRouter then
		S.installedRouter = true
	-- InventoryService:Equip -- hybrid asli/palsu.
	local originalEquip = InventoryService.Equip
	S.originalEquip = originalEquip
	InventoryService.Equip = function(_, id, ...)
		if SuiteActive.Ball and isBall(id) and not S.realOwned[id] then
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
		if SuiteActive.Jersey and isJersey(id) and not S.realOwned[id] then
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
		if SuiteActive.Emote and isEmote(id) and not S.realOwned[id] then
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
		if SuiteActive.PlayerCard and isCard(id) and not S.realOwned[id] then
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
		if SuiteActive.ScoreEffect and isScoreFx(id) and not S.realOwned[id] then
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
		if SuiteActive.ScoreEffect and isScoreFx(id) then
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
	end
	print(("[VL Suite] equip-router ready in %.2fs (shared wait %.2fs)"):format(os.clock() - t0, tShared - t0))
	suiteModuleLoaded("equip-router")
end

suiteExpectModule("equip-router")
task.spawn(initEquipRouter)
