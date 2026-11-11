----------------------------------------------------------------
-- modules/username-spoof.lua -- Modul fitur: Username Spoofer
--
-- Mengganti tampilan username + display name pemain lokal di
-- permukaan GUI game (leaderboard, kartu pemain, statistik,
-- panel spectate, lobi, skor pertandingan, chat) dengan nama
-- pilihan sendiri. CLIENT-SIDE saja: yang berubah hanya teks
-- di layar sendiri; server dan pemain lain tetap melihat nama
-- asli. Nametag di atas kepala ikut diganti lewat
-- Humanoid.DisplayName (properti yang dipakai renderer engine
-- untuk nama di atas karakter, dan bisa ditulis lokal);
-- diterapkan ulang tiap respawn dan dijaga sapuan berkala.
--
-- Mesinnya sapuan teks (text sweep): setiap TextLabel /
-- TextButton di PlayerGui + CoreGui yang teksnya memuat nama
-- asli ditimpa dengan nama spoof; teks asli dicatat agar Reset
-- memulihkan persis. Objek GUI baru diawasi lewat
-- DescendantAdded; label yang sudah kena diawasi perubahan
-- Text-nya (game menggambar ulang nama saat event, misalnya
-- papan skor); sapuan berkala menutup objek yang lolos dari
-- dua jalur itu.
--
-- UI-nya panel kecil berisi TextBox + tombol Apply yang
-- merupakan KLON dari kotak redeem code bawaan game sendiri
-- (Shop > Codes > Body.EnterBox / Body.EnterButton) -- pola
-- yang sama seperti redeem: teks dibaca saat Apply diklik
-- atau FocusLost ber-Enter. Panel dibuka dari baris Settings
-- "Username Spoofer" (modules/settings.lua) lewat
-- getgenv().VLUsernameOpenPanel / FeatureAPI.openUsernameSpoofer.
-- Nama spoof tersimpan di simpanan lokal (S.settings kunci
-- UsernameSpoof) dan diterapkan lagi otomatis saat masuk game.
--
-- BUKAN kategori inventory (tidak memakai suiteActivateFeature)
-- dan tidak digerbang Extreme Ultra Fast Mode, sama seperti
-- auto-shiftlock: ini fitur tampilan, bukan spoof inventory.
----------------------------------------------------------------

local realName = player.Name
local realDisplay = player.DisplayName or player.Name

local spoofName = nil -- nama spoof aktif; nil = mati
local engineOn = false
local roots = {} -- akar GUI yang diawasi (PlayerGui + CoreGui)
local rootConns = {} -- koneksi DescendantAdded
local originals = setmetatable({}, { __mode = "k" }) -- [obj] = teks asli
local textConns = setmetatable({}, { __mode = "k" }) -- [obj] = koneksi Text
local settingText = false -- penanda kita sendiri sedang menulis Text

local panelGui = nil
local inputBox = nil
local statusLabel = nil

-- Pola Lua untuk nama asli: DisplayName bisa memuat karakter
-- ajaib pola apa pun, jadi semua non-kata diloloskan.
local function escapePattern(s)
	return (s:gsub("%W", "%%%1"))
end
local displayPat = escapePattern(realDisplay)
local namePat = escapePattern(realName)

-- Teks hasil spoof, atau nil bila teks tidak memuat nama asli.
-- Penggantian memakai fungsi agar nama spoof yang memuat '%'
-- tidak ditafsirkan sebagai tangkapan pola.
local function spoofedText(text)
	if not spoofName or type(text) ~= "string" or text == "" then
		return nil
	end
	local out = text
	if realDisplay ~= "" then
		out = out:gsub(displayPat, function()
			return spoofName
		end)
	end
	if realName ~= "" and realName ~= realDisplay then
		out = out:gsub(namePat, function()
			return spoofName
		end)
	end
	if out == text then
		return nil
	end
	return out
end

local function setText(obj, text)
	settingText = true
	pcall(function()
		obj.Text = text
	end)
	settingText = false
end

local applyTo -- forward declaration (dipakai watchText)

-- Awasi perubahan Text sebuah label yang sudah kena spoof:
-- bila game menggambar ulangnya dengan nama asli, timpa lagi.
local function watchText(obj)
	if textConns[obj] then
		return
	end
	local ok, conn = pcall(function()
		return obj:GetPropertyChangedSignal("Text"):Connect(function()
			if settingText then
				return
			end
			applyTo(obj)
		end)
	end)
	if ok then
		textConns[obj] = conn
	end
end

applyTo = function(obj)
	if not spoofName then
		return
	end
	if panelGui and obj:IsDescendantOf(panelGui) then
		return
	end
	if not (obj:IsA("TextLabel") or obj:IsA("TextButton")) then
		return
	end
	local current = obj.Text
	if originals[obj] == nil then
		local newText = spoofedText(current)
		if newText then
			originals[obj] = current
			setText(obj, newText)
			watchText(obj)
		end
	else
		-- Sudah dilacak. Bila teks sekarang bukan lagi hasil
		-- spoof dari baseline (game menggambar ulang), catat
		-- teks barunya sebagai baseline dan timpa lagi.
		if current ~= spoofedText(originals[obj]) then
			local newText = spoofedText(current)
			if newText then
				originals[obj] = current
				setText(obj, newText)
			end
		end
	end
