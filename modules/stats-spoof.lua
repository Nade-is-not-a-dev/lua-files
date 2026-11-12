----------------------------------------------------------------
-- modules/stats-spoof.lua -- Modul fitur: Stats Spoofer
--
-- Mengganti angka statistik pemain lokal di tiga permukaan
-- tampilan (client-side saja; data server dan layar pemain
-- lain tidak berubah):
--
--  1. FLASH CARD (kartu saat mencetak poin + kartu MVP):
--     DisplayFlashCard menerima Context.Custom {Wins, Losses,
--     SeasonRank} dan Context.SingleStat (nilai stat tunggal
--     yang ditampilkan kartu ber-Metadata.Stat). Modul ini
--     membungkus DisplayFlashCard SETELAH bungkus player-card
--     dan menimpa angka-angkanya khusus untuk pemain lokal.
--     SeasonRank dihitung dari Elo spoof memakai fungsi game
--     sendiri (Configuration.Ranks.getRankFromElo/isUnranked).
--  2. HALAMAN CAREER (tab Career Stats): dirender dari Fusion
--     Value CareerController.Career (salinan lokal profil
--     "Career"). Nilai itu ditimpa dengan klon berisi angka
--     spoof; sinkronisasi server (DataService.ProfileUpdated
--     "Career" + CareerService.DataUpdated) dicerminkan ke
--     snapshot asli lalu ditimpa lagi -- handler kita terhubung
--     SETELAH handler game, jadi jalan belakangan.
--  3. TAB RANKED: InterfaceController.Ranked adalah Computed
--     dari Fusion Value InterfaceController.Seasonal (bidang
--     .Ranked = tabel per tipe {Elo, Wins, Games}). Seasonal
--     ditimpa klon dengan .Ranked hasil spoof: tipe Seasonal
--     membawa Wins/Games/Elo target, tipe lain di-nol-kan agar
--     agregat halaman (Wins total, Losses = Games - Wins,
--     Highest Rank) persis angka panel. RankedService.
--     DataUpdated dicerminkan ke snapshot asli juga.
--
-- Field panel: Wins, Losses, MVPs, Games, Points, Spikes,
-- Blocks, Aces, Saves, Elo. Kotak yang dikosongkan tidak
-- di-spoof (tampil asli). Reset memulihkan Career + Seasonal
-- ke snapshot asli terakhir dan mematikan bungkus flash.
--
-- Panel dibuka dari baris Settings "Stats Spoofer"
-- (modules/settings.lua) lewat getgenv().VLStatsOpenPanel /
-- FeatureAPI.openStatsSpoofer. Nilai tersimpan di simpanan
-- lokal (S.settings kunci StatsSpoof) dan diterapkan lagi
-- otomatis saat masuk game.
--
-- Fitur ini DIGERBANG Extreme
-- Ultra Fast Mode (S.extremeFast): saat Extreme menyala,
-- statistik asli tampil lagi (reconcile berkala yang
-- menegakkannya), sesuai desain "semua spoof mati" milik
-- Extreme. BUKAN kategori inventory.
--
-- CATATAN TEKNIS: seluruh state + fungsi modul ini hidup di
-- SATU tabel lokal (Stats). File gabungan dist adalah satu
-- chunk; total local di scope chunk dibatasi Luau (200
-- register) dan modul-modul sebelumnya sudah memakai
-- sebagian besar -- modul baru WAJIB hemat local seperti ini.
----------------------------------------------------------------

local Stats = {
	STAT_FIELDS = { "Wins", "Losses", "MVPs", "Games", "Points", "Spikes", "Blocks", "Aces", "Saves", "Elo" },
	CAREER_FIELDS = { "Wins", "MVPs", "Games", "Points", "Spikes", "Blocks", "Aces", "Saves" },
	RANKED_TYPE_MAIN = "Seasonal",
	CareerController = nil,
	CareerService = nil,
	RankedService = nil,
	Ranks = nil,
	spoof = nil, -- tabel spoof aktif (hanya field terisi); nil = mati
	realCareer = nil, -- snapshot Career asli terakhir
	realRanked = nil, -- snapshot tabel Ranked asli terakhir
	careerApplied = false,
	rankedApplied = false,
	hooksOn = false,
	hookConns = {},
	panelGui = nil,
	statusLabel = nil,
	fieldInputs = {}, -- [namaField] = TextBox
}

