----------------------------------------------------------------
-- modules/settings.lua -- Modul fitur: VL Settings
--
-- Grup Settings "VLSettings" (saklar World-Affecting Score
-- FX), bungkus SettingsService.ChangeSetting, halaman grup,
-- dan baris Settings untuk Avatar Lite.
-- Direstore dari v0.5.1 (suite/settings.lua); fungsi-fungsinya
-- identik. Penyesuaian ke arsitektur sekarang:
--  * init memanggil loadLocal() sendiri (sekali-jaga, seperti
--    jersey/emote) supaya S.settings dari simpanan sudah
--    terbaca sebelum applyVLSettings() menggabungkannya.
--  * applyVLSettings didaftarkan ke FeatureAPI, jadi pengawatan
--    ProfileUpdated di feature-shared memanggilnya ulang setiap
--    server menyinkronkan Settings.
--  * Settings BUKAN kategori inventory, jadi tidak memakai
--    suiteActivateFeature; hanya ikut pelacak READY
--    (suiteExpectModule / suiteModuleLoaded).
--  * Semua log/warn memakai awalan [VL Suite] (konvensi v0.8.1).
--  * Baris Avatar Lite tetap nil-guarded: tombol Open-nya baru
--    berfungsi setelah modul avatar kembali (masih di monolit).
----------------------------------------------------------------

-- Daftarkan grup VL Settings ke tabel SettingsGroups game. Ini
-- MURNI mutasi tabel modul (tidak butuh controller), jadi aman
-- dipanggil sedini mungkin -- dan WAJIB mendahului penggabungan
-- kunci kita ke Value Settings: halaman utama Settings menggambar
-- saklar untuk setiap kunci boolean yang tidak dikenali
-- SettingsGroups.parseKey, jadi kunci yang tergabung sebelum grup
-- terdaftar bocor ke halaman utama sebagai baris berlabel kunci
-- mentah (dan Fusion ForPairs tidak menggambar ulang kunci yang
-- nilainya tidak berubah, jadi kebocorannya tidak sembuh sendiri).
local function registerSettingsGroup()
	if S.settingsGroupRegistered then
		return
	end
	local ok = pcall(function()
		local groups = require(RS:WaitForChild("Configuration"):WaitForChild("SettingsGroups"))
		if not groups.Data[SETTINGS_GROUP] then
			groups.Data[SETTINGS_GROUP] = {
				DisplayName = "VL Settings",
				Members = { SETTING_MEMBER_WORLD_FX, SETTING_MEMBER_EXTREME, SETTING_MEMBER_SHIFTLOCK, SETTING_MEMBER_HITBOX, SETTING_MEMBER_AUTO_RECEIVE },
			}
			table.insert(groups.Order, SETTINGS_GROUP)
		end
		pcall(function()
			-- Label baris di halaman grup (peta milik KeybindController).
			local nameMap = require(ReplicatedFirst:WaitForChild("Controllers"):WaitForChild("KeybindController"):WaitForChild("DisplayNameMap"))
			if type(nameMap) == "table" and nameMap[SETTING_MEMBER_WORLD_FX] == nil then
				nameMap[SETTING_MEMBER_WORLD_FX] = "World-Affecting Score Effects"
			end
			if type(nameMap) == "table" and nameMap[SETTING_MEMBER_EXTREME] == nil then
				nameMap[SETTING_MEMBER_EXTREME] = "Extreme Ultra Fast Mode"
			end
			if type(nameMap) == "table" and nameMap[SETTING_MEMBER_SHIFTLOCK] == nil then
				nameMap[SETTING_MEMBER_SHIFTLOCK] = "Auto Shiftlock"
			end
			if type(nameMap) == "table" and nameMap[SETTING_MEMBER_HITBOX] == nil then
				nameMap[SETTING_MEMBER_HITBOX] = "Hitbox Expander"
			end
			if type(nameMap) == "table" and nameMap[SETTING_MEMBER_AUTO_RECEIVE] == nil then
				nameMap[SETTING_MEMBER_AUTO_RECEIVE] = "Auto Receive"
			end
		end)
		pcall(function()
			-- Asuransi label di halaman utama (peta milik
			-- SettingsController sendiri): bila baris kita entah
			-- bagaimana tetap tergambar di sana, labelnya benar.
			local mainMap = require(ReplicatedFirst:WaitForChild("Controllers"):WaitForChild("SettingsController"):WaitForChild("DisplayNameMap"))
			if type(mainMap) == "table" and mainMap[SETTINGS_KEY_WORLD_FX] == nil then
				mainMap[SETTINGS_KEY_WORLD_FX] = "World-Affecting Score Effects"
			end
			if type(mainMap) == "table" and mainMap[SETTINGS_KEY_EXTREME] == nil then
				mainMap[SETTINGS_KEY_EXTREME] = "Extreme Ultra Fast Mode"
			end
			if type(mainMap) == "table" and mainMap[SETTINGS_KEY_SHIFTLOCK] == nil then
				mainMap[SETTINGS_KEY_SHIFTLOCK] = "Auto Shiftlock"
			end
			if type(mainMap) == "table" and mainMap[SETTINGS_KEY_HITBOX] == nil then
				mainMap[SETTINGS_KEY_HITBOX] = "Hitbox Expander"
			end
			if type(mainMap) == "table" and mainMap[SETTINGS_KEY_AUTO_RECEIVE] == nil then
				mainMap[SETTINGS_KEY_AUTO_RECEIVE] = "Auto Receive"
			end
		end)
	end)
	if ok then
		S.settingsGroupRegistered = true
	end
