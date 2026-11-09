----------------------------------------------------------------
-- modules/auto-shiftlock.lua -- Modul fitur: Auto Shiftlock
--
-- Dulu bernama "Face Camera" (Bagian B monolit): karakter
-- diputar SEKALI menghadap arah kamera pada dua momen --
-- 1) setiap lompatan dimulai (deteksi lift-off), dan
-- 2) saat ability Redirection Jump / Boom Jump diaktifkan.
-- Dengan LOCK_DIRECTION (core.lua) arah kunci dipertahankan
-- selama di udara (AutoRotate dimatikan sementara), seperti
-- shiftlock. Sebagai pengaman ada PENGAWAS kunci arah di
-- bawah: ia mengecek berkala -- karakter di tanah DAN sedang
-- berjalan DAN arahnya terkunci (AutoRotate mati) berarti
-- kuncinya bocor dari lompatan, jadi dilepas. Modul ini
-- TIDAK menunggu feature-shared: ia hanya memakai
-- player/Knit dari core.
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

	-- Jalur lompat: deteksi lift-off tiap karakter.
	local heartbeatConn = nil
	local function watchCharacter(character)
		if heartbeatConn then
			heartbeatConn:Disconnect()
		end
		local humanoid = character:WaitForChild("Humanoid")
		local root = character:WaitForChild("HumanoidRootPart")
		local wasAirborne = humanoid.FloorMaterial == Enum.Material.Air
		local snapped = false
		local autoRotateBefore = nil

		heartbeatConn = RunService.Heartbeat:Connect(function()
			local airborne = humanoid.FloorMaterial == Enum.Material.Air

			if airborne and not wasAirborne and not snapped
				and root.AssemblyLinearVelocity.Y > 5 then
				if faceCamera() then
					snapped = true
					if LOCK_DIRECTION then
						autoRotateBefore = humanoid.AutoRotate
						humanoid.AutoRotate = false
					end
				end
			end

			if not airborne and wasAirborne then
				snapped = false
				if autoRotateBefore ~= nil then
					humanoid.AutoRotate = autoRotateBefore
					autoRotateBefore = nil
				end
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

	-- Pengawas kunci arah: rancangan sederhana sesuai permintaan
	-- -- cek berkala, dan bila karakter ada di tanah DAN sedang
	-- berjalan DAN arahnya terkunci (AutoRotate mati), lepas
	-- kuncinya (AutoRotate dinyalakan lagi). Humanoid dibaca
	-- SEGAR dari karakter yang hidup saat ini setiap kali cek,
	-- jadi pengawas tidak pernah nyangkut pada referensi lama.
	-- "Di tanah" dicek ganda (FloorMaterial + state Humanoid)
	-- supaya satu sinyal yang basi tidak memblokir pelepasan.
	task.spawn(function()
		while true do
			task.wait(0.15)
			pcall(function()
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if not humanoid then
					return
				end
				if humanoid.AutoRotate then
					return -- arah tidak terkunci, tidak ada yang dilepas
				end
				local state = humanoid:GetState()
				local onGround = humanoid.FloorMaterial ~= Enum.Material.Air
					or state == Enum.HumanoidStateType.Running
					or state == Enum.HumanoidStateType.RunningNoPhysics
					or state == Enum.HumanoidStateType.Landed
				local walking = humanoid.MoveDirection.Magnitude > 0.1
				if onGround and walking then
					humanoid.AutoRotate = true
				end
			end)
		end
	end)

	print(("[VL Suite] auto-shiftlock ready in %.2fs"):format(os.clock() - t0))
	suiteModuleLoaded("auto-shiftlock")
end
suiteExpectModule("auto-shiftlock")
task.spawn(initAutoShiftlock)