function Stats.spoofHas(field)
	return Stats.spoof ~= nil and Stats.spoof[field] ~= nil
end

function Stats.careerRelevant()
	if not Stats.spoof then
		return false
	end
	for _, f in ipairs(Stats.CAREER_FIELDS) do
		if Stats.spoof[f] ~= nil then
			return true
		end
	end
	return false
end

function Stats.rankedRelevant()
	return Stats.spoofHas("Wins") or Stats.spoofHas("Losses") or Stats.spoofHas("Elo")
end

function Stats.shouldRun()
	return Stats.spoof ~= nil and next(Stats.spoof) ~= nil and not S.extremeFast
end

----------------------------------------------------------------
-- Career
----------------------------------------------------------------

function Stats.applyCareer()
	local cc = Stats.CareerController
	if not (cc and cc.Career) then
		return
	end
	local doctored = table.clone(Stats.realCareer or {})
	for _, f in ipairs(Stats.CAREER_FIELDS) do
		if Stats.spoof[f] ~= nil then
			doctored[f] = Stats.spoof[f]
		end
	end
	local ok = pcall(function()
		cc.Career:set(doctored)
	end)
	if ok then
		Stats.careerApplied = true
	end
end

function Stats.restoreCareer()
	local cc = Stats.CareerController
	if cc and cc.Career and Stats.realCareer then
		pcall(function()
			cc.Career:set(Stats.realCareer)
		end)
	end
	Stats.careerApplied = false
end

function Stats.careerNeedsApply()
	local cc = Stats.CareerController
	if not (cc and cc.Career) then
		return false
	end
	local ok, cur = pcall(function()
		return cc.Career:get()
	end)
	if not ok or type(cur) ~= "table" then
		return true
	end
	for _, f in ipairs(Stats.CAREER_FIELDS) do
		if Stats.spoof[f] ~= nil and cur[f] ~= Stats.spoof[f] then
			return true
		end
	end
	return false
end

----------------------------------------------------------------
-- Ranked (lewat InterfaceController.Seasonal -> Computed Ranked)
----------------------------------------------------------------

function Stats.buildDoctoredRanked()
	local spoof = Stats.spoof
	local doctored = {}
	for k, v in pairs(Stats.realRanked or {}) do
		doctored[k] = (type(v) == "table") and table.clone(v) or v
	end
	local main = doctored[Stats.RANKED_TYPE_MAIN]
	if type(main) ~= "table" then
		main = {}
		doctored[Stats.RANKED_TYPE_MAIN] = main
	end
	if Stats.spoofHas("Wins") or Stats.spoofHas("Losses") then
		main.Wins = spoof.Wins or 0
		main.Games = (spoof.Wins or 0) + (spoof.Losses or 0)
	end
	if Stats.spoofHas("Elo") then
		main.Elo = spoof.Elo
	end
	-- Tipe lain di-nol-kan agar agregat halaman persis target:
	-- Wins total = jumlahan semua tipe, Losses = Games - Wins,
	-- Highest Rank dari Elo maksimum.
	for k, v in pairs(doctored) do
		if k ~= Stats.RANKED_TYPE_MAIN and type(v) == "table" then
			v.Wins = 0
			v.Games = 0
			v.Elo = 0
		end
	end
	return doctored
end

function Stats.seasonalValue()
	if not (InterfaceController and InterfaceController.Seasonal) then
		return nil
	end
	local ok, cur = pcall(function()
		return InterfaceController.Seasonal:get()
	end)
	if ok and type(cur) == "table" then
		return cur
	end
	return nil