end

local function sweepRoot(root)
	if not (root and root.Parent) then
		return
	end
	for _, obj in ipairs(root:GetDescendants()) do
		applyTo(obj)
	end
end

-- Nametag di atas kepala: renderer engine menggambarnya dari
-- Humanoid.DisplayName. Properti itu bisa ditulis dari sisi
-- klien, jadi nametag lokal ikut diganti. (Player.DisplayName
-- sendiri read-only -- itu yang tidak bisa disentuh.)
local function applyHumanoidName()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		pcall(function()
			hum.DisplayName = spoofName or realDisplay
		end)
	end
end

local function sweepAll()
	for _, root in ipairs(roots) do
		sweepRoot(root)
	end
	if spoofName then
		-- Tegaskan lagi nametag tiap sapuan: menutup bila game
		-- atau respawn mengembalikannya ke nama asli.
		applyHumanoidName()
	end
end

local function startEngine()
	if engineOn then
		return
	end
	engineOn = true
	table.clear(roots)
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg then
		table.insert(roots, pg)
	end
	local core
	pcall(function()
		core = (gethui and gethui()) or game:GetService("CoreGui")
	end)
	if core and core ~= pg then
		table.insert(roots, core)
	end
	for _, root in ipairs(roots) do
		local ok, conn = pcall(function()
			return root.DescendantAdded:Connect(function(obj)
				applyTo(obj)
			end)
		end)
		if ok then
			table.insert(rootConns, conn)
		end
	end
	-- Karakter baru (respawn) membawa Humanoid baru dengan
	-- nama asli; terapkan lagi nama spoof-nya.
	local okChar, charConn = pcall(function()
		return player.CharacterAdded:Connect(function(char)
			local hum = char:WaitForChild("Humanoid", 5)
			if hum and spoofName then
				pcall(function()
					hum.DisplayName = spoofName
				end)
			end
		end)
	end)
	if okChar then
		table.insert(rootConns, charConn)
	end
	sweepAll()
	-- Sapuan berkala: menutup label yang teksnya berubah tanpa
	-- pernah kena (mis. papan skor yang digambar sekali di awal).
	task.spawn(function()
		while engineOn do
			task.wait(2.5)
			if engineOn then
				sweepAll()
			end
		end
	end)
end

local function stopEngine()
	engineOn = false
	for _, conn in ipairs(rootConns) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	table.clear(rootConns)
	for obj, conn in pairs(textConns) do
		pcall(function()
			conn:Disconnect()
		end)
		-- Kosongkan entri juga: koneksi mati yang tertinggal
		-- akan membuat watchText melewatkan objek ini saat
		-- spoof dinyalakan lagi setelah Reset.
		textConns[obj] = nil
	end
end

-- Pulihkan semua teks ke aslinya dan kosongkan catatan.
local function restoreAll()
	for obj, orig in pairs(originals) do
		if obj and obj.Parent then
			setText(obj, orig)
		end
	end
	for k in pairs(originals) do
		originals[k] = nil
	end
end

local function updatePanelStatus()
	if statusLabel then
		if spoofName then
			statusLabel.Text = "Nama tampil saat ini: " .. spoofName .. " (spoof aktif)"
		else
			statusLabel.Text = "Nama tampil saat ini: " .. realDisplay .. " (asli)"
		end
	end
end

local function setSpoof(name)
	name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then
		return
	end
	if #name > 32 then
		name = name:sub(1, 32)
	end
	if spoofName and spoofName ~= name then
		-- Ganti nama: pulihkan baseline dulu agar catatan teks
		-- asli tidak terkontaminasi nama spoof sebelumnya.
		spoofName = nil
		restoreAll()
	end
	spoofName = name
	S.settings[SETTING_MEMBER_USERNAME] = name
	saveLocal()
	startEngine()
	sweepAll()
	updatePanelStatus()
end

local function clearSpoof()
	spoofName = nil
	restoreAll()
	applyHumanoidName() -- spoofName nil -> kembali ke nama asli
	stopEngine()
	S.settings[SETTING_MEMBER_USERNAME] = ""
	saveLocal()
	updatePanelStatus()
end

----------------------------------------------------------------
-- Panel UI (klon kotak redeem code bawaan game)
----------------------------------------------------------------

-- Cari EnterBox + EnterButton milik bagian Codes di Shop.
local function findCodesParts()
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil, nil
	end
	for _, desc in ipairs(pg:GetDescendants()) do
		if desc.Name == "Codes" then
			local body = desc:FindFirstChild("Body")
			local box = body and body:FindFirstChild("EnterBox")
			local btn = body and body:FindFirstChild("EnterButton")
			if box and box:IsA("TextBox") and btn and btn:IsA("GuiButton") then
				return box, btn
			end
		end
	end
	return nil, nil
end

-- Klon bersih: buang semua BaseScript di dalamnya agar tidak
-- ada logika game yang ikut terbawa ke panel kita.
local function cleanedClone(src)
	local clone = src:Clone()
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	return clone
end

