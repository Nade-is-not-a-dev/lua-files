----------------------------------------------------------------
-- modules/emote.lua -- Modul fitur: Emote Spoof + Prop Lokal
--
-- applyEmotes (slot roda palsu), tabel PROP_EMOTES, mesin
-- prop lokal (runEmoteProp dkk), bungkus InventoryService
-- .Use / .StopEmotes, dan penghentian prop saat respawn.
-- applyEmotes + PROP_EMOTES didaftarkan ke FeatureAPI:
-- pengawatan feature-shared dan bungkus Equip di
-- modules/init.lua memanggilnya dari file yang dimuat
-- lebih awal.
----------------------------------------------------------------

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
		if not S.extremeFast then
			for index, emoteId in pairs(S.fakeEmotes) do
				merged[index] = emoteId
			end
		end
		-- Hanya :set bila berubah: :set memicu hitung ulang
		-- Fusion roda emote, dan applyEmotes dipanggil pada
		-- setiap ProfileUpdated selama bermain.
		if not shallowSame(EmoteController.Emotes:get(), merged) then
			EmoteController.Emotes:set(merged)
		end
	end)
end

----------------------------------------------------------------
-- Emote yang Metadata.Callback-nya menelurkan properti di karakter
-- (dari definisi item di Content/Item/Entities). Untuk equip
-- palsu propertinya hanya jalan lokal (lihat bungkus Use di
-- bawah), tidak terlihat pemain lain.
local activeEmoteProps = {} -- [id emote] = fungsi cleanup prop berjalan
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

local function initEmote()
	local t0 = os.clock()
	if not awaitFeatureShared(90) then
		warn("[VL Suite] emote skipped: feature-shared not ready.")
		return
	end
	local tShared = os.clock()
	FeatureAPI.applyEmotes = applyEmotes
	FeatureAPI.propEmotes = PROP_EMOTES
	-- Pakai alat feature-shared sendiri: muat state lokal
	-- (slot emote palsu dari simpanan) + suntikkan kategori
	-- Emote ke inventory.
	loadLocal()
	injectInventory()
	if not S.installedEmote then
		S.installedEmote = true
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
	end
	applyEmotes()
	print(("[VL Suite] emote ready in %.2fs (shared wait %.2fs)"):format(os.clock() - t0, tShared - t0))
	suiteModuleLoaded("emote")
end

suiteActivateFeature("Emote")
suiteExpectModule("emote")
task.spawn(initEmote)
