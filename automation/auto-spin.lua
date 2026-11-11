----------------------------------------------------------------
-- automation/auto-spin.lua -- Bundle otomatisasi: Auto Spin
--
-- Auto spin Style & Ability untuk Volleyball Legends, satu
-- panel Settings ("VL Spin"):
--   * Daftar SEMUA style / ability yang sedang aktif dan bisa
--     didapatkan dari spin (Content.Style / Content.Ability
--     :GetActive() milik game sendiri -- item kedaluwarsa dan
--     UnobtainableStyle otomatis tersisih), diurutkan dari
--     rarity terlangka, lengkap dengan nama tampilan + warna
--     rarity resmi game.
--   * Jumlah Lucky Spins + Spins biasa terbaca langsung dari
--     Fusion Value StyleController / AbilityController (yang
--     sama yang mengikat label "Spins Left" / "Lucky Spins"
--     di UI game).
--   * Target dipilih sendiri, boleh LEBIH DARI SATU (klik baris
--     untuk menandai/melepas). Pilihan tersimpan persisten.
--   * Tombol START menjalankan putaran lewat service game
--     sendiri (StyleService:Roll(isLucky) /
--     AbilityService:Roll(isLucky) -- jalur yang sama dengan
--     tombol Spin UI; hasil yang dimenangkan = elemen terakhir
--     array hasil, persis cara StyleController membaca
--     hasilnya). Lucky dipakai lebih dulu; begitu Lucky habis
--     lanjut Spins biasa; begitu keduanya habis -> berhenti.
--   * BERHENTI OTOMATIS begitu salah satu target didapat --
--     termasuk bila target ternyata SUDAH dimiliki (cek awal:
--     ter-equip atau ada di slot mana pun), supaya tidak ada
--     spin terbuang. Spin MENIMPA slot aktif, jadi berburu
--     memang mengorbankan isi slot aktif selama prosesnya.
--   * TANPA rollback data: hasil setiap spin tersimpan apa
--     adanya. Modul ini sengaja tidak memakai trik apa pun
--     untuk membatalkan penyimpanan sesi.
--   * Persisten + auto-attach sama seperti auto farm: status
--     Enabled + target tersimpan di settings suite; saat
--     menyala, suite terantre via queue_on_teleport (lewat
--     FeatureAPI.queueAutomation milik bundle farm), jadi
--     perburuan lanjut sendiri setelah rejoin tanpa autoexec.
--   * Tidak berjalan bersamaan dengan Auto Farm (farm
--     me-respawn karakter dan mengendalikan sesi); START saat
--     farm menyala ditolak dengan pesan status.
--
-- Bagian dari bundle otomatisasi (auto-farm.lua +
-- auto-spin.lua): dimuat suite saat runtime sebagai file
-- terpisah yang di-obfuscate; kebutuhan bersama diambil dari
-- getgenv().VLBridge, BUKAN dari local chunk suite.
----------------------------------------------------------------

local SpinBridge = getgenv().VLBridge
if not SpinBridge then
	warn("[VL Suite] automation: VLBridge tidak ditemukan (suite belum siap / versi lama) -- auto spin dilewati.")
	return
end
local S = SpinBridge.S
local saveLocal = SpinBridge.saveLocal
local loadLocal = SpinBridge.loadLocal
local Knit = SpinBridge.Knit
local player = SpinBridge.player
local RS = SpinBridge.RS
local FeatureAPI = SpinBridge.FeatureAPI
local SETTINGS_SPIN_KEY = SpinBridge.SETTING_MEMBER_SPIN

local Spin = {}
Spin.StarterGui = game:GetService("StarterGui")
Spin.running = { Style = false, Ability = false }
Spin.statusText = { Style = "idle", Ability = "idle" }
Spin.currentKind = "Style"
Spin.rowButtons = {} -- [kind] = { [id] = TextButton }
Spin.listFrames = {} -- [kind] = ScrollingFrame