end

function Stats.applyRanked()
	local cur = Stats.seasonalValue()
	if not cur then
		return
	end
	if Stats.realRanked == nil and type(cur.Ranked) == "table" then
		Stats.realRanked = cur.Ranked
	end
	local clone = table.clone(cur)
	clone.Ranked = Stats.buildDoctoredRanked()
	local ok = pcall(function()
		InterfaceController.Seasonal:set(clone)
	end)
	if ok then
		Stats.rankedApplied = true
	end
end

function Stats.restoreRanked()
	local cur = Stats.seasonalValue()
	if cur and Stats.realRanked then
		local clone = table.clone(cur)
		clone.Ranked = Stats.realRanked
		pcall(function()
			InterfaceController.Seasonal:set(clone)
		end)
	end
	Stats.rankedApplied = false
end

function Stats.rankedNeedsApply()
	local spoof = Stats.spoof
	local cur = Stats.seasonalValue()
	if not cur or type(cur.Ranked) ~= "table" then
		return true
	end
	local main = cur.Ranked[Stats.RANKED_TYPE_MAIN]
	if type(main) ~= "table" then
		return true
	end
	if Stats.spoofHas("Wins") and main.Wins ~= spoof.Wins then
		return true
	end
	if (Stats.spoofHas("Wins") or Stats.spoofHas("Losses")) and main.Games ~= (spoof.Wins or 0) + (spoof.Losses or 0) then
		return true
	end
	if Stats.spoofHas("Elo") and main.Elo ~= spoof.Elo then
		return true
	end
	return false
end

----------------------------------------------------------------
-- Reconcile: samakan keadaan live dengan yang seharusnya
----------------------------------------------------------------

function Stats.reconcile()
	local run = Stats.shouldRun()
	if run and Stats.careerRelevant() then
		if not Stats.careerApplied or Stats.careerNeedsApply() then
			Stats.applyCareer()
		end
	elseif Stats.careerApplied then
		Stats.restoreCareer()
	end
	if run and Stats.rankedRelevant() then
		if not Stats.rankedApplied or Stats.rankedNeedsApply() then
			Stats.applyRanked()
		end
	elseif Stats.rankedApplied then
		Stats.restoreRanked()
	end
end

----------------------------------------------------------------
-- Cermin sinkronisasi server -> snapshot asli, lalu timpa lagi
----------------------------------------------------------------

function Stats.startHooks()
	if Stats.hooksOn then
		return
	end
	Stats.hooksOn = true
	local function hook(signal, fn)
		local ok, conn = pcall(function()
			return signal:Connect(fn)
		end)
		if ok then
			table.insert(Stats.hookConns, conn)
		end
	end
	if DataService and DataService.ProfileUpdated then
		hook(DataService.ProfileUpdated, function(key, value)
			if key == "Career" and type(value) == "table" then
				Stats.realCareer = value
				if Stats.shouldRun() and Stats.careerRelevant() then
					Stats.applyCareer()
				end
			elseif key == "Seasonal" and type(value) == "table" and type(value.Ranked) == "table" then
				Stats.realRanked = value.Ranked
				if Stats.shouldRun() and Stats.rankedRelevant() then
					Stats.applyRanked()
				end
			end
		end)
	end
	if Stats.CareerService and Stats.CareerService.DataUpdated then
		hook(Stats.CareerService.DataUpdated, function(delta)
			if type(delta) == "table" and type(Stats.realCareer) == "table" then
				local merged = table.clone(Stats.realCareer)
				for k, v in pairs(delta) do
					merged[k] = v
				end
				Stats.realCareer = merged
			end
			if Stats.shouldRun() and Stats.careerRelevant() then
				Stats.applyCareer()
			end
		end)
	end
	if Stats.RankedService and Stats.RankedService.DataUpdated then
		hook(Stats.RankedService.DataUpdated, function(typeKey, entry)
			if type(typeKey) == "string" and type(Stats.realRanked) == "table" then
				local updated = {}
				for k, v in pairs(Stats.realRanked) do
					updated[k] = v
				end
				updated[typeKey] = entry
				Stats.realRanked = updated
			end
			if Stats.shouldRun() and Stats.rankedRelevant() then
				Stats.applyRanked()
			end
		end)
	end
	-- Penjaga berkala: menutup jalur sinkron yang lolos dari
	-- ketiga cermin di atas + menegakkan gerbang Extreme.
	task.spawn(function()
		while Stats.hooksOn do
			task.wait(3)
			if Stats.hooksOn then
				Stats.reconcile()
			end
		end
	end)
