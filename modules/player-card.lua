----------------------------------------------------------------
-- modules/player-card.lua -- Modul fitur: Player Card Spoof
--
-- Resolver kartu tampil (termasuk RANDOM FAVORITES) dan
-- bungkus PlayerCardController.DisplayFlashCard. (Bungkus
-- ToggleFavorite sekarang di modules/init.lua.)
----------------------------------------------------------------

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

local function initPlayerCard()
	local t0 = os.clock()
	if not awaitFeatureShared(90) then
		warn("[VL Suite] player-card skipped: feature-shared not ready.")
		return
	end
	local tShared = os.clock()
	-- Pakai alat feature-shared sendiri: muat state lokal,
	-- suntikkan kategori
	-- PlayerCard ke inventory, terapkan lapisan equip kartu
	-- dan gabungan favorit.
	loadLocal()
	injectInventory()
	applyEquipped()
	applyFavorites()
	if not S.installedCard then
		S.installedCard = true
	-- Momen tampil kartu (flash card saat mencetak poin + kartu MVP)
	-- digerakkan event server yang membawa id kartu ASLI. Untuk
	-- event tentang pemain lokal, tukar id-nya dengan kartu palsu /
	-- hasil acak RANDOM FAVORITES sebelum dirender. Controller
	-- membaca DisplayFlashCard dari tabelnya setiap event, jadi
	-- membungkus method-nya efektif.
	if PlayerCardController and PlayerCardController.DisplayFlashCard then
		local originalDisplayFlashCard = PlayerCardController.DisplayFlashCard
		PlayerCardController.DisplayFlashCard = function(self, data)
			if type(data) == "table" and data.Player == player and not S.extremeFast then
				local resolved = resolveDisplayCardId()
				if resolved and resolved ~= data.PlayerCardItemId then
					data = table.clone(data)
					data.PlayerCardItemId = resolved
				end
			end
			return originalDisplayFlashCard(self, data)
		end
	end
	end
	print(("[VL Suite] player-card ready in %.2fs (shared wait %.2fs)"):format(os.clock() - t0, tShared - t0))
	suiteModuleLoaded("player-card")
end

suiteActivateFeature("PlayerCard")
suiteExpectModule("player-card")
task.spawn(initPlayerCard)