----------------------------------------------------------------
-- Akses data (controller / service / konten game)
----------------------------------------------------------------
function Spin.ensureSettings()
	if type(S.settings[SETTINGS_SPIN_KEY]) ~= "table" then
		S.settings[SETTINGS_SPIN_KEY] = { Style = { Enabled = false, Targets = {} }, Ability = { Enabled = false, Targets = {} } }
	end
	for _, kind in ipairs({ "Style", "Ability" }) do
		if type(S.settings[SETTINGS_SPIN_KEY][kind]) ~= "table" then
			S.settings[SETTINGS_SPIN_KEY][kind] = { Enabled = false, Targets = {} }
		end
		if type(S.settings[SETTINGS_SPIN_KEY][kind].Targets) ~= "table" then
			S.settings[SETTINGS_SPIN_KEY][kind].Targets = {}
		end
	end
end

function Spin.targets(kind)
	Spin.ensureSettings()
	return S.settings[SETTINGS_SPIN_KEY][kind].Targets
end

function Spin.acquire()
	local deadline = os.clock() + 90
	repeat
		pcall(function()
			Spin.StyleCtrl = Knit.GetController("StyleController")
			Spin.AbilityCtrl = Knit.GetController("AbilityController")
			Spin.TeamSelCtrl = Knit.GetController("TeamSelectionController")
			Spin.StyleService = Knit.GetService("StyleService")
			Spin.AbilityService = Knit.GetService("AbilityService")
		end)
		pcall(function()
			Spin.StyleMod = require(RS:WaitForChild("Content"):WaitForChild("Style"))
		end)
		pcall(function()
			Spin.AbilityMod = require(RS:WaitForChild("Content"):WaitForChild("Ability"))
		end)
		task.wait(0.25)
	until (Spin.StyleCtrl and Spin.AbilityCtrl and Spin.StyleService and Spin.AbilityService and Spin.StyleMod and Spin.AbilityMod)
		or os.clock() > deadline
	return Spin.StyleCtrl ~= nil and Spin.AbilityCtrl ~= nil
		and Spin.StyleService ~= nil and Spin.AbilityService ~= nil
end

function Spin.contentMod(kind)
	return kind == "Style" and Spin.StyleMod or Spin.AbilityMod
end

function Spin.controller(kind)
	return kind == "Style" and Spin.StyleCtrl or Spin.AbilityCtrl
end

-- Daftar item yang bisa didapatkan dari spin saat ini:
-- GetActive() milik konten game menyisihkan yang kedaluwarsa /
-- belum aktif; "UnobtainableStyle" disisihkan manual (ia lolos
-- isActive karena Timestamp-nya updateOn masa depan -- terlihat
-- dari Timestamp.hasEnded di isExpired).
function Spin.listItems(kind)
	local mod = Spin.contentMod(kind)
	local out = {}
	if not mod then
		return out
	end
	local ok, act = pcall(function()
		return mod:GetActive()
	end)
	if ok and type(act) == "table" then
		for _, data in ipairs(act) do
			if data and data.Id and data.Id ~= "UnobtainableStyle" then
				table.insert(out, data)
			end
		end
	end
	-- Terlangka dulu (nilai Rarity kecil = lebih langka), lalu
	-- nama tampilan A-Z.
	table.sort(out, function(a, b)
		local ra, rb = a.Rarity or 99, b.Rarity or 99
		if ra ~= rb then
			return ra < rb
		end
		return tostring(a.DisplayName or a.Id) < tostring(b.DisplayName or b.Id)
	end)
	return out
end

function Spin.rarityName(kind, rarity)
	local mod = Spin.contentMod(kind)
	if mod and mod.Rarity and mod.Rarity.Data and rarity ~= nil then
		local d = mod.Rarity.Data[rarity]
		if d and d.Name then
			return d.Name
		end
	end
	return "?"
end

function Spin.rarityColor(kind, rarity)
	local mod = Spin.contentMod(kind)
	if mod and mod.Rarity and mod.Rarity.Data and rarity ~= nil then
		local d = mod.Rarity.Data[rarity]
		if d and d.Color then
			return d.Color
		end
	end
	return Color3.fromRGB(200, 200, 200)
end

-- Sisa spin (Fusion Value controller; pola :get() pcall yang
-- sama seperti UI game membacanya).
function Spin.counts(kind)
	local ctrl = Spin.controller(kind)
	local spins, lucky = 0, 0
	if ctrl then
		pcall(function()
			spins = ctrl.Spins and ctrl.Spins:get() or 0
		end)
		pcall(function()
			lucky = ctrl.LuckySpins and ctrl.LuckySpins:get() or 0
		end)
	end
	return spins, lucky
