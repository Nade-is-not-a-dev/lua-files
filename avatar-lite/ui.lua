--[[
	VL Avatar Lite -- UI module (fetched at runtime by the host script).

	A faithful re-creation of the Catalog Avatar Creator game's
	CatalogGUI layout, measured from the actual game UI:
	- fullscreen fixed Holder (no dragging anywhere)
	- left column: AvatarPreview (backdrop + 3D viewport of your
	  character) over an EquippedItems strip
	- right Main panel (65% x 90%): dark Catalog panel with a
	  categories row, a status pill, a big display area, an
	  EnterAssetId box bottom-left and square buttons bottom-right

	Palette measured from the game:
	panel #232527, cell/input #343638, button #5A5D61,
	slate #4B535F, green #55FF7F, red #FF4C4C.

	API: local ui = require-this.Build(deps) -> {
		Show(), Hide(), Toggle(), IsVisible(),
		SetStatus(text), Refresh() }
	deps = {
		guiParent,                       -- PlayerGui
		getOutfit = fn() -> outfit,      -- {acc={{id,name}}, shirt, shirtName, pants, pantsName, face, faceName}
		getCharacter = fn() -> char|nil, -- for the 3D preview
		onWearId = fn(text),             -- wear by asset id text
		onRemoveAcc = fn(index),
		onClearSlot = fn("shirt"|"pants"|"face"),
		onStrip = fn(), onReset = fn(),
		onColor = fn(partKey, Color3),   -- partKey: All/Head/Torso/Left Arm/...
	}
]]

local M = {}

local UI_VERSION = "1.4"
M.VERSION = UI_VERSION

local DARK = Color3.fromRGB(35, 37, 39)
local CELL = Color3.fromRGB(52, 54, 56)
local BTN = Color3.fromRGB(90, 93, 97)
local SLATE = Color3.fromRGB(75, 83, 97)
local GREEN = Color3.fromRGB(85, 255, 127)
local RED = Color3.fromRGB(255, 76, 76)
local WHITE = Color3.fromRGB(255, 255, 255)
local GREY = Color3.fromRGB(170, 175, 180)

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = parent
	return c
end

local function label(parent, text, size, bold, color)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	l.TextSize = size or 13
	l.TextColor3 = color or WHITE
	l.Parent = parent
	return l
end

