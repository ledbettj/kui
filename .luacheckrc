-- luacheck config: run `luacheck .` from the addon folder

std = "lua51"
max_line_length = 120
exclude_files = { ".luacheckrc" }

ignore = {
	"211/addonName", -- every file unpacks `local addonName, ns = ...`
	"212/self", -- ns:Method() style functions that don't use self
}

-- Globals KUI defines or writes
globals = {
	"KUIDB", -- saved variables
	"SLASH_KUI1", "SlashCmdList",
	"ClickCastFrames", -- Clique's frame registry
	"GetMinimapShape", -- read by minimap button addons
}

-- WoW API and Blizzard UI that KUI reads. Add to this when using something
-- new; luacheck reports it as an undefined variable.
read_globals = {
	-- Lua extensions in the WoW environment
	"bit", "format", "strlower", "strtrim", "tinsert", "wipe",
	"CopyTable", "tDeleteItem", "tInvert",

	-- Namespaced APIs and enums
	"C_CombatLog", "C_Container", "C_Map", "C_NamePlate", "C_PartyInfo",
	"C_Reputation", "C_Spell", "C_Texture", "C_Timer",
	"Enum", "EventUtil", "GameRulesUtil", "Settings",

	-- Units
	"UnitAffectingCombat", "UnitCanAttack", "UnitCastingInfo", "UnitChannelInfo",
	"UnitClass", "UnitClassification", "UnitDetailedThreatSituation", "UnitExists",
	"UnitFactionGroup", "UnitGetIncomingHeals", "UnitGUID", "UnitHealth",
	"UnitHealthMax", "UnitInRange", "UnitIsConnected", "UnitIsDead",
	"UnitIsDeadOrGhost", "UnitIsGhost", "UnitIsGroupLeader", "UnitIsPlayer",
	"UnitIsPVP", "UnitIsPVPFreeForAll", "UnitIsTapDenied", "UnitIsUnit",
	"UnitIsVisible", "UnitLevel", "UnitName", "UnitPower", "UnitPowerMax",
	"UnitPowerType", "UnitReaction", "UnitThreatSituation", "UnitXP", "UnitXPMax",
	"GetComboPoints", "GetPlayerInfoByGUID", "GetRaidTargetIndex",
	"SetRaidTargetIconTexture", "Ambiguate",

	-- Spells, actions, items
	"GetActionInfo", "GetItemInfoInstant", "GetMacroSpell", "GetNumSpellTabs",
	"GetSpellBookItemInfo", "GetSpellBookItemName", "GetSpellInfo", "GetSpellSubtext",
	"GetSpellTabInfo", "IsActionInRange", "IsUsableAction",
	"GetInventoryItemDurability", "INVSLOT_FIRST_EQUIPPED", "INVSLOT_LAST_EQUIPPED",
	"NUM_BAG_SLOTS",

	-- Player and system state
	"GetCoinTextureString", "GetFramerate", "GetMoney", "GetNetStats",
	"GetNumGroupMembers", "GetQuestDifficultyColor", "GetTime", "GetXPExhaustion",
	"InCombatLockdown", "IsInGroup", "IsInRaid", "IsPlayerAtEffectiveMaxLevel",
	"IsResting", "IsXPUserDisabled", "CombatLogGetCurrentEventInfo",

	-- Frames and widgets
	"CreateFont", "CreateFrame", "hooksecurefunc", "LibStub",
	"RegisterStateDriver", "RegisterUnitWatch", "UnregisterStateDriver", "UnregisterUnitWatch",
	"CooldownFrame_Set", "GameTooltip", "GameTooltip_Hide", "AuraUtil",
	"UnitFrame_OnEnter", "UnitFrame_OnLeave", "GameTime_GetTime",
	"ColorPickerFrame", "MinimalSliderWithSteppersMixin",
	"GameFontHighlightSmall", "SystemFont_NamePlate",

	-- Blizzard frames KUI restyles or hides
	"UIParent", "BuffFrame", "DebuffFrame", "NamePlateDriverFrame",
	"StatusTrackingBarManager", "TextToSpeechButtonFrame", "CHAT_FRAMES",
	"MainMenuBarBackpackButton", "MicroMenuContainer",
	"Minimap", "MinimapCluster", "MinimapBorder", "MinimapNorthTag",
	"MinimapCompassTexture", "MinimapZoomIn", "MinimapZoomOut",
	"MinimapToggleButton", "GameTimeFrame", "TimeManagerAlarmFiredTexture",

	-- Blizzard data and strings
	"FACTION_BAR_COLORS", "LOCALIZED_CLASS_NAMES_MALE", "PowerBarColor",
	"RAID_CLASS_COLORS", "FAILED", "INTERRUPTED", "RESET",
}
