----------------------------------------------------------------
-- modules/auto-farm.lua -- Modul fitur: Auto Farm (v15 extreme)
--
-- Port v15 extreme (volleyball-farm-autoloop.lua, 1.736 baris)
-- menjadi modul VL Suite. Perilaku farm-nya IDENTIK dengan
-- script standalone-nya:
--   * Farm inti BLOCK ONLY: TP ke bola tiap frame (Heartbeat) +
--     percobaan Block paralel (satu thread per percobaan,
--     interval default 0) lewat CreateHitbox + Interact("Block")
--     + UpdateTilt milik BallService.
--   * Loop AUTO: join match (RequestJoin sweep portal) -> farm
--     -> post-match (klik SKIP replay + Back summary, fallback
--     ReelFinished) -> reset/respawn -> join lagi. Serve
--     ditangani handler serve (Toss x2 -> melangkah ke bawah
--     bola -> Jump -> burst Spike di apex).
--   * Overlay progres level 15 + klaim Level Rewards + redeem
--     kode otomatis (batch Update 95) dengan alur respawn-first
--     bila level 15 tercapai di tengah match, console mirror,
--     dan error context logger ke VolleyballFarmLogs/.
--   * FastMode + UltraFastMode bawaan game dinyalakan sekali
--     saat modul init (persis seperti v15 saat startup).
--
-- Perbedaan dari standalone (integrasi suite):
--   * TIDAK ada GUI AUTO sendiri: saklar utamanya adalah
--     S.settings.AutoFarm (persisten di vl-ball-spoof.json),
--     dikendalikan dari panel Settings "VL Farm". GUI farm
--     kecil v15 (toggle TP/BALL/SPIKE/JUMP + kotak interval +
--     status) tetap ada, tampil saat AUTO menyala.
--   * AUTO-ATTACH ala Infinite Yield: saat AUTO dinyalakan,
--     suite mengantrekan loadstring-nya sendiri lewat
--     queue_on_teleport, jadi setelah rejoin / pindah server /
--     teleport, suite termuat lagi TANPA perlu autoexec, dan
--     status AutoFarm yang tersimpan membuat loop lanjut
--     sendiri. Antrean diperbarui tiap init selama AutoFarm
--     masih menyala.
--   * Semua state/fungsi modul hidup di SATU tabel lokal
--     (Farm) -- batas 200 local di cakupan chunk dist.
--   * Modul ini TIDAK memakai rollback data sama sekali.
--
-- BUNDLE OTOMATISASI: file ini TIDAK
-- digabung ke chunk suite. Ia dimuat suite saat runtime sebagai
-- bundle terpisah yang di-obfuscate Prometheus (config light),
-- jadi semua kebutuhan bersamanya diambil dari bridge yang
-- diterbitkan suite di getgenv().VLBridge -- BUKAN dari local
-- chunk suite. Bila bridge tidak ada (suite versi lama), bundle
-- berhenti dengan peringatan.
----------------------------------------------------------------

local VLBridge = getgenv().VLBridge
if not VLBridge then
	warn("[VL Suite] automation: VLBridge tidak ditemukan (suite belum siap / versi lama) -- auto farm dilewati.")
	return
end
local S = VLBridge.S
local saveLocal = VLBridge.saveLocal
local loadLocal = VLBridge.loadLocal
local Knit = VLBridge.Knit
local player = VLBridge.player
local RS = VLBridge.RS
local ReplicatedFirst = VLBridge.ReplicatedFirst
local CollectionService = VLBridge.CollectionService
local FeatureAPI = VLBridge.FeatureAPI
local SETTING_MEMBER_FARM = VLBridge.SETTING_MEMBER_FARM

local Farm = {}
Farm.RunService = game:GetService("RunService")
Farm.LogService = game:GetService("LogService")
Farm.VIM = game:GetService("VirtualInputManager")
Farm.LOADSTRING = 'loadstring(game:HttpGet("https://nade-is-not-a-dev.github.io/vl-suite/vl-suite.lua"))()'

-- Konfigurasi loop AUTO (identik v15).
Farm.CFG = {
	Positions = 6,
	JoinSweepWait = 2,
	NoBallEndSeconds = 25,
	MaxMatchSeconds = 25 * 60,
	AlsoFarmJump = false,
	PostTimeoutSeconds = 180,
	PostStableSeconds = 3,
	PostNothingSeconds = 30,
	ReelSkipFallbackSeconds = 20,
	ServeEnabled = true,
	ServePowerWait = 0.7,
	ServeJumpDelay = 0.95,
	ServeApexWait = 0.38,
}
Farm.TARGET_LEVEL = 15
-- Batch Update 95 (2026-11-08); kode berganti tiap update mingguan.
Farm.REDEEM_CODES = { "UPDATE_95", "YEEHAW", "TWINS_STANDOFF", "DAILYCUP", "GOLDHINATA", "NEKOMAROUTE", "INARIZAKI", "VAMPIRES" }
Farm.ENABLE_PERF_MODES = true

-- State runtime (padanan variabel chunk v15).
Farm.running = false -- saklar AUTO
Farm.flags = { TP = false, BALL = false, SPIKE = false, JUMP = false }
Farm.togButtons = {}
Farm.intervalText = "0"
Farm.jumpState = false
Farm.lastPrint = 0
Farm.handlersModule = nil
Farm.serveBusy = false
Farm.matchEnded = false
Farm.reelActive = false
Farm.reelStartedAt = 0
Farm.pendingRespawnRedeem = false
Farm.redeemSignal = nil
-- Overlay / redeem
Farm.curLevel = 0
Farm.curXP = nil
Farm.levelConfirmed = false
Farm.redeemState = "menunggu level " .. Farm.TARGET_LEVEL
Farm.redeemRunning = false
Farm.redeemDone = false
Farm.levelBaselineKnown = false
Farm.wasBelowTarget = false
-- GUI
Farm.gui = nil -- ScreenGui panel farm kecil (sg v15)
Farm.statusLbl = nil
Farm.overlayGui = nil -- ScreenGui overlay level + console (og v15)
Farm.panelGui = nil
Farm.panelToggleBtn = nil
Farm.panelStatusLbl = nil
-- Error logger
Farm.logBuffer = {}
Farm.pendingCaptures = {}
Farm.blocksWritten = 0
Farm.lastWrittenByMsg = {}
Farm.knownNoted = {}
Farm.memLog = ""

----------------------------------------------------------------
-- Persistensi + auto-attach
----------------------------------------------------------------

-- Pastikan struktur settings farm ada (simpanan lama dari
-- versi suite sebelum modul ini ada belum punya kuncinya).
function Farm.ensureSettings()
	if type(S.settings[SETTING_MEMBER_FARM]) ~= "boolean" then
		S.settings[SETTING_MEMBER_FARM] = false
	end
end

-- Antrekan suite untuk termuat lagi setelah teleport/rejoin
-- berikutnya (self-requeue ala Infinite Yield). Aman dipanggil
-- berulang: antrean executor menimpa antrean sebelumnya.
function Farm.queueSelf()
	pcall(function()
		local q = queue_on_teleport or (syn and syn.queue_on_teleport)
			or (getgenv and getgenv().queue_on_teleport)
		if q then
			q(Farm.LOADSTRING)
			Farm.requeueArmed = true
		end
	end)
end

-- Antrekan ulang hanya bila otomatisasi masih menyala.
function Farm.queueSelfIfActive()
	Farm.ensureSettings()
	if S.settings[SETTING_MEMBER_FARM] then
		Farm.queueSelf()
	end
end

----------------------------------------------------------------
-- Pencarian remote Knit (pola v15: jalur langsung, lalu pindai)
----------------------------------------------------------------
function Farm.getSvc(service, kind, name)
	local ok, v = pcall(function()
		return RS.Packages._Index["sleitnick_knit@1.7.0"].knit.Services[service][kind][name]
	end)
	if ok and v then
		return v
	end
	local ok2, v2 = pcall(function()
		local packages = RS:FindFirstChild("Packages")
		if not packages then
			return nil
		end
		local index = packages:FindFirstChild("_Index")
		if not index then
			return nil
		end
		for _, folder in index:GetChildren() do
			if folder.Name:find("knit") then
				local path = folder:FindFirstChild("knit")
				if path then
					local svc = path:FindFirstChild("Services") and path.Services:FindFirstChild(service)
					if svc then
						local k = svc:FindFirstChild(kind)
						if k then
							return k:FindFirstChild(name)
						end
					end
				end
			end
		end
		return nil
	end)
	return ok2 and v2 or nil
end

