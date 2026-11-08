----------------------------------------------------------------
-- suite/player-card.lua -- Modul fitur: Player Card Spoof
--
-- Resolver kartu tampil (termasuk RANDOM FAVORITES), bungkus
-- ToggleFavorite untuk favorit kartu palsu, dan bungkus
-- PlayerCardController.DisplayFlashCard.
-- Diekstrak apa adanya dari remaining-features.lua (Bagian A
-- monolit); penyesuaian hanya di kerangka peluncuran
-- (menunggu feature-shared + guard S.installedCard) dan baris timing
-- "[VL Suite] player-card ready in ..." untuk memburu lag awal.
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
		warn("[VLPlayerCard] feature-shared tidak siap; modul player-card dilewati.")
		return
	end
	local tShared = os.clock()
	if not S.installedCard then
		S.installedCard = true
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
	end
	print(("[VL Suite] player-card ready in %.2fs (shared wait %.2fs)"):format(os.clock() - t0, tShared - t0))
end

task.spawn(initPlayerCard)