end

-- Daftar id yang dimiliki (semua slot) + id ter-equip.
function Spin.ownedIds(kind)
	local ids = {}
	local equipped = nil
	if kind == "Style" then
		pcall(function()
			local list = Spin.TeamSelCtrl and Spin.TeamSelCtrl.Styles and Spin.TeamSelCtrl.Styles:get()
			if type(list) == "table" then
				for _, id in ipairs(list) do
					if type(id) == "string" then
						ids[id] = true
					end
				end
				local slot = Spin.TeamSelCtrl.CurrentStyleSlot and Spin.TeamSelCtrl.CurrentStyleSlot:get() or 1
				equipped = list[slot]
			end
		end)
	else
		pcall(function()
			local ctrl = Spin.AbilityCtrl
			local list = ctrl and ctrl.Abilities and ctrl.Abilities:get()
			if type(list) == "table" then
				for _, id in ipairs(list) do
					if type(id) == "string" then
						ids[id] = true
					end
				end
				local slot = ctrl.CurrentAbilitySlot and ctrl.CurrentAbilitySlot:get() or 1
				equipped = list[slot]
			end
		end)
	end
	return ids, equipped
end

-- Target yang sudah dimiliki (untuk cek awal + penanda daftar).
function Spin.ownedTarget(kind)
	local targets = Spin.targets(kind)
	local owned = Spin.ownedIds(kind)
	for id in pairs(targets) do
		if owned[id] then
			return id
		end
	end
	return nil
end

function Spin.notify(title, text)
	pcall(function()
		Spin.StarterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = 6 })
	end)
end

function Spin.setStatus(kind, txt)
	Spin.statusText[kind] = txt
	print(("[VL Suite] auto spin %s: %s"):format(kind, txt))
	Spin.refreshPanel()
end

----------------------------------------------------------------
-- Mesin spin
----------------------------------------------------------------
function Spin.doRoll(kind, isLucky)
	local svc = kind == "Style" and Spin.StyleService or Spin.AbilityService
	local ok, a, b = pcall(function()
		local r1, r2 = svc:Roll(isLucky):await()
		return r1, r2
	end)
	return ok, a, b
end