function Farm.acquireRemotes()
	Farm.CreateHitbox = Farm.getSvc("BallService", "RF", "CreateHitbox")
	Farm.Interact = Farm.getSvc("BallService", "RF", "Interact")
	Farm.JumpRF = Farm.getSvc("BallService", "RF", "Jump")
	Farm.UpdateTilt = Farm.getSvc("BallService", "RF", "UpdateTilt")
	Farm.RequestJoin = Farm.getSvc("GameService", "RF", "RequestJoin")
	Farm.GameEndedRE = Farm.getSvc("GameService", "RE", "GameEnded")
	Farm.MatchReelRE = Farm.getSvc("GameService", "RE", "MatchReel")
	Farm.ReelFinishedRE = Farm.getSvc("GameService", "RE", "ReelFinished")
	Farm.CodeRedeem = Farm.getSvc("CodeService", "RF", "Redeem")
	Farm.DataGet = Farm.getSvc("DataService", "RF", "Get")
	Farm.LevelUpRE = Farm.getSvc("LevelService", "RE", "LevelUp")
	Farm.ProfileUpdatedRE = Farm.getSvc("DataService", "RE", "ProfileUpdated")
	Farm.ClaimRewardsRF = Farm.getSvc("LevelService", "RF", "ClaimLevelRewards")
	Farm.ClaimRewardsRE = Farm.getSvc("LevelService", "RE", "ClaimLevelRewards")
	local names = { "CreateHitbox", "Interact", "JumpRF", "UpdateTilt", "RequestJoin", "GameEndedRE", "MatchReelRE", "ReelFinishedRE", "CodeRedeem", "DataGet", "ClaimRewardsRF", "ClaimRewardsRE" }
	local found, missing = 0, {}
	for _, n in ipairs(names) do
		if Farm[n] then
			found += 1
		else
			table.insert(missing, n)
		end
	end
	print(("[VL Suite] farm remotes: %d/%d found%s"):format(found, #names,
		#missing > 0 and (" (missing: " .. table.concat(missing, ", ") .. ")") or ""))
	pcall(function()
		Farm.LevelTools = require(RS:WaitForChild("Tools"):WaitForChild("Level"))
	end)
end

----------------------------------------------------------------
-- GUI farm kecil (panel v15: toggle + interval + status)
----------------------------------------------------------------
function Farm.setStatus(txt)
	if Farm.statusLbl then
		Farm.statusLbl.Text = "AUTO: " .. txt
	end
	Farm.statusText = txt
	if Farm.panelStatusLbl then
		Farm.panelStatusLbl.Text = "Status: " .. txt
	end
	print("[AUTO] " .. txt)
end

function Farm.setToggle(name, on)
	Farm.flags[name] = on == true
	local b = Farm.togButtons[name]
	if b then
		b.Text = name .. " " .. (Farm.flags[name] and "ON" or "OFF")
		b.BackgroundColor3 = Farm.flags[name] and Color3.fromRGB(0, 140, 0) or Color3.fromRGB(55, 55, 55)
	end
end

function Farm.buildGui()
	if Farm.gui then
		return
	end
	local pg = player:WaitForChild("PlayerGui")
	local sg = Instance.new("ScreenGui")
	sg.Name = "VLFarmGui"
	sg.ResetOnSpawn = false
	sg.Enabled = false
	sg.Parent = pg

	local f = Instance.new("Frame")
	f.Size = UDim2.new(0, 150, 0, 235)
	f.Position = UDim2.new(0.05, 0, 0.3, 0)
	f.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	f.BorderSizePixel = 0
	f.Active = true
	f.Draggable = true
	f.Parent = sg

	local function mkTog(y, txt)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0, 65, 0, 24)
		b.Position = UDim2.new(0, 8, 0, y)
		b.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
		b.Text = txt .. " OFF"
		b.TextColor3 = Color3.new(1, 1, 1)
		b.TextSize = 12
		b.Font = Enum.Font.SourceSansBold
		b.Parent = f
		b.MouseButton1Click:Connect(function()
			Farm.setToggle(txt, not Farm.flags[txt])
		end)
		Farm.togButtons[txt] = b
		return b
	end
	mkTog(8, "TP")
	mkTog(36, "BALL")
	mkTog(64, "SPIKE")
	mkTog(92, "JUMP")

	local tb = Instance.new("TextBox")
	tb.Size = UDim2.new(0, 134, 0, 24)
	tb.Position = UDim2.new(0, 8, 0, 122)
	tb.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	tb.Text = "0"
	tb.PlaceholderText = "interval"
	tb.TextColor3 = Color3.new(1, 1, 1)
	tb.TextSize = 13
	tb.Font = Enum.Font.SourceSans
	tb.ClearTextOnFocus = false
	tb.Parent = f
	tb:GetPropertyChangedSignal("Text"):Connect(function()
		Farm.intervalText = tb.Text
	end)

	local statusLbl = Instance.new("TextLabel")
	statusLbl.Size = UDim2.new(0, 134, 0, 48)
	statusLbl.Position = UDim2.new(0, 8, 0, 180)
	statusLbl.BackgroundTransparency = 1
	statusLbl.Text = "AUTO: idle"
	statusLbl.TextColor3 = Color3.fromRGB(180, 180, 180)
	statusLbl.TextSize = 11
	statusLbl.Font = Enum.Font.SourceSans
	statusLbl.TextWrapped = true
	statusLbl.TextXAlignment = Enum.TextXAlignment.Left
	statusLbl.TextYAlignment = Enum.TextYAlignment.Top
	statusLbl.Parent = f
	Farm.statusLbl = statusLbl
	Farm.gui = sg
end

function Farm.setGuiVisible(v)
	Farm.buildGui()
	if Farm.gui then
		Farm.gui.Enabled = v == true
	end
	if Farm.overlayGui then
		Farm.overlayGui.Enabled = v == true
	end
end

----------------------------------------------------------------
-- Helper farm (dari v15)
----------------------------------------------------------------
function Farm.getBall()
	for _, v in workspace:GetDescendants() do
		if typeof(v.Name) == "string" and v.Name:sub(1, 12) == "CLIENT_BALL_" then
			local part = v:IsA("BasePart") and v or v:FindFirstChildWhichIsA("BasePart", true)
			if part then
				local id = v:GetAttribute("ServerId")
					or part:GetAttribute("ServerId")
					or v:GetAttribute("Id")
					or part:GetAttribute("Id")
					or tonumber(v.Name:sub(13))
				if id then
					return part, id
				end
			end
		end
	end
	return nil, 0
end

function Farm.getHRP()
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

function Farm.getTimestamp()
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and typeof(t) == "number" then
		return t
	end
	return tick()
end

-- TP ultra-cepat ke bola (tiap frame, hanya bila toggle TP on).
function Farm.startTpLoop()
	Farm.RunService.Heartbeat:Connect(function()
		if not Farm.flags.TP then
			return
		end
		local ball = select(1, Farm.getBall())
		local hrp = Farm.getHRP()
		if ball and hrp then
			pcall(function()
				hrp.CFrame = ball.CFrame
			end)
		end
	end)
end

-- Satu percobaan Block = CreateHitbox + Interact("Block") +
-- UpdateTilt; dijalankan di thread sendiri (paralel).
function Farm.doBlock(ball, bid, look, move)
	local tilt = Vector3.new(0, 1, 0)
	local ts = Farm.getTimestamp()
	local key = "Block" .. math.random(1000000, 9999999)
	pcall(function()
		Farm.CreateHitbox:InvokeServer({
			BallId = bid,
			Charge = 1,
			Key = key,
			ClientTimestamp = ts,
			Move = "Block",
		})
	end)
	pcall(function()
		Farm.Interact:InvokeServer({
			Charge = 1,
			Move = "Block",
			SpecialCharge = 0,
			TiltDirection = tilt,
			BallId = bid,
			MoveDirection = move,
			Key = key,
			From = "Client",
			LookVector = look,
			Timestamp = ts,
			ClientCanRunSpecial = false,
			CustomClient = {},
		})
	end)
	if Farm.UpdateTilt then
		pcall(function()
			Farm.UpdateTilt:InvokeServer(tilt)
		end)
	end
end

-- Loop aksi farm: Block paralel / Spike manual / Jump, mengikuti
-- toggle GUI; interval dari kotak interval (default 0).
function Farm.startActionLoop()
	task.spawn(function()
		while true do
			local waitT = tonumber(Farm.intervalText) or 0
			local ball, bid = Farm.getBall()
			local hrp = Farm.getHRP()
			local cam = workspace.CurrentCamera
			local look = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)
			local move = hrp and hrp.CFrame.LookVector or Vector3.zero
			local ts = Farm.getTimestamp()

			if Farm.flags.BALL then
				if bid == 0 or not ball then
					if tick() - Farm.lastPrint > 1 then
						print("[BLOCK] No BID / ball found")
						Farm.lastPrint = tick()
					end
				elseif not Farm.CreateHitbox or not Farm.Interact then
					if tick() - Farm.lastPrint > 1 then
						print("[BLOCK] Missing remote(s)")
						Farm.lastPrint = tick()
					end
				else
					if tick() - Farm.lastPrint > 1 then
						print("[BLOCK] Using BallId:", bid)
						Farm.lastPrint = tick()
					end
					task.spawn(Farm.doBlock, ball, bid, look, move)
				end
			end

			if Farm.flags.SPIKE then
				if bid == 0 or not ball then
					if tick() - Farm.lastPrint > 1 then
						print("[SPIKE] No BID / ball found")
						Farm.lastPrint = tick()
					end
				elseif not Farm.Interact then
					if tick() - Farm.lastPrint > 1 then
						print("[SPIKE] Missing Interact remote")
						Farm.lastPrint = tick()
					end
				else
					if tick() - Farm.lastPrint > 1 then
						print("[SPIKE] Using BallId:", bid)
						Farm.lastPrint = tick()
					end
					local realTilt = Vector3.new(look.X, 1, look.Z)
					pcall(function()
						Farm.Interact:InvokeServer({
							Charge = 1,
							Move = "Spike",
							SpecialCharge = 0,
							TiltDirection = realTilt,
							LookVector = look,
							MoveDirection = move,
							ClientCanRunSpecial = false,
							From = "Client",
							Timestamp = ts,
							BallId = bid,
							CustomClient = {},
						})
					end)
					if Farm.UpdateTilt then
						pcall(function()
							Farm.UpdateTilt:InvokeServer(realTilt)
						end)
					end
				end
			end

			if Farm.flags.JUMP and Farm.JumpRF then
				Farm.jumpState = not Farm.jumpState
				pcall(function()
					Farm.JumpRF:InvokeServer(Farm.jumpState)
				end)
			end

			task.wait(waitT)
		end
	end)
