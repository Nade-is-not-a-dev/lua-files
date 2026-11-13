----------------------------------------------------------------
-- modules/hitbox-expander.lua -- Modul fitur: Hitbox Expander
--
-- Memperbesar hitbox DETEKSI pukulan sendiri (Bump/Set/JumpSet/
-- Spike/Block/Dive/Serve) saat menyentuh bola.
--
-- Cara kerja game (dari dump, ReplicatedFirst/Controllers/
-- GameController/Actions/Move/DoMove/ClientHitbox.lua):
--   * Saat move jalan, game membuat part hitbox klien dengan
--     ukuran params.HitboxSize (bila ada; khusus special aktif)
--     atau Hitbox.Size milik assembly hitbox per move
--     (ReplicatedStorage/Assets/HitboxesNew -- Offset+Size+Debug
--     Color dari Part, Custom modul untuk AdjustBoundsLocal).
--   * tryCollidingWithBall mencari part bertag "Ball" di dalam
--     part itu (GetPartsInPart, Values.HitboxParams), digerbang
--     Common.Physics.canInteract: bola harus di sisi tim sendiri,
--     jarak bola <= 20 stud (30 untuk Dive), plus aturan debounce/
--     serve. Bila lolos, BallService:Interact dikirim ke server
--     dengan BallId + Key hitbox server.
-- Modul ini membungkus ClientHitbox.new dan menggandakan ukuran
-- HitboxSize pada parameternya (parameternya dibuat baru tiap
-- move oleh Orchestrator, jadi mutasinya aman). Gerbang jarak
-- canInteract tetap jalan, jadi makin besar skalanya makin
-- sering di-clamp -- skala 3x sudah melampaui jarak 20 stud di
-- sebagian besar arah.
--
-- VISUAL: saat aktif, flag _DebugHitboxes di
-- ReplicatedStorage/Configuration/Game dinyalakan (mekanisme
-- debug milik game sendiri -- konsol ToggleHitboxes), jadi part
-- hitbox tergambar transparan neon dan ukurannya kelihatan.
-- Mati = flag dikembalikan nil.
--
-- Saklar: "Hitbox Expander" di grup VL Settings (anggota
-- HitboxExpander, persisten di S.settings; skala persisten di
-- S.hitboxScale, default 1.9, dibatasi 1..3 -- ubah lewat
-- FeatureAPI.setHitboxScale). Titik masuk saklar:
-- FeatureAPI.setHitboxExpanderEnabled(bool) dari bungkus
-- ChangeSetting di modules/settings.lua. Bukan kategori
-- inventory: tanpa suiteActivateFeature.
----------------------------------------------------------------

local function applyHitboxScale(enabled)
	S._hitboxScaleActive = enabled and S.hitboxScale or 1
end

local function initHitboxExpander()
	local t0 = os.clock()
	if getgenv().VLHitboxExpanderInstalled then
		suiteModuleLoaded("hitbox-expander")
		return
	end
	getgenv().VLHitboxExpanderInstalled = true
	-- Tunggu state lokal selesai dimuat (saklar awal + skala).
	local deadline = t0 + 30
	while not LocalStateLoaded and os.clock() < deadline do
		task.wait(0.25)
	end
	local sharedWait = os.clock() - t0

	local installedWrap = false
	FeatureAPI.setHitboxExpanderEnabled = function(enabled)
		applyHitboxScale(enabled)
		pcall(function()
			-- Visual debug milik game: hitbox part digambar
			-- transparan neon saat _DebugHitboxes truthy.
			local gameConfig = require(RS:WaitForChild("Configuration"):WaitForChild("Game"))
			gameConfig._DebugHitboxes = enabled or nil
		end)
	end
	FeatureAPI.setHitboxScale = function(scale)
		if type(scale) == "number" and scale >= 1 and scale <= 3 then
			S.hitboxScale = scale
			saveLocal()
			applyHitboxScale(S.settings[SETTING_MEMBER_HITBOX] == true)
		end
	end

	if S.installedHitboxWrap then
		installedWrap = true
	end

	local function installWrap()
		if installedWrap then
			return
		end
		installedWrap = true
		S.installedHitboxWrap = true
		local ClientHitbox = require(ReplicatedFirst:WaitForChild("Controllers")
			:WaitForChild("GameController")
			:WaitForChild("Actions")
			:WaitForChild("Move")
			:WaitForChild("DoMove")
			:WaitForChild("ClientHitbox"))
		local originalNew = ClientHitbox.new
		ClientHitbox.new = function(params)
			local scale = S._hitboxScaleActive or 1
			if params and params.Hitbox and scale > 1 then
				-- Ukuran dasar: HitboxSize (khusus special) atau
				-- Hitbox.Size milik assembly. Kita selalu set
				-- HitboxSize eksplisit agar table Hitbox bersama
				-- (hasil register game) TIDAK dimutasi.
				local base = params.HitboxSize or params.Hitbox.Size
				if base then
					params.HitboxSize = base * scale
				end
			end
			return originalNew(params)
		end
	end

	-- Bungkus modulnya saat modul fitur ini init (modul game sudah
	-- ada di tree ReplicatedFirst); guard pcall supaya kegagalan
	-- path tidak menggagalkan modul lain.
	pcall(installWrap)

	-- Terapkan keadaan awal dari saklar tersimpan.
	if S.localStateLoaded then
		FeatureAPI.setHitboxExpanderEnabled(S.settings[SETTING_MEMBER_HITBOX] == true)
	end

	print(("[VL Suite] hitbox-expander ready in %.2fs (shared wait %.2fs)"):format(os.clock() - t0, sharedWait))
	suiteModuleLoaded("hitbox-expander")
end
suiteExpectModule("hitbox-expander")
task.spawn(initHitboxExpander)
