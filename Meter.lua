local addonName, ns = ...

-- A small damage/healing meter for the group: one window with a bar per
-- player, for the current (or last) fight or everything since the last
-- reset. Pets and summons count as their owner. Healing is what actually
-- landed (no overhealing) plus damage absorbed by shields.
--
-- Title bar: left-click switches damage/healing, right-click current/
-- overall, drag to move. The corner grip resizes, snapping the height to
-- whole rows.

local MODE_LABELS = { damage = "Damage", healing = "Healing" }
local SEGMENT_LABELS = { current = "Current", overall = "Overall" }
local TITLE_HEIGHT = 16
local ROW_GAP = 1
local REFRESH_INTERVAL = 0.5
-- Size limits, matching the config sliders
local MIN_WIDTH, MAX_WIDTH = 120, 400
local MAX_ROWS = 25

local GetEventInfo = C_CombatLog and C_CombatLog.GetCurrentEventInfo or CombatLogGetCurrentEventInfo
local CLO = Enum.CombatLogObject
local GROUP_MASK = bit.bor(CLO.AffiliationMine, CLO.AffiliationParty, CLO.AffiliationRaid)

-- Position of the amount in each damage event's arguments
local DAMAGE_AMOUNT_ARG = {
	SWING_DAMAGE = 12,
	RANGE_DAMAGE = 15,
	SPELL_DAMAGE = 15,
	SPELL_PERIODIC_DAMAGE = 15,
	DAMAGE_SHIELD = 15,
	DAMAGE_SPLIT = 15,
}
local HEAL_EVENTS = { SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true }

local window
local rows = {}

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

-- actors: owner GUID -> { guid, name, class, damage, healing }
local function NewSegment()
	return { actors = {}, duration = 0 }
end

local segments = { current = NewSegment(), overall = NewSegment() }
local fightStart -- GetTime() while a fight is in progress
local petOwners = {} -- pet / summon GUID -> owner GUID

local function Duration(seg)
	if fightStart then return seg.duration + GetTime() - fightStart end
	return seg.duration
end

local function GroupInCombat()
	if UnitAffectingCombat("player") then return true end
	local prefix = IsInRaid() and "raid" or "party"
	for i = 1, GetNumGroupMembers() do
		if UnitAffectingCombat(prefix .. i) then return true end
	end
	return false
end

local function MapPet(owner, pet)
	local petGUID, ownerGUID = UnitGUID(pet), UnitGUID(owner)
	if petGUID and ownerGUID then petOwners[petGUID] = ownerGUID end
end

-- Pets with a unit token; summons (totems, Shadowfiend) come from
-- SPELL_SUMMON instead. Entries are kept so summons stay credited.
local function ScanPets()
	MapPet("player", "pet")
	for i = 1, 4 do MapPet("party" .. i, "partypet" .. i) end
	for i = 1, 40 do MapPet("raid" .. i, "raidpet" .. i) end
end

-- The group member to credit for a combat log source, if any
local function Owner(guid, flags)
	if bit.band(flags, GROUP_MASK) == 0 then return end
	if bit.band(flags, CLO.TypePlayer) ~= 0 then return guid end
	return petOwners[guid]
end

local function Actor(seg, guid)
	local a = seg.actors[guid]
	if not a then
		a = { guid = guid, damage = 0, healing = 0 }
		seg.actors[guid] = a
	end
	return a
end

local function Add(guid, key, amount)
	if not amount or amount <= 0 then return end
	-- Events outside combat (topping people off afterwards) would otherwise
	-- start a new fight and replace the last one
	if not fightStart then
		if not GroupInCombat() then return end
		segments.current = NewSegment()
		fightStart = GetTime()
	end
	for _, seg in pairs(segments) do
		local a = Actor(seg, guid)
		a[key] = a[key] + amount
	end
end

local function EndFight()
	local elapsed = GetTime() - fightStart
	for _, seg in pairs(segments) do
		seg.duration = seg.duration + elapsed
	end
	fightStart = nil
end

local function OnCombatLog()
	local _, event, _, srcGUID, _, srcFlags, _, dstGUID, _, dstFlags, _,
		a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22 = GetEventInfo()

	if event == "SPELL_SUMMON" then
		local owner = Owner(srcGUID, srcFlags)
		if owner then petOwners[dstGUID] = owner end
		return
	end

	local arg = DAMAGE_AMOUNT_ARG[event]
	if arg then
		-- Hitting friendlies (mind control, duels inside the group) isn't damage done
		if bit.band(dstFlags, CLO.ReactionFriendly) ~= 0 then return end
		local owner = Owner(srcGUID, srcFlags)
		if owner then Add(owner, "damage", arg == 12 and a12 or a15) end
	elseif HEAL_EVENTS[event] then
		local owner = Owner(srcGUID, srcFlags)
		if owner then Add(owner, "healing", a15 - (a16 or 0)) end
	elseif event == "SPELL_ABSORBED" then
		-- The shield's caster comes after the attacking spell's id, name and
		-- school when the absorbed hit was a spell, first for a melee swing
		if type(a12) == "number" then
			local owner = Owner(a15, a17)
			if owner then Add(owner, "healing", a22) end
		else
			local owner = Owner(a12, a14)
			if owner then Add(owner, "healing", a19) end
		end
	end