end

----------------------------------------------------------------
-- Mode performa game (FastMode + UltraFastMode, sekali di init)
----------------------------------------------------------------
function Farm.applyPerfModesOnce()
	local remoteOk = false
	pcall(function()
		local svc = Knit.GetService("SettingsService")
		svc:ChangeSetting("FastMode", true)
		svc:ChangeSetting("UltraFastMode", true)
		remoteOk = true
	end)
	pcall(function()
		local ctrl = Knit.GetController("SettingsController")
		ctrl:ApplySetting("FastMode", true)
		ctrl:ApplySetting("UltraFastMode", true)
	end)
	return remoteOk
end

function Farm.startPerfModes()
	if not Farm.ENABLE_PERF_MODES then
		return
	end
	task.spawn(function()
		for _ = 1, 20 do
			if Farm.applyPerfModesOnce() then
				print("[PERF] FastMode + UltraFastMode ON (via SettingsService)")
				return
			end
			task.wait(1)
		end
		print("[PERF] FastMode + UltraFastMode applied locally only (SettingsService unreachable after retries)")
	end)
end

----------------------------------------------------------------
-- Otomatisasi: join -> farm -> post-match -> reset -> ulang
----------------------------------------------------------------
function Farm.autoOn()
	return Farm.running
end

function Farm.inGame()
	return player:GetAttribute("Gameplay_InGame") == true
end

function Farm.setFarm(on)
	Farm.setToggle("TP", on)
	Farm.setToggle("BALL", on) -- toggle BALL = farm Block
	Farm.setToggle("SPIKE", false) -- farm AUTO hanya Block
	if Farm.CFG.AlsoFarmJump then
		Farm.setToggle("JUMP", on)
	end
end

-- Sentuh pad portal Play sekali (menu pilih tim game terbuka
-- dari pad ini; juga menaruh kita di dekat lapangan).
function Farm.tpToPortal()
	local ok, tagged = pcall(function()
		return CollectionService:GetTagged("PlayPortalTouchpad")
	end)
	if ok and tagged and tagged[1] then
		local pad = tagged[1]
		local hrp = Farm.getHRP()
		if hrp and pad:IsA("BasePart") then
			pcall(function()
				hrp.CFrame = pad.CFrame + Vector3.new(0, 3, 0)
			end)
			return true
		end
	end
	return false
end

function Farm.tryJoinSweep()
	if not Farm.RequestJoin then
		return false
	end
	for team = 1, 2 do
		for pos = 1, Farm.CFG.Positions do
			if not Farm.autoOn() then
				return false
			end
			local ok, res = pcall(function()
				return Farm.RequestJoin:InvokeServer(team, pos)
			end)
			if ok and res then
				print(("[AUTO] RequestJoin OK: team %d, position %d"):format(team, pos))
				return true
			end
		end
	end
	return false
end

----------------------------------------------------------------
-- Helper klik GUI (SKIP replay + tombol Back summary)
----------------------------------------------------------------
function Farm.effectivelyVisible(obj)
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local o = obj
	while o and o ~= pg do
		if o:IsA("GuiObject") and not o.Visible then
			return false
		end
		if o:IsA("ScreenGui") and not o.Enabled then
			return false
		end
		o = o.Parent
	end
	return true
end

function Farm.clickButton(btn)
	if not btn then
		return false
	end
	if typeof(firesignal) == "function" then
		if pcall(firesignal, btn.Activated) then
			return true
		end
	end
	if typeof(getconnections) == "function" then
		local ok, conns = pcall(getconnections, btn.Activated)
		if ok and conns and #conns > 0 then
			for _, c in conns do
				pcall(function()
					c:Fire()
				end)
			end
			return true
		end
	end
	if pcall(function()
		btn:Activate()
	end) then
		return true
	end
	local ok = pcall(function()
		local pos, size = btn.AbsolutePosition, btn.AbsoluteSize
		local x, y = pos.X + size.X / 2, pos.Y + size.Y / 2
		Farm.VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
		Farm.VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
	end)
	return ok
end

function Farm.findReplaySkipButton()
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local gui = pg and pg:FindFirstChild("ReplaySkip")
	if not gui then
		return nil
	end
	for _, d in gui:GetDescendants() do
		if d:IsA("GuiButton") and Farm.effectivelyVisible(d) then
			return d
		end
	end
	return nil
end

-- Sidik jari layar summary: BackBtn di dalam ReturnContainer
-- yang juga memuat RequeueBtn, di bawah root berisi
-- YenAmountButton.
function Farm.findSummaryBackButton()
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	for _, d in pg:GetDescendants() do
		if d.Name == "BackBtn" and d:IsA("GuiButton") then
			local rc = d.Parent
			if rc and rc.Name == "ReturnContainer" and rc:FindFirstChild("RequeueBtn") then
				local root = rc.Parent
				if root and root:FindFirstChild("YenAmountButton", true) and Farm.effectivelyVisible(d) then
					return d
				end
			end
		end
	end
	return nil
end

-- Fase post-match: lewati replay, lalu tutup layar summary.
-- Urutan game: GameEnded -> cutscene -> replay (SKIP) -> summary.
function Farm.handlePostMatch()
	local start = tick()
	local sawAny = false
	local absentSince = nil
	local lastClickSkip, lastClickBack = 0, 0
	local reelFallbackDone = false
	while Farm.autoOn() do
		local now = tick()
		if now - start > Farm.CFG.PostTimeoutSeconds then
			print("[AUTO] Post-match timeout, moving on")
			break
		end
		local skipBtn = Farm.findReplaySkipButton()
		if skipBtn then
			sawAny = true
			absentSince = nil
			if now - lastClickSkip > 1 then
				lastClickSkip = now
				print("[AUTO] Replay SKIP button found, clicking")
				Farm.clickButton(skipBtn)
			end
		end
		local backBtn = Farm.findSummaryBackButton()
		if backBtn then
			sawAny = true
			absentSince = nil
			if now - lastClickBack > 1 then
				lastClickBack = now
				print("[AUTO] Summary screen found, clicking Back")
				Farm.clickButton(backBtn)
			end
		end
		-- Reel jalan tapi tombol SKIP tidak pernah muncul: beri
		-- tahu server kita selesai, seperti yang dilakukan skip.
		if Farm.reelActive and not reelFallbackDone and not skipBtn and Farm.ReelFinishedRE
			and now - Farm.reelStartedAt > Farm.CFG.ReelSkipFallbackSeconds then
			reelFallbackDone = true
			sawAny = true
			print("[AUTO] No SKIP button for " .. Farm.CFG.ReelSkipFallbackSeconds .. "s, firing ReelFinished directly")
			pcall(function()
				Farm.ReelFinishedRE:FireServer(true, false, {
					watch_seconds = math.floor(now - Farm.reelStartedAt),
					reel_duration_seconds = 0,
					clip_count = 0,
				})
			end)
		end
		if not skipBtn and not backBtn then
			absentSince = absentSince or now
			if sawAny and now - absentSince >= Farm.CFG.PostStableSeconds then
				print("[AUTO] Post-match screens cleared")
				break
			end
			if not sawAny and now - start >= Farm.CFG.PostNothingSeconds then
				print("[AUTO] No post-match screens appeared, moving on")
				break
			end
		end
		task.wait(0.5)
	end
	Farm.reelActive = false
end

function Farm.resetAndRespawn()
	local newChar = nil
	local conn = player.CharacterAdded:Connect(function(c)
		newChar = c
	end)
	local char = player.Character
	if char then
		pcall(function()
			char:BreakJoints()
		end)
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			pcall(function()
				hum.Health = 0
			end)
		end
	end
	local t0 = tick()
	while not newChar and tick() - t0 < 15 do
		task.wait(0.2)
	end
	conn:Disconnect()
	if newChar then
		newChar:WaitForChild("HumanoidRootPart", 10)
		task.wait(1)
		return true
	end
	return false
end