end

function Stats.stopHooks()
	Stats.hooksOn = false
	for _, conn in ipairs(Stats.hookConns) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	table.clear(Stats.hookConns)
end

----------------------------------------------------------------
-- Terapkan / matikan spoof
----------------------------------------------------------------

function Stats.sanitizeStats(input)
	if type(input) ~= "table" then
		return nil
	end
	local clean = {}
	for _, f in ipairs(Stats.STAT_FIELDS) do
		local v = input[f]
		if type(v) == "number" and v >= 0 then
			clean[f] = math.min(math.floor(v), 999999999)
		end
	end
	if next(clean) == nil then
		return nil
	end
	return clean
end

function Stats.updatePanelStatus()
	if not Stats.statusLabel then
		return
	end
	if Stats.spoof and next(Stats.spoof) ~= nil then
		local parts = {}
		for _, f in ipairs(Stats.STAT_FIELDS) do
			if Stats.spoof[f] ~= nil then
				table.insert(parts, f .. "=" .. tostring(Stats.spoof[f]))
			end
		end
		Stats.statusLabel.Text = "Aktif: " .. table.concat(parts, ", ")
	else
		Stats.statusLabel.Text = "Nonaktif — statistik asli tampil."
	end
end

function Stats.setSpoof(input)
	local clean = Stats.sanitizeStats(input)
	if not clean then
		return
	end
	Stats.spoof = clean
	S.settings[SETTING_MEMBER_STATS] = clean
	saveLocal()
	Stats.startHooks()
	Stats.reconcile()
	Stats.updatePanelStatus()
end

function Stats.clearSpoof()
	Stats.spoof = nil
	S.settings[SETTING_MEMBER_STATS] = {}
	saveLocal()
	if Stats.careerApplied then
		Stats.restoreCareer()
	end
	if Stats.rankedApplied then
		Stats.restoreRanked()
	end
	Stats.stopHooks()
	Stats.updatePanelStatus()
end

----------------------------------------------------------------
-- Bungkus flash card
----------------------------------------------------------------

-- Indeks rank untuk Custom.SeasonRank dari Elo spoof, memakai
-- fungsi game sendiri agar persis tampilan aslinya.
function Stats.rankIndexFromElo(elo)
	local Ranks = Stats.Ranks
	if Ranks and Ranks.getRankFromElo then
		local games = (Stats.spoof.Wins or 0) + (Stats.spoof.Losses or 0)
		if games == 0 and type(Stats.realRanked) == "table" then
			for _, v in pairs(Stats.realRanked) do
				if type(v) == "table" then
					games = games + (v.Games or 0)
				end
			end
		end
		local ok, idx = pcall(function()
			if Ranks.isUnranked and Ranks.isUnranked(games, elo) then
				return -1
			end
			return Ranks.getRankFromElo(elo)
		end)
		if ok and type(idx) == "number" then
			return idx
		end
	end
	return math.clamp(math.floor(elo / 100), 0, 12)
end

