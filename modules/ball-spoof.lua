----------------------------------------------------------------
-- modules/ball-spoof.lua -- Modul fitur: Ball Spoof SAJA
--
-- Isi: mesin bola weld (spoofWelded dkk), kepemilikan serve
-- (recordServe / replayBelongsToMe), sintesis SurfaceHit,
-- bungkus Ball.new + GhostBall.new, dan penjaga bola weld
-- baru. Fitur lain (jersey, emote, kartu, Score FX, settings)
-- TIDAK di sini -- mereka di remaining-features.lua untuk
-- sementara, menunggu modulnya masing-masing.
--
-- Diekstrak apa adanya dari Bagian A monolit; penyesuaian
-- hanya di kerangka peluncuran (menunggu feature-shared +
-- guard S.installedBall) dan registrasi scanWeldedBalls ke
-- FeatureAPI (dipanggil applyEquipped milik feature-shared).
----------------------------------------------------------------

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

local ALERT_BALL_SURFACE = "This ball's surface effect is normally sent by the server. The script recreates it locally: only you see it, and only on hard impacts. Equip anyway?"

local ALERT_EMOTE_PROP = "This emote's prop is normally run by the server. The script runs it locally: only you see the prop; others only see the animation. Equip anyway?"

local ALERT_FX_WORLD = "This score effect physically affects players. The spoof shows only on your screen and only affects your own character. Equip anyway?"

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

FeatureAPI.scanWeldedBalls = scanWeldedBalls
suiteActivateFeature("Ball")

local function initBallSpoof()
	local t0 = os.clock()
	if not awaitFeatureShared(90) then
		warn("[VL Suite] ball-spoof skipped: feature-shared not ready.")
		return
	end
	local tShared = os.clock()
	-- Pakai alat feature-shared sendiri: muat state lokal,
	-- pasang pengawatan event bersama, suntikkan kategori
	-- Ball saja ke inventory, terapkan lapisan equip bola.
	loadLocal()
	installSuiteWiring()
	injectInventory()
	applyEquipped()
	if not S.installedBall then
		S.installedBall = true
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
	end
	if S.fakeEquipped and InventoryController.Selected then
		InventoryController.Selected:set(S.fakeEquipped)
	end
	print(("[VL Suite] ball-spoof ready in %.2fs (shared wait %.2fs)"):format(os.clock() - t0, tShared - t0))
	suiteModuleLoaded("ball-spoof")
end
suiteExpectModule("ball-spoof")
task.spawn(initBallSpoof)
