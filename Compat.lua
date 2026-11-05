local addonName, ns = ...

-- Which game client KUI is running in, and which of its features run there.
--
-- KUI supports two clients from one folder; each loads its own TOC:
--   KUI_TBC.toc   TBC Anniversary (interface 20506). Classic UI code with
--                 modern APIs; everything here was built and tested on it.
--   KUI.toc       WoW "forever" (interface 16001, the Camelot game type).
--                 Retail's UI code, including secret values: in combat and
--                 instances many unit, aura, cast and combat log values
--                 can be shown but not compared or used in math.
--
-- On forever, each feature stays off until it has been ported to that
-- client's APIs. ns.supported is what Core, the settings pages and modules
-- check; a feature that's off is never initialized and its settings are
-- hidden.

ns.isTBC = WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC
-- Only defined when the Camelot game type is loaded
ns.isForever = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
-- Secret values exist on this client (forever); see the notes above
ns.hasSecrets = issecretvalue ~= nil

-- Whether a value is a secret this addon can only pass along. Check before
-- comparing, doing math on, or indexing with anything the forever client
-- may hand over as a secret. Always false on TBC.
function ns.IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

-- Feature -> runs on this client. Everything KUI has runs on TBC; FOREVER
-- lists what has been ported there.
local FEATURES = {
	"unitframes", -- unit frames, their cast bars, auras, heal prediction, aggro
	"nameplates",
	"actionbars",
	"buffs", -- the player buff/debuff frame restyle
	"menubar", -- bag buttons and micro menu
	"infobar",
	"statusbars", -- XP / reputation bars
	"minimap",
	"chat",
	"uifont", -- the whole-UI font
	"tooltips",
	"vendor",
	"meter", -- TBC only: forever's combat log is closed to addons, and it has its own meter
	"spellranks", -- action button marks for spells below their best rank
}

-- Ported to forever, though not yet tested in game there
local FOREVER = {
	infobar = true, vendor = true, tooltips = true, chat = true, uifont = true,
	menubar = true, buffs = true, actionbars = true,
	unitframes = true, statusbars = true, minimap = true, spellranks = true,
}

ns.supported = {}
for _, feature in ipairs(FEATURES) do
	ns.supported[feature] = ns.isTBC or (ns.isForever and FOREVER[feature] == true)
end
