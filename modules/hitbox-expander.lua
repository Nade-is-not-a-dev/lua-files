----------------------------------------------------------------
-- modules/hitbox-expander.lua -- Modul fitur: Hitbox Expander
--
-- Memperbesar hitbox DETEKSI pukulan sendiri (Bump/Set/JumpSet/
-- Spike/Block/Dive/Serve) saat menyentuh bola.
--
-- Cara kerja game (dari dump, ReplicatedFirst/Controllers/
-- GameController/Actions/Move/DoMove/ClientHitbox.lua):
--   * Saat move jalan, game membuat part hitbox klien dengan
--     ukuran params.HitboxSize (bila ada; khusus special aktif)
--     atau Hitbox.Size milik assembly hitbox per move
--     (ReplicatedStorage/Assets/HitboxesNew -- Offset+Size+Debug
--     Color dari Part, Custom modul untuk AdjustBoundsLocal).
--   * tryCollidingWithBall mencari part bertag "Ball" di dalam
--     part itu (GetPartsInPart, Values.HitboxParams), digerbang
--     Common.Physics.canInteract: bola harus di sisi tim sendiri,
--     jarak bola <= 20 stud (30 untuk Dive), plus aturan debounce/
--     serve. Bila lolos, BallService:Interact dikirim ke server
--     dengan BallId + Key hitbox server.
-- Modul ini membungkus ClientHitbox.new dan menggandakan ukuran
-- HitboxSize pada parameternya (parameternya dibuat baru tiap
-- move oleh Orchestrator, jadi mutasinya aman). Gerbang jarak
-- canInteract tetap jalan, jadi makin besar skalanya makin
-- sering di-clamp -- skala 3x sudah melampaui jarak 20 stud di
-- sebagian besar arah.
--
-- VISUAL: saat aktif, flag _DebugHitboxes di
-- ReplicatedStorage/Configuration/Game dinyalakan (mekanisme
-- debug milik game sendiri -- konsol ToggleHitboxes), jadi part
-- hitbox tergambar transparan neon dan ukurannya kelihatan.
-- Mati = flag dikembalikan nil.
--
-- Saklar: "Hitbox Expander" di grup VL Settings (anggota
-- HitboxExpander, persisten di S.settings; skala persisten di
-- S.hitboxScale, default 1.9, dibatasi 1..3 -- ubah lewat
-- FeatureAPI.setHitboxScale). Titik masuk saklar:
-- FeatureAPI.setHitboxExpanderEnabled(bool) dari bungkus
-- ChangeSetting di modules/settings.lua.
--
-- CINCIN JANGKAUAN: sphere semi-transparan (radius 20 stud)
-- menempel di tiap bola bertag "Ball" per Heartbeat. Hijau bila
-- karakter di dalam cincin DAN bola di sisi tim sendiri
-- (Common.Physics.isPointOnTeamSide milik game), biru bila belum.
-- Bukan kategori inventory: tanpa suiteActivateFeature.
----------------------------------------------------------------

local function applyHitboxScale(enabled)
	S._hitboxScaleActive = enabled and S.hitboxScale or 1
end

----------------------------------------------------------------
-- VISUAL: cincin jangkauan yang menempel di bola.
-- Sphere semi-transparan radius = jangkauan pukulan (20 stud,
-- gerbang DistanceFromCharacter milik canInteract). Cincin ikut
-- bola (tag "Ball" -- kandidat yang bisa dipukul hitbox) tiap
-- Heartbeat. Warna: HIJAU bila bola saat ini DALAM JANGKAUAN
-- (karakter di dalam cincin) dan di sisi tim sendiri (cek lewat
-- Common.Physics.isPointOnTeamSide milik game); BIRU bila belum.
----------------------------------------------------------------
local RING_REACH = 20
local RING_COLOR_OK = Color3.fromRGB(90, 255, 130)
local RING_COLOR_FAR = Color3.fromRGB(120, 175, 255)
local RunService = game:GetService("RunService")

local ringParts = {} -- [instansi bola] = part cincin
local ringHeartbeatConn, ringAddedConn, ringRemovedConn
local Physics -- Common.Physics milik game (diisi saat init)

local function removeRing(ball)
	local part = ringParts[ball]
	if part then
		ringParts[ball] = nil
		if part.Parent then
			part:Destroy()
		end
	end
end

local function ensureRing(ball)
	if ringParts[ball] or not ball:IsDescendantOf(workspace) then
		return
	end
	local part = Instance.new("Part")
	part.Name = "VLHitboxRing"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(RING_REACH * 2, RING_REACH * 2, RING_REACH * 2)
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Anchored = true
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Transparency = 0.85
	part.Color = RING_COLOR_FAR
	part.Parent = workspace
	ringParts[ball] = part
end