local function setButtonText(btn, text)
	pcall(function()
		btn.Text = text
	end)
	for _, d in ipairs(btn:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			d.Text = text
		end
	end
end

local function buildPanel()
	if panelGui then
		return panelGui
	end
	local codesBox, codesBtn = findCodesParts()

	local gui = Instance.new("ScreenGui")
	gui.Name = "VLUsernameSpoofGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Enabled = false

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.Size = UDim2.fromOffset(360, 224)
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
	title.Name = "Title"
	title.Size = UDim2.new(1, -40, 0, 26)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Username Spoofer"
	title.Parent = frame

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Close"
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

	statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.new(1, 0, 0, 20)
	statusLabel.Position = UDim2.fromOffset(0, 34)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextSize = 13
	statusLabel.TextColor3 = Color3.fromRGB(190, 190, 200)
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Text = ""
	statusLabel.Parent = frame

	-- Kotak input: klon EnterBox redeem code bila ketemu,
	-- kalau tidak bangun TextBox polos bergaya sama.
	local box
	if codesBox then
		box = cleanedClone(codesBox)
	else
		box = Instance.new("TextBox")
		box.BackgroundColor3 = Color3.fromRGB(38, 38, 46)
		box.Font = Enum.Font.Gotham
		box.TextSize = 15
		box.TextColor3 = Color3.fromRGB(255, 255, 255)
		box.PlaceholderColor3 = Color3.fromRGB(150, 150, 160)
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 8)
		bc.Parent = box
	end
	box.Name = "UsernameBox"
	box.Size = UDim2.new(1, 0, 0, 46)
	box.Position = UDim2.fromOffset(0, 62)
	box.Text = ""
	box.PlaceholderText = "Type username here"
	box.ClearTextOnFocus = false
	box.Parent = frame
	inputBox = box

	local function makeActionButton(name, text, width, x)
		local btn
		if codesBtn then
			btn = cleanedClone(codesBtn)
			setButtonText(btn, text)
		else
			btn = Instance.new("TextButton")
			btn.BackgroundColor3 = Color3.fromRGB(64, 120, 242)
			btn.Font = Enum.Font.GothamBold
			btn.TextSize = 15
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
			btn.Text = text
			local bc = Instance.new("UICorner")
			bc.CornerRadius = UDim.new(0, 8)
			bc.Parent = btn
		end
		btn.Name = name
		btn.Size = UDim2.fromOffset(width, 46)
		btn.Position = UDim2.fromOffset(x, 120)
		btn.Parent = frame
		return btn
	end

	local applyBtn = makeActionButton("ApplyButton", "Apply", 208, 0)
	local resetBtn = makeActionButton("ResetButton", "Reset", 112, 216)

	local note = Instance.new("TextLabel")
	note.Name = "Note"
	note.Size = UDim2.new(1, 0, 0, 30)
	note.Position = UDim2.fromOffset(0, 176)
	note.BackgroundTransparency = 1
	note.Font = Enum.Font.Gotham
	note.TextSize = 11
	note.TextColor3 = Color3.fromRGB(140, 140, 152)
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.TextWrapped = true
	note.Text = "Client-side saja: hanya tampilan di layarmu, termasuk nametag di atas kepala. Pemain lain tetap melihat nama asli."
	note.Parent = frame

	local function doApply()
		if inputBox then
			setSpoof(inputBox.Text)
		end
	end
	applyBtn.Activated:Connect(doApply)
	resetBtn.Activated:Connect(function()
		clearSpoof()
		if inputBox then
			inputBox.Text = ""
		end
	end)
	closeBtn.Activated:Connect(function()
		gui.Enabled = false
	end)
	-- Sama seperti redeem code: teks dibaca saat FocusLost.
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			doApply()
		end
	end)

	local parented = pcall(function()
		gui.Parent = player:WaitForChild("PlayerGui")
	end)
	if not parented or not gui.Parent then
		pcall(function()
			gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
		end)
	end
	panelGui = gui
	updatePanelStatus()
	return gui
end

local function openPanel()
	buildPanel()
	if inputBox then
		inputBox.Text = spoofName or ""
	end
	updatePanelStatus()
	panelGui.Enabled = true
end

local function initUsernameSpoof()
	local t0 = os.clock()
	if not awaitFeatureShared(90) then
		warn("[VL Suite] username-spoof skipped: feature-shared not ready.")
		return
	end
	local tShared = os.clock()
	loadLocal()
	FeatureAPI.openUsernameSpoofer = openPanel
	getgenv().VLUsernameOpenPanel = openPanel
	-- Terapkan lagi nama spoof tersimpan dari sesi sebelumnya.
	local saved = S.settings[SETTING_MEMBER_USERNAME]
	if type(saved) == "string" and saved ~= "" then
		setSpoof(saved)
	end
	print(("[VL Suite] username-spoof ready in %.2fs (shared wait %.2fs)"):format(os.clock() - t0, tShared - t0))
	suiteModuleLoaded("username-spoof")
end

suiteExpectModule("username-spoof")
task.spawn(initUsernameSpoof)
