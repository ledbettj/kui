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
	"StaticPopupDialogs",
}

-- WoW API and Blizzard UI that KUI reads. Add to this when using something
-- new; luacheck reports it as an undefined variable.
read_globals = {
	-- Lua extensions in the WoW environment
	"bit", "format", "strlower", "strtrim", "tinsert", "wipe",
	"CopyTable", "tDeleteItem", "tIndexOf", "tInvert",

	-- Which client this is (Compat.lua)
	"WOW_PROJECT_ID", "WOW_PROJECT_BURNING_CRUSADE_CLASSIC", "WOW_PROJECT_CAMELOT", "issecretvalue",

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
	"GetCoinTextureString", "GetFramerate", "GetMoney", "GetNetStats", "GetRealmName",
	"GetNumGroupMembers", "GetQuestDifficultyColor", "GetTime", "GetXPExhaustion",
	"InCombatLockdown", "IsInGroup", "IsInInstance", "IsInRaid", "GetInstanceInfo", "IsPlayerAtEffectiveMaxLevel",
	"IsResting", "IsXPUserDisabled", "CombatLogGetCurrentEventInfo",

	-- Frames and widgets
	"CreateFont", "CreateFrame", "hooksecurefunc", "LibStub",
	"RegisterStateDriver", "RegisterUnitWatch", "UnregisterStateDriver", "UnregisterUnitWatch",
	"CooldownFrame_Set", "GameTooltip", "GameTooltip_Hide", "AuraUtil",
	"UnitFrame_OnEnter", "UnitFrame_OnLeave", "GameTime_GetTime",
	"ColorPickerFrame", "MinimalSliderWithSteppersMixin",
	"GameFontHighlightSmall", "SystemFont_NamePlate", "StaticPopup_Show",

	-- Blizzard frames KUI restyles or hides
	"UIParent", "BuffFrame", "DebuffFrame", "NamePlateDriverFrame",
	"StatusTrackingBarManager", "TextToSpeechButtonFrame", "CHAT_FRAMES",
	"MainMenuBarBackpackButton", "MicroMenuContainer",
	"Minimap", "MinimapCluster", "MinimapBorder", "MinimapNorthTag",
	"MinimapCompassTexture", "MinimapZoomIn", "MinimapZoomOut",
	"MinimapToggleButton", "GameTimeFrame", "TimeManagerAlarmFiredTexture",

	-- Blizzard data and strings
	"FACTION_BAR_COLORS", "LOCALIZED_CLASS_NAMES_MALE", "PowerBarColor",
	"RAID_CLASS_COLORS", "FAILED", "INTERRUPTED", "RESET", "YES", "NO", "ACCEPT", "CANCEL",
	"LOCALIZED_CLASS_NAMES_FEMALE", "ITEM_QUALITY_COLORS", "FRIEND_TAB_FRIENDS",

	-- Tooltips, vendors and the info bar's readouts
	"GameTooltipStatusBar", "GetItemInfo", "IsShiftKeyDown",
	"CanMerchantRepair", "GetRepairAllCost", "RepairAllItems", "CanGuildBankRepair",
	"GetGuildBankMoney", "GetGuildBankWithdrawMoney",
	"C_FriendList", "C_GuildInfo", "C_AddOns", "BNGetNumFriends",
	"IsInGuild", "GetGuildInfo", "GetNumGuildMembers", "GetGuildRosterInfo",
	"GetInventoryItemLink", "GetRealZoneText", "GetSubZoneText", "GetManaRegen",
	"UpdateAddOnMemoryUsage", "GetAddOnMemoryUsage", "SecondsToTime",
	"GameTime_GetLocalTime", "GameTime_GetGameTime", "UIParentLoadAddOn", "TimeManager_Toggle",
	"ToggleAllBags", "ToggleCharacter", "ToggleFriendsFrame", "ToggleGuildFrame", "ToggleWorldMap",
}