end

-- Saklar bagian Settings tambahan hidup sebagai kunci komposit
-- "VLSettings_<Anggota>" di dalam Value Settings milik
-- InterfaceController (yang dibaca baris-baris Settings) -- gabung
-- nilai lokal kita ke sana, dan gabung ulang setiap server
-- menyinkronkan Settings (sinkron server menimpa seluruh tabel).
local function applyVLSettings()
	if not (InterfaceController and InterfaceController.Settings) then
		return
	end
	registerSettingsGroup()
	pcall(function()
		local current = InterfaceController.Settings:get() or {}
		if current[SETTINGS_KEY_WORLD_FX] == S.settings[SETTING_MEMBER_WORLD_FX]
			and current[SETTINGS_KEY_EXTREME] == S.settings[SETTING_MEMBER_EXTREME]
			and current[SETTINGS_KEY_SHIFTLOCK] == S.settings[SETTING_MEMBER_SHIFTLOCK]
			and current[SETTINGS_KEY_HITBOX] == S.settings[SETTING_MEMBER_HITBOX]
			and current[SETTINGS_KEY_AUTO_RECEIVE] == S.settings[SETTING_MEMBER_AUTO_RECEIVE] then
			return
		end
		local merged = table.clone(current)
		merged[SETTINGS_KEY_WORLD_FX] = S.settings[SETTING_MEMBER_WORLD_FX]
		merged[SETTINGS_KEY_EXTREME] = S.settings[SETTING_MEMBER_EXTREME]
		merged[SETTINGS_KEY_SHIFTLOCK] = S.settings[SETTING_MEMBER_SHIFTLOCK]
		merged[SETTINGS_KEY_HITBOX] = S.settings[SETTING_MEMBER_HITBOX]
		merged[SETTINGS_KEY_AUTO_RECEIVE] = S.settings[SETTING_MEMBER_AUTO_RECEIVE]
		InterfaceController.Settings:set(merged)
	end)
end

