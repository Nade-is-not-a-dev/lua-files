-- Konfigurasi Prometheus kustom untuk vl-ball-spoof.lua:
-- perlindungan isi (enkripsi string + constant array + angka jadi
-- ekspresi + rename variabel) TANPA Vmify/Cff/AntiTamper --
-- lapisan VM dan perataan alur membuat keluaran preset Medium
-- membengkak ke ~6 MB dan berisiko mengubah perilaku Luau.
return {
	LuaVersion = "LuaU",
	VarNamePrefix = "",
	NameGenerator = "MangledShuffled",
	PrettyPrint = false,
	Seed = 0,
	Steps = {
		{ Name = "EncryptStrings", Settings = {} },
		{
			Name = "ConstantArray",
			Settings = {
				Threshold = 1,
				StringsOnly = true,
				Shuffle = true,
				Rotate = true,
				LocalWrapperThreshold = 0,
			},
		},
		{ Name = "NumbersToExpressions", Settings = {} },
		{ Name = "WrapInFunction", Settings = {} },
	},
}
