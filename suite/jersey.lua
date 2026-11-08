----------------------------------------------------------------
-- suite/jersey.lua -- Modul fitur: Jersey Spoof
--
-- Render jersey lokal (tim dari folder varian aset),
-- penjaga timpaan server per karakter, scrub gembok layar
-- Jersey Preview, dan bungkus JerseyPreviewController.Open.
-- Diekstrak apa adanya dari remaining-features.lua (Bagian A
-- monolit); penyesuaian hanya di kerangka peluncuran
-- (menunggu feature-shared + guard S.installedJersey) dan baris timing
-- "[VL Suite] jersey ready in ..." untuk memburu lag awal.
----------------------------------------------------------------

local function fetchJerseyProps()
	if JerseyService and JerseyService.GetPlayerJerseyPropsAsync then
		local ok, props = pcall(function()
			local raw = JerseyService:GetPlayerJerseyPropsAsync(player, player.Character)
			-- Tahan dua bentuk hasil: promise Knit (perlu :expect())
			-- atau tabel props langsung.
			if type(raw) == "table" and type(raw.expect) == "function" then
				return raw:expect()
			end
			return raw
		end)
		if ok and type(props) == "table"
			and (props.Name ~= nil or props.Number ~= nil or props.TeamName ~= nil) then
			jerseyPropsCache = {
				Name = props.Name,
				Number = props.Number,
				TeamName = props.TeamName,
			}
		end
	end
	return jerseyPropsCache
end

local lastTeamName = nil

local function resolveTeamName()
	-- Warna jersey ditentukan oleh FOLDER VARIAN TIM di dalam aset
	-- (bukan pewarnaan runtime): Tools.Jersey memakai folder bernama
	-- TeamName bila diberikan, dan memilih ACAK bila tidak. Urutan
	-- sumber kami: props resmi server -> tim terakhir yang terpakai
	-- -> baca-balik dari jersey asli yang sedang dipakai karakter
	-- (template kaos/celana yang terpasang hanya cocok dengan satu
	-- folder tim di aset jersey asli).
	if jerseyPropsCache and jerseyPropsCache.TeamName then
		lastTeamName = jerseyPropsCache.TeamName
		return lastTeamName
	end
	if lastTeamName then
		return lastTeamName
	end
	local char = player.Character
	if not char then
		return nil
	end
	local wornShirt, wornPants
	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Shirt") and child.ShirtTemplate ~= "" then
			wornShirt = child.ShirtTemplate
		elseif child:IsA("Pants") and child.PantsTemplate ~= "" then
			wornPants = child.PantsTemplate
		end
	end
	if not wornShirt and not wornPants then
		return nil
	end
	local realItem = ContentItem:Get(S.serverEquipped.Jersey or "ClassicJersey")
	if not realItem then
		return nil
	end
	local asset = JerseyTool.getAsset(JerseyTool.getItemRenderId(realItem))
	if not asset then
		return nil
	end
	for _, folder in ipairs(asset:GetChildren()) do
		if folder.Name:find("Team") then
			for _, desc in ipairs(folder:GetDescendants()) do
				if (desc:IsA("Shirt") and wornShirt and desc.ShirtTemplate == wornShirt)
					or (desc:IsA("Pants") and wornPants and desc.PantsTemplate == wornPants) then
					lastTeamName = folder.Name
					return lastTeamName
				end
			end
		end
	end
	return nil
end

local function setJerseyLocal(id)
	local char = player.Character
	if not char then
		return
	end
	local props = jerseyPropsCache
	local teamName = resolveTeamName() -- baca SEBELUM set() membersihkan karakter
	pcall(function()
		JerseyTool.set({
			Character = char,
			Id = id,
			Player = player,
			Name = props and props.Name or nil,
			Number = props and props.Number or nil,
			TeamName = teamName,
		})
	end)
	lastJerseyApply = os.clock()
end

