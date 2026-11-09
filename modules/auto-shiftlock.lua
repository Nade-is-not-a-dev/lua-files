----------------------------------------------------------------
-- modules/auto-shiftlock.lua -- Modul fitur: Auto Shiftlock
--
-- Dulu bernama "Face Camera" (Bagian B monolit): karakter
-- diputar SEKALI menghadap arah kamera pada dua momen --
-- 1) setiap lompatan dimulai (deteksi lift-off), dan
-- 2) saat ability Redirection Jump / Boom Jump diaktifkan.
-- Dengan LOCK_DIRECTION (core.lua) arah kunci dipertahankan
-- selama di udara (AutoRotate dimatikan sementara), seperti
-- shiftlock. Pelepas kunci berbasis KEADAAN (dicek tiap
-- frame: tidak di udara lagi / kunci > 2 detik / terdeteksi
-- teleport), BUKAN hanya tepi transisi mendarat -- tepi itu
-- bisa terlewat saat game ikut campur di tengah lompatan
-- (teleport pergantian ronde, fase tunggu serve), dan dulu
-- AutoRotate tertinggal mati: karakter berjalan sambil
-- tetap menghadap arah lompatan terakhir (shiftlock
-- nyangkut). Modul ini TIDAK menunggu feature-shared: ia
-- hanya memakai player/Knit dari core.
----------------------------------------------------------------
----------------------------------------------------------------
-- Auto Shiftlock (lompat + Redirection/Boom Jump)
-- Karakter diputar SEKALI menghadap arah kamera pada dua momen:
-- 1) setiap lompatan dimulai (deteksi lift-off), dan
-- 2) saat ability Redirection Jump / Boom Jump diaktifkan
--    (termasuk aktivasi di tengah udara).
-- Rumus putarannya sama dengan kode game sendiri (yaw kamera).
----------------------------------------------------------------
local function initAutoShiftlock()
	local t0 = os.clock()
	if getgenv().VLAutoShiftlockInstalled then
		suiteModuleLoaded("auto-shiftlock")
		return
	end
	getgenv().VLAutoShiftlockInstalled = true

	local RunService = game:GetService("RunService")
	local Workspace = game:GetService("Workspace")

	local TARGET_ABILITIES = {
		RedirectionJump = true,
		BoomJump = true,
	}

	local function faceCamera()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local camera = Workspace.CurrentCamera
		if not root or not camera then
			return false
		end
		local _, yaw, _ = camera.CFrame.Rotation:ToOrientation()
		root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
		return true
	end

	-- Jalur ability: AbilityService mungkin belum siap saat autoexec,
	-- jadi dicoba berkala sampai 30 detik; jalur lompat tidak menunggu.
	task.spawn(function()
		for _ = 1, 60 do
			local ok = pcall(function()
				local AbilityService = Knit.GetService("AbilityService")
				AbilityService.AbilityAction:Connect(function(abilityName)
					if TARGET_ABILITIES[abilityName] then
						faceCamera()
					end
				end)
			end)
			if ok then
				return
			end
			task.wait(0.5)
		end
	end)

	-- Jalur lompat: deteksi lift-off tiap karakter. Keadaan
	-- kunci disimpan di level modul (bukan per-karakter).
	local heartbeatConn = nil
	local lockHumanoid = nil
	local lockBefore = nil
	local lockSince = 0
	local LOCK_MAX_SECONDS = 2

	local function releaseLock()
		if lockHumanoid and lockBefore ~= nil then
			pcall(function()
				lockHumanoid.AutoRotate = lockBefore
			end)
		end
		lockHumanoid = nil
		lockBefore = nil
	end

	local function watchCharacter(character)
		if heartbeatConn then
			heartbeatConn:Disconnect()
			heartbeatConn = nil
		end
		-- Karakter berganti selagi kunci aktif: pulihkan
		-- humanoid yang lama dulu.
		releaseLock()
		local humanoid = character:WaitForChild("Humanoid")
		local root = character:WaitForChild("HumanoidRootPart")
		local wasAirborne = humanoid.FloorMaterial == Enum.Material.Air
		local snapped = false
		local lastPosition = root.Position

		heartbeatConn = RunService.Heartbeat:Connect(function()
			-- Teleport (pergantian ronde / penempatan serve):
			-- posisi melompat jauh dalam satu frame berarti
			-- game memindahkan karakter -- keadaan lompatan
			-- dianggap mulai dari nol.
			local position = root.Position
			if (position - lastPosition).Magnitude > 15 then
				releaseLock()
				snapped = false
				wasAirborne = humanoid.FloorMaterial == Enum.Material.Air
			end
			lastPosition = position

			local airborne = humanoid.FloorMaterial == Enum.Material.Air

			if airborne and not wasAirborne and not snapped
				and root.AssemblyLinearVelocity.Y > 5 then
				if faceCamera() then
					snapped = true
					if LOCK_DIRECTION then
						lockHumanoid = humanoid
						lockBefore = humanoid.AutoRotate
						lockSince = os.clock()
						humanoid.AutoRotate = false
					end
				end
			end

			if not airborne and wasAirborne then
				snapped = false
			end

			-- Pelepas berbasis keadaan: kunci lepas pada frame
			-- PERTAMA syaratnya terpenuhi (sudah di tanah, atau
			-- kunci terlalu tua), walau tepi transisi mendarat
			-- di atas terlewat karena campur tangan game.
			if lockHumanoid == humanoid
				and (not airborne or os.clock() - lockSince > LOCK_MAX_SECONDS) then
				releaseLock()
			end

			wasAirborne = airborne
		end)
	end

	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		task.spawn(watchCharacter, character)
	end)

	print(("[VL Suite] auto-shiftlock ready in %.2fs"):format(os.clock() - t0))
	suiteModuleLoaded("auto-shiftlock")
end
suiteExpectModule("auto-shiftlock")
task.spawn(initAutoShiftlock)