local function ringHeartbeat()
	-- Posisi bola + jarak karakter dihitung tanpa alokasi berlebih.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local rootPos = root and root.Position
	local mapOk = workspace:FindFirstChild("Map") ~= nil
	for ball, part in pairs(ringParts) do
		if not ball.Parent or not ball:IsDescendantOf(workspace) or not part.Parent then
			removeRing(ball)
		else
			local pos
			if ball:IsA("BasePart") then
				pos = ball.Position
			else
				local ok, pivot = pcall(ball.GetPivot, ball)
				pos = ok and pivot.Position
			end
			if pos then
				part.CFrame = CFrame.new(pos)
				local inRange = rootPos ~= nil
					and (rootPos - pos).Magnitude < RING_REACH
				local onSide = false
				if mapOk then
					local ok, result = pcall(Physics.isPointOnTeamSide, player, pos, "Bump")
					onSide = ok and result == true
				end
				part.Color = (inRange and onSide) and RING_COLOR_OK or RING_COLOR_FAR
			else
				removeRing(ball)
			end
		end
	end
end

local function startRing()
	if ringHeartbeatConn then
		return
	end
	-- Bola yang sudah ada + bola yang muncul belakangan.
	for _, ball in ipairs(CollectionService:GetTagged("Ball")) do
		ensureRing(ball)
	end
	ringAddedConn = CollectionService:GetInstanceAddedSignal("Ball"):Connect(ensureRing)
	ringRemovedConn = CollectionService:GetInstanceRemovedSignal("Ball"):Connect(removeRing)
	ringHeartbeatConn = RunService.Heartbeat:Connect(ringHeartbeat)
end

local function stopRing()
	if ringHeartbeatConn then
		ringHeartbeatConn:Disconnect()
		ringHeartbeatConn = nil
	end
	if ringAddedConn then
		ringAddedConn:Disconnect()
		ringAddedConn = nil
	end
	if ringRemovedConn then
		ringRemovedConn:Disconnect()
		ringRemovedConn = nil
	end
	for ball in pairs(ringParts) do
		removeRing(ball)
	end
end

local function initHitboxExpander()
	local t0 = os.clock()
	if getgenv().VLHitboxExpanderInstalled then
		suiteModuleLoaded("hitbox-expander")
		return
	end
	getgenv().VLHitboxExpanderInstalled = true
	-- Tunggu state lokal selesai dimuat (saklar awal + skala).
	local deadline = t0 + 30
	while not LocalStateLoaded and os.clock() < deadline do
		task.wait(0.25)
	end
	local sharedWait = os.clock() - t0

	pcall(function()
		Physics = require(RS:WaitForChild("Common"):WaitForChild("Physics"))
	end)

	local installedWrap = false
	FeatureAPI.setHitboxExpanderEnabled = function(enabled)
		applyHitboxScale(enabled)
		pcall(function()
			-- Visual debug milik game: hitbox part digambar
			-- transparan neon saat _DebugHitboxes truthy.
			local gameConfig = require(RS:WaitForChild("Configuration"):WaitForChild("Game"))
			gameConfig._DebugHitboxes = enabled or nil
		end)
		-- Cincin jangkauan menempel di bola (lihat atas).
		pcall(function()
			if enabled then
				startRing()
			else
				stopRing()
			end
		end)
	end
	FeatureAPI.setHitboxScale = function(scale)
		if type(scale) == "number" and scale >= 1 and scale <= 3 then
			S.hitboxScale = scale
			saveLocal()
			applyHitboxScale(S.settings[SETTING_MEMBER_HITBOX] == true)
		end
	end

	if S.installedHitboxWrap then
		installedWrap = true
	end

	local function installWrap()
		if installedWrap then
			return
		end
		installedWrap = true
		S.installedHitboxWrap = true
		local ClientHitbox = require(ReplicatedFirst:WaitForChild("Controllers")
			:WaitForChild("GameController")
			:WaitForChild("Actions")
			:WaitForChild("Move")
			:WaitForChild("DoMove")
			:WaitForChild("ClientHitbox"))
		local originalNew = ClientHitbox.new
		ClientHitbox.new = function(params)
			local scale = S._hitboxScaleActive or 1
			if params and params.Hitbox and scale > 1 then
				-- Ukuran dasar: HitboxSize (khusus special) atau
				-- Hitbox.Size milik assembly. Kita selalu set
				-- HitboxSize eksplisit agar table Hitbox bersama
				-- (hasil register game) TIDAK dimutasi.
				local base = params.HitboxSize or params.Hitbox.Size
				if base then
					params.HitboxSize = base * scale
				end
			end
			return originalNew(params)
		end
	end

	-- Bungkus modulnya saat modul fitur ini init (modul game sudah
	-- ada di tree ReplicatedFirst); guard pcall supaya kegagalan
	-- path tidak menggagalkan modul lain.
	pcall(installWrap)

	-- Terapkan keadaan awal dari saklar tersimpan.
	if S.localStateLoaded then
		FeatureAPI.setHitboxExpanderEnabled(S.settings[SETTING_MEMBER_HITBOX] == true)
	end

	print(("[VL Suite] hitbox-expander ready in %.2fs (shared wait %.2fs)"):format(os.clock() - t0, sharedWait))
	suiteModuleLoaded("hitbox-expander")
end
suiteExpectModule("hitbox-expander")
task.spawn(initHitboxExpander)
