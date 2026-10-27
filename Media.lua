local addonName, ns = ...

local MODERN_ATLAS = "UI-HUD-CoolDownManager-Bar"
local HAS_MODERN = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(MODERN_ATLAS) ~= nil
local DEFAULT_BAR = "Interface\\TargetingFrame\\UI-StatusBar"

-- Built-in media. LibSharedMedia entries get appended when some addon
-- provides it, so users with SharedMedia packs see those too.
local media = {
	statusbar = {
		-- Modern nameplate art; shading is baked in and tinted via vertex color
		{ name = "Modern", atlas = HAS_MODERN and MODERN_ATLAS or nil, path = DEFAULT_BAR },
		{ name = "Blizzard", path = DEFAULT_BAR },
		{ name = "Blizzard Classic", path = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill" },
		{ name = "Skills", path = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
		{ name = "Flat", path = "Interface\\Buttons\\WHITE8X8" },
	},
	-- insetScale: how far inside the edge the border art ends, as a fraction
	-- of edge size (rounded tooltip art has transparent padding)
	border = {
		{ name = "Rounded", path = "Interface\\Tooltips\\UI-Tooltip-Border", insetScale = 0.25 },
		{ name = "Flat", path = "Interface\\Buttons\\WHITE8X8", insetScale = 1 },
		{ name = "None", insetScale = 0 },
	},
	font = {
		{ name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
		{ name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
		{ name = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
		{ name = "Skurri", path = "Fonts\\SKURRI.TTF" },
	},
}

-- Looked up lazily: LSM is usually embedded in some other addon, which may
-- load after us.
local function GetLSM()
	return LibStub and LibStub("LibSharedMedia-3.0", true)
end

local function FindBuiltin(kind, name)
	for _, entry in ipairs(media[kind]) do
		if entry.name == name then return entry end
	end
end

-- Returns atlas, path. Exactly one is used: atlas when non-nil.
function ns:GetStatusbar(name)
	local entry = FindBuiltin("statusbar", name)
	if entry then return entry.atlas, entry.path end

	local lsm = GetLSM()
	if lsm and lsm:IsValid("statusbar", name) then
		return nil, lsm:Fetch("statusbar", name)
	end

	entry = media.statusbar[1]
	return entry.atlas, entry.path
end

function ns:GetFontPath(name)
	local entry = FindBuiltin("font", name)
	if entry then return entry.path end

	local lsm = GetLSM()
	if lsm and lsm:IsValid("font", name) then
		return lsm:Fetch("font", name)
	end

	return media.font[1].path
end

-- Returns edgeFile path (nil for none), insetScale.
function ns:GetBorder(name)
	local entry = FindBuiltin("border", name)
	if entry then return entry.path, entry.insetScale end

	local lsm = GetLSM()
	if lsm and lsm:IsValid("border", name) then
		local path = lsm:Fetch("border", name)
		-- LSM's "None" entry maps to a nil-ish path
		if path and path ~= "" and path ~= "Interface\\None" then
			return path, 0.25
		end
		return nil, 0
	end

	entry = media.border[1]
	return entry.path, entry.insetScale
end

-- Built-ins first, then any extra LSM names.
function ns:ListMedia(kind)
	local names, seen = {}, {}
	for _, entry in ipairs(media[kind]) do
		names[#names + 1] = entry.name
		seen[entry.name] = true
	end

	local lsm = GetLSM()
	if lsm then
		for _, name in ipairs(lsm:List(kind)) do
			if not seen[name] then
				names[#names + 1] = name
				seen[name] = true
			end
		end
	end

	return names
end
