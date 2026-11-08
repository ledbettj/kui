-- luacheck config: run `luacheck .` from the repo root or an addon folder

std = "lua51"
max_line_length = 120
exclude_files = { ".luacheckrc", "**/test/**" }

ignore = {
	"211/addonName", -- every file unpacks `local addonName, ns = ...`
	"212/self", -- ns:Method() style functions that don't use self
}

-- Globals KUI defines or writes
globals = {
	"KUIDB", "QuestBrosDB", -- saved variables
	"SLASH_KUI1", "SLASH_QUESTBROS1", "SLASH_QUESTBROS2", "SlashCmdList",
	"ClickCastFrames", -- Clique's frame registry
	"GetMinimapShape", -- read by minimap button addons
	"StaticPopupDialogs",
}

-- WoW API and Blizzard UI that KUI reads. Add to this when using something
-- new; luacheck reports it as an undefined variable.
read_globals = {
	-- Lua extensions in the WoW environment
	"format", "strlower", "strtrim", "tinsert", "wipe",
	"CopyTable", "tDeleteItem", "tInvert",

	"issecretvalue",
	"geterrorhandler",

	-- Namespaced APIs and enums
	"C_Container", "C_Map", "C_NamePlate", "C_PartyInfo",
	"C_Reputation", "C_Timer",
	"Enum", "EventUtil", "GameRulesUtil", "Settings",

	-- Units
	"UnitAffectingCombat", "UnitCanAttack", "UnitCastingInfo", "UnitChannelInfo",
	"UnitClass", "UnitClassification", "UnitDetailedThreatSituation", "UnitExists",
	"UnitFactionGroup", "UnitHealth",
	"UnitHealthMax", "UnitInRange", "UnitIsConnected", "UnitIsDead",
	"UnitIsDeadOrGhost", "UnitIsGhost", "UnitIsGroupLeader", "UnitIsPlayer",
	"UnitIsPVP", "UnitIsPVPFreeForAll", "UnitIsTapDenied", "UnitIsUnit",
	"UnitIsVisible", "UnitLevel", "UnitName", "UnitPower", "UnitPowerMax",
	"UnitPowerType", "UnitReaction", "UnitThreatSituation", "UnitXP", "UnitXPMax",
	"GetComboPoints", "GetRaidTargetIndex",
	"SetRaidTargetIconTexture", "Ambiguate",

	-- Spells, actions, items
	"GetActionInfo", "GetItemInfoInstant", 
	"IsActionInRange", "IsUsableAction",
	"GetInventoryItemDurability", "INVSLOT_FIRST_EQUIPPED", "INVSLOT_LAST_EQUIPPED",
	"NUM_BAG_SLOTS",

	-- Player and system state
	"GetCoinTextureString", "GetFramerate", "GetMoney", "GetNetStats", "GetRealmName",
	"C_PlayerInfo", "GetDifficultyColor", "GetTime", "GetXPExhaustion",
	"InCombatLockdown", "IsInGroup", "IsPlayerAtEffectiveMaxLevel",
	"IsResting", "IsXPUserDisabled", 

	-- Frames and widgets
	"CreateFont", "CreateFrame", "hooksecurefunc", "LibStub",
	"RegisterStateDriver", "RegisterUnitWatch", "UnregisterStateDriver", "UnregisterUnitWatch",
	"GameTooltip", "GameTooltip_Hide", "AuraUtil",
	"UnitFrame_OnEnter", "UnitFrame_OnLeave", "GameTime_GetTime",
	"ColorPickerFrame", "MinimalSliderWithSteppersMixin",
	"GameFontHighlightSmall", "SystemFont_NamePlate", "StaticPopup_Show",

	-- Blizzard frames KUI restyles or hides
	"UIParent", "BuffFrame", "DebuffFrame", "NamePlateDriverFrame",
	"StatusTrackingBarManager", "TextToSpeechButtonFrame", "CHAT_FRAMES",
	"MainMenuBarBackpackButton", "MicroMenuContainer",
	"Minimap", "MinimapCluster", 
	"MinimapCompassTexture", 
	"GameTimeFrame", "TimeManagerAlarmFiredTexture", "MinimapCompassTextureUnderlay",

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
	"GameTime_GetLocalTime", "GameTime_GetGameTime", "TimeManager_Toggle",
	"ToggleAllBags", "ToggleCharacter", "ToggleFriendsFrame", "ToggleGuildFrame", "ToggleWorldMap",

	"C_ActionBar", "C_CurrencyInfo", "C_Spell", "C_Item", "TooltipDataProcessor", "TooltipUtil", "MainActionBar",
	"Constants",
	"BagsBar", "QuickJoinToastButton",
	-- Secret-safe unit APIs
	"AbbreviateLargeNumbers", "UnitHealthPercent", "UnitPowerPercent", "CurveConstants", "C_CurveUtil",
	"CreateUnitHealPredictionCalculator", "UnitGetDetailedHealPrediction",
	"AnchorUtil", "C_Secrets",
	"UnitCastingDuration", "UnitChannelDuration", "C_DurationUtil",

	-- QuestBros
	"C_ChatInfo", "C_QuestLog", "GetNormalizedRealmName", "GetQuestID", "GetServerTime", "strsplit",
	"QuestFrame", "QuestFrameDetailPanel", "QuestFrameGreetingPanel", "QuestFrameProgressPanel",
	"QuestFrameRewardPanel", "QuestLogPopupDetailFrame", "QuestMapFrame", "QuestScrollFrame",
}