-- Tutup menu pilih tim dengan benar: join lewat RequestJoin
-- tidak menutupnya (klik slot yang menutup), jadi panggil
-- Close(true) milik TeamSelectionController sendiri (juga
-- memulihkan kamera/FOV + visibilitas App).
function Farm.findTeamReturnButton()
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	for _, d in pg:GetDescendants() do
		if d.Name == "TeamSelection" and d:IsA("GuiObject") and Farm.effectivelyVisible(d) then
			local btn = d:FindFirstChild("Return", true)
			if btn and btn:IsA("GuiButton") then
				return btn
			end
		end
	end
	return nil
end

function Farm.closeTeamMenu()
	local closed = false
	pcall(function()
		local tsc = Knit.GetController("TeamSelectionController")
		if tsc and tsc.Close then
			tsc:Close(true)
			closed = true
		end
	end)
	if closed then
		print("[AUTO] Menu pilih team ditutup (Knit controller)")
		return true
	end
	pcall(function()
		local controllers = ReplicatedFirst:WaitForChild("Controllers", 2)
		local mod = controllers and controllers:WaitForChild("TeamSelectionController", 2)
		if mod then
			local tsc = require(mod)
			if tsc and tsc.Close then
				tsc:Close(true)
				closed = true
			end
		end
	end)
	if closed then
		print("[AUTO] Menu pilih team ditutup (require controller)")
		return true
	end
	local btn = Farm.findTeamReturnButton()
	if btn and Farm.clickButton(btn) then
		print("[AUTO] Menu pilih team ditutup (klik Return)")
		return true
	end
	print("[AUTO] Menu pilih team: tidak ada yang perlu ditutup / cara menutup tidak ditemukan")
	return false
end

----------------------------------------------------------------
-- Handler serve (di fase farm, saat giliran serve kita)
-- Deteksi: atribut state pemain berakhiran "IsServing"
-- (fallback: States.IsServing milik GameController Handlers).
-- Urutan (meniru tutorial SpikeServe game sendiri):
--   Toss 1 -> power ball; Toss 2 -> bola terlempar +
--   GameService:Serve; melangkah ke bawah bola -> Jump ->
--   burst Spike di apex lompatan.
----------------------------------------------------------------
function Farm.isServing()
	for k, v in pairs(player:GetAttributes()) do
		if typeof(k) == "string" and k:sub(-9) == "IsServing" and v == true then
			return true
		end
	end
	if Farm.handlersModule == nil then
		pcall(function()
			local controllers = ReplicatedFirst:FindFirstChild("Controllers")
			local gc = controllers and controllers:FindFirstChild("GameController")
			local h = gc and gc:FindFirstChild("Handlers")
			if h then
				Farm.handlersModule = require(h)
			end
		end)
		Farm.handlersModule = Farm.handlersModule or false
	end
	if Farm.handlersModule then
		local ok, val = pcall(function()
			return Farm.handlersModule.States.IsServing:get()
		end)
		if ok and val == true then
			return true
		end
	end
	return false
end

function Farm.isHitting()
	for k, v in pairs(player:GetAttributes()) do
		if typeof(k) == "string" and k:sub(-9) == "IsHitting" and v == true then
			return true
		end
	end
	return false
end

function Farm.pressToss()
	-- 1) Handler Toss milik game sendiri (fungsi yang sama
	--    dengan penekanan tombol Toss asli).
	local ok = pcall(function()
		local node = ReplicatedFirst
		for _, name in ipairs({ "Controllers", "GameController", "Actions", "Binding", "Registry", "Toss" }) do
			node = node and node:FindFirstChild(name)
		end
		if not node then
			error("Toss module not found")
		end
		local reg = require(node)
		if not (reg and reg.onTossRequest) then
			error("onTossRequest missing")
		end
		reg.onTossRequest(Enum.UserInputState.Begin)
	end)
	if ok then
		return "handler Toss"
	end
	-- 2) Tombol Toss di layar (UI aksi mobile).
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg then
		for _, d in pg:GetDescendants() do
			if d.Name == "Toss" and d:IsA("GuiButton") and Farm.effectivelyVisible(d) then
				if Farm.clickButton(d) then
					return "tombol Toss di layar"
				end
				break
			end
		end
	end
	return nil
end

-- Jalan terakhir bila kedua penekanan Toss gagal: panggil Serve
-- yang sama seperti executeToss game (arah nol = default, power
-- tengah).
function Farm.serveDirect()
	local ok = pcall(function()
		local gs = Knit.GetService("GameService")
		gs:Serve(Vector3.new(0, 0, 0), 50)
	end)
	print("[SERVE] Fallback Serve langsung via GameService:", ok and "terkirim" or "gagal")
	return ok
end

function Farm.fireJumpTap()
	if not Farm.JumpRF then
		return
	end
	Farm.jumpState = not Farm.jumpState
	pcall(function()
		Farm.JumpRF:InvokeServer(Farm.jumpState)
	end)
	task.wait(0.15)
	Farm.jumpState = not Farm.jumpState
	pcall(function()
		Farm.JumpRF:InvokeServer(Farm.jumpState)
	end)
end

function Farm.serveSpikeBurst(duration)
	local t0 = tick()
	while tick() - t0 < duration and Farm.autoOn() and not Farm.matchEnded do
		local ball, bid = Farm.getBall()
		local hrp = Farm.getHRP()
		if ball and bid ~= 0 and Farm.Interact then
			local cam = workspace.CurrentCamera
			local look = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)
			local move = hrp and hrp.CFrame.LookVector or Vector3.zero
			local realTilt = Vector3.new(look.X, 1, look.Z)
			local ts = Farm.getTimestamp()
			pcall(function()
				Farm.Interact:InvokeServer({
					Charge = 1,
					Move = "Spike",
					SpecialCharge = 0,
					TiltDirection = realTilt,
					LookVector = look,
					MoveDirection = move,
					ClientCanRunSpecial = false,
					From = "Client",
					Timestamp = ts,
					BallId = bid,
					CustomClient = {},
				})
			end)
			if Farm.UpdateTilt then
				pcall(function()
					Farm.UpdateTilt:InvokeServer(realTilt)
				end)
			end
		end
		task.wait(0.03)
	end
end

function Farm.handleServe()
	if Farm.serveBusy then
		return
	end
	Farm.serveBusy = true
	local ran = pcall(function()
		print("[SERVE] Giliran serve kita - handler serve jalan, farm dijeda")
		Farm.setStatus("giliran serve: toss, jump, spike...")
		Farm.setFarm(false) -- TP akan menempel ke bola di tangan; spam Block tak berguna di sini
		task.wait(0.3)
		if not Farm.autoOn() or Farm.matchEnded then
			return
		end
		if not Farm.isServing() then
			print("[SERVE] Status serve sudah hilang sebelum mulai, batal")
			return
		end

		local via1 = Farm.pressToss()
		print("[SERVE] Toss #1 (power ball):", via1 or "GAGAL")
		task.wait(Farm.CFG.ServePowerWait)
		if not Farm.autoOn() or Farm.matchEnded then
			return
		end
		local via2 = Farm.pressToss()
		print("[SERVE] Toss #2 (lempar bola):", via2 or "GAGAL")
		if not via1 and not via2 then
			Farm.serveDirect()
		end

		-- Bola di udara sekarang: melangkah ke bawahnya, lompat,
		-- spike di apex.
		task.wait(Farm.CFG.ServeJumpDelay)
		local ball = select(1, Farm.getBall())
		local hrp = Farm.getHRP()
		if ball and hrp then
			pcall(function()
				local rot = hrp.CFrame - hrp.CFrame.Position
				hrp.CFrame = CFrame.new(Vector3.new(ball.Position.X, hrp.Position.Y, ball.Position.Z)) * rot
			end)
		end
		Farm.fireJumpTap()
		task.wait(Farm.CFG.ServeApexWait)
		Farm.serveSpikeBurst(0.5)

		local hit = Farm.isHitting()
		local ballNow = select(1, Farm.getBall())
		local fast = ballNow and ballNow.AssemblyLinearVelocity.Magnitude > 25 or false
		print(("[SERVE] Selesai. IsHitting terdeteksi: %s | bola meluncur cepat: %s"):format(tostring(hit), tostring(fast)))
	end)
	if not ran then
		print("[SERVE] Handler serve error (detail error ada di console / error log)")
	end
	-- Tunggu status serve hilang agar tidak langsung terpicu
	-- lagi; bila tidak hilang (toss gagal), loop farm memanggil
	-- kita lagi.
	local t0 = tick()
	while Farm.autoOn() and Farm.isServing() and tick() - t0 < 4 do
		task.wait(0.25)
	end
	if Farm.autoOn() and not Farm.matchEnded then
		Farm.setFarm(true)
		Farm.setStatus("di dalam match, farming (Block only)...")
	end
	Farm.serveBusy = false
end

