----------------------------------------------------------------
-- modules/auto-receive.lua -- Modul fitur: Auto Receive
--
-- Menerima otomatis bola yang datang (serve/spike/pass lawan
-- maupun teman) dengan memicu move BUMP seperti tekan tombol
-- manual -- lewat jalur resmi game, bukan langsung ke server.
--
-- Cara kerja game (dari dump):
--   * Tekan tombol -> Binding/Registry/DoMove.onMoveRequest ->
--     GameController:DoMove{ActionName, InputState, IsAerial,
--     Metadata} (DoMove/_source.lua) -> Orchestrator: prepare
--     (cooldown/busy/serve), hitbox klien, tryCollidingWithBall,
--     lalu BallService:Interact bila bola terkena. Validasi
--     canInteract tetap jalan (sisi tim, jarak <= 20, debounce).
--   * Nama action valid: Configuration/Actions.lua (Bump ground,
--     Spike/Block/JumpSet aerial, Set, Dive).
--
-- Mekanisme modul ini:
--   1. Tiap Heartbeat, ambil bola bertag "Ball" yang bergerak
--      (|vel| > 8) dan simulasi lintasannya dengan gravitasi
--      game (17, Configuration/Game/Physics.lua).
--   2. Cari waktu t paling awal (langkah 0.05 s, horizon 1 s)
--      saat jarak bola-prediksi ke HumanoidRootPart < jangkauan
--      pemicu (TRIGGER_RADIUS = 12 stud).
--   3. Bila t <= TRIGGER_LEAD (0.25 s -- hitbox hidup 0.3 s,
--      DefaultHitboxDuration) DAN karakter di tanah AND bola
--      bukan bola yang terakhir KITA pukul (LastHitter) ->
--      picu GameController:DoMove("Bump") sekali, dengan
--      cooldown lokal sendiri agar tidak spam.
--   4. Orchestrator game menolak sendiri bila sedang busy/
--      cooldown/serve/lompat -- DoMove hanya mengembalikan
--      false, tidak merusak apa pun.
--
-- Saklar: "Auto Receive" di grup VL Settings (anggota
-- AutoReceive, persisten di S.settings). Titik masuk saklar:
-- FeatureAPI.setAutoReceiveEnabled(bool) dari bungkus
-- ChangeSetting di modules/settings.lua. Bukan kategori
-- inventory: tanpa suiteActivateFeature.
----------------------------------------------------------------

local RunService = game:GetService("RunService")

-- Tuning (sadar batasan: hitbox assembly game tidak ada di dump,
-- jadi radius pakai perkiraan konservatif di bawah jangkauan
-- canInteract 20 stud).
local GRAVITY = 17            -- Configuration/Game/Physics.lua
local TRIGGER_RADIUS = 12     -- jarak bola-prediksi ke root
local TRIGGER_LEAD = 0.25     -- picu bila bola sampai <= 0.25 s
local HORIZON = 1.0           -- horizon simulasi (detik)
local STEP = 0.05             -- langkah simulasi (detik)
local MIN_SPEED = 8           -- bola harus benar-benar bergerak
local LOCAL_COOLDOWN = 0.7    -- jeda minimum antar pemicu

local lastTrigger = 0

local function simEarliestArrival(ballPos, ballVel, rootPos)
	local px, py, pz = ballPos.X, ballPos.Y, ballPos.Z
	local vx, vy, vz = ballVel.X, ballVel.Y, ballVel.Z
	local t = 0
	while t < HORIZON do
		t = t + STEP
		vy = vy - GRAVITY * STEP
		px = px + vx * STEP
		py = py + vy * STEP
		pz = pz + vz * STEP
		local dx, dy, dz = px - rootPos.X, py - rootPos.Y, pz - rootPos.Z
		if dx * dx + dy * dy + dz * dz < TRIGGER_RADIUS * TRIGGER_RADIUS then
			return t
		end
	end
	return nil
end

local function tryTriggerReceive()
	if os.clock() - lastTrigger < LOCAL_COOLDOWN then
		return
	end
	-- Bola terakhir yang KITA pukul: jangan dipicu ulang (anti
	-- re-hit; gerbang LastHitter milik game di isHitboxSkipped).
	if workspace:GetAttribute("LastHitter") == player.Name then
		return
	end
	local character = player.Character
	if not character or not character.Parent then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.FloorMaterial == Enum.Material.Air then
		return -- Bump ground: butuh di tanah (IsJumping harus false)
	end
	local rootPos = root.Position

	local GameController
	pcall(function()
		GameController = Knit.GetController("GameController")
	end)
	if not (GameController and GameController.DoMove) then
		return
	end

	for _, ball in ipairs(CollectionService:GetTagged("Ball")) do
		local pos = ball:IsA("BasePart") and ball.Position
		local vel = ball:IsA("BasePart") and ball.AssemblyLinearVelocity
		if pos and vel and vel.Magnitude > MIN_SPEED then
			local t = simEarliestArrival(pos, vel, rootPos)
			if t and t <= TRIGGER_LEAD then
				lastTrigger = os.clock()
				task.spawn(function()
					pcall(function()
						GameController:DoMove({
							ActionName = "Bump",
							InputState = Enum.UserInputState.Begin,
							IsAerial = false,
						})
					end)
				end)
				return
			end
		end
	end
end

local function startAutoReceive()
	if S[RECEIVE_CONN] then
		return
	end
	S[RECEIVE_CONN] = RunService.Heartbeat:Connect(tryTriggerReceive)
end

local function stopAutoReceive()
	local conn = S[RECEIVE_CONN]
	if conn then
		S[RECEIVE_CONN] = nil
		pcall(function()
			conn:Disconnect()
		end)
	end
end

local function initAutoReceive()
	local t0 = os.clock()
	-- RE-RUN SAFE: selalu daftarkan ulang FeatureAPI + terapkan
	-- ulang state tersimpan (fungsi instance lama mati bersama
	-- localnya; koneksi disimpan di S agar lintas instance).
	local deadline = t0 + 30
	while not LocalStateLoaded and os.clock() < deadline do
		task.wait(0.25)
	end
	local sharedWait = os.clock() - t0

	FeatureAPI.setAutoReceiveEnabled = function(enabled)
		if enabled then
			startAutoReceive()
		else
			stopAutoReceive()
		end
	end

	-- Keadaan awal dari saklar tersimpan (idempoten).
	FeatureAPI.setAutoReceiveEnabled(S.settings[SETTING_MEMBER_AUTO_RECEIVE] == true)

	print(("[VL Suite] auto-receive ready in %.2fs (shared wait %.2fs)"):format(os.clock() - t0, sharedWait))
	suiteModuleLoaded("auto-receive")
end
suiteExpectModule("auto-receive")
task.spawn(initAutoReceive)
