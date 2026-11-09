----------------------------------------------------------------
-- modules/extreme-ultra-fast.lua -- Modul fitur: Extreme
-- Ultra Fast Mode
--
-- Saklar "Extreme Ultra Fast Mode" di grup VL Settings
-- (anggota ExtremeUltraFastMode; persisten di S.settings).
-- Saat AKTIF (S.extremeFast):
--  1. Visual game dicabut sampai tinggal yang penting:
--     tekstur dunia (MeshPart / Decal / Texture) dikosongkan,
--     SurfaceAppearance + Sky + Atmosphere diparkir, efek
--     partikel dan cahaya dinamis dimatikan, bayangan global
--     + PostEffect mati, kualitas grafis dipaksa Level 1.
--     Yang TIDAK disentuh: karakter pemain, bola (termasuk
--     replay dan bola weld), dan net.
--  2. Semua fitur spoof suite berhenti menerapkan efeknya:
--     gerbang S.extremeFast dibaca alat bersama
--     (applyEquipped / applyFavorites / injectInventory --
--     item palsu bahkan dicabut dari Value inventaris) dan
--     bungkus tiap modul (Ball.new / GhostBall / bola weld,
--     PlayScoreEffect, DisplayFlashCard, roda emote, render
--     jersey, Equip / Favorite). Game berjalan seperti tanpa
--     suite; state palsu tetap tersimpan apa adanya.
-- Saat DIMATIKAN: semua properti / parkiran dipulihkan dari
-- catatan modul ini dan fitur suite diterapkan lagi.
--
-- Titik masuk dari luar: FeatureAPI.applyExtremeFast(bool),
-- dipanggil bungkus ChangeSetting di modules/settings.lua
-- (yang juga membalik S.extremeFast secara langsung, jadi
-- gerbang tetap bekerja walau modul ini belum termuat).
-- Bukan kategori inventory: tanpa suiteActivateFeature.
----------------------------------------------------------------

local Lighting = game:GetService("Lighting")

-- Catatan pemulihan (lokal modul; nilai pertama yang tercatat
-- untuk satu properti selalu menang, supaya penegakan berkala
-- tidak menimpa nilai asli dengan nilai yang sudah dicabut).
local xfSaved = {} -- [inst] = { [prop] = nilaiAsli }
local xfParked = {} -- [inst] = parentAsli (SurfaceAppearance/Sky/Atmosphere)
local xfFxSet = {} -- [inst] = true, efek yang ditegakkan berkala
local xfConn = nil
local xfAlive = false
local xfOldQuality = nil
local xfVisualsApplied = false

local function xfSaveProp(inst, prop)
	local entry = xfSaved[inst]
	if not entry then
		entry = {}
		xfSaved[inst] = entry
	end
	if entry[prop] == nil then
		local ok, value = pcall(function()
			return inst[prop]
		end)
		if ok then
			entry[prop] = value
		end
	end
end

-- Yang paling penting tidak disentuh: bola (tag/nama Ball,
-- termasuk leluhurnya -- bola replay dan bola weld), net,
-- dan karakter pemain mana pun.
local function xfIsExempt(inst)
	local node = inst
	while node and node ~= workspace do
		if node:HasTag("Ball") or node.Name == "Ball" or node.Name == "ReplayBall" then
			return true
		end
		if node.Name == "Net" then
			return true
		end
		if node:IsA("Model") and Players:GetPlayerFromCharacter(node) then
			return true
		end
		node = node.Parent
	end
	return false
end

local function xfStrip(inst)
	if xfIsExempt(inst) then
		return
	end
	if inst:IsA("MeshPart") then
		if inst.TextureID ~= "" then
			xfSaveProp(inst, "TextureID")
			inst.TextureID = ""
		end
	elseif inst:IsA("Decal") or inst:IsA("Texture") then
		if inst.Texture ~= "" then
			xfSaveProp(inst, "Texture")
			inst.Texture = ""
		end
	elseif inst:IsA("SurfaceAppearance") then
		if not xfParked[inst] then
			xfParked[inst] = inst.Parent
			inst.Parent = nil
		end
	end
end

local function xfKillFx(inst)
	if xfIsExempt(inst) then
		return
	end
	if inst:IsA("ParticleEmitter") then
		xfFxSet[inst] = true
		xfSaveProp(inst, "Enabled")
		xfSaveProp(inst, "Rate")
		-- Rate 0 juga: burst yang dinyalakan ulang game tetap
		-- kosong (dan loop penegak mematikannya lagi).
		inst.Rate = 0
		inst.Enabled = false
	elseif inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles")
		or inst:IsA("Trail") or inst:IsA("Beam")
		or inst:IsA("PointLight") or inst:IsA("SpotLight") or inst:IsA("SurfaceLight") then
		xfFxSet[inst] = true
		xfSaveProp(inst, "Enabled")
		inst.Enabled = false
	end