----------------------------------------------------------------
-- Loop utama AUTO (thread sendiri; diam saat AUTO mati)
----------------------------------------------------------------
function Farm.startMainLoop()
	task.spawn(function()
		while true do
			task.wait(0.5)
			if not Farm.autoOn() then
				continue
			end

			------------------------------------------------ JOIN
			Farm.setStatus("mencari match (RequestJoin)...")
			Farm.matchEnded = false
			local joined = Farm.inGame()
			if joined then
				print("[AUTO] Gameplay_InGame already true, skipping join")
			else
				Farm.tpToPortal()
			end
			local ballSeenSweeps = 0
			while Farm.autoOn() and not joined do
				joined = Farm.tryJoinSweep()
				if not joined and Farm.inGame() then
					joined = true
					break
				end
				if not joined then
					-- Sudah di dalam match (AUTO dinyalakan di
					-- tengah game)? RequestJoin terus gagal, tapi
					-- bola hidup: setelah 3 sweep ada bola, anggap
					-- sudah masuk dan lanjut farm.
					if select(1, Farm.getBall()) then
						ballSeenSweeps += 1
						if ballSeenSweeps >= 3 then
							print("[AUTO] Ball live but joins rejected; assuming already in match")
							joined = true
							break
						end
					else
						ballSeenSweeps = 0
					end
					task.wait(Farm.CFG.JoinSweepWait)
				end
			end
			if not Farm.autoOn() then
				Farm.setFarm(false)
				continue
			end
			-- Join lewat pad portal membuka menu tim: tutup seperti
			-- klik slot, lalu sekali lagi tak lama kemudian (event
			-- Touched yang membukanya bisa tiba setelah join).
			task.wait(0.5)
			Farm.closeTeamMenu()
			task.delay(2, function()
				if Farm.autoOn() then
					Farm.closeTeamMenu()
				end
			end)

			------------------------------------------------ FARM
			Farm.setStatus("di dalam match, farming (Block only)...")
			Farm.matchEnded = false -- abaikan GameEnded dari sebelum kita join
			Farm.setFarm(true)
			local farmStart = tick()
			local noBallSince = nil
			local wasInGame = Farm.inGame()
			local outSince = nil
			while Farm.autoOn() and not Farm.matchEnded do
				if Farm.CFG.ServeEnabled and Farm.isServing() then
					Farm.handleServe()
				end
				-- Level 15 tercapai di tengah match? Keluar match:
				-- fase RESET me-respawn kita, kode di-redeem tepat
				-- setelahnya.
				if Farm.pendingRespawnRedeem then
					print("[AUTO] Level 15 tercapai di match - keluar untuk respawn + redeem")
					break
				end
				if tick() - farmStart > Farm.CFG.MaxMatchSeconds then
					print("[AUTO] MaxMatchSeconds reached, treating as ended")
					break
				end
				local ig = player:GetAttribute("Gameplay_InGame")
				if ig == true then
					wasInGame = true
					outSince = nil
				elseif ig == false and wasInGame then
					outSince = outSince or tick()
					if tick() - outSince > 5 then
						print("[AUTO] Gameplay_InGame turned false, match over")
						break
					end
				end
				local ball = select(1, Farm.getBall())
				if ball then
					noBallSince = nil
				else
					noBallSince = noBallSince or tick()
					if tick() - noBallSince > Farm.CFG.NoBallEndSeconds and tick() - farmStart > 30 then
						print("[AUTO] No ball for " .. Farm.CFG.NoBallEndSeconds .. "s, treating as ended")
						break
					end
				end
				task.wait(1)
			end
			Farm.setFarm(false)
			if not Farm.autoOn() then
				continue
			end

			------------------------------------------------ POST-MATCH
			if Farm.pendingRespawnRedeem then
				print("[AUTO] Skip post-match (respawn untuk redeem level 15)")
			else
				Farm.setStatus("match selesai, skip replay + summary...")
				Farm.handlePostMatch()
			end
			if not Farm.autoOn() then
				continue
			end

			------------------------------------------------ RESET
			Farm.setStatus("reset karakter...")
			Farm.resetAndRespawn()
			if Farm.pendingRespawnRedeem then
				Farm.pendingRespawnRedeem = false
				print("[AUTO] Respawn selesai - redeem code sekarang")
				if Farm.redeemSignal then
					Farm.redeemSignal()
				end
			end
			Farm.setStatus("respawn selesai, loop lagi...")
			task.wait(2)
		end
	end)
end

-- Koneksi event match (dipasang sekali di init).
function Farm.connectMatchEvents()
	if Farm.eventsConnected then
		return
	end
	Farm.eventsConnected = true
	if Farm.GameEndedRE then
		Farm.GameEndedRE.OnClientEvent:Connect(function()
			Farm.matchEnded = true
			print("[AUTO] GameEnded event received")
		end)
	end
	if Farm.MatchReelRE then
		Farm.MatchReelRE.OnClientEvent:Connect(function()
			Farm.reelActive = true
			Farm.reelStartedAt = tick()
			print("[AUTO] MatchReel received (replay starting)")
		end)
	end
	pcall(function()
		RS:GetAttributeChangedSignal("RoundState"):Connect(function()
			print("[AUTO] RoundState ->", RS:GetAttribute("RoundState"))
		end)
		print("[AUTO] RoundState now:", RS:GetAttribute("RoundState"))
	end)
end

-- Saklar utama AUTO: persisten + auto-attach + tampilkan GUI.
function Farm.setEnabled(on)
	Farm.ensureSettings()
	Farm.running = on == true
	S.settings[SETTING_MEMBER_FARM] = Farm.running
	S.autoFarmRunning = Farm.running
	saveLocal()
	if Farm.running then
		Farm.queueSelf()
		Farm.setGuiVisible(true)
		Farm.setStatus("AUTO dinyalakan")
	else
		Farm.setFarm(false)
		Farm.setStatus("AUTO dimatikan")
	end
	Farm.refreshPanel()
end

----------------------------------------------------------------
-- Overlay progres level 15 + klaim reward + redeem kode
-- Level dari atribut pemain "User_Level" (yang sama yang diikat
-- UI game); progres XP memakai Tools.Level + DataService
-- "Career", persis seperti bar level game sendiri.
-- Aturan redeem (identik v15):
--   * Sudah level 15 / tercapai di luar match: redeem langsung.
--   * Tercapai DI TENGAH match: jangan redeem dulu -- tandai
--     pendingRespawnRedeem; loop AUTO keluar match, respawn,
--     lalu redeem. Bila AUTO mati, thread koordinator di bawah
--     yang me-respawn lalu redeem.
----------------------------------------------------------------
function Farm.readLevelAttr()
	local v = player:GetAttribute("User_Level")
	if typeof(v) == "number" then
		return v
	end
	-- Terima juga atribut numerik apa pun berakhiran "_Level"
	-- (awalan kunci state diisi saat runtime; trik akhiran yang
	-- sama seperti deteksi IsServing).
	local best = nil
	for k, val in pairs(player:GetAttributes()) do
		if typeof(k) == "string" and k:sub(-6) == "_Level" and typeof(val) == "number" then
			if not best or val > best then
				best = val
			end
		end
	end
	if best then
		return best
	end
	local ls = player:FindFirstChild("leaderstats")
	local lv = ls and ls:FindFirstChild("Level")
	if lv and typeof(lv.Value) == "number" then
		return lv.Value
	end
	return nil
end

function Farm.refreshXP()
	if not (Farm.LevelTools and Farm.DataGet) then
		return
	end
	local ok, career = pcall(function()
		return Farm.DataGet:InvokeServer("Career")
	end)
	if ok and typeof(career) == "table" then
		local ok2, xp = pcall(function()
			return Farm.LevelTools.evaluateExperience(career)
		end)
		if ok2 and typeof(xp) == "number" then
			Farm.curXP = xp
		end
	end
end

-- Klaim SEMUA reward level yang tertunda dengan panggilan game
-- sendiri: tombol Claim di layar Level Rewards memanggil
-- LevelService:ClaimLevelRewards() tanpa argumen.
function Farm.claimLevelRewards()
	if Farm.ClaimRewardsRF then
		local ok, res = pcall(function()
			return Farm.ClaimRewardsRF:InvokeServer()
		end)
		print("[REWARD] ClaimLevelRewards via RF:", ok and "OK" or "error", res)
		return ok
	end
	if Farm.ClaimRewardsRE then
		local ok = pcall(function()
			Farm.ClaimRewardsRE:FireServer()
		end)
		print("[REWARD] ClaimLevelRewards via RE:", ok and "terkirim" or "error")
		return ok
	end
	print("[REWARD] Remote ClaimLevelRewards tidak ditemukan (RF maupun RE)")
	return false
end