local function applyJerseyRender()
	if not S.fakeJersey then
		return
	end
	jerseySeq += 1
	local mySeq = jerseySeq
	task.spawn(function()
		fetchJerseyProps()
		if mySeq == jerseySeq and S.fakeJersey then
			setJerseyLocal(S.fakeJersey)
		end
	end)
end

local function restoreJerseyRender()
	-- Unequip palsu: pasang kembali jersey ASLI secara lokal (persis
	-- tampilan dari server) tanpa perlu respawn.
	jerseySeq += 1
	local mySeq = jerseySeq
	task.spawn(function()
		fetchJerseyProps()
		if mySeq == jerseySeq and not S.fakeJersey then
			setJerseyLocal(S.serverEquipped.Jersey or "ClassicJersey")
		end
	end)
end

local function watchCharacterJersey(char)
	-- Server menimpa jersey karakter pada momen-momen tertentu
	-- (spawn, update style). Pemasangan server menambahkan anak
	-- jersey ke karakter; bila itu terjadi di luar pemasangan lokal
	-- kita, pasang ulang yang palsu.
	char.ChildAdded:Connect(function(child)
		if not S.fakeJersey then
			return
		end
		if os.clock() - lastJerseyApply < 2 then
			return
		end
		if child.Name == "JerseyBack" or child.Name == "JerseyFront"
			or child.Name == "_jerseyInstances" or child:IsA("Clothing")
			or child:IsA("ShirtGraphic") then
			task.delay(0.3, applyJerseyRender)
		end
	end)
end

local function scrubJerseyPreviewLocks()
	-- Sentuhan akhir kosmetik: paksa sembunyikan gembok + kembalikan
	-- warna penuh gambar di daftar layar Jersey Preview yang sudah
	-- terlanjur dibuat (sumber datanya tetap Value hasil injeksi,
	-- jadi hitungan ulang Fusion berikutnya pun konsisten).
	pcall(function()
		local interfaceController = Knit.GetController("InterfaceController")
		local lobby = interfaceController and interfaceController.App
			and interfaceController.App:FindFirstChild("Lobby")
		local menu = lobby and lobby:FindFirstChild("JerseyPreview")
		local list = menu and menu:FindFirstChild("Dropdown", true)
		if not list then
			return
		end
		for _, row in ipairs(list:GetChildren()) do
			if isJersey(row.Name) then
				local lock = row:FindFirstChild("Lock", true)
				if lock then
					lock.Visible = false
				end
				local img = row:FindFirstChild("ImageLabel", true)
				if img then
					img.ImageColor3 = Color3.new(1, 1, 1)
				end
			end
		end
	end)
end

local function initJersey()
	local t0 = os.clock()
	if not awaitFeatureShared(90) then
		warn("[VLJersey] feature-shared tidak siap; modul jersey dilewati.")
		return
	end
	local tShared = os.clock()
	if not S.installedJersey then
		S.installedJersey = true
	-- Layar Jersey Preview: pastikan injeksi segar + gembok hilang
	-- setiap kali layar dibuka.
	if JerseyPreviewController and JerseyPreviewController.Open then
		local originalPreviewOpen = JerseyPreviewController.Open
		JerseyPreviewController.Open = function(self, id, ...)
			injectInventory()
			local result = originalPreviewOpen(self, id, ...)
			task.delay(0.5, scrubJerseyPreviewLocks)
			return result
		end
	end
	-- Jersey: karakter baru (respawn) dipasangi yang asli oleh
	-- server; pasang ulang yang palsu + pasang penjaga timpaan.
	player.CharacterAdded:Connect(function(char)
		watchCharacterJersey(char)
		task.delay(1, function()
			if S.fakeJersey then
				applyJerseyRender()
			end
		end)
	end)
	if player.Character then
		watchCharacterJersey(player.Character)
	end
	end
	if S.fakeJersey then
		applyJerseyRender()
	end
	task.delay(3, scrubJerseyPreviewLocks)
	print(("[VL Suite] jersey ready in %.2fs (shared wait %.2fs)"):format(os.clock() - t0, tShared - t0))
end

task.spawn(initJersey)
