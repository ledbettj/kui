local addonName, ns = ...

-- Static configuration: which unit frames exist and how each is built, plus
-- the default value of every saved setting. Loaded first; nothing here
-- touches the game state.

---------------------------------------------------------------------------
-- Unit frames
---------------------------------------------------------------------------

-- Creation order; also the order of the width sliders in the config panel
ns.unitOrder = {
	"player", "target", "targettarget", "pet", "focus",
	"party1", "party2", "party3", "party4",
	"partypet1", "partypet2", "partypet3", "partypet4",
}

-- Per-unit build options. Frames are positioned by ns:ApplyPositions from
-- the layout settings rather than individually.
--   w, h               default width (configurable) and fixed height
--   power              has a power bar
--   powerFromSettings  power bar height comes from style.powerHeight
--   powerHeight        fixed power bar height (else a quarter of h)
--   portrait           3D portrait on the left
--   auras              aura layout key (see LAYOUTS in Auras.lua)
--   castbar            cast bar row inside the frame
--   detachedCastbar    cast bar in its own holder under the frame
--   combo              combo point pips
--   status             status icons: leader/looter always, plus pvp/state
--   poll               no reliable events, refresh on a timer
--   party              party unit: raid-hidden, roster-aware, range fade
--   owner              a pet: refresh when this unit's pet changes
--   threat             border in the threat color while it has aggro
--   widthFrom          share another unit's width setting
ns.units = {
	player       = { label = "Player", w = 234, h = 56, power = true, powerFromSettings = true, portrait = true, auras = "above", castbar = true, status = { pvp = true, state = true }, threat = true },
	target       = { label = "Target", w = 234, h = 56, power = true, powerFromSettings = true, portrait = true, auras = "above", castbar = true, combo = true, status = { pvp = true } },
	targettarget = { label = "ToT",    w = 108, h = 22, poll = true },
	pet          = { label = "Pet",    w = 108, h = 22, power = true, owner = "player", threat = true },
	focus        = { label = "Focus",  w = 108, h = 22, widthFrom = "targettarget", detachedCastbar = true },
}
-- Party: the other four members (like Blizzard's classic party frames, the
-- player isn't included), each with a pet frame to its right. Members share
-- party1's width; pets are focus/ToT sized and share that width.
for i = 1, 4 do
	ns.units["party" .. i] = {
		label = "Party " .. i, w = 170, h = 36, power = true, powerHeight = 8, portrait = true, auras = "below",
		party = true, widthFrom = i > 1 and "party1" or nil, status = {}, threat = true,
	}
	ns.units["partypet" .. i] = {
		label = "Pet " .. i, w = 108, h = 22,
		party = true, owner = "party" .. i, widthFrom = "targettarget", threat = true,
	}
end

---------------------------------------------------------------------------
-- Saved settings: KUIDB[section][key]. Sections missing keys are filled
-- from here on load, and "Reset to defaults" restores them.
---------------------------------------------------------------------------

ns.settingsDefaults = {
	style = {
		font = "Arial Narrow",
		fontSize = 11,
		healthTexture = "Modern",
		powerTexture = "Modern",
		border = "Rounded",
		borderSize = 12, -- small frames use 2/3 of this
		borderColor = { 0.5, 0.5, 0.5 },
		bgAlpha = 0.8,
		padding = 1, -- gap between the border and the bars/portrait
		powerHeight = 10, -- player/target only; party and pet keep fixed sizes
		outOfRangeAlpha = 0.45, -- party members out of range
		-- Background of empty power bars and idle cast bars
		emptyColor = { 0, 0, 0 },
		emptyAlpha = 0.5,
	},

	--   [focus] [player] - - | - - [target] [tot]
	layout = {
		y = -200, -- vertical offset of the whole row from screen center
		centerGap = 120, -- center line to player's right / target's left edge
		sideGap = 8, -- player-focus and target-tot (always symmetric)
		-- Party column, top-left anchored, the classic spot
		partyX = 20,
		partyY = -180,
		partySpacing = 14,
	},

	-- Cast bar row inside the player/target frames, under the power bar
	castbar = {
		height = 12,
		focusHeight = 12, -- detached bar under the focus frame
		texture = "Modern",
		showIcon = true,
	},

	-- Restyling of Blizzard's action buttons (layout stays with Edit Mode)
	actionbars = {
		enabled = true,
		showHotkeys = true,
		showMacroNames = true,
		rangeColor = true,
		activeColor = { 1, 0.82, 0 }, -- border color while an action is active
		markLowRank = true, -- dot on buttons with a spell below its highest trained rank
	},

	-- XP / reputation bars replacing Blizzard's status tracking bars
	statusbars = {
		enabled = true,
		width = 500,
		height = 10,
		texture = "Modern",
		position = "Top", -- or "Bottom"; centered horizontally
	},

	nameplates = {
		enabled = true,
		width = 130,
		height = 14,
		castHeight = 12,
		highlightTarget = true,
		targetColor = { 1, 0.82, 0 }, -- border color on the current target's plate
		threatBorder = true, -- border in the threat color while pulling/tanking
		threatPercent = true, -- threat % beside the plate while on its threat list
	},

	-- Restyling of Blizzard's player buff/debuff frames (layout stays with
	-- Edit Mode)
	buffs = {
		enabled = true,
	},

	aggro = {
		enabled = true, -- threat-colored border on player, pet and party frames
	},

	healPrediction = {
		enabled = true, -- incoming heals on the unit frames' health bars
	},

	minimap = {
		style = "Blizzard", -- or "Square", in the KUI border
	},

	-- Bottom-right bag buttons and micro menu
	menubar = {
		bags = "All", -- or "Backpack only" (no bag slots or keyring), or "None"
		hideMicroMenu = false, -- character, spellbook, ... game menu buttons
	},

	chat = {
		hideButtons = true, -- the button column beside the chat windows
	},

	meter = {
		enabled = true,
		width = 200,
		rows = 6,
		rowHeight = 14,
		texture = "Modern",
		mode = "damage", -- or "healing"
		segment = "current", -- or "overall"
		point = { "BOTTOMRIGHT", "BOTTOMRIGHT", -20, 220 }, -- point, UIParent point, x, y
	},
}