function Farm.startRedeem()
	if Farm.redeemDone or Farm.redeemRunning then
		return
	end
	if not Farm.CodeRedeem then
		Farm.redeemState = "CodeService.Redeem tidak ditemukan"
		Farm.redeemDone = true
		return
	end
	Farm.redeemRunning = true
	Farm.redeemState = "claim level rewards + redeem code..."
	task.spawn(function()
		local claimOk = Farm.claimLevelRewards()
		task.wait(1)
		local parts = {}
		for _, code in ipairs(Farm.REDEEM_CODES) do
			local res = { pcall(function()
				return Farm.CodeRedeem:InvokeServer(code)
			end) }
			if res[1] and res[2] == true then
				table.insert(parts, code .. " OK")
				print("[REDEEM] " .. code .. " -> OK:", res[3])
			elseif res[1] then
				table.insert(parts, code .. " gagal")
				print("[REDEEM] " .. code .. " -> gagal:", res[3])
			else
				table.insert(parts, code .. " error")
				print("[REDEEM] " .. code .. " -> error:", res[2])
			end
			task.wait(2)
		end
		Farm.redeemState = (claimOk and "Level rewards: OK | " or "Level rewards: ? | ") .. "Codes: " .. table.concat(parts, " | ")
		Farm.redeemDone = true
		Farm.redeemRunning = false
	end)
end

function Farm.tryAutoRedeem()
	if Farm.redeemDone or Farm.redeemRunning then
		return
	end
	-- Nilai HANYA dari bacaan level yang TERKONFIRMASI. Tepat
	-- setelah script mulai, level sempat belum diketahui
	-- (curLevel masih 0 bawaan sementara atribut/data belum
	-- tereplikasi). Menghitung keadaan tak-diketahui itu sebagai
	-- "di bawah 15" meracuni baseline: level asli lalu tampak
	-- seperti naik level di tengah match, dan alur respawn-first
	-- terpicu untuk pemain yang SUDAH level 15 sebelum match.
	if not Farm.levelConfirmed then
		return
	end
	if Farm.curLevel < Farm.TARGET_LEVEL then
		Farm.levelBaselineKnown = true
		Farm.wasBelowTarget = true
		return
	end
	if not Farm.levelBaselineKnown then
		Farm.levelBaselineKnown = true
		Farm.wasBelowTarget = false
	end
	if Farm.pendingRespawnRedeem then
		return
	end
	if Farm.wasBelowTarget and Farm.inGame() then
		Farm.pendingRespawnRedeem = true
		Farm.redeemState = "Level 15 tercapai di match! Respawn dulu, baru redeem..."
		print("[REDEEM] Level 15 tercapai di dalam match - respawn dulu, baru redeem")
		return
	end
	Farm.startRedeem()
end

function Farm.refreshOverlay()
	if not Farm.ovLevel then
		return
	end
	local lv = Farm.readLevelAttr()
	if lv then
		Farm.curLevel = lv
		Farm.levelConfirmed = true
	end
	if Farm.curXP and Farm.LevelTools then
		local ok, fromXp = pcall(function()
			return Farm.LevelTools.fromExperience(Farm.curXP)
		end)
		if ok and typeof(fromXp) == "number" then
			Farm.levelConfirmed = true
			if fromXp > Farm.curLevel then
				Farm.curLevel = fromXp
			end
		end
	end
	local frac
	if Farm.curLevel >= Farm.TARGET_LEVEL then
		frac = 1
	elseif Farm.curXP and Farm.LevelTools then
		local ok, need = pcall(function()
			return Farm.LevelTools.toExperience(Farm.TARGET_LEVEL)
		end)
		if ok and typeof(need) == "number" and need > 0 then
			frac = math.clamp(Farm.curXP / need, 0, 1)
		end
	end
	if not frac then
		frac = math.clamp(Farm.curLevel / Farm.TARGET_LEVEL, 0, 1)
	end
	Farm.ovLevel.Text = "Level " .. Farm.curLevel .. " / " .. Farm.TARGET_LEVEL
	Farm.barFill.Size = UDim2.fromScale(frac, 1)
	if Farm.curLevel >= Farm.TARGET_LEVEL then
		Farm.ovSub.Text = "Target tercapai! (" .. math.floor(frac * 100) .. "%)"
	else
		local xpTxt = ""
		if Farm.curXP and Farm.LevelTools then
			local ok, need = pcall(function()
				return Farm.LevelTools.toExperience(Farm.TARGET_LEVEL)
			end)
			if ok and typeof(need) == "number" then
				xpTxt = ("XP %d / %d - "):format(Farm.curXP, need)
			end
		end
		Farm.ovSub.Text = xpTxt .. math.floor(frac * 100) .. "% - sisa " .. (Farm.TARGET_LEVEL - Farm.curLevel) .. " level lagi"
	end
	Farm.ovStatus.Text = Farm.redeemState
	Farm.tryAutoRedeem()
end

function Farm.buildOverlay()
	if Farm.overlayGui then
		return
	end
	local pg = player:WaitForChild("PlayerGui")
	local og = Instance.new("ScreenGui")
	og.Name = "VLFarmOverlay"
	og.ResetOnSpawn = false
	og.DisplayOrder = 100
	og.Enabled = false
	og.Parent = pg

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	-- Panel + console di bawahnya terpusat sebagai SATU grup
	-- (268 px), jadi tidak ada yang keluar layar.
	panel.Position = UDim2.new(0.5, 0, 0.5, -88)
	panel.Size = UDim2.new(0, 280, 0, 92)
	panel.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	panel.BackgroundTransparency = 0.25
	panel.BorderSizePixel = 0
	panel.Active = false
	panel.Parent = og
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel

	local function mkLabel(y, h, size, bold, color)
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(1, -16, 0, h)
		l.Position = UDim2.new(0, 8, 0, y)
		l.BackgroundTransparency = 1
		l.TextColor3 = color or Color3.new(1, 1, 1)
		l.TextSize = size
		l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
		l.TextXAlignment = Enum.TextXAlignment.Center
		l.Text = ""
		l.Parent = panel
		return l
	end
	local ovTitle = mkLabel(4, 16, 12, true, Color3.fromRGB(170, 170, 190))
	ovTitle.Text = "PROGRESS KE LEVEL " .. Farm.TARGET_LEVEL
	Farm.ovLevel = mkLabel(20, 26, 22, true)
	Farm.ovLevel.Text = "Level ? / " .. Farm.TARGET_LEVEL

	local barBack = Instance.new("Frame")
	barBack.Size = UDim2.new(1, -16, 0, 12)
	barBack.Position = UDim2.new(0, 8, 0, 50)
	barBack.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
	barBack.BorderSizePixel = 0
	barBack.Parent = panel
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = barBack
	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = Color3.fromRGB(80, 210, 120)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBack
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = barFill
	Farm.barFill = barFill

	Farm.ovSub = mkLabel(64, 12, 11, false, Color3.fromRGB(200, 200, 210))
	Farm.ovStatus = mkLabel(76, 12, 11, true, Color3.fromRGB(255, 210, 90))

	Farm.buildConsole(og)
	Farm.overlayGui = og
end

-- Thread overlay: refresh berkala + XP poll + koordinator
-- redeem untuk kasus AUTO mati + koneksi event level.
function Farm.startOverlayLoops()
	Farm.redeemSignal = Farm.startRedeem
	pcall(function()
		player:GetAttributeChangedSignal("User_Level"):Connect(function()
			Farm.refreshXP()
			Farm.refreshOverlay()
		end)
	end)
	if Farm.LevelUpRE then
		Farm.LevelUpRE.OnClientEvent:Connect(function()
			print("[LEVEL] LevelUp event, refreshing overlay")
			Farm.refreshXP()
			Farm.refreshOverlay()
		end)
	end
	if Farm.ProfileUpdatedRE then
		Farm.ProfileUpdatedRE.OnClientEvent:Connect(function(section, data)
			if section == "Career" and Farm.LevelTools and typeof(data) == "table" then
				local ok, xp = pcall(function()
					return Farm.LevelTools.evaluateExperience(data)
				end)
				if ok and typeof(xp) == "number" then
					Farm.curXP = xp
				end
				Farm.refreshOverlay()
			end
		end)
	end
	-- Koordinator AUTO-mati: respawn tertunda diurus di sini.
	task.spawn(function()
		while true do
			if Farm.pendingRespawnRedeem and not Farm.autoOn() and not Farm.redeemDone and not Farm.redeemRunning then
				if Farm.inGame() then
					print("[REDEEM] AUTO mati - respawn karakter dari handler redeem...")
					Farm.redeemState = "Level 15 di match: respawn dulu, baru redeem..."
					Farm.resetAndRespawn()
				end
				if not Farm.inGame() then
					Farm.pendingRespawnRedeem = false
					print("[REDEEM] Sudah respawn/keluar match - redeem code sekarang")
					Farm.startRedeem()
				end
			end
			task.wait(1)
		end
	end)
	task.spawn(function()
		Farm.refreshXP()
		while true do
			Farm.refreshOverlay()
			task.wait(2)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(15)
			Farm.refreshXP()
		end
	end)
end

----------------------------------------------------------------
-- Console mirror (di bawah overlay level)
-- Mencerminkan keluaran console developer (print/warn/error
-- semua script klien) lewat LogService.MessageOut, jadi tidak
-- perlu membuka dev console di HP. Maksimal 80 baris terakhir.
----------------------------------------------------------------
Farm.TYPE_COLORS = {
	[Enum.MessageType.MessageOutput] = Color3.fromRGB(225, 225, 230),
	[Enum.MessageType.MessageInfo] = Color3.fromRGB(120, 180, 255),
	[Enum.MessageType.MessageWarning] = Color3.fromRGB(255, 200, 80),
	[Enum.MessageType.MessageError] = Color3.fromRGB(255, 95, 95),
}
Farm.MAX_LOG_LINES = 80
Farm.logCount = 0

