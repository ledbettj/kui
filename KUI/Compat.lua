local addonName, ns = ...

-- Secret values and which of KUI's features are on.
--
-- In combat and instances the client hands addons many unit, aura, cast and
-- combat log values as secrets, which can be shown but not compared or used
-- in math.

-- Whether a value is a secret this addon can only pass along. Check before
-- comparing, doing math on, or indexing with anything that may be one.
ns.IsSecret = issecretvalue

-- ns.supported is what Core, the settings pages and modules check: a feature
-- that's off is never initialized and its settings are hidden.
ns.supported = {
	unitframes = true, -- unit frames, their cast bars, auras, heal prediction, aggro
	nameplates = true,
	actionbars = true,
	buffs = true, -- the player buff/debuff frame restyle
	menubar = true, -- bag buttons and micro menu
	infobar = true,
	statusbars = true, -- XP / reputation bars
	minimap = true,
	chat = true,
	uifont = true, -- the whole-UI font
	tooltips = true,
	vendor = true,
}
