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

---------------------------------------------------------------------------
-- Colors. Lookup order: the user's override (KUIDB.colors.<kind>), then
-- the selected palette, then Blizzard's tables (or KUI's cast defaults).
-- Resetting a row removes the override, falling back to the palette.
---------------------------------------------------------------------------

ns.classOrder = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
ns.powerOrder = { "MANA", "RAGE", "ENERGY", "FOCUS" }
ns.reactionOrder = { "hostile", "neutral", "friendly" }
ns.castOrder = { "cast", "channel", "failed" }

-- KUI's own cast bar colors (no Blizzard table to defer to)
local CAST_DEFAULTS = {
	cast = { 1, 0.7, 0 },
	channel = { 0, 0.8, 0.2 },
	failed = { 0.9, 0.1, 0.1 },
}

-- Palettes only list what they change; anything missing falls through to
-- the Blizzard/KUI default. "Muted" is hand-tuned: roughly 20-30% less
-- saturated with a little grey mixed in, keyed off a mana blue of
-- (0.20, 0.38, 0.95).
ns.paletteOrder = { "Default", "Muted" }
ns.palettes = {
	Default = {},
	Muted = {
		class = {
			WARRIOR = { 0.70, 0.60, 0.49 },
			PALADIN = { 0.85, 0.58, 0.70 },
			HUNTER  = { 0.62, 0.74, 0.48 },
			ROGUE   = { 0.88, 0.84, 0.50 },
			PRIEST  = { 0.86, 0.86, 0.86 },
			SHAMAN  = { 0.25, 0.48, 0.78 },
			MAGE    = { 0.42, 0.70, 0.80 },
			WARLOCK = { 0.56, 0.56, 0.80 },
			DRUID   = { 0.86, 0.55, 0.28 },
		},
		reaction = {
			hostile  = { 0.72, 0.33, 0.30 },
			neutral  = { 0.85, 0.80, 0.40 },
			friendly = { 0.33, 0.62, 0.36 },
		},
		power = {
			MANA   = { 0.20, 0.38, 0.95 },
			RAGE   = { 0.80, 0.30, 0.30 },
			ENERGY = { 0.88, 0.80, 0.40 },
			FOCUS  = { 0.85, 0.55, 0.38 },
		},
		cast = {
			cast    = { 0.88, 0.70, 0.32 },
			channel = { 0.35, 0.70, 0.42 },
			failed  = { 0.75, 0.30, 0.30 },
		},
	},
}

-- Index into FACTION_BAR_COLORS (Blizzard's classic target frame colors)
local REACTION_INDEX = { hostile = 2, neutral = 4, friendly = 5 }

local function BlizzardColor(kind, key)
	local c
	if kind == "class" then
		c = RAID_CLASS_COLORS[key]
	elseif kind == "reaction" then
		c = FACTION_BAR_COLORS[REACTION_INDEX[key]]
	elseif kind == "power" then
		c = PowerBarColor[key]
	elseif kind == "cast" then
		return CAST_DEFAULTS[key]
	end
	if c then return { c.r, c.g, c.b } end
end

-- The color a row shows with no user override: palette, else Blizzard
function ns:GetDefaultColor(kind, key)
	local palette = ns.palettes[KUIDB.colors.palette] or ns.palettes.Default
	return (palette[kind] and palette[kind][key]) or BlizzardColor(kind, key)
end

local function Lookup(kind, key)
	return KUIDB.colors[kind][key] or ns:GetDefaultColor(kind, key)
end

-- Effective color for any palette entry, e.g. ("power", "MANA")
function ns:GetColor(kind, key)
	return Lookup(kind, key)
end

-- Returns { r, g, b } or nil for an unknown class
function ns:GetClassColor(class)
	return Lookup("class", class)
end

-- ptype is the numeric power type, a fallback for tokens PowerBarColor
-- only knows by index
function ns:GetPowerColor(token, ptype)
	local c = Lookup("power", token)
	if c then return c end
	c = PowerBarColor[ptype] or PowerBarColor.MANA
	return { c.r, c.g, c.b }
end

function ns:GetCastColor(key)
	return Lookup("cast", key)
end

-- NPC health color by reaction; unfriendly (3) counts as hostile, units
-- with no reaction as neutral
function ns:GetReactionColor(unit)
	local reaction = UnitReaction(unit, "player")
	local key = not reaction and "neutral"
		or reaction <= 3 and "hostile"
		or reaction == 4 and "neutral"
		or "friendly"
	return Lookup("reaction", key)
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