function Farm.buildConsole(og)
	local consoleFrame = Instance.new("Frame")
	consoleFrame.Name = "Console"
	consoleFrame.AnchorPoint = Vector2.new(0.5, 0)
	consoleFrame.Position = UDim2.new(0.5, 0, 0.5, -34)
	consoleFrame.Size = UDim2.new(0.92, 0, 0, 140)
	consoleFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
	consoleFrame.BackgroundTransparency = 0.25
	consoleFrame.BorderSizePixel = 0
	consoleFrame.Active = false
	consoleFrame.Parent = og
	local cap = Instance.new("UISizeConstraint")
	cap.MaxSize = Vector2.new(440, 140)
	cap.Parent = consoleFrame
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 10)
	cc.Parent = consoleFrame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -12, 0, 16)
	title.Position = UDim2.new(0, 6, 0, 2)
	title.BackgroundTransparency = 1
	title.Text = "CONSOLE"
	title.TextColor3 = Color3.fromRGB(150, 150, 170)
	title.TextSize = 11
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = consoleFrame

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Log"
	scroll.Size = UDim2.new(1, -12, 1, -24)
	scroll.Position = UDim2.new(0, 6, 0, 20)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = Color3.fromRGB(110, 110, 130)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.Parent = consoleFrame
	Farm.consoleScroll = scroll

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	Farm.consoleLayout = layout

	-- Pin ke baris terbaru dipicu perubahan AbsoluteContentSize
	-- (tinggi baris terbungkus baru stabil beberapa frame setelah
	-- ditambahkan; timer tetap akan meleset).
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		task.defer(function()
			Farm.pinConsole()
		end)
	end)

	-- Isi awal dari riwayat console sebelum script ini jalan.
	pcall(function()
		local history = Farm.LogService:GetLogHistory()
		for _, entry in history do
			Farm.addLogLine(entry.message, entry.messageType, entry.timestamp)
		end
	end)
	Farm.LogService.MessageOut:Connect(function(message, msgType)
		Farm.addLogLine(message, msgType, os.time())
	end)
end

function Farm.pinConsole()
	local scroll = Farm.consoleScroll
	local layout = Farm.consoleLayout
	if not (scroll and layout) then
		return
	end
	local y = layout.AbsoluteContentSize.Y
	if y > 0 then
		scroll.CanvasPosition = Vector2.new(0, y)
	end
end

