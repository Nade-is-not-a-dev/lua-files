----------------------------------------------------------------
-- modules/auto-shiftlock.lua -- Modul fitur: Auto Shiftlock
--
-- Dulu bernama "Face Camera" (Bagian B monolit): karakter
-- diputar SEKALI menghadap arah kamera pada dua momen --
-- 1) setiap lompatan dimulai (deteksi lift-off), dan
-- 2) saat ability Redirection Jump / Boom Jump diaktifkan.
-- Dengan LOCK_DIRECTION (core.lua) arah kunci dipertahankan
-- selama di udara (AutoRotate dimatikan sementara), seperti
-- shiftlock. Sebagai pengaman ada PENGAWAS kunci arah:
-- berkala mengecek -- karakter di tanah DAN sedang berjalan
-- DAN arahnya terkunci berarti kuncinya bocor dari lompatan,
-- jadi dilepas.
--
-- BISA DI-TOGGLE: saklar "Auto Shiftlock" di grup VL Settings
-- (anggota AutoShiftlock, persisten di S.settings), dan
-- keadaan BAWAANNYA MATI. Semua hook (lompat, ability,
-- CharacterAdded, pengawas) hanya terpasang saat saklar
-- NYALA; mematikannya mencabut semua koneksi dan melepas
-- kunci arah yang sedang aktif. Titik masuk saklar:
-- FeatureAPI.setAutoShiftlockEnabled(bool) dari bungkus
-- ChangeSetting di modules/settings.lua. Keadaan awal dibaca
-- dari S.settings begitu state lokal selesai dimuat
-- (S.localStateLoaded) -- sebelumnya modul tidak memasang
-- apa pun.
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

	local aslEnabled = false
	local aslInstalled = false
	local heartbeatConn = nil
	local charAddedConn = nil
	local abilityConn = nil
	local abilityStop = false
	-- Keadaan kunci arah (level modul, supaya mencabut modul
	-- bisa melepaskan kunci yang sedang aktif).
	local lockHumanoid = nil
	local lockBefore = nil

	local function releaseLock()
		if lockHumanoid and lockBefore ~= nil then
			pcall(function()
				lockHumanoid.AutoRotate = lockBefore
			end)
		end
		lockHumanoid = nil
		lockBefore = nil
	end

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

	-- Jalur lompat: deteksi lift-off tiap karakter.
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

		heartbeatConn = RunService.Heartbeat:Connect(function()
			local airborne = humanoid.FloorMaterial == Enum.Material.Air

			if airborne and not wasAirborne and not snapped
				and root.AssemblyLinearVelocity.Y > 5 then
				if faceCamera() then
					snapped = true
					if LOCK_DIRECTION then
						lockHumanoid = humanoid
						lockBefore = humanoid.AutoRotate
						humanoid.AutoRotate = false
					end
				end
			end

			if not airborne and wasAirborne then
				snapped = false
				if lockHumanoid == humanoid then
					releaseLock()
				end
			end

			wasAirborne = airborne
		end)
	end

	local function installAsl()
		if aslInstalled then
			return
		end
		aslInstalled = true
		abilityStop = false
		-- Jalur ability: AbilityService mungkin belum siap,
		-- jadi dicoba berkala sampai 30 detik; jalur lompat
		-- tidak menunggu.
		task.spawn(function()
			for _ = 1, 60 do
				if abilityStop then
					return
				end
				local ok = pcall(function()
					local AbilityService = Knit.GetService("AbilityService")
					abilityConn = AbilityService.AbilityAction:Connect(function(abilityName)
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
		if player.Character then
			task.spawn(watchCharacter, player.Character)
		end
		charAddedConn = player.CharacterAdded:Connect(function(character)
			task.spawn(watchCharacter, character)
		end)
	end

	local function uninstallAsl()
		if not aslInstalled then
			return
		end
		aslInstalled = false
		abilityStop = true
		if abilityConn then
			abilityConn:Disconnect()
			abilityConn = nil
		end
		if charAddedConn then
			charAddedConn:Disconnect()
			charAddedConn = nil
		end
		if heartbeatConn then
			heartbeatConn:Disconnect()
			heartbeatConn = nil
		end
		releaseLock()
	end

	local function setAslEnabled(value)
		aslEnabled = value == true
		if aslEnabled then
			installAsl()
		else
			uninstallAsl()
		end
	end
	FeatureAPI.setAutoShiftlockEnabled = setAslEnabled

	-- Pengawas kunci arah: cek berkala, dan bila karakter ada
	-- di tanah DAN sedang berjalan DAN arahnya terkunci
	-- (AutoRotate mati), lepas kuncinya. Humanoid dibaca SEGAR
	-- dari karakter yang hidup saat ini setiap kali cek.
	-- Hanya bekerja saat fitur NYALA (saklarnya yang memiliki
	-- pengawas ini).
	task.spawn(function()
		while true do
			task.wait(0.15)
			if aslEnabled then
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
		end
	end)

	-- Keadaan awal: saklar persisten dari S.settings, dibaca
	-- begitu state lokal selesai dimuat. Bawaan MATI: tanpa
	-- simpanan yang menyalakan, tidak ada hook yang terpasang.
	task.spawn(function()
		local deadline = os.clock() + 90
		while os.clock() < deadline do
			if S.localStateLoaded then
				break
			end
			task.wait(0.25)
		end
		if S.settings[SETTING_MEMBER_SHIFTLOCK] == true then
			setAslEnabled(true)
		end
	end)

	print(("[VL Suite] auto-shiftlock ready in %.2fs"):format(os.clock() - t0))
	suiteModuleLoaded("auto-shiftlock")
end
suiteExpectModule("auto-shiftlock")
task.spawn(initAutoShiftlock)