-- Bangun halaman bagian kita memakai mekanisme grup milik game
-- (GroupPages): daftarkan grup ke tabel SettingsGroups, lalu panggil
-- pembangun halaman game sendiri. Dikerjakan setelah Settings
-- selesai dimuat (bootstrap grup asli berjalan di KnitStart).
local function buildSettingsSection()
	if S.settingsSectionBuilt then
		return
	end
	local deadline = os.clock() + 30
	while os.clock() < deadline do
		if SettingsController and SettingsController.Loaded then
			break
		end
		task.wait(0.5)
	end
	if not (SettingsController and SettingsController.Loaded) then
		return
	end
	pcall(function()
		registerSettingsGroup()
		local groups = require(RS:WaitForChild("Configuration"):WaitForChild("SettingsGroups"))
		local groupPages = require(ReplicatedFirst:WaitForChild("Controllers"):WaitForChild("SettingsController"):WaitForChild("GroupPages"))
		if groupPages.Components[SETTINGS_GROUP] then
			S.settingsSectionBuilt = true
			return
		end
		local index = #groups.Order
		groupPages._loadPage(SETTINGS_GROUP)
		groupPages._loadRows(SETTINGS_GROUP)
		groupPages._loadSettingsRow(SETTINGS_GROUP, index)
		S.settingsSectionBuilt = true
	end)
end

-- Baris tombol Avatar Lite di daftar utama Settings, meniru
-- ButtonEditController:LoadSettingsButton milik game sendiri
-- (baris "Buttons / Edit [Open]"): header BB_TextLabel + baris
-- B_Template dengan tombol Open. Nama baris dipilih agar urutan
-- nama UIListLayout menaruhnya setelah baris Buttons bawaan.
local function buildAvatarSettingsRow()
	if S.avatarSettingsRowBuilt then
		return
	end
	local function findList()
		local ok, found = pcall(function()
			return InterfaceController.App.Lobby.Settings.BGFrame.Body.List
		end)
		if ok and found then
			return found
		end
		local ok, found = pcall(function()
			local app = player.PlayerGui:FindFirstChild("App")
			local lobby = app and app:FindFirstChild("Lobby")
			local settings = lobby and lobby:FindFirstChild("Settings")
			local bg = settings and settings:FindFirstChild("BGFrame")
			local body = bg and bg:FindFirstChild("Body")
			return body and body:FindFirstChild("List")
		end)
		if ok and found then
			return found
		end
		return nil
	end
	local deadline = os.clock() + 120
	local list
	while os.clock() < deadline do
		list = findList()
		if list then
			break
		end
		task.wait(0.5)
	end
	if not list then
		warn("[VL Suite] Avatar settings list not found; row not built.")
		return
	end
	if list:FindFirstChild("B_VLAvatarRow") then
		S.avatarSettingsRowBuilt = true
		return
	end
	local okBuild, err = pcall(function()
		local Fusion = require(RS:WaitForChild("Packages"):WaitForChild("Fusion"))
		local Button = require(ReplicatedFirst:WaitForChild("Components"):WaitForChild("Button"))
		-- Visible WAJIB diset eksplisit: template baris game
		-- tersembunyi (Visible=false), klonnya mewarisi itu.
		Fusion.Hydrate(list.BB_TextLabel:Clone())({
			["Name"] = "B_VLAvatarLabel",
			["Text"] = "VL Avatar",
			["Visible"] = true,
			["Parent"] = list,
		})
		local row = Fusion.Hydrate(list.B_Template:Clone())({
			["Name"] = "B_VLAvatarRow",
			["Visible"] = true,
			["Parent"] = list,
		})
		row.Setting.Text = "Avatar Lite"
		row.ImageButton.KeyCode.Text = "Open"
		Button(row.ImageButton)({
			["OnActivated"] = function()
				local opener = getgenv().VLAvatarOpenPanel
				if opener then
					pcall(opener)
				end
			end,
		})
	end)
	if okBuild then
		S.avatarSettingsRowBuilt = true
		print("[VL Suite] Avatar settings row built (Settings > VL Avatar > Open).")
	else
		warn("[VL Suite] Avatar settings row failed: " .. tostring(err))
	end
end