function Farm.addLogLine(text, msgType, epoch)
	local scroll = Farm.consoleScroll
	if not scroll then
		return
	end
	Farm.logCount = Farm.logCount + 1
	local stamp = ""
	if epoch then
		local ok, s = pcall(function()
			return os.date("%H:%M:%S", epoch)
		end)
		if ok then
			stamp = "[" .. s .. "] "
		end
	end
	local l = Instance.new("TextLabel")
	l.LayoutOrder = Farm.logCount
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.BackgroundTransparency = 1
	l.Text = stamp .. tostring(text)
	l.TextColor3 = Farm.TYPE_COLORS[msgType] or Farm.TYPE_COLORS[Enum.MessageType.MessageOutput]
	l.TextSize = 12
	l.Font = Enum.Font.Code
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.Parent = scroll

	-- Pangkas baris lama (urut LayoutOrder = yang tertua dulu).
	local labels = {}
	for _, child in scroll:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(labels, child)
		end
	end
	table.sort(labels, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	local excess = #labels - Farm.MAX_LOG_LINES
	for i = 1, excess do
		labels[i]:Destroy()
	end
	task.defer(function()
		Farm.pinConsole()
	end)
	task.delay(0.15, function()
		Farm.pinConsole()
	end)
end

----------------------------------------------------------------
-- Error context logger -> file di folder workspace executor
-- Buffer bergulir baris console. Setiap baris ERROR muncul,
-- satu blok ditulis ke VolleyballFarmLogs/error-log.txt berisi
-- 10 baris sebelum + error + 10 baris sesudah (menunggu sampai
-- 4 detik untuk mengumpulkan baris sesudahnya). Error identik
-- tidak dicatat ulang dalam 10 detik; maksimal 50 blok/sesi.
-- KNOWN_ERRORS: error yang teksnya MEMUAT salah satu fragmen
-- ini dilewati seluruhnya (bug game yang sudah teridentifikasi).
----------------------------------------------------------------
Farm.LOG_FOLDER = "VolleyballFarmLogs"
Farm.LOG_FILE = "VolleyballFarmLogs/error-log.txt"
Farm.CTX_LINES = 10
Farm.AFTER_WAIT_SECONDS = 4
Farm.MAX_BLOCKS_PER_SESSION = 50
Farm.BUFFER_MAX = 300
Farm.KNOWN_ERRORS = {
	-- Lomba refresh SpectateController saat setup match (bug game, 2026-11-01)
	"Team:GetPlayers() failed because team must be a child of the Teams service",
}

function Farm.isKnownError(msg)
	for _, frag in ipairs(Farm.KNOWN_ERRORS) do
		if msg:find(frag, 1, true) then
			return true
		end
	end
	return false
end

function Farm.fmtLogEntry(e)
	local stamp = "?"
	local ok, s = pcall(function()
		return os.date("%H:%M:%S", e.t)
	end)
	if ok then
		stamp = s
	end
	local tag = "OUT"
	if e.ty == Enum.MessageType.MessageError then
		tag = "ERROR"
	elseif e.ty == Enum.MessageType.MessageWarning then
		tag = "WARN"
	elseif e.ty == Enum.MessageType.MessageInfo then
		tag = "INFO"
	end
	return ("[%s] [%s] %s"):format(stamp, tag, e.s)
end

function Farm.writeBlockToFile(block)
	if typeof(writefile) ~= "function" then
		Farm.memLog = Farm.memLog .. block
		return false
	end
	if typeof(makefolder) == "function" and typeof(isfolder) == "function" then
		pcall(function()
			if not isfolder(Farm.LOG_FOLDER) then
				makefolder(Farm.LOG_FOLDER)
			end
		end)
	end
	if typeof(appendfile) == "function" then
		local ok = pcall(appendfile, Farm.LOG_FILE, block)
		if ok then
			return true
		end
	end
	Farm.memLog = Farm.memLog .. block
	pcall(writefile, Farm.LOG_FILE, Farm.memLog)
	return true
end

function Farm.finalizeCapture(cap)
	if cap.done then
		return
	end
	cap.done = true
	Farm.blocksWritten = Farm.blocksWritten + 1
	local lines = {}
	table.insert(lines, "")
	table.insert(lines, "==================== ERROR #" .. Farm.blocksWritten .. " ====================")
	table.insert(lines, "--- " .. Farm.CTX_LINES .. " lines before ---")
	if #cap.before == 0 then
		table.insert(lines, "(no earlier lines in buffer)")
	end
	for _, e in ipairs(cap.before) do
		table.insert(lines, "    " .. Farm.fmtLogEntry(e))
	end
	table.insert(lines, "--- ERROR ---")
	table.insert(lines, ">>> " .. Farm.fmtLogEntry(cap.err))
	table.insert(lines, "--- up to " .. Farm.CTX_LINES .. " lines after ---")
	if #cap.after == 0 then
		table.insert(lines, "(no lines followed within " .. Farm.AFTER_WAIT_SECONDS .. "s)")
	end
	for _, e in ipairs(cap.after) do
		table.insert(lines, "    " .. Farm.fmtLogEntry(e))
	end
	table.insert(lines, "====================================================")
	local block = table.concat(lines, "\n") .. "\n"
	if Farm.writeBlockToFile(block) then
		print("[LOG] Error block #" .. Farm.blocksWritten .. " written to workspace file: " .. Farm.LOG_FILE)
	else
		print("[LOG] Error block #" .. Farm.blocksWritten .. " captured in memory only (executor has no writefile)")
	end
end

function Farm.startCapture(errEntry)
	if Farm.blocksWritten + #Farm.pendingCaptures >= Farm.MAX_BLOCKS_PER_SESSION then
		return
	end
	local last = Farm.lastWrittenByMsg[errEntry.s]
	if last and (os.time() - last) < 10 then
		return
	end
	Farm.lastWrittenByMsg[errEntry.s] = os.time()
	local cap = { err = errEntry, before = {}, after = {}, done = false }
	local n = #Farm.logBuffer
	for i = math.max(1, n - Farm.CTX_LINES), n do
		if Farm.logBuffer[i] ~= errEntry then
			table.insert(cap.before, Farm.logBuffer[i])
		end
	end
	if #cap.before > Farm.CTX_LINES then
		local trimmed = {}
		for i = #cap.before - Farm.CTX_LINES + 1, #cap.before do
			table.insert(trimmed, cap.before[i])
		end
		cap.before = trimmed
	end
	table.insert(Farm.pendingCaptures, cap)
	task.spawn(function()
		local waited = 0
		while not cap.done and #cap.after < Farm.CTX_LINES and waited < Farm.AFTER_WAIT_SECONDS do
			task.wait(0.25)
			waited = waited + 0.25
		end
		Farm.finalizeCapture(cap)
		local idx = table.find(Farm.pendingCaptures, cap)
		if idx then
			table.remove(Farm.pendingCaptures, idx)
		end
	end)
end

function Farm.onLogLine(message, msgType, epoch)
	local entry = { t = epoch or os.time(), ty = msgType, s = tostring(message) }
	table.insert(Farm.logBuffer, entry)
	if #Farm.logBuffer > Farm.BUFFER_MAX then
		table.remove(Farm.logBuffer, 1)
	end
	for _, cap in ipairs(Farm.pendingCaptures) do
		if not cap.done and cap.err ~= entry then
			table.insert(cap.after, entry)
			if #cap.after >= Farm.CTX_LINES then
				Farm.finalizeCapture(cap)
			end
		end
	end
	if msgType == Enum.MessageType.MessageError then
		if Farm.isKnownError(message) then
			local key = tostring(message)
			if not Farm.knownNoted[key] then
				Farm.knownNoted[key] = true
				print("[LOG] Known error diabaikan (tidak disimpan): " .. key:sub(1, 90))
			end
		else
			Farm.startCapture(entry)
		end
	end
end

function Farm.startErrorLogger()
	pcall(function()
		for _, e in ipairs(Farm.LogService:GetLogHistory()) do
			table.insert(Farm.logBuffer, { t = e.timestamp or os.time(), ty = e.messageType, s = tostring(e.message) })
		end
		while #Farm.logBuffer > Farm.BUFFER_MAX do
			table.remove(Farm.logBuffer, 1)
		end
	end)
	Farm.LogService.MessageOut:Connect(function(message, msgType)
		Farm.onLogLine(message, msgType, os.time())
	end)
	if typeof(writefile) == "function" then
		print("[LOG] Error context logger active -> workspace file: " .. Farm.LOG_FILE)
	else
		print("[LOG] Error context logger active (memory only: executor has no writefile)")
	end
end

----------------------------------------------------------------
-- Panel Settings "VL Farm" (dibuka dari baris Settings suite)
----------------------------------------------------------------
function Farm.refreshPanel()
	if Farm.panelToggleBtn then
		if Farm.running then
			Farm.panelToggleBtn.Text = "AUTO FARM: ON"
			Farm.panelToggleBtn.BackgroundColor3 = Color3.fromRGB(24, 130, 60)
		else
			Farm.panelToggleBtn.Text = "AUTO FARM: OFF"
			Farm.panelToggleBtn.BackgroundColor3 = Color3.fromRGB(64, 64, 76)
		end
	end
	if Farm.panelStatusLbl and Farm.statusText then
		Farm.panelStatusLbl.Text = "Status: " .. Farm.statusText
	end
end

function Farm.buildPanel()
	if Farm.panelGui then
		return Farm.panelGui
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "VLFarmPanelGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Enabled = false

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.Size = UDim2.fromOffset(360, 300)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
	frame.BackgroundTransparency = 0.05
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(70, 70, 84)
	stroke.Thickness = 1
	stroke.Parent = frame
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.PaddingTop = UDim.new(0, 14)
	pad.PaddingBottom = UDim.new(0, 14)
	pad.Parent = frame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -40, 0, 26)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Auto Farm (v15 Extreme)"
	title.Parent = frame

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(28, 28)
	closeBtn.Position = UDim2.new(1, -28, 0, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(52, 52, 62)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 14
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Text = "X"
	closeBtn.Parent = frame
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = closeBtn
	closeBtn.Activated:Connect(function()
		gui.Enabled = false
	end)

	Farm.panelStatusLbl = Instance.new("TextLabel")
	Farm.panelStatusLbl.Size = UDim2.new(1, 0, 0, 20)
	Farm.panelStatusLbl.Position = UDim2.fromOffset(0, 36)
	Farm.panelStatusLbl.BackgroundTransparency = 1
	Farm.panelStatusLbl.Font = Enum.Font.Gotham
	Farm.panelStatusLbl.TextSize = 13
	Farm.panelStatusLbl.TextColor3 = Color3.fromRGB(190, 190, 200)
	Farm.panelStatusLbl.TextXAlignment = Enum.TextXAlignment.Left
	Farm.panelStatusLbl.Text = "Status: idle"
	Farm.panelStatusLbl.Parent = frame

	Farm.panelToggleBtn = Instance.new("TextButton")
	Farm.panelToggleBtn.Size = UDim2.new(1, 0, 0, 48)
	Farm.panelToggleBtn.Position = UDim2.fromOffset(0, 64)
	Farm.panelToggleBtn.BackgroundColor3 = Color3.fromRGB(64, 64, 76)
	Farm.panelToggleBtn.Font = Enum.Font.GothamBold
	Farm.panelToggleBtn.TextSize = 16
	Farm.panelToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	Farm.panelToggleBtn.Text = "AUTO FARM: OFF"
	Farm.panelToggleBtn.Parent = frame
	local togCorner = Instance.new("UICorner")
	togCorner.CornerRadius = UDim.new(0, 8)
	togCorner.Parent = Farm.panelToggleBtn
	Farm.panelToggleBtn.Activated:Connect(function()
		Farm.setEnabled(not Farm.running)
	end)

	local uiBtn = Instance.new("TextButton")
	uiBtn.Size = UDim2.new(1, 0, 0, 36)
	uiBtn.Position = UDim2.fromOffset(0, 122)
	uiBtn.BackgroundColor3 = Color3.fromRGB(52, 52, 62)
	uiBtn.Font = Enum.Font.Gotham
	uiBtn.TextSize = 13
	uiBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	uiBtn.Text = "Tampilkan / Sembunyikan UI Farm"
	uiBtn.Parent = frame
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, 8)
	uiCorner.Parent = uiBtn
	uiBtn.Activated:Connect(function()
		local nowVisible = not (Farm.gui and Farm.gui.Enabled)
		Farm.setGuiVisible(nowVisible)
	end)

	local note = Instance.new("TextLabel")
	note.Size = UDim2.new(1, 0, 0, 120)
	note.Position = UDim2.fromOffset(0, 168)
	note.BackgroundTransparency = 1
	note.Font = Enum.Font.Gotham
	note.TextSize = 11
	note.TextColor3 = Color3.fromRGB(140, 140, 152)
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.TextYAlignment = Enum.TextYAlignment.Top
	note.TextWrapped = true
	note.Text = "Loop v15: join -> farm Block-only -> skip replay/summary -> reset -> ulang, plus handler serve dan redeem kode otomatis di level 15. Sekali ON, suite mengantrekan dirinya lewat queue_on_teleport (gaya Infinite Yield): setelah rejoin/pindah server loop lanjut sendiri tanpa autoexec. Matikan dari panel ini bila mau berhenti total."
	note.Parent = frame

	local parented = pcall(function()
		gui.Parent = player:WaitForChild("PlayerGui")
	end)
	if not parented or not gui.Parent then
		pcall(function()
			gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
		end)
	end
	Farm.panelGui = gui
	Farm.refreshPanel()
	return gui
end

function Farm.openPanel()
	Farm.buildPanel()
	Farm.refreshPanel()
	if Farm.panelGui then
		Farm.panelGui.Enabled = true
	end
end

----------------------------------------------------------------
-- Init bundle auto farm
----------------------------------------------------------------
local function initAutoFarm()
	if not (VLBridge.awaitFeatureShared and VLBridge.awaitFeatureShared(90)) then
		warn("[VL Suite] automation: feature-shared tidak siap -- auto farm dilewati.")
		return
	end
	loadLocal()
	Farm.ensureSettings()
	Farm.acquireRemotes()
	Farm.connectMatchEvents()
	Farm.buildGui()
	Farm.buildOverlay()
	Farm.startTpLoop()
	Farm.startActionLoop()
	Farm.startMainLoop()
	Farm.startPerfModes()
	Farm.startOverlayLoops()
	Farm.startErrorLogger()
	FeatureAPI.setAutoFarmEnabled = Farm.setEnabled
	FeatureAPI.openAutoFarmPanel = Farm.openPanel
	FeatureAPI.queueAutomation = Farm.queueSelfIfActive
	getgenv().VLFarmOpenPanel = Farm.openPanel
	-- Lanjutkan sesi sebelumnya: saklar tersimpan -> nyalakan
	-- lagi (beri waktu lobby selesai memuat dulu).
	if S.settings[SETTING_MEMBER_FARM] then
		Farm.running = true
		S.autoFarmRunning = true
		Farm.refreshPanel()
		task.delay(4, function()
			if S.settings[SETTING_MEMBER_FARM] then
				Farm.setEnabled(true)
			end
		end)
	end
	Farm.queueSelfIfActive()
	print("[VL Suite] automation: auto farm ready.")
end

task.spawn(initAutoFarm)