end

local function xfVisit(inst)
	pcall(xfStrip, inst)
	pcall(xfKillFx, inst)
end

local function xfApplyVisuals()
	if xfVisualsApplied then
		return
	end
	xfVisualsApplied = true
	for _, desc in ipairs(workspace:GetDescendants()) do
		xfVisit(desc)
	end
	xfConn = workspace.DescendantAdded:Connect(function(desc)
		task.defer(xfVisit, desc)
	end)
	-- Langit + atmosfer diparkir (langit polos bawaan), efek
	-- pasca-proses Lighting dimatikan.
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Sky") or child:IsA("Atmosphere") then
			if not xfParked[child] then
				xfParked[child] = Lighting
				child.Parent = nil
			end
		elseif child:IsA("PostEffect") then
			xfSaveProp(child, "Enabled")
			child.Enabled = false
		end
	end
	xfSaveProp(Lighting, "GlobalShadows")
	Lighting.GlobalShadows = false
	pcall(function()
		local ugs = UserSettings():GetService("UserGameSettings")
		xfOldQuality = ugs.SavedQualityLevel
		ugs.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1
	end)
	-- Tegakkan lagi efek yang dinyalakan ulang oleh game.
	xfAlive = true
	task.spawn(function()
		while xfAlive do
			task.wait(2)
			for inst in pairs(xfFxSet) do
				if inst.Parent then
					pcall(xfKillFx, inst)
				else
					xfFxSet[inst] = nil
				end
			end
		end
	end)
	print("[VL Suite] Extreme Ultra Fast Mode ON: visuals stripped, suite features gated.")
end

local function xfRestoreVisuals()
	if not xfVisualsApplied then
		return
	end
	xfVisualsApplied = false
	xfAlive = false
	if xfConn then
		xfConn:Disconnect()
		xfConn = nil
	end
	for inst, props in pairs(xfSaved) do
		for prop, value in pairs(props) do
			pcall(function()
				inst[prop] = value
			end)
		end
	end
	xfSaved = {}
	for inst, parent in pairs(xfParked) do
		pcall(function()
			inst.Parent = parent
		end)
	end
	xfParked = {}
	xfFxSet = {}
	if xfOldQuality then
		pcall(function()
			UserSettings():GetService("UserGameSettings").SavedQualityLevel = xfOldQuality
		end)
		xfOldQuality = nil
	end
	print("[VL Suite] Extreme Ultra Fast Mode OFF: visuals restored.")
end

-- Segarkan terapan fitur mengikuti keadaan gerbang sekarang:
-- alat bersama membaca S.extremeFast, jadi memanggil ulang
-- mereka saja sudah cukup (plus emote + jersey lewat
-- FeatureAPI karena penerapnya milik modul masing-masing).
local function xfRefreshFeatures()
	applyEquipped()
	applyFavorites()
	injectInventory()
	if FeatureAPI.applyEmotes then
		FeatureAPI.applyEmotes()
	end
	if S.extremeFast then
		if FeatureAPI.restoreJerseyRender then
			FeatureAPI.restoreJerseyRender()
		end
	else
		if FeatureAPI.applyJerseyRender then
			FeatureAPI.applyJerseyRender()
		end
	end
end

local function setExtremeFast(enabled)
	S.extremeFast = enabled == true
	if S.extremeFast then
		xfApplyVisuals()
	else
		xfRestoreVisuals()
	end
	xfRefreshFeatures()
end

local function initExtremeFast()
	local t0 = os.clock()
	if not awaitFeatureShared(90) then
		warn("[VL Suite] extreme-ultra-fast skipped: feature-shared not ready.")
		return
	end
	local tShared = os.clock()
	loadLocal()
	FeatureAPI.applyExtremeFast = setExtremeFast
	-- Keadaan persisten dari sesi lalu (saklar ditinggal AKTIF):
	-- terapkan penuh sekarang -- visual dicabut dan terapan
	-- fitur ditarik -- tanpa menunggu saklar disentuh lagi.
	if S.extremeFast then
		task.spawn(setExtremeFast, true)
	end
	print(("[VL Suite] extreme-ultra-fast ready in %.2fs (shared wait %.2fs)"):format(os.clock() - t0, tShared - t0))
	suiteModuleLoaded("extreme-ultra-fast")
end

suiteExpectModule("extreme-ultra-fast")
task.spawn(initExtremeFast)
