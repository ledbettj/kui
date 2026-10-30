local addonName, ns = ...

-- Colors, as { r, g, b } arrays. Lookup order: the user's override
-- (KUIDB.colors.<kind>[key]), then the selected palette, then Blizzard's
-- tables (or KUI's own defaults for cast bars, heal prediction, threat and
-- spell schools). Resetting a row removes the override, falling back to the
-- palette.
--
-- Returned tables are shared; callers must not modify them.

ns.colorKinds = { "class", "reaction", "power", "cast", "heal", "threat", "school" }

-- Row order for each kind in the config panel
ns.classOrder = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
ns.powerOrder = { "MANA", "RAGE", "ENERGY", "FOCUS" }
ns.reactionOrder = { "hostile", "neutral", "friendly" }
ns.castOrder = { "cast", "channel", "failed" }
ns.healOrder = { "mine", "others" }
-- Indexed by UnitThreatSituation status (1-3)
ns.threatOrder = { "pulling", "insecure", "tanking" }
ns.schoolOrder = { "physical", "holy", "fire", "nature", "frost", "shadow", "arcane" }

---------------------------------------------------------------------------
-- Palettes
---------------------------------------------------------------------------

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
		heal = {
			mine   = { 0.30, 0.72, 0.45 },
			others = { 0.25, 0.55, 0.40 },
		},
		threat = {
			pulling  = { 0.88, 0.84, 0.50 },
			insecure = { 0.88, 0.58, 0.30 },
			tanking  = { 0.80, 0.30, 0.30 },
		},
		school = {
			physical = { 0.62, 0.56, 0.48 },
			holy     = { 0.88, 0.80, 0.52 },
			fire     = { 0.86, 0.50, 0.28 },
			nature   = { 0.40, 0.70, 0.40 },
			frost    = { 0.45, 0.70, 0.82 },
			shadow   = { 0.52, 0.45, 0.78 },
			arcane   = { 0.80, 0.52, 0.80 },
		},
	},
}

---------------------------------------------------------------------------
-- Blizzard defaults
---------------------------------------------------------------------------

-- Kinds with no Blizzard table to defer to
local KUI_DEFAULTS = {
	cast = {
		cast = { 1, 0.7, 0 },
		channel = { 0, 0.8, 0.2 },
		failed = { 0.9, 0.1, 0.1 },
	},
	-- Incoming heals: the player's own brighter than other healers'
	heal = {
		mine = { 0, 0.85, 0.45 },
		others = { 0, 0.6, 0.35 },
	},
	-- Blizzard's GetThreatStatusColor values
	threat = {
		pulling = { 1, 1, 0.47 },
		insecure = { 1, 0.6, 0 },
		tanking = { 1, 0, 0 },
	},
	-- Blizzard's combat log school colors, except physical: theirs is a
	-- bright yellow that reads badly as a bar
	school = {
		physical = { 0.75, 0.65, 0.50 },
		holy = { 1, 0.9, 0.5 },
		fire = { 1, 0.5, 0 },
		nature = { 0.3, 1, 0.3 },
		frost = { 0.5, 1, 1 },
		shadow = { 0.5, 0.5, 1 },
		arcane = { 1, 0.5, 1 },
	},
}

-- Index into FACTION_BAR_COLORS (Blizzard's classic target frame colors)
local REACTION_INDEX = { hostile = 2, neutral = 4, friendly = 5 }

local function BlizzardSource(kind, key)
	if kind == "class" then
		return RAID_CLASS_COLORS[key]
	elseif kind == "reaction" then
		return FACTION_BAR_COLORS[REACTION_INDEX[key]]
	elseif kind == "power" then
		return PowerBarColor[key]
	end
end

-- Converted { r, g, b } copies, built once: health and power updates look
-- these up constantly
local blizzardCache = {}
for _, kind in ipairs(ns.colorKinds) do blizzardCache[kind] = {} end

local function BlizzardColor(kind, key)
	if KUI_DEFAULTS[kind] then return KUI_DEFAULTS[kind][key] end
	if key == nil then return end
	local cache = blizzardCache[kind]
	local c = cache[key]
	if c == nil then
		local src = BlizzardSource(kind, key)
		c = src and { src.r, src.g, src.b } or false
		cache[key] = c
	end
	return c or nil
end

---------------------------------------------------------------------------
-- Lookup
---------------------------------------------------------------------------

-- The color a row shows with no user override: palette, else Blizzard
function ns:GetDefaultColor(kind, key)
	local palette = ns.palettes[KUIDB.colors.palette] or ns.palettes.Default
	return (palette[kind] and palette[kind][key]) or BlizzardColor(kind, key)
end

-- Effective color for any entry, e.g. ("power", "MANA"); nil if unknown
function ns:GetColor(kind, key)
	return (key ~= nil and KUIDB.colors[kind][key]) or ns:GetDefaultColor(kind, key)
end

function ns:GetClassColor(class)
	return ns:GetColor("class", class)
end

-- ptype is the numeric power type, a fallback for tokens PowerBarColor
-- only knows by index
function ns:GetPowerColor(token, ptype)
	return ns:GetColor("power", token)
		or BlizzardColor("power", ptype)
		or BlizzardColor("power", "MANA")
end

function ns:GetCastColor(key)
	return ns:GetColor("cast", key)
end

-- Combat log school bits; a spell of several schools (Shadowfrost) takes the
-- first magic one it has, so physical goes last
local SCHOOL_BITS = {
	{ 2, "holy" }, { 4, "fire" }, { 8, "nature" }, { 16, "frost" },
	{ 32, "shadow" }, { 64, "arcane" }, { 1, "physical" },
}

-- Color for a combat log school mask; physical if unknown
function ns:GetSchoolColor(mask)
	for _, entry in ipairs(SCHOOL_BITS) do
		if mask and bit.band(mask, entry[1]) ~= 0 then
			return ns:GetColor("school", entry[2])
		end
	end
	return ns:GetColor("school", "physical")
end

-- NPC health color by reaction; unfriendly (3) counts as hostile, units
-- with no reaction as neutral
function ns:GetReactionColor(unit)
	local reaction = UnitReaction(unit, "player")
	local key = not reaction and "neutral"
		or reaction <= 3 and "hostile"
		or reaction == 4 and "neutral"
		or "friendly"
	return ns:GetColor("reaction", key)
end
