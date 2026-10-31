local addonName, ns = ...

-- A full-width strip along the bottom of the screen in the KUI backdrop,
-- with only its top border on screen. The XP/reputation bars sit on top of
-- it when they're at the bottom.
--
-- It holds small readouts (gold, bags, durability, friends, guild,
-- coordinates, XP per hour, mana regen, fps, latency, clock) in three
-- slots: left, center and right. Each readout is assigned a slot or hidden.
-- Hovering one shows details, and most open something when clicked.
-- ns.db.infobar.order is kept grouped by slot (left, center, right,
-- hidden) and is the left-to-right order within each one.

ns.infoBarSlots = { "Left", "Center", "Right", "Hidden" }
local SLOT_RANK = tInvert(ns.infoBarSlots)

local bar
local slotFrames = {} -- "Left"/"Center"/"Right" -> frame holding its readouts
local buttons = {} -- readout id -> button
local eventReadouts = {} -- event -> list of readout ids it updates

---------------------------------------------------------------------------
-- Readouts. update returns the text ("" hides the readout for now);
-- interval (seconds) and/or events say when to call it. tooltip(tt) adds
-- lines to the shown GameTooltip; click(mouseButton) runs on a click, with
-- hint describing it at the bottom of the tooltip.
---------------------------------------------------------------------------

local WHITE = { 1, 1, 1 }

local function Hex(c)
	return format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

-- Localized class name ("Priest", "Prêtresse") -> class token ("PRIEST");
-- the friends list only gives the name
local classTokens = {}
for token, name in pairs(LOCALIZED_CLASS_NAMES_MALE) do classTokens[name] = token end
for token, name in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do classTokens[name] = token end

local function ClassHex(token)
	return Hex((token and ns:GetClassColor(token)) or WHITE)
end

-- Blizzard panels are opened through the UI panel system, which addon code
-- shouldn't touch in combat
local function OutOfCombat(fn)
	return function(...)
		if InCombatLockdown() then return ns.Print("can't open that in combat.") end
		fn(...)
	end
end

local function LatencyColor(ms)
	if ms < 100 then return "|cff40ff40" elseif ms < 250 then return "|cffffd040" end
	return "|cffff4040"
end

-- Green / yellow / red text for a share remaining (0-1)
local function PercentColor(share)
	if share > 0.5 then return "|cff40ff40" elseif share > 0.25 then return "|cffffd040" end
	return "|cffff4040"
end

-- Lowest durability among equipped items, 0-1; nil with nothing that wears
local function LowestDurability()
	local lowest
	for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
		local cur, max = GetInventoryItemDurability(slot)
		if cur and max > 0 then
			lowest = math.min(lowest or 1, cur / max)
		end
	end
	return lowest
end

local function BagSlots()
	local free, total = 0, 0
	for bag = 0, NUM_BAG_SLOTS do
		local bagFree, bagType = C_Container.GetContainerNumFreeSlots(bag)
		-- Ammo pouches, quivers and soul bags hold only their own items
		if bagType == 0 then
			free = free + bagFree
			total = total + C_Container.GetContainerNumSlots(bag)
		end
	end
	return free, total
end

---------------------------------------------------------------------------
-- Gold on every character, kept account-wide: KUIDB.gold["Name - Realm"]
---------------------------------------------------------------------------

local sessionStartMoney

local function SaveGold()
	KUIDB.gold = KUIDB.gold or {}
	local _, class = UnitClass("player")
	KUIDB.gold[ns.charKey] = { money = GetMoney(), class = class }
end