function Stats.installFlashWrap()
	if S.installedStatsFlash then
		return
	end
	if not (PlayerCardController and PlayerCardController.DisplayFlashCard) then
		return
	end
	S.installedStatsFlash = true
	local originalDisplayFlashCard = PlayerCardController.DisplayFlashCard
	PlayerCardController.DisplayFlashCard = function(self, data)
		if Stats.shouldRun() and type(data) == "table" and data.Player == player and type(data.Context) == "table" then
			local spoof = Stats.spoof
			local ctx = data.Context
			local newData = nil
			local function editedContext()
				if not newData then
					newData = table.clone(data)
					newData.Context = table.clone(ctx)
				end
				return newData.Context
			end
			if type(ctx.Custom) == "table" and Stats.rankedRelevant() then
				local custom = table.clone(ctx.Custom)
				if spoof.Wins ~= nil then
					custom.Wins = spoof.Wins
				end
				if spoof.Losses ~= nil then
					custom.Losses = spoof.Losses
				end
				if spoof.Elo ~= nil and custom.SeasonRank ~= nil then
					custom.SeasonRank = Stats.rankIndexFromElo(spoof.Elo)
				end
				editedContext().Custom = custom
			end
			if ctx.SingleStat ~= nil then
				local item = ContentItem:Get(data.PlayerCardItemId)
				local statName = item and item.Metadata and item.Metadata.Stat
				if statName and spoof[statName] ~= nil then
					editedContext().SingleStat = spoof[statName]
				end
			end
			if newData then
				data = newData
			end
		end
		return originalDisplayFlashCard(self, data)
	end
end

----------------------------------------------------------------
-- Panel UI
----------------------------------------------------------------

function Stats.buildPanel()
	if Stats.panelGui then
		return Stats.panelGui
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "VLStatsSpoofGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Enabled = false

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.Size = UDim2.fromOffset(400, 396)
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
	title.Text = "Stats Spoofer"
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

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.Size = UDim2.new(1, 0, 0, 20)
	status.Position = UDim2.fromOffset(0, 34)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.Gotham
	status.TextSize = 13
	status.TextColor3 = Color3.fromRGB(190, 190, 200)
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Text = ""
	status.Parent = frame
	Stats.statusLabel = status

	-- Grid 2 kolom x 5 baris: label + kotak angka per field.
	-- Kotak kosong = field itu tidak di-spoof.
	local gridY = 62
	local colW = 178
	local rowH = 42
	for i, field in ipairs(Stats.STAT_FIELDS) do
		local idx = i - 1
		local col = idx % 2
		local row = math.floor(idx / 2)
		local x = col * (colW + 12)
		local y = gridY + row * rowH
		local label = Instance.new("TextLabel")
		label.Name = field .. "Label"
		label.Size = UDim2.fromOffset(58, 34)
		label.Position = UDim2.fromOffset(x, y)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Gotham
		label.TextSize = 13
		label.TextColor3 = Color3.fromRGB(210, 210, 220)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = field
		label.Parent = frame
		local box = Instance.new("TextBox")
		box.Name = field .. "Box"
		box.Size = UDim2.fromOffset(colW - 62, 34)
		box.Position = UDim2.fromOffset(x + 62, y)
		box.BackgroundColor3 = Color3.fromRGB(38, 38, 46)
		box.Font = Enum.Font.Gotham
		box.TextSize = 14
		box.TextColor3 = Color3.fromRGB(255, 255, 255)
		box.PlaceholderColor3 = Color3.fromRGB(150, 150, 160)
		box.PlaceholderText = "asli"
		box.Text = ""
		box.ClearTextOnFocus = false
		box.Parent = frame
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 8)
		bc.Parent = box
		Stats.fieldInputs[field] = box
	end

	local function makeButton(name, text, width, x, color)
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.Size = UDim2.fromOffset(width, 46)
		btn.Position = UDim2.fromOffset(x, 284)
		btn.BackgroundColor3 = color
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 15
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.Text = text
		btn.Parent = frame
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 8)
		bc.Parent = btn
		return btn
	end
	local applyBtn = makeButton("ApplyButton", "Apply", 240, 0, Color3.fromRGB(64, 120, 242))
	local resetBtn = makeButton("ResetButton", "Reset", 116, 252, Color3.fromRGB(52, 52, 62))

	local note = Instance.new("TextLabel")
	note.Name = "Note"
	note.Size = UDim2.new(1, 0, 0, 40)
	note.Position = UDim2.fromOffset(0, 342)
	note.BackgroundTransparency = 1
	note.Font = Enum.Font.Gotham
	note.TextSize = 11
	note.TextColor3 = Color3.fromRGB(140, 140, 152)
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.TextWrapped = true
	note.Text = "Client-side saja: flash card, halaman Career, dan tab Ranked di layarmu. Kotak kosong = pakai angka asli. Ranked: Wins/Losses/Elo ditulis ke tipe Seasonal, tipe lain di-nol-kan agar totalnya pas."
	note.Parent = frame

	applyBtn.Activated:Connect(function()
		local input = {}
		for _, f in ipairs(Stats.STAT_FIELDS) do
			local box = Stats.fieldInputs[f]
			local text = box and box.Text or ""
			local n = tonumber((text:gsub("%s", "")))
			if n then
				input[f] = n
			end
		end
		if next(input) ~= nil then
			Stats.setSpoof(input)
		else
			Stats.clearSpoof()
		end
	end)
	resetBtn.Activated:Connect(function()
		Stats.clearSpoof()
		for _, box in pairs(Stats.fieldInputs) do
			box.Text = ""
		end
	end)
	closeBtn.Activated:Connect(function()
		gui.Enabled = false
	end)

	local parented = pcall(function()
		gui.Parent = player:WaitForChild("PlayerGui")
	end)
	if not parented or not gui.Parent then
		pcall(function()
			gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
		end)
	end
	Stats.panelGui = gui
	Stats.updatePanelStatus()
	return gui