-- Baris tombol Username Spoofer di daftar utama Settings,
-- pola yang sama persis dengan baris Avatar Lite di atas:
-- header BB_TextLabel + baris B_Template dengan tombol Open.
-- Tombolnya membuka panel modul username-spoof (nil-guarded
-- lewat getgenv sampai modul itu selesai init).
local function buildUsernameSettingsRow()
	if S.usernameSettingsRowBuilt then
		return
	end
	local function findList()
		local ok, found = pcall(function()
			return InterfaceController.App.Lobby.Settings.BGFrame.Body.List
		end)
		if ok and found then
			return found
		end
		local ok, found = pcall(function()
			local app = player.PlayerGui:FindFirstChild("App")
			local lobby = app and app:FindFirstChild("Lobby")
			local settings = lobby and lobby:FindFirstChild("Settings")
			local bg = settings and settings:FindFirstChild("BGFrame")
			local body = bg and bg:FindFirstChild("Body")
			return body and body:FindFirstChild("List")
		end)
		if ok and found then
			return found
		end
		return nil
	end
	local deadline = os.clock() + 120
	local list
	while os.clock() < deadline do
		list = findList()
		if list then
			break
		end
		task.wait(0.5)
	end
	if not list then
		warn("[VL Suite] Username settings list not found; row not built.")
		return
	end
	if list:FindFirstChild("B_VLUsernameRow") then
		S.usernameSettingsRowBuilt = true
		return
	end
	local okBuild, err = pcall(function()
		local Fusion = require(RS:WaitForChild("Packages"):WaitForChild("Fusion"))
		local Button = require(ReplicatedFirst:WaitForChild("Components"):WaitForChild("Button"))
		Fusion.Hydrate(list.BB_TextLabel:Clone())({
			["Name"] = "B_VLUsernameLabel",
			["Text"] = "VL Username",
			["Visible"] = true,
			["Parent"] = list,
		})
		local row = Fusion.Hydrate(list.B_Template:Clone())({
			["Name"] = "B_VLUsernameRow",
			["Visible"] = true,
			["Parent"] = list,
		})
		row.Setting.Text = "Username Spoofer"
		row.ImageButton.KeyCode.Text = "Open"
		Button(row.ImageButton)({
			["OnActivated"] = function()
				local opener = getgenv().VLUsernameOpenPanel
				if opener then
					pcall(opener)
				end
			end,
		})
	end)
	if okBuild then
		S.usernameSettingsRowBuilt = true
		print("[VL Suite] Username settings row built (Settings > VL Username > Open).")
	else
		warn("[VL Suite] Username settings row failed: " .. tostring(err))
	end
end

-- Baris tombol Stats Spoofer di daftar utama Settings, pola
-- yang sama dengan baris Avatar Lite / Username Spoofer:
-- header BB_TextLabel + baris B_Template dengan tombol Open
-- yang membuka panel modul stats-spoof (nil-guarded).
local function buildStatsSettingsRow()
	if S.statsSettingsRowBuilt then
		return
	end
	local function findList()
		local ok, found = pcall(function()
			return InterfaceController.App.Lobby.Settings.BGFrame.Body.List
		end)
		if ok and found then
			return found
		end
		local ok, found = pcall(function()
			local app = player.PlayerGui:FindFirstChild("App")
			local lobby = app and app:FindFirstChild("Lobby")
			local settings = lobby and lobby:FindFirstChild("Settings")
			local bg = settings and settings:FindFirstChild("BGFrame")
			local body = bg and bg:FindFirstChild("Body")
			return body and body:FindFirstChild("List")
		end)
		if ok and found then
			return found
		end
		return nil
	end
	local deadline = os.clock() + 120
	local list
	while os.clock() < deadline do
		list = findList()
		if list then
			break
		end
		task.wait(0.5)
	end
	if not list then
		warn("[VL Suite] Stats settings list not found; row not built.")
		return
	end
	if list:FindFirstChild("B_VLStatsRow") then
		S.statsSettingsRowBuilt = true
		return
	end
	local okBuild, err = pcall(function()
		local Fusion = require(RS:WaitForChild("Packages"):WaitForChild("Fusion"))
		local Button = require(ReplicatedFirst:WaitForChild("Components"):WaitForChild("Button"))
		Fusion.Hydrate(list.BB_TextLabel:Clone())({
			["Name"] = "B_VLStatsLabel",
			["Text"] = "VL Stats",
			["Visible"] = true,
			["Parent"] = list,
		})
		local row = Fusion.Hydrate(list.B_Template:Clone())({
			["Name"] = "B_VLStatsRow",
			["Visible"] = true,
			["Parent"] = list,
		})
		row.Setting.Text = "Stats Spoofer"
		row.ImageButton.KeyCode.Text = "Open"
		Button(row.ImageButton)({
			["OnActivated"] = function()
				local opener = getgenv().VLStatsOpenPanel
				if opener then
					pcall(opener)
				end
			end,
		})
	end)
	if okBuild then
		S.statsSettingsRowBuilt = true
		print("[VL Suite] Stats settings row built (Settings > VL Stats > Open).")
	else
		warn("[VL Suite] Stats settings row failed: " .. tostring(err))
	end