end

function ns:ResetMeter()
	segments.current, segments.overall = NewSegment(), NewSegment()
	fightStart = nil
	ns:RefreshMeter()
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------

local function ShortValue(v)
	if v >= 1e6 then
		return format("%.2fm", v / 1e6)
	elseif v >= 1e3 then
		return format("%.1fk", v / 1e3)
	end
	return format("%d", v)
end

local function FormatTime(seconds)
	return format("%d:%02d", seconds / 60, seconds % 60)
end

-- Names and classes come from the GUID, which can be uncached at first
local function Identify(a)
	if a.name and a.class then return end
	local _, class, _, _, _, name = GetPlayerInfoByGUID(a.guid)
	a.class = a.class or class
	a.name = a.name or (name and Ambiguate(name, "short"))
end

local UNKNOWN_COLOR = { 0.6, 0.6, 0.6 } -- class not cached yet

-- Reused every refresh, with a static comparator reading the mode
local sorted, sortKey = {}, nil
local function ByValue(x, y)
	return x[sortKey] > y[sortKey]
end

function ns:RefreshMeter()
	if not window or not window:IsShown() then return end
	local M = KUIDB.meter
	local seg, key = segments[M.segment], M.mode

	window.title:SetFormattedText("%s - %s  |cffaaaaaa%s|r",
		MODE_LABELS[key], SEGMENT_LABELS[M.segment], FormatTime(Duration(seg)))

	wipe(sorted)
	for _, a in pairs(seg.actors) do
		if a[key] > 0 then sorted[#sorted + 1] = a end
	end
	sortKey = key
	table.sort(sorted, ByValue)

	local top = sorted[1] and sorted[1][key] or 1
	local seconds = math.max(1, Duration(seg))
	for i = 1, M.rows do
		local row, a = rows[i], sorted[i]
		if a then
			Identify(a)
			local c = (a.class and ns:GetClassColor(a.class)) or UNKNOWN_COLOR
			row:SetMinMaxValues(0, top)
			row:SetValue(a[key])
			row:SetStatusBarColor(c[1], c[2], c[3])
			row.name:SetFormattedText("%d. %s", i, a.name or "?")
			row.value:SetFormattedText("%s (%s)", ShortValue(a[key]), ShortValue(a[key] / seconds))
			row:Show()
		else
			row:Hide()
		end
	end
end

-- Refreshes while a fight is running and notices when it ends
local elapsedSinceRefresh = 0
local function OnUpdate(_, elapsed)
	if not fightStart then return end
	elapsedSinceRefresh = elapsedSinceRefresh + elapsed
	if elapsedSinceRefresh < REFRESH_INTERVAL then return end
	elapsedSinceRefresh = 0
	if not GroupInCombat() then EndFight() end
	ns:RefreshMeter()
end

---------------------------------------------------------------------------
-- Layout / style
---------------------------------------------------------------------------

local function CreateRow()
	local row = ns.CreateBar(window)
	row.name = ns.CreateText(row, ns.fonts.normal, "LEFT")
	row.name:SetPoint("LEFT", 3, 0)
	row.value = ns.CreateText(row, ns.fonts.normal, "RIGHT")
	row.value:SetPoint("RIGHT", -3, 0)
	row.name:SetPoint("RIGHT", row.value, "LEFT", -4, 0)
	ns.StyleBar(row, KUIDB.meter.texture)
	return row
end

local function WindowHeight(numRows)
	return window.inset * 2 + TITLE_HEIGHT + numRows * (KUIDB.meter.rowHeight + ROW_GAP)
end

-- Rows under the title bar; they follow the window's width by anchoring
local function LayoutRows()
	local M = KUIDB.meter
	local inset = window.inset
	for i = 1, math.max(M.rows, #rows) do
		local row = rows[i]
		if i <= M.rows then
			row = row or CreateRow()
			rows[i] = row
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", window.titleBar, "BOTTOMLEFT", 0, -ROW_GAP - (i - 1) * (M.rowHeight + ROW_GAP))
			row:SetPoint("RIGHT", -inset, 0)
			row:SetHeight(M.rowHeight)
		else
			row:Hide()
		end
	end
	ns:RefreshMeter()
end

function ns:LayoutMeter()
	if not window then return end
	local M = KUIDB.meter
	local inset = ns:ApplyBackdrop(window, true)
	window.inset = inset
	window:SetSize(M.width, WindowHeight(M.rows))
	window:SetResizeBounds(MIN_WIDTH, WindowHeight(1), MAX_WIDTH, WindowHeight(MAX_ROWS))

	local p = M.point
	window:ClearAllPoints()
	window:SetPoint(p[1], UIParent, p[2], p[3], p[4])

	window.titleBar:ClearAllPoints()
	window.titleBar:SetPoint("TOPLEFT", inset, -inset)
	window.titleBar:SetPoint("TOPRIGHT", -inset, -inset)
	window.titleBar:SetHeight(TITLE_HEIGHT)

	LayoutRows()
end

function ns:StyleMeter()
	if not window then return end
	for _, row in ipairs(rows) do
		ns.StyleBar(row, KUIDB.meter.texture)
	end
	ns:RefreshMeter() -- texture swaps drop the class colors
end

---------------------------------------------------------------------------
-- Creation
---------------------------------------------------------------------------

local function TitleBar_OnClick(_, button)
	local M = KUIDB.meter
	if button == "LeftButton" then
		M.mode = M.mode == "damage" and "healing" or "damage"
	else
		M.segment = M.segment == "current" and "overall" or "current"
	end
	ns:RefreshMeter()
end

local function TitleBar_OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:AddLine("KUI meter")
	GameTooltip:AddLine("Left-click: damage / healing", 1, 1, 1)
	GameTooltip:AddLine("Right-click: current fight / overall", 1, 1, 1)
	GameTooltip:AddLine("Drag: move", 1, 1, 1)
	GameTooltip:Show()
end

local function SavePosition()
	local point, _, relPoint, x, y = window:GetPoint()
	KUIDB.meter.point = { point, relPoint, x, y }
end

local function OnDragStop()
	window:StopMovingOrSizing()
	SavePosition()
end

-- Rows are added or dropped live while dragging the grip
local function OnSizeChanged(self, width, height)
	if not self.sizing then return end
	local M = KUIDB.meter
	local rowsFit = math.floor((height - WindowHeight(0)) / (M.rowHeight + ROW_GAP) + 0.5)
	M.width = math.floor(width + 0.5)
	M.rows = math.max(1, math.min(MAX_ROWS, rowsFit))
	LayoutRows()
end

-- Sizing can re-anchor the window, so the position is saved too; the
-- relayout then snaps the height to the row count
local function CreateResizeGrip()
	local grip = CreateFrame("Button", nil, window)
	grip:SetSize(12, 12)
	grip:SetPoint("BOTTOMRIGHT", -1, 1)
	grip:SetFrameLevel(window:GetFrameLevel() + 10) -- above the rows
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function()
		window.sizing = true
		window:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		window:StopMovingOrSizing()
		window.sizing = nil
		SavePosition()
		ns:LayoutMeter()
	end)
end

local function CreateWindow()
	window = CreateFrame("Frame", "KUI_Meter", UIParent, "BackdropTemplate")
	window:SetMovable(true)
	window:SetResizable(true)
	window:SetClampedToScreen(true)
	window:SetScript("OnSizeChanged", OnSizeChanged)
	CreateResizeGrip()

	local titleBar = CreateFrame("Button", nil, window)
	titleBar:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	titleBar:RegisterForDrag("LeftButton")
	titleBar:SetScript("OnClick", TitleBar_OnClick)
	titleBar:SetScript("OnDragStart", function() window:StartMoving() end)
	titleBar:SetScript("OnDragStop", OnDragStop)
	titleBar:SetScript("OnEnter", TitleBar_OnEnter)
	titleBar:SetScript("OnLeave", GameTooltip_Hide)
	window.titleBar = titleBar

	local reset = CreateFrame("Button", nil, titleBar)
	reset:SetPoint("RIGHT", -2, 0)
	reset:SetSize(32, TITLE_HEIGHT)
	reset.text = ns.CreateText(reset, ns.fonts.small, "RIGHT")
	reset.text:SetPoint("RIGHT")
	reset.text:SetText("Reset")
	reset.text:SetTextColor(0.7, 0.7, 0.7)
	reset:SetScript("OnClick", function() ns:ResetMeter() end)
	reset:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
	reset:SetScript("OnLeave", function(self) self.text:SetTextColor(0.7, 0.7, 0.7) end)

	window.title = ns.CreateText(titleBar, ns.fonts.normal, "LEFT")
	window.title:SetPoint("LEFT", 3, 0)
	window.title:SetPoint("RIGHT", reset, "LEFT", -4, 0)

	window:SetScript("OnUpdate", OnUpdate)
	window:SetScript("OnShow", function() ns:RefreshMeter() end)
	window:SetScript("OnEvent", function(_, event)
		if event == "COMBAT_LOG_EVENT_UNFILTERED" then
			OnCombatLog()
		else
			ScanPets()
		end
	end)
end

local EVENTS = { "COMBAT_LOG_EVENT_UNFILTERED", "GROUP_ROSTER_UPDATE", "UNIT_PET", "PLAYER_ENTERING_WORLD" }

-- Shows or hides the window; hidden, it records nothing
function ns:ApplyMeter()
	if not window then return end
	local enabled = KUIDB.meter.enabled
	-- Nothing would notice the fight ending while switched off
	if not enabled and fightStart then EndFight() end
	for _, event in ipairs(EVENTS) do
		if enabled then window:RegisterEvent(event) else window:UnregisterEvent(event) end
	end
	if enabled then ScanPets() end
	window:SetShown(enabled)
end

function ns:InitMeter()
	CreateWindow()
	ns:LayoutMeter()
	ns:ApplyMeter()
end