-- Hasil Roll = (bool, array id); yang dimenangkan = elemen
-- terakhir array (pola StyleController.Spin game sendiri).
function Spin.winnerOf(a, b)
	local arr = nil
	if type(b) == "table" and #b > 0 then
		arr = b
	elseif type(a) == "table" and #a > 0 then
		arr = a
	end
	if arr then
		local last = arr[#arr]
		if type(last) == "string" then
			return last
		end
	end
	return nil
end

function Spin.stop(kind, reason)
	Spin.running[kind] = false
	Spin.ensureSettings()
	S.settings[SETTINGS_SPIN_KEY][kind].Enabled = false
	saveLocal()
	Spin.setStatus(kind, reason)
	Spin.refreshPanel()
end

function Spin.runEngine(kind)
	if Spin.running[kind] then
		return
	end
	local targets = Spin.targets(kind)
	if not next(targets) then
		Spin.setStatus(kind, "pilih minimal 1 target dulu")
		return
	end
	if S.autoFarmRunning then
		Spin.setStatus(kind, "auto farm sedang jalan -- matikan farm dulu")
		return
	end
	-- Cek awal: target sudah dimiliki -> jangan buang spin.
	local owned = Spin.ownedTarget(kind)
	if owned then
		Spin.stop(kind, "target " .. owned .. " SUDAH dimiliki -- tidak spin")
		Spin.notify("Auto Spin " .. kind, "Sudah punya " .. owned .. ", tidak spin.")
		return
	end
	Spin.running[kind] = true
	Spin.ensureSettings()
	S.settings[SETTINGS_SPIN_KEY][kind].Enabled = true
	saveLocal()
	if FeatureAPI.queueAutomation then
		pcall(FeatureAPI.queueAutomation)
	end
	Spin.setStatus(kind, "berburu target...")
	task.spawn(function()
		local used = 0
		local rejectStreak = 0
		while Spin.running[kind] do
			local spins, lucky = Spin.counts(kind)
			if spins + lucky <= 0 then
				Spin.stop(kind, ("spin habis setelah %d putaran, target belum didapat"):format(used))
				Spin.notify("Auto Spin " .. kind, "Spin habis, target belum didapat.")
				break
			end
			local ok, a, b = Spin.doRoll(kind, lucky > 0)
			if not ok then
				rejectStreak = rejectStreak + 1
				if rejectStreak >= 5 then
					Spin.stop(kind, "roll error beruntun -- berhenti")
					break
				end
				task.wait(1)
			elseif a == false then
				-- Server menolak (biasanya balapan debounce /
				-- status belum siap): tunggu, nilai ulang dari
				-- sisa spin; berhenti bila ditolak terus.
				rejectStreak = rejectStreak + 1
				if rejectStreak >= 10 then
					Spin.stop(kind, "server menolak terus -- berhenti")
					break
				end
				task.wait(0.6)
			else
				rejectStreak = 0
				used = used + 1
				local winner = Spin.winnerOf(a, b)
				if winner then
					local mod = Spin.contentMod(kind)
					local name = winner
					pcall(function()
						local d = mod and mod:Get(winner)
						if d and d.DisplayName then
							name = d.DisplayName
						end
					end)
					Spin.setStatus(kind, ("putaran #%d: %s (sisa lucky %d, biasa %d)"):format(used, name, Spin.counts(kind)))
					if targets[winner] then
						Spin.stop(kind, ("DAPAT TARGET %s setelah %d putaran"):format(name, used))
						Spin.notify("Auto Spin " .. kind, "DAPAT " .. name .. "!")
						break
					end
				else
					Spin.setStatus(kind, ("putaran #%d: hasil tidak terbaca"):format(used))
				end
				task.wait(0.65)
			end
		end
	end)
end

function Spin.setEnabled(kind, on)
	if on then
		Spin.runEngine(kind)
	else
		if Spin.running[kind] or S.settings[SETTINGS_SPIN_KEY][kind].Enabled then
			Spin.stop(kind, "dimatikan manual")
		end
	end
	Spin.refreshPanel()
end

----------------------------------------------------------------
-- Panel Settings "VL Spin"
-- Tata letak: judul + tab Style|Ability + label jumlah spin +
-- daftar gulir target (klik = tandai/lepas) + tombol START/STOP
-- + status + catatan. Satu panel untuk dua jenis; tab menukar
-- daftar + konteks tombolnya.
----------------------------------------------------------------
function Spin.refreshRow(kind, id)
	local btn = Spin.rowButtons[kind] and Spin.rowButtons[kind][id]
	if not btn then
		return
	end
	local selected = Spin.targets(kind)[id] == true
	local owned = Spin.ownedIds(kind)[id] == true
	local base = btn:GetAttribute("BaseText") or id
	btn.Text = (selected and "[TARGET] " or "") .. base .. (owned and "  (dimiliki)" or "")
	btn.BackgroundColor3 = selected and Color3.fromRGB(24, 110, 55) or Color3.fromRGB(44, 44, 54)
end

function Spin.buildList(kind)
	local frame = Spin.listFrames[kind]
	if not frame then
		return
	end
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	Spin.rowButtons[kind] = {}
	local items = Spin.listItems(kind)
	for _, data in ipairs(items) do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, -6, 0, 26)
		btn.BackgroundColor3 = Color3.fromRGB(44, 44, 54)
		btn.Font = Enum.Font.Gotham
		btn.TextSize = 13
		btn.TextColor3 = Spin.rarityColor(kind, data.Rarity)
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.Text = ("%s  (%s)"):format(data.DisplayName or data.Id, Spin.rarityName(kind, data.Rarity))
		btn:SetAttribute("BaseText", btn.Text)
		btn.Parent = frame
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 6)
		bc.Parent = btn
		local id = data.Id
		btn.Activated:Connect(function()
			local targets = Spin.targets(kind)
			if targets[id] then
				targets[id] = nil
			else
				targets[id] = true
			end
			saveLocal()
			Spin.refreshRow(kind, id)
			Spin.refreshPanel()
		end)
		Spin.rowButtons[kind][id] = btn
		Spin.refreshRow(kind, id)
	end
end