end

function Stats.openPanel()
	Stats.buildPanel()
	for _, f in ipairs(Stats.STAT_FIELDS) do
		local box = Stats.fieldInputs[f]
		if box then
			box.Text = (Stats.spoof and Stats.spoof[f] ~= nil) and tostring(Stats.spoof[f]) or ""
		end
	end
	Stats.updatePanelStatus()
	Stats.panelGui.Enabled = true
end

local function initStatsSpoof()
	local t0 = os.clock()
	if not awaitFeatureShared(90) then
		warn("[VL Suite] stats-spoof skipped: feature-shared not ready.")
		return
	end
	local tShared = os.clock()
	loadLocal()
	pcall(function()
		Stats.CareerController = Knit.GetController("CareerController")
	end)
	pcall(function()
		Stats.CareerService = Knit.GetService("CareerService")
	end)
	pcall(function()
		Stats.RankedService = Knit.GetService("RankedService")
	end)
	pcall(function()
		Stats.Ranks = require(RS:WaitForChild("Configuration"):WaitForChild("Ranks"))
	end)
	-- Snapshot asli awal, sebelum penimpaan apa pun.
	local cc = Stats.CareerController
	if cc and cc.Career then
		local ok, v = pcall(function()
			return cc.Career:get()
		end)
		if ok and type(v) == "table" then
			Stats.realCareer = v
		end
	end
	local seasonal = Stats.seasonalValue()
	if seasonal and type(seasonal.Ranked) == "table" then
		Stats.realRanked = seasonal.Ranked
	end
	FeatureAPI.openStatsSpoofer = Stats.openPanel
	getgenv().VLStatsOpenPanel = Stats.openPanel
	Stats.installFlashWrap()
	-- Terapkan lagi spoof tersimpan dari sesi sebelumnya.
	local saved = Stats.sanitizeStats(S.settings[SETTING_MEMBER_STATS])
	if saved then
		Stats.spoof = saved
		Stats.startHooks()
		Stats.reconcile()
	end
	print(("[VL Suite] stats-spoof ready in %.2fs (shared wait %.2fs)"):format(os.clock() - t0, tShared - t0))
	suiteModuleLoaded("stats-spoof")
end

suiteExpectModule("stats-spoof")
task.spawn(initStatsSpoof)
