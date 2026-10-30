local addonName, ns = ...

-- A full-width strip along the bottom of the screen in the KUI backdrop,
-- with only its top border on screen. The XP/reputation bars sit on top of
-- it when they're at the bottom.
--
-- It holds small readouts (gold, bag slots, durability, coordinates, fps,
-- latency, clock) in three slots:
-- left, center and right. Each readout is assigned a slot or hidden.
-- ns.db.infobar.order is kept grouped by slot (left, center, right,
-- hidden) and is the left-to-right order within each one.

ns.infoBarSlots = { "Left", "Center", "Right", "Hidden" }
local SLOT_RANK = tInvert(ns.infoBarSlots)

local bar
local slotFrames = {} -- "Left"/"Center"/"Right" -> frame holding its readouts
local buttons = {} -- readout id -> button
local eventReadouts = {} -- event -> list of readout ids it updates

---------------------------------------------------------------------------
-- Readouts. update returns the text; interval (seconds) and/or events say
-- when to call it.
---------------------------------------------------------------------------

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

ns.readouts = {
	gold = {
		label = "Gold",
		events = { "PLAYER_MONEY" },
		update = function() return GetCoinTextureString(GetMoney()) end,
	},
	bags = {
		label = "Bag slots",
		events = { "BAG_UPDATE_DELAYED" },
		update = function()
			local free, total = BagSlots()
			-- The backpack button's icon, sized to the font
			return format("|TInterface\\Buttons\\Button-Backpack-Up:0|t %d/%d", total - free, total)
		end,
	},
	durability = {
		label = "Durability",
		events = { "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED" },
		update = function()
			local share = LowestDurability() or 1
			-- The repair tracking icon, sized to the font
			return format("|TInterface\\Minimap\\Tracking\\Repair:0|t %s%d%%|r", PercentColor(share), share * 100)
		end,
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
	},
	clock = {
		label = "Clock",
		interval = 1,
		-- Follows the clock options (12/24 hour, local or server time)
		update = function() return (GameTime_GetTime(true)) end,
	},
	fps = {
		label = "FPS",
		interval = 1,
		update = function() return format("%d fps", GetFramerate()) end,
	},
	latency = {
		label = "Latency",
		interval = 5,
		update = function()
			local _, _, home, world = GetNetStats()
			local ms = math.max(home, world)
			return format("%s%d|r ms", LatencyColor(ms), ms)
		end,
	},
}

local SyncSavedReadouts -- defined with the ordering code below

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
		if SlotOf(id) == slot then
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
		button.text = ns.CreateText(button, ns.fonts.normal, "LEFT")
		button.text:SetPoint("LEFT")
		buttons[id] = button
	end

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