local goldList = {}
local function GoldTooltip(tt)
	local total = 0
	wipe(goldList)
	for char, entry in pairs(KUIDB.gold or {}) do
		goldList[#goldList + 1] = char
		total = total + entry.money
	end
	table.sort(goldList, function(a, b) return KUIDB.gold[a].money > KUIDB.gold[b].money end)

	tt:AddLine("Gold")
	for _, char in ipairs(goldList) do
		local entry = KUIDB.gold[char]
		tt:AddDoubleLine(ClassHex(entry.class) .. char .. "|r", GetCoinTextureString(entry.money), 1, 1, 1, 1, 1, 1)
	end
	if #goldList > 1 then
		tt:AddDoubleLine("Total", GetCoinTextureString(total), 1, 0.82, 0, 1, 1, 1)
	end

	local change = GetMoney() - (sessionStartMoney or GetMoney())
	if change ~= 0 then
		tt:AddLine(" ")
		tt:AddDoubleLine(change > 0 and "Gained this session" or "Spent this session",
			GetCoinTextureString(math.abs(change)), 1, 0.82, 0, 1, 1, 1)
	end
end

---------------------------------------------------------------------------
-- XP per hour since login (or since the last click)
---------------------------------------------------------------------------

local xp = { gained = 0 } -- start (GetTime), last (XP), lastMax

local function ResetXP()
	xp.gained, xp.start = 0, GetTime()
	xp.last, xp.lastMax = UnitXP("player"), UnitXPMax("player")
end

-- Adds what was earned since the last check; a level up wraps around
local function TrackXP()
	if not xp.start then ResetXP() end
	local cur, max = UnitXP("player"), UnitXPMax("player")
	if cur < xp.last then
		xp.gained = xp.gained + (xp.lastMax - xp.last) + cur
	else
		xp.gained = xp.gained + (cur - xp.last)
	end
	xp.last, xp.lastMax = cur, max
end

local function XPPerHour()
	local hours = (GetTime() - xp.start) / 3600
	return hours > 0 and xp.gained / hours or 0
end

local function AtMaxLevel()
	return IsPlayerAtEffectiveMaxLevel() or (IsXPUserDisabled and IsXPUserDisabled())
end

---------------------------------------------------------------------------
-- Friends and guild
---------------------------------------------------------------------------

local function FriendsTooltip(tt)
	local online = C_FriendList.GetNumOnlineFriends() or 0
	tt:AddLine("Friends online")
	if online == 0 then tt:AddLine("None", 0.6, 0.6, 0.6) end
	for i = 1, C_FriendList.GetNumFriends() do
		local info = C_FriendList.GetFriendInfoByIndex(i)
		if info and info.connected then
			local status = info.afk and " |cffffd040(away)|r" or info.dnd and " |cffff4040(busy)|r" or ""
			tt:AddDoubleLine(ClassHex(classTokens[info.className]) .. info.name .. "|r " .. info.level .. status,
				info.area or "", 1, 1, 1, 0.7, 0.7, 0.7)
		end
	end
	local _, bnetOnline = BNGetNumFriends()
	if bnetOnline and bnetOnline > 0 then
		tt:AddLine(" ")
		tt:AddLine(format("%d Battle.net friend%s online", bnetOnline, bnetOnline == 1 and "" or "s"), 0.5, 0.8, 1)
	end
end

local GUILD_TOOLTIP_MAX = 30 -- members listed; the rest are summed up
local ROSTER_INTERVAL = 30 -- seconds between roster requests

-- The roster only refreshes when asked for
local lastRosterRequest = 0
local function RequestRoster()
	if IsInGuild() and GetTime() - lastRosterRequest >= ROSTER_INTERVAL then
		lastRosterRequest = GetTime()
		C_GuildInfo.GuildRoster()
	end
end

local function GuildTooltip(tt)
	local guildName = GetGuildInfo("player")
	local total, online = GetNumGuildMembers()
	tt:AddLine(guildName or "Guild")
	local shown = 0
	for i = 1, total do
		local name, _, _, level, _, zone, _, _, isOnline, status, class = GetGuildRosterInfo(i)
		if isOnline and name then
			shown = shown + 1
			if shown <= GUILD_TOOLTIP_MAX then
				local away = status == 1 and " |cffffd040(away)|r" or status == 2 and " |cffff4040(busy)|r" or ""
				tt:AddDoubleLine(ClassHex(class) .. Ambiguate(name, "guild") .. "|r " .. level .. away,
					zone or "", 1, 1, 1, 0.7, 0.7, 0.7)
			end
		end
	end
	if shown > GUILD_TOOLTIP_MAX then
		tt:AddLine(format("and %d more", shown - GUILD_TOOLTIP_MAX), 0.6, 0.6, 0.6)
	end
	tt:AddLine(format("%d of %d online", online or 0, total or 0), 0.6, 0.6, 0.6)
end

---------------------------------------------------------------------------
-- Addon memory, for the fps tooltip
---------------------------------------------------------------------------

local MEMORY_TOOLTIP_MAX = 10
local memoryList = {}

local function MemoryText(kb)
	return kb >= 1024 and format("%.1f MB", kb / 1024) or format("%d KB", kb)
end

local function MemoryTooltip(tt)
	UpdateAddOnMemoryUsage()
	wipe(memoryList)
	local total = 0
	for i = 1, C_AddOns.GetNumAddOns() do
		local kb = GetAddOnMemoryUsage(i)
		if kb > 0 then
			memoryList[#memoryList + 1] = { name = (C_AddOns.GetAddOnInfo(i)), kb = kb }
			total = total + kb
		end
	end
	table.sort(memoryList, function(a, b) return a.kb > b.kb end)

	tt:AddDoubleLine("Addon memory", MemoryText(total))
	for i = 1, math.min(#memoryList, MEMORY_TOOLTIP_MAX) do
		tt:AddDoubleLine(memoryList[i].name, MemoryText(memoryList[i].kb), 1, 1, 1, 1, 1, 1)
	end
end

---------------------------------------------------------------------------
-- The readouts
---------------------------------------------------------------------------

ns.readouts = {
	gold = {
		label = "Gold",
		events = { "PLAYER_MONEY" },
		update = function()
			SaveGold()
			return GetCoinTextureString(GetMoney())
		end,
		tooltip = GoldTooltip,
		hint = "Click: open bags",
		click = function() ToggleAllBags() end,
	},
	bags = {
		label = "Bag slots",
		events = { "BAG_UPDATE_DELAYED" },
		update = function()
			local free, total = BagSlots()
			-- The backpack button's icon, sized to the font
			return format("|TInterface\\Buttons\\Button-Backpack-Up:0|t %d/%d", total - free, total)
		end,
		tooltip = function(tt)
			tt:AddLine("Bags")
			for bag = 0, NUM_BAG_SLOTS do
				local slots = C_Container.GetContainerNumSlots(bag)
				if slots > 0 then
					local free = C_Container.GetContainerNumFreeSlots(bag)
					tt:AddDoubleLine(C_Container.GetBagName(bag) or "?", format("%d/%d used", slots - free, slots),
						1, 1, 1, 1, 1, 1)
				end
			end
		end,
		hint = "Click: open bags",
		click = function() ToggleAllBags() end,
	},
	durability = {
		label = "Durability",
		events = { "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED" },
		update = function()
			local share = LowestDurability() or 1
			-- The repair tracking icon, sized to the font
			return format("|TInterface\\Minimap\\Tracking\\Repair:0|t %s%d%%|r", PercentColor(share), share * 100)
		end,
		tooltip = function(tt)
			tt:AddLine("Durability")
			local any
			for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
				local cur, max = GetInventoryItemDurability(slot)
				if cur and max > 0 and cur < max then
					any = true
					local share = cur / max
					tt:AddDoubleLine(GetInventoryItemLink("player", slot) or "?",
						format("%s%d%%|r", PercentColor(share), share * 100))
				end
			end
			if not any then tt:AddLine("Everything is fully repaired", 0.6, 0.6, 0.6) end
		end,
		hint = "Click: character",
		click = OutOfCombat(function() ToggleCharacter("PaperDollFrame") end),
	},
	friends = {
		label = "Friends",
		events = { "FRIENDLIST_UPDATE", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "BN_FRIEND_INFO_CHANGED" },
		update = function()
			local _, bnetOnline = BNGetNumFriends()
			return format("Friends: %d", (C_FriendList.GetNumOnlineFriends() or 0) + (bnetOnline or 0))
		end,
		tooltip = FriendsTooltip,
		hint = "Click: friends list",
		click = OutOfCombat(function() ToggleFriendsFrame(FRIEND_TAB_FRIENDS) end),
	},
	guild = {
		label = "Guild",
		interval = ROSTER_INTERVAL,
		events = { "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" },
		update = function()
			if not IsInGuild() then return "" end
			RequestRoster()
			local _, online = GetNumGuildMembers()
			return format("Guild: %d", online or 0)
		end,
		tooltip = GuildTooltip,
		hint = "Click: guild",
		click = OutOfCombat(function() ToggleGuildFrame() end),
	},
	coords = {
		label = "Coordinates",
		interval = 0.5,
		update = function()
			local map = C_Map.GetBestMapForUnit("player")
			local pos = map and C_Map.GetPlayerMapPosition(map, "player")
			if not pos then return "--, --" end -- instances have no position
			local x, y = pos:GetXY()
			return format("%.1f, %.1f", x * 100, y * 100)
		end,
		tooltip = function(tt)
			tt:AddLine(GetRealZoneText())
			local sub = GetSubZoneText()
			if sub ~= "" then tt:AddLine(sub, 1, 1, 1) end
		end,
		hint = "Click: world map",
		click = OutOfCombat(function() ToggleWorldMap() end),
	},
	xp = {
		label = "XP per hour",
		interval = 5, -- the rate drifts down between kills
		events = { "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP" },
		update = function()
			if AtMaxLevel() then return "" end
			TrackXP()
			return format("%s xp/h", ns.ShortValue(XPPerHour()))
		end,
		tooltip = function(tt)
			local cur, max = UnitXP("player"), UnitXPMax("player")
			local rate = XPPerHour()
			tt:AddLine("Experience")
			tt:AddDoubleLine("Level progress", format("%s / %s (%d%%)", ns.ShortValue(cur), ns.ShortValue(max),
				cur / max * 100), 1, 1, 1, 1, 1, 1)
			local rested = GetXPExhaustion()
			if rested then tt:AddDoubleLine("Rested", ns.ShortValue(rested), 1, 1, 1, 0.4, 0.6, 1) end
			tt:AddDoubleLine("Gained", ns.ShortValue(xp.gained) .. " in " .. SecondsToTime(GetTime() - xp.start),
				1, 1, 1, 1, 1, 1)
			if rate > 0 then
				tt:AddDoubleLine("Level in", SecondsToTime((max - cur) / rate * 3600), 1, 1, 1, 1, 1, 1)
			end
		end,
		hint = "Click: start counting again",
		click = function()
			ResetXP()
			ns:LayoutInfoBar()
		end,
	},
	regen = {
		label = "Mana regen",
		interval = 2,
		update = function()
			if UnitPowerMax("player", Enum.PowerType.Mana) == 0 then return "" end
			local base, casting = GetManaRegen()
			return format("%d / %d mp5", base * 5, casting * 5)
		end,
		tooltip = function(tt)
			local base, casting = GetManaRegen()
			tt:AddLine("Mana regeneration per 5 seconds")
			tt:AddDoubleLine("Not casting", format("%d", base * 5), 1, 1, 1, 1, 1, 1)
			tt:AddDoubleLine("Within 5 seconds of a cast", format("%d", casting * 5), 1, 1, 1, 1, 1, 1)
		end,
	},
	clock = {
		label = "Clock",
		interval = 1,
		-- Follows the clock options (12/24 hour, local or server time)
		update = function() return (GameTime_GetTime(true)) end,
		tooltip = function(tt)
			tt:AddLine("Time")
			tt:AddDoubleLine("Local", (GameTime_GetLocalTime(true)), 1, 1, 1, 1, 1, 1)
			tt:AddDoubleLine("Realm", (GameTime_GetGameTime(true)), 1, 1, 1, 1, 1, 1)
		end,
		hint = "Click: clock options and alarm",
		click = function()
			if not C_AddOns.IsAddOnLoaded("Blizzard_TimeManager") then
				UIParentLoadAddOn("Blizzard_TimeManager")
			end
			TimeManager_Toggle()
		end,
	},
	fps = {
		label = "FPS",
		interval = 1,
		update = function() return format("%d fps", GetFramerate()) end,
		tooltip = MemoryTooltip,
		hint = "Click: free unused addon memory",
		click = function()
			local before = collectgarbage("count")
			collectgarbage("collect")
			ns.Print("freed " .. MemoryText(before - collectgarbage("count")) .. " of addon memory.")
		end,
	},
	latency = {
		label = "Latency",
		interval = 5,
		update = function()
			local _, _, home, world = GetNetStats()
			local ms = math.max(home, world)
			return format("%s%d|r ms", LatencyColor(ms), ms)
		end,
		tooltip = function(tt)
			local down, up, home, world = GetNetStats()
			tt:AddLine("Latency")
			tt:AddDoubleLine("Home (chat, auction house)", format("%s%d|r ms", LatencyColor(home), home), 1, 1, 1)
			tt:AddDoubleLine("World (combat, movement)", format("%s%d|r ms", LatencyColor(world), world), 1, 1, 1)
			tt:AddDoubleLine("Bandwidth down / up", format("%.1f / %.1f KB/s", down, up), 1, 1, 1, 1, 1, 1)
		end,
	},
}

local SyncSavedReadouts -- defined with the ordering code below
local ShowTooltip, OnClick -- button scripts, defined with the updates

local function SlotOf(id)
	return ns.db.infobar.slots[id]
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

-- Readouts left to right in the list order, each as wide as its text
local function LayoutSlot(slot)
	local I = ns.db.infobar
	local frame, x = slotFrames[slot], 0
	for _, id in ipairs(I.order) do
		local button = buttons[id]
		-- An empty readout takes no room, spacing included, and can't be
		-- hovered where it last was
		local empty = button.text:GetText() == ""
		button:EnableMouse(not empty)
		if SlotOf(id) == slot and not empty then
			button:SetWidth(button.text:GetStringWidth())
			button:ClearAllPoints()
			button:SetPoint("LEFT", frame, "LEFT", x, 0)
			x = x + button:GetWidth() + I.spacing
		end
	end
	frame:SetWidth(math.max(1, x - I.spacing))
end

local function UpdateReadout(id)
	local button = buttons[id]
	button.text:SetText(ns.readouts[id].update())
	-- Widths in the slot change with the text
	LayoutSlot(SlotOf(id))
end

-- Screen height the bar takes up, for anything stacked above it
function ns:InfoBarHeight()
	return (bar and ns.db.infobar.enabled) and ns.db.infobar.height or 0
end

-- Positions the bar and slots and refreshes every shown readout
function ns:LayoutInfoBar()
	if not bar then return end
	SyncSavedReadouts() -- a different profile may be from an older version
	local I = ns.db.infobar
	bar:SetShown(I.enabled)

	-- Sides and bottom edge pushed just off screen so only the top border shows
	local edge = ns:ApplyBackdrop(bar) - ns.db.style.padding
	bar:ClearAllPoints()
	bar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -edge, -edge)
	bar:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", edge, -edge)
	bar:SetHeight(I.height + edge)

	-- Slots span the visible height
	for slot, frame in pairs(slotFrames) do
		frame:SetHeight(I.height)
		frame:ClearAllPoints()
		if slot == "Left" then
			frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", I.edgePadding, 0)
		elseif slot == "Right" then
			frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -I.edgePadding, 0)
		else
			frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
		end
	end

	for id, button in pairs(buttons) do
		local slot = SlotOf(id)
		local shown = slot ~= "Hidden"
		button:SetShown(shown)
		if shown then
			button:SetParent(slotFrames[slot])
			button:SetHeight(I.height)
			button.text:SetText(ns.readouts[id].update())
		end
	end
	for slot in pairs(slotFrames) do
		LayoutSlot(slot)
	end
end

---------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------

local elapsed = {} -- readout id -> seconds since its last update

local function OnUpdate(_, dt)
	for id, readout in pairs(ns.readouts) do
		if readout.interval and buttons[id]:IsShown() then
			elapsed[id] = (elapsed[id] or 0) + dt
			if elapsed[id] >= readout.interval then
				elapsed[id] = 0
				UpdateReadout(id)
			end
		end
	end
end

local function OnEvent(_, event)
	for _, id in ipairs(eventReadouts[event]) do
		if buttons[id]:IsShown() then UpdateReadout(id) end
	end
end

-- Tooltip above the readout, lined up with its screen-edge side in the
-- left and right slots so it stays on screen
local ANCHORS = { Left = "LEFT", Center = "", Right = "RIGHT" }

function ShowTooltip(button)
	local readout = ns.readouts[button.id]
	if not readout.tooltip then return end
	local side = ANCHORS[SlotOf(button.id)] or ""
	GameTooltip:SetOwner(button, "ANCHOR_NONE")
	GameTooltip:SetPoint("BOTTOM" .. side, button, "TOP" .. side, 0, 6)
	readout.tooltip(GameTooltip)
	if readout.hint then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(readout.hint, 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

function OnClick(button, mouseButton)
	local readout = ns.readouts[button.id]
	if readout.click then readout.click(mouseButton) end
end

---------------------------------------------------------------------------
-- Order
---------------------------------------------------------------------------

-- Regroups the order by slot, keeping each readout's place within its slot
local function GroupBySlot()
	local I = ns.db.infobar
	local position = {}
	for i, id in ipairs(I.order) do position[id] = i end
	table.sort(I.order, function(a, b)
		local ra, rb = SLOT_RANK[I.slots[a]], SLOT_RANK[I.slots[b]]
		if ra ~= rb then return ra < rb end
		return position[a] < position[b]
	end)
end

-- Saved order/slots get readouts added in later versions, and lose any
-- that no longer exist
function SyncSavedReadouts()
	local I, defaults = ns.db.infobar, ns.settingsDefaults.infobar
	local order, seen = {}, {}
	for _, id in ipairs(I.order) do
		if ns.readouts[id] and not seen[id] then
			order[#order + 1] = id
			seen[id] = true
		end
	end
	for _, id in ipairs(defaults.order) do
		if not seen[id] then order[#order + 1] = id end
		if not SLOT_RANK[I.slots[id]] then
			I.slots[id] = defaults.slots[id] or "Hidden"
		end
	end
	I.order = order
	GroupBySlot()
end

-- Whether the readout at index can move one place earlier (-1) or later
-- (+1): only past a neighbor in the same slot
function ns:CanMoveReadout(index, step)
	local I = ns.db.infobar
	local id, other = I.order[index], I.order[index + step]
	return other ~= nil and I.slots[id] == I.slots[other]
end

function ns:MoveReadout(index, step)
	if not ns:CanMoveReadout(index, step) then return end
	local order = ns.db.infobar.order
	order[index], order[index + step] = order[index + step], order[index]
	ns:LayoutInfoBar()
end

-- A readout moving to another slot goes to the end of it
function ns:SetReadoutSlot(id, slot)
	local I = ns.db.infobar
	if I.slots[id] == slot then return end
	tDeleteItem(I.order, id)
	tinsert(I.order, id)
	I.slots[id] = slot
	GroupBySlot()
	ns:LayoutInfoBar()
end

function ns:InitInfoBar()
	bar = CreateFrame("Frame", "KUI_InfoBar", UIParent, "BackdropTemplate")
	bar:SetFrameStrata("BACKGROUND")

	for _, slot in ipairs({ "Left", "Center", "Right" }) do
		slotFrames[slot] = CreateFrame("Frame", nil, bar)
	end

	for id in pairs(ns.readouts) do
		local button = CreateFrame("Button", nil, bar)
		button.id = id
		button.text = ns.CreateText(button, ns.fonts.normal, "LEFT")
		button.text:SetPoint("LEFT")
		button:RegisterForClicks("LeftButtonUp")
		button:SetScript("OnEnter", ShowTooltip)
		button:SetScript("OnLeave", GameTooltip_Hide)
		button:SetScript("OnClick", OnClick)
		buttons[id] = button
	end

	sessionStartMoney = GetMoney()
	ResetXP()
	-- The friends list only arrives when asked for
	C_FriendList.ShowFriends()
	RequestRoster()

	-- Everything refreshes on entering the world, plus its own events
	eventReadouts.PLAYER_ENTERING_WORLD = {}
	for id, readout in pairs(ns.readouts) do
		tinsert(eventReadouts.PLAYER_ENTERING_WORLD, id)
		for _, event in ipairs(readout.events or {}) do
			eventReadouts[event] = eventReadouts[event] or {}
			tinsert(eventReadouts[event], id)
		end
	end
	for event in pairs(eventReadouts) do
		bar:RegisterEvent(event)
	end
	bar:SetScript("OnEvent", OnEvent)
	bar:SetScript("OnUpdate", OnUpdate)

	ns:LayoutInfoBar()
end