function M.Build(deps)
	local gui = Instance.new("ScreenGui")
	gui.Name = "VLAvatarLiteGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 999 -- selalu di atas UI game (App VL tertimpa ini)
	gui.Parent = deps.guiParent

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.ZIndex = 2
	holder.Parent = gui

	local versionLabel = label(holder, "Avatar Lite UI v" .. UI_VERSION, 11, true, GREY)
	versionLabel.Size = UDim2.fromScale(0.25, 0.03)
	versionLabel.Position = UDim2.fromScale(0.008, 0.006)
	versionLabel.TextXAlignment = Enum.TextXAlignment.Left
	versionLabel.ZIndex = 300

	------------------------------------------------------------
	-- Kolom kiri: AvatarPreview + EquippedItems
	------------------------------------------------------------
	local preview = Instance.new("Frame")
	preview.Name = "AvatarPreview"
	preview.Size = UDim2.fromScale(0.275, 0.66)
	preview.Position = UDim2.fromScale(0.025, 0.05)
	preview.BackgroundTransparency = 1
	preview.ZIndex = 2
	preview.Parent = holder

	local backdrop = Instance.new("ImageLabel")
	backdrop.Name = "Background"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundTransparency = 1
	backdrop.Image = "rbxassetid://6998183803" -- backdrop bawaan CAC
	backdrop.ZIndex = 0
	backdrop.Parent = preview
	corner(backdrop, 10)

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Viewport"
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(190, 190, 200)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-1, -2, -1)
	viewport.ZIndex = 2
	viewport.Parent = preview
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local cam = Instance.new("Camera")
	cam.FieldOfView = 45
	cam.CFrame = CFrame.new(Vector3.new(0, 0.6, 7.4), Vector3.new(0, 0.2, 0))
	cam.Parent = viewport
	viewport.CurrentCamera = cam

	local previewModel = nil
	local spinAngle = math.rad(180)
	local function refreshPreview()
		for _, ch in ipairs(world:GetChildren()) do
			ch:Destroy()
		end
		previewModel = nil
		local char = deps.getCharacter()
		if not char then
			return
		end
		pcall(function()
			char.Archivable = true
			local clone = char:Clone()
			char.Archivable = false
			for _, d in ipairs(clone:GetDescendants()) do
				if d:IsA("BaseScript") or d:IsA("Sound") then
					d:Destroy()
				end
			end
			local hum = clone:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			end
			clone.Parent = world
			spinAngle = math.rad(180)
			clone:PivotTo(CFrame.new(Vector3.new(0, 0, 0)) * CFrame.Angles(0, spinAngle, 0))
			previewModel = clone
		end)
	end
	game:GetService("RunService").RenderStepped:Connect(function(dt)
		if holder.Visible and previewModel then
			spinAngle += dt * 0.5
			pcall(function()
				previewModel:PivotTo(CFrame.new(Vector3.new(0, 0, 0)) * CFrame.Angles(0, spinAngle, 0))
			end)
		end
	end)

	-- Strip item terpasang (bawah kiri), gaya EquippedItems CAC.
	local equipped = Instance.new("Frame")
	equipped.Name = "EquippedItems"
	equipped.Size = UDim2.fromScale(0.275, 0.12)
	equipped.Position = UDim2.fromScale(0.025, 0.95)
	equipped.AnchorPoint = Vector2.new(0, 1)
	equipped.BackgroundColor3 = DARK
	equipped.ZIndex = 2
	equipped.Parent = holder
	corner(equipped, 10)
	local eqPad = Instance.new("UIPadding")
	eqPad.PaddingLeft = UDim.new(0, 6)
	eqPad.PaddingRight = UDim.new(0, 6)
	eqPad.PaddingTop = UDim.new(0, 6)
	eqPad.PaddingBottom = UDim.new(0, 6)
	eqPad.Parent = equipped

	local eqList = Instance.new("ScrollingFrame")
	eqList.Name = "List"
	eqList.Size = UDim2.fromScale(1, 1)
	eqList.BackgroundTransparency = 1
	eqList.ScrollBarThickness = 3
	eqList.ScrollingDirection = Enum.ScrollingDirection.X
	eqList.ClipsDescendants = true
	eqList.ZIndex = 2
	eqList.Parent = equipped
	local eqLayout = Instance.new("UIListLayout")
	eqLayout.FillDirection = Enum.FillDirection.Horizontal
	eqLayout.Padding = UDim.new(0, 6)
	eqLayout.SortOrder = Enum.SortOrder.LayoutOrder
	eqLayout.Parent = eqList
	eqLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		eqList.CanvasSize = UDim2.new(0, eqLayout.AbsoluteContentSize.X + 12, 0, 0)
	end)

	-- Bar opsi untuk sel strip yang dipilih (REMOVE gaya CAC).
	local eqOptions = Instance.new("Frame")
	eqOptions.Name = "EquippedOptions"
	eqOptions.Size = UDim2.fromScale(0.275, 0.07)
	eqOptions.Position = UDim2.fromScale(0.025, 0.815)
	eqOptions.AnchorPoint = Vector2.new(0, 1)
	eqOptions.BackgroundColor3 = DARK
	eqOptions.Visible = false
	eqOptions.ZIndex = 5
	eqOptions.Parent = holder
	corner(eqOptions, 10)
	local eqOptName = label(eqOptions, "", 12, true)
	eqOptName.Size = UDim2.new(0.62, 0, 1, 0)
	eqOptName.Position = UDim2.fromScale(0.03, 0)
	eqOptName.TextXAlignment = Enum.TextXAlignment.Left
	eqOptName.TextTruncate = Enum.TextTruncate.AtEnd
	local eqRemove = Instance.new("TextButton")
	eqRemove.Size = UDim2.new(0.3, 0, 0.7, 0)
	eqRemove.Position = UDim2.new(0.97, 0, 0.5, 0)
	eqRemove.AnchorPoint = Vector2.new(1, 0.5)
	eqRemove.BackgroundColor3 = RED
	eqRemove.TextColor3 = DARK
	eqRemove.Font = Enum.Font.GothamBold
	eqRemove.TextSize = 12
	eqRemove.Text = "REMOVE"
	eqRemove.ZIndex = 6
	eqRemove.Parent = eqOptions
	corner(eqRemove, 8)
	local selectedRemove = nil
	eqRemove.Activated:Connect(function()
		if selectedRemove then
			selectedRemove()
		end
		eqOptions.Visible = false
		selectedRemove = nil
	end)

	------------------------------------------------------------
	-- Panel kanan: Main > Catalog
	------------------------------------------------------------
	local main = Instance.new("Frame")
	main.Name = "Main"
	main.Size = UDim2.fromScale(0.65, 0.9)
	main.Position = UDim2.fromScale(0.975, 0.5)
	main.AnchorPoint = Vector2.new(1, 0.5)
	main.BackgroundTransparency = 1
	main.ZIndex = 2
	main.Parent = holder

	local catalog = Instance.new("Frame")
	catalog.Name = "Catalog"
	catalog.Size = UDim2.fromScale(1, 1)
	catalog.BackgroundColor3 = DARK
	catalog.ZIndex = 2
	catalog.ClipsDescendants = true
	catalog.Parent = main
	corner(catalog, 12)

	-- Tombol keluar PERSIS milik CAC: ImageButton 'Exit' ikon X
	-- (rbxassetid://9154608052), tanpa latar, Size 0.035,
	-- Position (0.98, 0.03), AnchorPoint (1, 0), ZIndex 202.
	local exitBtn = Instance.new("ImageButton")
	exitBtn.Name = "Exit"
	exitBtn.Size = UDim2.fromScale(0.035, 0.035)
	exitBtn.Position = UDim2.fromScale(0.98, 0.03)
	exitBtn.AnchorPoint = Vector2.new(1, 0)
	exitBtn.BackgroundTransparency = 1
	exitBtn.Image = "rbxassetid://9154608052"
	exitBtn.ZIndex = 202
	exitBtn.Parent = catalog
	local exitRatio = Instance.new("UIAspectRatioConstraint")
	exitRatio.AspectRatio = 1
	exitRatio.Parent = exitBtn

	local exitFallback = Instance.new("TextButton")
	exitFallback.Name = "ExitFallback"
	exitFallback.Size = UDim2.fromScale(0.035, 0.035)
	exitFallback.Position = UDim2.fromScale(0.98, 0.03)
	exitFallback.AnchorPoint = Vector2.new(1, 0)
	exitFallback.BackgroundTransparency = 1
	exitFallback.TextColor3 = WHITE
	exitFallback.Font = Enum.Font.GothamBold
	exitFallback.TextSize = 16
	exitFallback.Text = "X"
	exitFallback.Visible = false
	exitFallback.ZIndex = 202
	exitFallback.Parent = catalog
	local exitFallbackRatio = Instance.new("UIAspectRatioConstraint")
	exitFallbackRatio.AspectRatio = 1
	exitFallbackRatio.Parent = exitFallback
	task.delay(3, function()
		if not exitBtn.IsLoaded then
			exitBtn.Visible = false
			exitFallback.Visible = true
		end
	end)

	-- Baris kategori (tab) di atas, gaya Categories CAC.
	local tabsBar = Instance.new("Frame")
	tabsBar.Name = "Categories"
	tabsBar.Size = UDim2.fromScale(0.96, 0.075)
	tabsBar.Position = UDim2.fromScale(0.5, 0.02)
	tabsBar.AnchorPoint = Vector2.new(0.5, 0)
	tabsBar.BackgroundTransparency = 1
	tabsBar.ZIndex = 10
	tabsBar.Parent = catalog
	local tabsLayout = Instance.new("UIListLayout")
	tabsLayout.FillDirection = Enum.FillDirection.Horizontal
	tabsLayout.Padding = UDim.new(0, 8)
	tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabsLayout.Parent = tabsBar

	-- Pil status (seperti AppliedSearchOptions CAC).
	local statusPill = Instance.new("Frame")
	statusPill.Size = UDim2.fromScale(0.95, 0.04)
	statusPill.Position = UDim2.fromScale(0.5, 0.11)
	statusPill.AnchorPoint = Vector2.new(0.5, 0)
	statusPill.BackgroundColor3 = CELL
	statusPill.ZIndex = 40
	statusPill.Parent = catalog
	corner(statusPill, 8)
	local statusText = label(statusPill, "Avatar Lite -- paste an asset ID below, or tap a worn item to remove it.", 12, false)
	statusText.Size = UDim2.fromScale(1, 1)
	statusText.Position = UDim2.fromScale(0.01, 0)
	statusText.TextXAlignment = Enum.TextXAlignment.Left
	statusText.TextTruncate = Enum.TextTruncate.AtEnd

	-- Latar area tampil + daftar tampil (batas persis CAC).
	local displayBg = Instance.new("Frame")
	displayBg.Size = UDim2.fromScale(1, 0.8)
	displayBg.Position = UDim2.fromScale(0.5, 0.915)
	displayBg.AnchorPoint = Vector2.new(0.5, 1)
	displayBg.BackgroundColor3 = DARK
	displayBg.ZIndex = 2
	displayBg.Parent = catalog

	local pages = {}
	local tabButtons = {}
	local currentTab = "Wearing"
	local function showTab(name)
		currentTab = name
		for tabName, page in pairs(pages) do
			page.Visible = tabName == name
		end
		for tabName, btn in pairs(tabButtons) do
			btn.BackgroundColor3 = tabName == name and SLATE or CELL
		end
	end
	local function mkTab(name, order)
		local b = Instance.new("TextButton")
		b.Name = "Tab_" .. name
		b.Size = UDim2.new(0, 0, 1, 0)
		b.AutomaticSize = Enum.AutomaticSize.X
		b.BackgroundColor3 = CELL
		b.TextColor3 = WHITE
		b.Font = Enum.Font.GothamBold
		b.TextSize = 14
		b.Text = "  " .. name .. "  "
		b.LayoutOrder = order
		b.ZIndex = 10
		b.Parent = tabsBar
		corner(b, 8)
		tabButtons[name] = b
		b.Activated:Connect(function()
			showTab(name)
		end)
		local page = Instance.new("ScrollingFrame")
		page.Name = "Page_" .. name
		page.Size = UDim2.fromScale(1, 0.8)
		page.Position = UDim2.fromScale(0.5, 0.915)
		page.AnchorPoint = Vector2.new(0.5, 1)
		page.BackgroundTransparency = 1
		page.ScrollBarThickness = 4
		page.ClipsDescendants = true
		page.Visible = false
		page.ZIndex = 3
		page.Parent = catalog
		pages[name] = page
		return page
	end


	------------------------------------------------------------
	-- Tab Catalog: jelajah + cari katalog asli Roblox lewat API
	-- resmi (data dari host: deps.queryCatalog). Ketuk sel, lalu
	-- WEAR untuk memakai -- tanpa mengetik ID.
	------------------------------------------------------------
	local CAT_CHIPS = {
		{ label = "All" },
		{ label = "Accessories", category = "Accessories" },
		{ label = "Head", category = "Accessories", subcategory = "Head" },
		{ label = "Hair", category = "Accessories", subcategory = "Hair" },
		{ label = "Face Acc.", category = "Accessories", subcategory = "Face" },
		{ label = "Back", category = "Accessories", subcategory = "Back" },
		{ label = "Clothing", category = "Clothing" },
		{ label = "Faces", category = "Faces" },
	}
	local TYPE_TAGS = {
		[2] = "T-SHIRT", [8] = "HAT", [11] = "SHIRT", [12] = "PANTS", [18] = "FACE",
		[41] = "HAIR", [42] = "FACE ACC", [43] = "NECK", [44] = "SHOULDER",
		[45] = "FRONT", [46] = "BACK", [47] = "WAIST",
		[64] = "LAYERED", [65] = "LAYERED", [66] = "LAYERED", [67] = "LAYERED", [68] = "LAYERED",
	}

	local catButton = Instance.new("TextButton")
	catButton.Name = "Tab_Catalog"
	catButton.Size = UDim2.new(0, 0, 1, 0)
	catButton.AutomaticSize = Enum.AutomaticSize.X
	catButton.BackgroundColor3 = CELL
	catButton.TextColor3 = WHITE
	catButton.Font = Enum.Font.GothamBold
	catButton.TextSize = 14
	catButton.Text = "  Catalog  "
	catButton.LayoutOrder = 1
	catButton.ZIndex = 10
	catButton.Parent = tabsBar
	corner(catButton, 8)
	tabButtons["Catalog"] = catButton
	catButton.Activated:Connect(function()
		showTab("Catalog")
	end)

	local catPage = Instance.new("Frame")
	catPage.Name = "Page_Catalog"
	catPage.Size = UDim2.fromScale(1, 0.8)
	catPage.Position = UDim2.fromScale(0.5, 0.915)
	catPage.AnchorPoint = Vector2.new(0.5, 1)
	catPage.BackgroundTransparency = 1
	catPage.ClipsDescendants = true
	catPage.Visible = false
	catPage.ZIndex = 3
	catPage.Parent = catalog
	pages["Catalog"] = catPage

	local searchRow = Instance.new("Frame")
	searchRow.Size = UDim2.new(1, -20, 0, 40)
	searchRow.Position = UDim2.fromOffset(10, 8)
	searchRow.BackgroundTransparency = 1
	searchRow.ZIndex = 3
	searchRow.Parent = catPage
	local searchBox = Instance.new("TextBox")
	searchBox.Size = UDim2.new(0.8, -6, 1, 0)
	searchBox.BackgroundColor3 = CELL
	searchBox.TextColor3 = WHITE
	searchBox.PlaceholderColor3 = GREY
	searchBox.PlaceholderText = "Search the catalog..."
	searchBox.Font = Enum.Font.Gotham
	searchBox.TextSize = 13
	searchBox.Text = ""
	searchBox.ClearTextOnFocus = false
	searchBox.ZIndex = 3
	searchBox.Parent = searchRow
	corner(searchBox, 8)
	local searchBtn = Instance.new("TextButton")
	searchBtn.Size = UDim2.new(0.2, 0, 1, 0)
	searchBtn.Position = UDim2.fromScale(0.8, 0)
	searchBtn.BackgroundColor3 = GREEN
	searchBtn.TextColor3 = DARK
	searchBtn.Font = Enum.Font.GothamBold
	searchBtn.TextSize = 13
	searchBtn.Text = "SEARCH"
	searchBtn.ZIndex = 3
	searchBtn.Parent = searchRow
	corner(searchBtn, 8)

	local chipsScroll = Instance.new("ScrollingFrame")
	chipsScroll.Size = UDim2.new(1, -20, 0, 38)
	chipsScroll.Position = UDim2.fromOffset(10, 56)
	chipsScroll.BackgroundTransparency = 1
	chipsScroll.ScrollBarThickness = 3
	chipsScroll.ScrollingDirection = Enum.ScrollingDirection.X
	chipsScroll.ZIndex = 3
	chipsScroll.Parent = catPage
	local chipsLayout = Instance.new("UIListLayout")
	chipsLayout.FillDirection = Enum.FillDirection.Horizontal
	chipsLayout.Padding = UDim.new(0, 6)
	chipsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipsLayout.Parent = chipsScroll
	chipsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		chipsScroll.CanvasSize = UDim2.new(0, chipsLayout.AbsoluteContentSize.X + 12, 0, 0)
	end)

	local catScroll = Instance.new("ScrollingFrame")
	catScroll.Size = UDim2.new(1, -20, 1, -152)
	catScroll.Position = UDim2.fromOffset(10, 102)
	catScroll.BackgroundTransparency = 1
	catScroll.ScrollBarThickness = 4
	catScroll.ClipsDescendants = true
	catScroll.ZIndex = 3
	catScroll.Parent = catPage
	local catGrid = Instance.new("UIGridLayout")
	catGrid.CellSize = UDim2.new(0.185, 0, 0.44, 0)
	catGrid.CellPadding = UDim2.new(0.012, 0, 0.03, 0)
	catGrid.SortOrder = Enum.SortOrder.LayoutOrder
	catGrid.Parent = catScroll
	catGrid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		catScroll.CanvasSize = UDim2.new(0, 0, 0, catGrid.AbsoluteContentSize.Y + 20)
	end)

	local moreBtn = Instance.new("TextButton")
	moreBtn.Size = UDim2.new(0.3, 0, 0, 36)
	moreBtn.Position = UDim2.new(0.5, 0, 1, -44)
	moreBtn.AnchorPoint = Vector2.new(0.5, 0)
	moreBtn.BackgroundColor3 = CELL
	moreBtn.TextColor3 = WHITE
	moreBtn.Font = Enum.Font.GothamBold
	moreBtn.TextSize = 13
	moreBtn.Text = "LOAD MORE"
	moreBtn.Visible = false
	moreBtn.ZIndex = 3
	moreBtn.Parent = catPage
	corner(moreBtn, 8)

	local catState = { keyword = "", category = nil, subcategory = nil, cursor = nil, busy = false, loaded = false }
	local function catStatus(text)
		statusText.Text = text
	end
	local chipButtons = {}
	local function runCatalog(append)
		if catState.busy or not deps.queryCatalog then
			return
		end
		catState.busy = true
		catStatus("Loading catalog...")
		deps.queryCatalog({
			keyword = catState.keyword,
			category = catState.category,
			subcategory = catState.subcategory,
			cursor = append and catState.cursor or nil,
		}, function(items, nextCursor, err)
			catState.busy = false
			if err then
				catStatus("Catalog: " .. err)
				return
			end
			if not append then
				for _, ch in ipairs(catScroll:GetChildren()) do
					if ch:IsA("ImageButton") then
						ch:Destroy()
					end
				end
			end
			local n = 0
			for _, it in ipairs(items) do
				n += 1
				local captured = it
				mkItemCell(catScroll, {
					id = it.id,
					name = it.name,
					tag = TYPE_TAGS[it.assetType] or "ITEM",
				}, "WEAR", GREEN, function()
					deps.onWearId(tostring(captured.id))
				end)
			end
			catState.cursor = nextCursor
			catState.loaded = true
			moreBtn.Visible = nextCursor ~= nil
			if append then
				catStatus(("Catalog: %d more items loaded."):format(n))
			else
				catStatus(("Catalog: %d items found. Tap one, then WEAR."):format(n))
			end
		end)
	end
	local function refreshChipsUI()
		for i, btn in ipairs(chipButtons) do
			local chip = CAT_CHIPS[i]
			local active = (catState.category == chip.category) and (catState.subcategory == chip.subcategory)
			btn.BackgroundColor3 = active and SLATE or CELL
		end
	end
	for i, chip in ipairs(CAT_CHIPS) do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0, 0, 1, 0)
		b.AutomaticSize = Enum.AutomaticSize.X
		b.BackgroundColor3 = CELL
		b.TextColor3 = WHITE
		b.Font = Enum.Font.GothamBold
		b.TextSize = 12
		b.Text = "  " .. chip.label .. "  "
		b.LayoutOrder = i
		b.ZIndex = 3
		b.Parent = chipsScroll
		corner(b, 8)
		chipButtons[i] = b
		local captured = chip
		b.Activated:Connect(function()
			catState.category = captured.category
			catState.subcategory = captured.subcategory
			catState.cursor = nil
			refreshChipsUI()
			runCatalog(false)
		end)
	end
	refreshChipsUI()
	local function submitSearch()
		catState.keyword = searchBox.Text
		catState.cursor = nil
		runCatalog(false)
	end
	searchBtn.Activated:Connect(submitSearch)
	searchBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submitSearch()
		end
	end)
	moreBtn.Activated:Connect(function()
		runCatalog(true)
	end)
	local function ensureCatalogLoaded()
		if not catState.loaded and not catState.busy then
			runCatalog(false)
		end
	end

	------------------------------------------------------------
	-- Tab Wearing: grid item terpasang (sel gaya katalog CAC)
	------------------------------------------------------------
	local wearingPage = mkTab("Wearing", 2)
	local wearGrid = Instance.new("UIGridLayout")
	wearGrid.CellSize = UDim2.new(0.185, 0, 0.44, 0)
	wearGrid.CellPadding = UDim2.new(0.012, 0, 0.03, 0)
	wearGrid.SortOrder = Enum.SortOrder.LayoutOrder
	wearGrid.Parent = wearingPage
	local wearPad = Instance.new("UIPadding")
	wearPad.PaddingLeft = UDim.new(0, 10)
	wearPad.PaddingTop = UDim.new(0, 10)
	wearPad.Parent = wearingPage
	wearGrid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		wearingPage.CanvasSize = UDim2.new(0, 0, 0, wearGrid.AbsoluteContentSize.Y + 20)
	end)

	local openOverlay = nil
	local function mkItemCell(parent, entry, primaryText, primaryColor, onPrimary)
		-- entry: {id, name, tag}
		local cellBtn = Instance.new("ImageButton")
		cellBtn.BackgroundTransparency = 1
		cellBtn.Image = ""
		cellBtn.ZIndex = 3
		cellBtn.Parent = parent
		local img = Instance.new("ImageLabel")
		img.Name = "AssetImage"
		img.Size = UDim2.fromScale(0.72, 0.62)
		img.Position = UDim2.fromScale(0.5, 0.02)
		img.AnchorPoint = Vector2.new(0.5, 0)
		img.BackgroundColor3 = CELL
		img.Image = ("rbxthumb://type=Asset&id=%d&w=420&h=420"):format(entry.id)
		img.ZIndex = 3
		img.Parent = cellBtn
		corner(img, 8)
		local info = Instance.new("Frame")
		info.Name = "AssetInfo"
		info.Size = UDim2.fromScale(0.95, 0.32)
		info.Position = UDim2.fromScale(0.5, 0.66)
		info.AnchorPoint = Vector2.new(0.5, 0)
		info.BackgroundTransparency = 1
		info.ZIndex = 3
		info.Parent = cellBtn
		local nm = label(info, entry.name or tostring(entry.id), 12, false)
		nm.Size = UDim2.fromScale(1, 0.62)
		nm.TextWrapped = true
		nm.TextTruncate = Enum.TextTruncate.AtEnd
		nm.TextYAlignment = Enum.TextYAlignment.Top
		if entry.tag then
			local tg = label(info, entry.tag, 10, true, GREY)
			tg.Size = UDim2.new(1, 0, 0.35, 0)
			tg.Position = UDim2.fromScale(0, 0.62)
		end
		-- Overlay opsi di dalam sel (seperti Options CAC).
		local overlay = Instance.new("Frame")
		overlay.Name = "Options"
		overlay.Size = UDim2.fromScale(1, 1)
		overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		overlay.BackgroundTransparency = 0.25
		overlay.Visible = false
		overlay.ZIndex = 20
		overlay.Parent = cellBtn
		corner(overlay, 8)
		local rm = Instance.new("TextButton")
		rm.Size = UDim2.fromScale(0.8, 0.3)
		rm.Position = UDim2.fromScale(0.5, 0.3)
		rm.AnchorPoint = Vector2.new(0.5, 0.5)
		rm.BackgroundColor3 = primaryColor
		rm.TextColor3 = DARK
		rm.Font = Enum.Font.GothamBold
		rm.TextSize = 13
		rm.Text = primaryText
		rm.ZIndex = 21
		rm.Parent = overlay
		corner(rm, 8)
		local cl = Instance.new("TextButton")
		cl.Size = UDim2.fromScale(0.8, 0.3)
		cl.Position = UDim2.fromScale(0.5, 0.68)
		cl.AnchorPoint = Vector2.new(0.5, 0.5)
		cl.BackgroundColor3 = BTN
		cl.TextColor3 = WHITE
		cl.Font = Enum.Font.GothamBold
		cl.TextSize = 13
		cl.Text = "CLOSE"
		cl.ZIndex = 21
		cl.Parent = overlay
		corner(cl, 8)
		cellBtn.Activated:Connect(function()
			if openOverlay and openOverlay ~= overlay then
				openOverlay.Visible = false
			end
			overlay.Visible = not overlay.Visible
			openOverlay = overlay.Visible and overlay or nil
		end)
		cl.Activated:Connect(function()
			overlay.Visible = false
			openOverlay = nil
		end)
		rm.Activated:Connect(function()
			overlay.Visible = false
			openOverlay = nil
			onPrimary()
		end)
	end

	------------------------------------------------------------
	-- Tab Body Color: pemilih bagian + grid warna (gaya ColourList CAC)
	------------------------------------------------------------
	local bodyPage = mkTab("Body Color", 3)
	bodyPage.ScrollBarThickness = 0
	bodyPage.CanvasSize = UDim2.new(0, 0, 0, 0)

	local PARTS = { "All", "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
	local selectedPart = "All"
	local partButtons = {}
	local chipsBar = Instance.new("Frame")
	chipsBar.Size = UDim2.new(1, -20, 0, 40)
	chipsBar.Position = UDim2.fromOffset(10, 10)
	chipsBar.BackgroundTransparency = 1
	chipsBar.ZIndex = 3
	chipsBar.Parent = bodyPage
	local chipsLayout = Instance.new("UIListLayout")
	chipsLayout.FillDirection = Enum.FillDirection.Horizontal
	chipsLayout.Padding = UDim.new(0, 6)
	chipsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipsLayout.Parent = chipsBar
	local function refreshChips()
		for partName, btn in pairs(partButtons) do
			btn.BackgroundColor3 = partName == selectedPart and SLATE or CELL
		end
	end
	for i, partName in ipairs(PARTS) do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0, 0, 1, 0)
		b.AutomaticSize = Enum.AutomaticSize.X
		b.BackgroundColor3 = CELL
		b.TextColor3 = WHITE
		b.Font = Enum.Font.GothamBold
		b.TextSize = 12
		b.Text = "  " .. partName .. "  "
		b.LayoutOrder = i
		b.ZIndex = 3
		b.Parent = chipsBar
		corner(b, 8)
		partButtons[partName] = b
		b.Activated:Connect(function()
			selectedPart = partName
			refreshChips()
		end)
	end
	refreshChips()

	local colourList = Instance.new("ScrollingFrame")
	colourList.Name = "ColourList"
	colourList.Size = UDim2.new(1, -20, 1, -70)
	colourList.Position = UDim2.fromOffset(10, 60)
	colourList.BackgroundTransparency = 1
	colourList.ScrollBarThickness = 4
	colourList.ZIndex = 3
	colourList.Parent = bodyPage
	local colourGrid = Instance.new("UIGridLayout")
	colourGrid.CellSize = UDim2.new(0.09, 0, 0.09, 0)
	colourGrid.CellPadding = UDim2.new(0.008, 0, 0.02, 0)
	colourGrid.SortOrder = Enum.SortOrder.LayoutOrder
	colourGrid.Parent = colourList
	colourGrid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		colourList.CanvasSize = UDim2.new(0, 0, 0, colourGrid.AbsoluteContentSize.Y + 16)
	end)
	local PALETTE = {
		"White", "Grey", "Really black", "Black metallic", "Nougat", "Brown",
		"Reddish brown", "Brick yellow", "Light orange", "Bright orange",
		"Bright yellow", "Lime green", "Bright green", "Dark green",
		"Bright blue", "Medium blue", "Pastel Blue", "Bright violet",
		"Magenta", "Bright red", "Really red", "Hot pink", "Pastel orange",
		"Gold", "Silver", "Institutional white", "Cork", "Olive", "Teal",
		"Navy blue", "Lavender", "Lilac", "Daisy orange", "Cool yellow",
	}
	for _, colorName in ipairs(PALETTE) do
		local bc = BrickColor.new(colorName)
		local cellBtn = Instance.new("TextButton")
		cellBtn.BackgroundColor3 = bc.Color
		cellBtn.Text = ""
		cellBtn.ZIndex = 3
		cellBtn.Parent = colourList
		corner(cellBtn, 6)
		local ratio = Instance.new("UIAspectRatioConstraint")
		ratio.AspectRatio = 1
		ratio.Parent = cellBtn
		cellBtn.Activated:Connect(function()
			deps.onColor(selectedPart, bc.Color)
		end)
	end

	------------------------------------------------------------
	-- Tab Actions
	------------------------------------------------------------
	local actionsPage = mkTab("Actions", 4)
	actionsPage.ScrollBarThickness = 0
	local function actionButton(text, desc, y, fn)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0.6, 0, 0, 52)
		b.Position = UDim2.new(0.03, 0, 0, y)
		b.BackgroundColor3 = CELL
		b.TextColor3 = WHITE
		b.Font = Enum.Font.GothamBold
		b.TextSize = 15
		b.Text = text
		b.ZIndex = 3
		b.Parent = actionsPage
		corner(b, 8)
		b.Activated:Connect(fn)
		local d = label(actionsPage, desc, 12, false, GREY)
		d.Size = UDim2.new(0.6, 0, 0, 30)
		d.Position = UDim2.new(0.03, 0, 0, y + 58)
		d.TextWrapped = true
		d.TextYAlignment = Enum.TextYAlignment.Top
		d.ZIndex = 3
	end
	actionButton("STRIP REAL ACCESSORIES", "Remove your real (server-given) accessories locally. They return on Reset + respawn.", 16, deps.onStrip)
	actionButton("RESET AVATAR", "Remove everything Avatar Lite applied and restore your server look.", 130, deps.onReset)

	------------------------------------------------------------
	-- EnterAssetId + WEAR (posisi persis CAC) dan tombol kanan bawah
	------------------------------------------------------------
	local idBox = Instance.new("TextBox")
	idBox.Name = "EnterAssetId"
	idBox.Size = UDim2.fromScale(0.25, 0.05)
	idBox.Position = UDim2.fromScale(0.02, 0.955)
	idBox.AnchorPoint = Vector2.new(0, 0.5)
	idBox.BackgroundColor3 = CELL
	idBox.TextColor3 = WHITE
	idBox.PlaceholderColor3 = GREY
	idBox.PlaceholderText = "Enter Asset ID"
	idBox.Font = Enum.Font.Gotham
	idBox.TextSize = 13
	idBox.Text = ""
	idBox.ClearTextOnFocus = false
	idBox.ZIndex = 10
	idBox.Parent = catalog
	corner(idBox, 8)
	local idStroke = Instance.new("UIStroke")
	idStroke.Color = SLATE
	idStroke.Parent = idBox
	local function submitId()
		if idBox.Text ~= "" then
			deps.onWearId(idBox.Text)
		end
	end
	idBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submitId()
		end
	end)
	local wearBtn = Instance.new("TextButton")
	wearBtn.Size = UDim2.fromScale(0.09, 0.05)
	wearBtn.Position = UDim2.fromScale(0.28, 0.955)
	wearBtn.AnchorPoint = Vector2.new(0, 0.5)
	wearBtn.BackgroundColor3 = GREEN
	wearBtn.TextColor3 = DARK
	wearBtn.Font = Enum.Font.GothamBold
	wearBtn.TextSize = 13
	wearBtn.Text = "WEAR"
	wearBtn.ZIndex = 10
	wearBtn.Parent = catalog
	corner(wearBtn, 8)
	wearBtn.Activated:Connect(submitId)

	local bottomRight = Instance.new("Frame")
	bottomRight.Name = "BottomRightButtons"
	bottomRight.Size = UDim2.fromScale(0.3, 0.07)
	bottomRight.Position = UDim2.fromScale(0.98, 0.98)
	bottomRight.AnchorPoint = Vector2.new(1, 1)
	bottomRight.BackgroundTransparency = 1
	bottomRight.ZIndex = 10
	bottomRight.Parent = catalog
	local brLayout = Instance.new("UIListLayout")
	brLayout.FillDirection = Enum.FillDirection.Horizontal
	brLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	brLayout.Padding = UDim.new(0, 8)
	brLayout.SortOrder = Enum.SortOrder.LayoutOrder
	brLayout.Parent = bottomRight
	local function squareButton(text, order)
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromScale(1, 1)
		b.BackgroundColor3 = BTN
		b.TextColor3 = WHITE
		b.Font = Enum.Font.GothamBold
		b.TextSize = 16
		b.Text = text
		b.LayoutOrder = order
		b.ZIndex = 10
		b.Parent = bottomRight
		corner(b, 8)
		local ratio = Instance.new("UIAspectRatioConstraint")
		ratio.AspectRatio = 1
		ratio.Parent = b
		return b
	end
	local refreshBtn = squareButton("R", 1)
	refreshBtn.Activated:Connect(function()
		refreshPreview()
	end)

	------------------------------------------------------------
	-- Penyegaran daftar (strip + grid) dan API modul
	------------------------------------------------------------
	local function outfitEntries()
		local outfit = deps.getOutfit()
		local entries = {}
		for i, e in ipairs(outfit.acc) do
			local idx = i
			table.insert(entries, {
				id = e.id,
				name = e.name,
				onRemove = function()
					deps.onRemoveAcc(idx)
				end,
			})
		end
		if outfit.shirt then
			table.insert(entries, { id = outfit.shirt, name = outfit.shirtName, tag = "SHIRT", onRemove = function()
				deps.onClearSlot("shirt")
			end })
		end
		if outfit.pants then
			table.insert(entries, { id = outfit.pants, name = outfit.pantsName, tag = "PANTS", onRemove = function()
				deps.onClearSlot("pants")
			end })
		end
		if outfit.face then
			table.insert(entries, { id = outfit.face, name = outfit.faceName, tag = "FACE", onRemove = function()
				deps.onClearSlot("face")
			end })
		end
		return entries
	end

	local api = {}
	function api.Refresh()
		eqOptions.Visible = false
		selectedRemove = nil
		openOverlay = nil
		for _, ch in ipairs(eqList:GetChildren()) do
			if ch:IsA("ImageButton") then
				ch:Destroy()
			end
		end
		for _, ch in ipairs(wearingPage:GetChildren()) do
			if ch:IsA("ImageButton") then
				ch:Destroy()
			end
		end
		local entries = outfitEntries()
		for _, entry in ipairs(entries) do
			local cellBtn = Instance.new("ImageButton")
			cellBtn.BackgroundColor3 = CELL
			cellBtn.Image = ""
			cellBtn.ZIndex = 2
			cellBtn.ClipsDescendants = true
			cellBtn.Parent = eqList
			corner(cellBtn, 8)
			local ratio = Instance.new("UIAspectRatioConstraint")
			ratio.AspectRatio = 1
			ratio.Parent = cellBtn
			local img = Instance.new("ImageLabel")
			img.Name = "AssetImage"
			img.Size = UDim2.fromScale(1, 1)
			img.BackgroundTransparency = 1
			img.Image = ("rbxthumb://type=Asset&id=%d&w=150&h=150"):format(entry.id)
			img.ZIndex = 2
			img.Parent = cellBtn
			local captured = entry
			cellBtn.Activated:Connect(function()
				eqOptName.Text = captured.name or tostring(captured.id)
				selectedRemove = captured.onRemove
				eqOptions.Visible = true
			end)
			mkItemCell(wearingPage, entry, "REMOVE", RED, entry.onRemove)
		end
		if holder.Visible then
			refreshPreview()
		end
	end
	function api.SetStatus(text)
		statusText.Text = text
	end
	function api.Show()
		holder.Visible = true
		refreshPreview()
		if ensureCatalogLoaded then
			ensureCatalogLoaded()
		end
	end
	function api.Hide()
		holder.Visible = false
	end
	function api.Toggle()
		holder.Visible = not holder.Visible
		if holder.Visible then
			refreshPreview()
		end
	end
	function api.IsVisible()
		return holder.Visible
	end
	exitBtn.Activated:Connect(api.Hide)
	exitFallback.Activated:Connect(api.Hide)

	showTab("Catalog")
	api.Refresh()
	print("[VLAvatar] UI v" .. UI_VERSION .. " loaded")
	return api
end

return M