function Spin.refreshCounts()
	if not Spin.countsLbl then
		return
	end
	local kind = Spin.currentKind
	local spins, lucky = Spin.counts(kind)
	local nTargets = 0
	for _ in pairs(Spin.targets(kind)) do
		nTargets = nTargets + 1
	end
	Spin.countsLbl.Text = ("Lucky %s Spins: %d   |   Spins biasa: %d   |   Target dipilih: %d"):format(kind, lucky, spins, nTargets)
end

function Spin.refreshPanel()
	if not Spin.panelGui then
		return
	end
	Spin.refreshCounts()
	if Spin.statusLbl then
		Spin.statusLbl.Text = "Status " .. Spin.currentKind .. ": " .. (Spin.statusText[Spin.currentKind] or "idle")
	end
	if Spin.runBtn then
		local kind = Spin.currentKind
		if Spin.running[kind] then
			Spin.runBtn.Text = "STOP " .. kind:upper() .. " SPIN"
			Spin.runBtn.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
		else
			Spin.runBtn.Text = "START " .. kind:upper() .. " SPIN"
			Spin.runBtn.BackgroundColor3 = Color3.fromRGB(24, 130, 60)
		end
	end
	for _, kind in ipairs({ "Style", "Ability" }) do
		local tab = Spin.tabBtns and Spin.tabBtns[kind]
		if tab then
			tab.BackgroundColor3 = Spin.currentKind == kind and Color3.fromRGB(70, 70, 92) or Color3.fromRGB(44, 44, 54)
		end
		local frame = Spin.listFrames[kind]
		if frame then
			frame.Visible = Spin.currentKind == kind
		end
	end
end

function Spin.buildPanel()
	if Spin.panelGui then
		return Spin.panelGui
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "VLSpinPanelGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Enabled = false

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.Size = UDim2.fromOffset(380, 520)
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
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.Parent = frame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -40, 0, 26)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Auto Spin"
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

	Spin.tabBtns = {}
	for i, kind in ipairs({ "Style", "Ability" }) do
		local tab = Instance.new("TextButton")
		tab.Size = UDim2.new(0.5, -4, 0, 34)
		tab.Position = UDim2.new((i - 1) * 0.5, (i - 1) * 4, 0, 36)
		tab.BackgroundColor3 = Color3.fromRGB(44, 44, 54)
		tab.Font = Enum.Font.GothamBold
		tab.TextSize = 14
		tab.TextColor3 = Color3.fromRGB(255, 255, 255)
		tab.Text = kind
		tab.Parent = frame
		local tc = Instance.new("UICorner")
		tc.CornerRadius = UDim.new(0, 8)
		tc.Parent = tab
		tab.Activated:Connect(function()
			Spin.currentKind = kind
			Spin.refreshPanel()
		end)
		Spin.tabBtns[kind] = tab
	end

	Spin.countsLbl = Instance.new("TextLabel")
	Spin.countsLbl.Size = UDim2.new(1, 0, 0, 18)
	Spin.countsLbl.Position = UDim2.fromOffset(0, 76)
	Spin.countsLbl.BackgroundTransparency = 1
	Spin.countsLbl.Font = Enum.Font.Gotham
	Spin.countsLbl.TextSize = 12
	Spin.countsLbl.TextColor3 = Color3.fromRGB(190, 190, 200)
	Spin.countsLbl.TextXAlignment = Enum.TextXAlignment.Left
	Spin.countsLbl.Text = ""
	Spin.countsLbl.Parent = frame

	for _, kind in ipairs({ "Style", "Ability" }) do
		local scroll = Instance.new("ScrollingFrame")
		scroll.Name = "List" .. kind
		scroll.Size = UDim2.new(1, 0, 0, 264)
		scroll.Position = UDim2.fromOffset(0, 98)
		scroll.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
		scroll.BackgroundTransparency = 0.3
		scroll.BorderSizePixel = 0
		scroll.ScrollBarThickness = 4
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		scroll.Visible = false
		scroll.Parent = frame
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 4)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = scroll
		local sc = Instance.new("UICorner")
		sc.CornerRadius = UDim.new(0, 8)
		sc.Parent = scroll
		Spin.listFrames[kind] = scroll
	end

	Spin.runBtn = Instance.new("TextButton")
	Spin.runBtn.Size = UDim2.new(1, 0, 0, 44)
	Spin.runBtn.Position = UDim2.fromOffset(0, 370)
	Spin.runBtn.BackgroundColor3 = Color3.fromRGB(24, 130, 60)
	Spin.runBtn.Font = Enum.Font.GothamBold
	Spin.runBtn.TextSize = 15
	Spin.runBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	Spin.runBtn.Text = "START STYLE SPIN"
	Spin.runBtn.Parent = frame
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(0, 8)
	rc.Parent = Spin.runBtn
	Spin.runBtn.Activated:Connect(function()
		local kind = Spin.currentKind
		Spin.setEnabled(kind, not Spin.running[kind])
	end)

	Spin.statusLbl = Instance.new("TextLabel")
	Spin.statusLbl.Size = UDim2.new(1, 0, 0, 18)
	Spin.statusLbl.Position = UDim2.fromOffset(0, 422)
	Spin.statusLbl.BackgroundTransparency = 1
	Spin.statusLbl.Font = Enum.Font.Gotham
	Spin.statusLbl.TextSize = 12
	Spin.statusLbl.TextColor3 = Color3.fromRGB(255, 210, 90)
	Spin.statusLbl.TextXAlignment = Enum.TextXAlignment.Left
	Spin.statusLbl.Text = ""
	Spin.statusLbl.Parent = frame

	local note = Instance.new("TextLabel")
	note.Size = UDim2.new(1, 0, 0, 56)
	note.Position = UDim2.fromOffset(0, 444)
	note.BackgroundTransparency = 1
	note.Font = Enum.Font.Gotham
	note.TextSize = 11
	note.TextColor3 = Color3.fromRGB(140, 140, 152)
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.TextYAlignment = Enum.TextYAlignment.Top
	note.TextWrapped = true
	note.Text = "Klik baris untuk memilih target (boleh lebih dari satu). Spin menimpa isi slot aktif. Berhenti otomatis saat target didapat atau spin habis. Tanpa rollback: setiap hasil tersimpan."
	note.Parent = frame

	local parented = pcall(function()
		gui.Parent = player:WaitForChild("PlayerGui")
	end)
	if not parented or not gui.Parent then
		pcall(function()
			gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
		end)
	end
	Spin.panelGui = gui
	return gui