end

local function initSettings()
	local t0 = os.clock()
	if not awaitFeatureShared(90) then
		warn("[VL Suite] settings skipped: feature-shared not ready.")
		return
	end
	local tShared = os.clock()
	loadLocal()
	FeatureAPI.applyVLSettings = applyVLSettings
	if not S.installedSettings then
		S.installedSettings = true
		-- Saklar bagian Settings tambahan: ChangeSetting untuk kunci
		-- komposit milik kita ditangani lokal (server tidak mengenal
		-- kuncinya); kunci asli diteruskan ke server seperti biasa.
		if SettingsService and SettingsService.ChangeSetting then
			local originalChangeSetting = SettingsService.ChangeSetting
			SettingsService.ChangeSetting = function(_, key, value, ...)
				if key == SETTINGS_KEY_WORLD_FX then
					S.settings[SETTING_MEMBER_WORLD_FX] = value == true
					applyVLSettings()
					saveLocal()
					return resolvedPromise(true)
				end
				if key == SETTINGS_KEY_SHIFTLOCK then
					S.settings[SETTING_MEMBER_SHIFTLOCK] = value == true
					applyVLSettings()
					saveLocal()
					if FeatureAPI.setAutoShiftlockEnabled then
						task.spawn(FeatureAPI.setAutoShiftlockEnabled, value == true)
					end
					return resolvedPromise(true)
				end
				if key == SETTINGS_KEY_AUTO_RECEIVE then
					S.settings[SETTING_MEMBER_AUTO_RECEIVE] = value == true
					applyVLSettings()
					saveLocal()
					if FeatureAPI.setAutoReceiveEnabled then
						task.spawn(FeatureAPI.setAutoReceiveEnabled, value == true)
					end
					return resolvedPromise(true)
				end
				if key == SETTINGS_KEY_HITBOX then
					S.settings[SETTING_MEMBER_HITBOX] = value == true
					applyVLSettings()
					saveLocal()
					if FeatureAPI.setHitboxExpanderEnabled then
						task.spawn(FeatureAPI.setHitboxExpanderEnabled, value == true)
					end
					return resolvedPromise(true)
				end
				if key == SETTINGS_KEY_EXTREME then
					S.settings[SETTING_MEMBER_EXTREME] = value == true
					-- Balik gerbangnya langsung di sini juga, supaya
					-- alat bersama + bungkus berhenti menerapkan
					-- spoof sejak klik ini juga, lalu modul extreme
					-- mengurus visual + penyegaran terapan.
					S.extremeFast = value == true
					applyVLSettings()
					saveLocal()
					if FeatureAPI.applyExtremeFast then
						task.spawn(FeatureAPI.applyExtremeFast, value == true)
					end
					return resolvedPromise(true)
				end
				return originalChangeSetting(_, key, value, ...)
			end
		end
	end
	applyVLSettings()
	task.spawn(buildSettingsSection)
	task.spawn(buildAvatarSettingsRow)
	task.spawn(buildUsernameSettingsRow)
	task.spawn(buildStatsSettingsRow)
	print(("[VL Suite] settings ready in %.2fs (shared wait %.2fs)"):format(os.clock() - t0, tShared - t0))
	suiteModuleLoaded("settings")
end

suiteExpectModule("settings")
task.spawn(initSettings)