end

function Spin.openPanel()
	Spin.buildPanel()
	-- Daftar dibangun ulang tiap panel dibuka: item aktif,
	-- kepemilikan, dan jumlah spin selalu yang terbaru.
	Spin.buildList("Style")
	Spin.buildList("Ability")
	Spin.refreshPanel()
	if Spin.panelGui then
		Spin.panelGui.Enabled = true
	end
end

----------------------------------------------------------------
-- Init bundle auto spin
----------------------------------------------------------------
local function initAutoSpin()
	if not (VLBridge.awaitFeatureShared and VLBridge.awaitFeatureShared(90)) then
		warn("[VL Suite] automation: feature-shared tidak siap -- auto spin dilewati.")
		return
	end
	loadLocal()
	Spin.ensureSettings()
	if not Spin.acquire() then
		warn("[VL Suite] automation: controller/service spin tidak lengkap -- auto spin dilewati.")
		return
	end
	FeatureAPI.openAutoSpinPanel = Spin.openPanel
	FeatureAPI.setAutoSpinEnabled = Spin.setEnabled
	getgenv().VLSpinOpenPanel = Spin.openPanel
	-- Segarkan label jumlah spin selama panel terbuka.
	task.spawn(function()
		while true do
			task.wait(2)
			if Spin.panelGui and Spin.panelGui.Enabled then
				Spin.refreshCounts()
			end
		end
	end)
	-- Lanjutkan perburuan yang tersimpan (beri waktu lobby siap).
	for _, kind in ipairs({ "Style", "Ability" }) do
		if S.settings[SETTINGS_SPIN_KEY][kind].Enabled then
			task.delay(5, function()
				if S.settings[SETTINGS_SPIN_KEY][kind].Enabled and not Spin.running[kind] then
					Spin.runEngine(kind)
				end
			end)
		end
	end
	print("[VL Suite] automation: auto spin ready.")
end

task.spawn(initAutoSpin)
