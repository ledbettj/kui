local addonName, ns = ...

-- A small damage/healing meter for the group: one window with a bar per
-- player, for the current (or last) fight or everything since the last
-- reset. Pets and summons count as their owner. Healing is what actually
-- landed plus damage absorbed by shields; overhealing is its own view. The
-- current fight is named after the enemy the group hit hardest. Entering a
-- different instance than last time can reset everything.
--
-- Title bar: left-click cycles damage/healing/overhealing, right-click current/
-- overall, drag to move. Clicking a player's bar breaks their total down
-- by spell (their pets' spells listed separately); right-clicking goes
-- back. The corner grip resizes, snapping the height to whole rows.

local MODES = { "damage", "healing", "overhealing" }
local MODE_LABELS = { damage = "Damage", healing = "Healing", overhealing = "Overhealing" }
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

-- spell id -> combat log school mask, for coloring the breakdown
local spellSchools = { [0] = 1 } -- melee is physical

-- actors: owner GUID -> { guid, name, class, damage, healing, overhealing, spells }
--   spells: mode -> caster -> spell id -> amount, the caster
--   being "" for the player and the name of a pet or summon. Melee swings
--   are spell id 0.
-- enemies (current fight only): name -> { damage, count }, with
--   enemyGUIDs telling which enemies were already counted
local function NewSegment()
	return { actors = {}, duration = 0, enemies = {}, enemyGUIDs = {} }
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
	-- Guards against event layouts other than the ones parsed below
	if not guid or type(flags) ~= "number" then return end
	if bit.band(flags, GROUP_MASK) == 0 then return end
	if bit.band(flags, CLO.TypePlayer) ~= 0 then return guid end
	return petOwners[guid]
end

local function Actor(seg, guid)
	local a = seg.actors[guid]
	if not a then
		a = {
			guid = guid, damage = 0, healing = 0, overhealing = 0,
			spells = { damage = {}, healing = {}, overhealing = {} },
		}
		seg.actors[guid] = a
	end
	return a
end

-- Credits amount to owner, from spellID (of school) cast by srcGUID (the
-- owner or their pet). Returns whether it counted.
local function Add(owner, key, amount, srcGUID, srcName, spellID, school)
	if not amount or amount <= 0 then return false end
	if school then spellSchools[spellID] = school end
	-- Events outside combat (topping people off afterwards) would otherwise
	-- start a new fight and replace the last one
	if not fightStart then
		if not GroupInCombat() then return false end
		segments.current = NewSegment()
		fightStart = GetTime()
	end
	local caster = srcGUID == owner and "" or (srcName or "?")
	for _, seg in pairs(segments) do
		local a = Actor(seg, owner)
		a[key] = a[key] + amount
		local byCaster = a.spells[key]
		local spells = byCaster[caster]
		if not spells then
			spells = {}
			byCaster[caster] = spells
		end
		spells[spellID] = (spells[spellID] or 0) + amount
	end
	return true
end

-- Damage the group dealt to an enemy, for naming the current fight
local function AddEnemy(guid, name, amount)
	local seg = segments.current
	local e = seg.enemies[name or "?"]
	if not e then
		e = { damage = 0, count = 0 }
		seg.enemies[name or "?"] = e
	end
	if not seg.enemyGUIDs[guid] then
		seg.enemyGUIDs[guid] = true
		e.count = e.count + 1
	end
	e.damage = e.damage + amount
end

local function EndFight()
	local elapsed = GetTime() - fightStart
	for _, seg in pairs(segments) do
		seg.duration = seg.duration + elapsed
	end
	fightStart = nil
end

local function OnCombatLog()
	local _, event, _, srcGUID, srcName, srcFlags, _, dstGUID, dstName, dstFlags, _,
		a12, a13, a14, a15, a16, a17, a18, a19, _, a21, a22 = GetEventInfo()

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
		if not owner then return end
		-- Swings have no spell; everything else starts with its id and school
		local amount, spellID, school = a15, a12, a14
		if arg == 12 then amount, spellID, school = a12, 0, nil end
		if Add(owner, "damage", amount, srcGUID, srcName, spellID, school) then
			AddEnemy(dstGUID, dstName, amount)
		end
	elseif HEAL_EVENTS[event] then
		local owner = Owner(srcGUID, srcFlags)
		if owner then
			local over = a16 or 0
			Add(owner, "healing", a15 - over, srcGUID, srcName, a12, a14)
			Add(owner, "overhealing", over, srcGUID, srcName, a12, a14)
		end
	elseif event == "SPELL_ABSORBED" then
		-- The shield's caster and spell come after the attacking spell's id,
		-- name and school when the absorbed hit was a spell, first for a
		-- melee swing
		if type(a12) == "number" then
			local owner = Owner(a15, a17)
			if owner then Add(owner, "healing", a22, a15, a16, a19, a21) end
		else
			local owner = Owner(a12, a14)
			if owner then Add(owner, "healing", a19, a12, a13, a16, a18) end
		end
	end
end

local viewGUID -- the player whose breakdown is shown, nil for the list

function ns:ResetMeter()
	segments.current, segments.overall = NewSegment(), NewSegment()
	fightStart = nil
	viewGUID = nil
	ns:RefreshMeter()
end

StaticPopupDialogs.KUI_RESET_METER = {
	text = "Reset the damage meter?",
	button1 = YES,
	button2 = NO,
	OnAccept = function() ns:ResetMeter() end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

function ns:ConfirmResetMeter()
	StaticPopup_Show("KUI_RESET_METER")
end

-- Instance map last entered; going back into the same one (running back
-- after a wipe) keeps the data
local lastInstance

local function OnEnteringWorld()
	ScanPets()
	if not IsInInstance() then return end
	local instance = select(8, GetInstanceInfo())
	if instance ~= lastInstance and ns.db.meter.autoReset then ns:ResetMeter() end
	lastInstance = instance
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------

local ShortValue = ns.ShortValue

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

local function ClassColor(a)
	return (a.class and ns:GetClassColor(a.class)) or UNKNOWN_COLOR
end

local AUTO_ATTACK = 6603 -- for the melee icon

local function SpellName(id)
	if id == 0 then return "Melee" end
	return C_Spell.GetSpellName(id) or ("Spell " .. id)
end

local function SpellIcon(id)
	return C_Spell.GetSpellTexture(id == 0 and AUTO_ATTACK or id)
end

-- The enemy the group did the most damage to in seg, with how many others
-- there were
local function MainEnemy(seg)
	local name, damage, total = nil, 0, 0
	for n, e in pairs(seg.enemies) do
		total = total + e.count
		if e.damage > damage then name, damage = n, e.damage end
	end
	return name, name and total - 1 or 0
end

-- "Current" fights are named after their main enemy
local function SegmentLabel(segment)
	if segment == "current" then
		local name, others = MainEnemy(segments.current)
		if name then
			return others > 0 and format("%s +%d", name, others) or name
		end
	end
	return SEGMENT_LABELS[segment]
end

-- Reused every refresh, with a static comparator reading sortKey
local sorted, sortKey = {}, nil
local function ByValue(x, y)
	return x[sortKey] > y[sortKey]
end

-- One player's spells (and their pets', labelled with the pet), reusing
-- entry tables between refreshes
local entries = {}
local function CollectSpells(a, key)
	wipe(sorted)
	local n = 0
	for caster, spells in pairs(a.spells[key]) do
		for id, amount in pairs(spells) do
			n = n + 1
			local e = entries[n] or {}
			entries[n] = e
			e.id, e.caster, e.amount = id, caster, amount
			sorted[n] = e
		end
	end
	sortKey = "amount"
	table.sort(sorted, ByValue)
end

-- icon: shown at the bar's left end with the name after it; nil for none
-- Share of a heal that was wasted, as a whole percent
local function OverhealPercent(over, effective)
	local total = over + (effective or 0)
	return total > 0 and math.floor(over / total * 100 + 0.5) or 0
end

local function ShowRow(row, value, top, c, name, valueText, icon)
	row.icon:SetTexture(icon)
	row.icon:SetShown(icon ~= nil)
	row.name:SetPoint("LEFT", icon and ns.db.meter.rowHeight + 3 or 3, 0)
	row:SetMinMaxValues(0, top)
	row:SetValue(value)
	row:SetStatusBarColor(c[1], c[2], c[3])
	row.name:SetText(name)
	row.value:SetText(valueText)
	row:Show()
end

-- The players in the group, highest first
local function RefreshList(seg, key, numRows)
	window.title:SetFormattedText("%s - %s", MODE_LABELS[key], SegmentLabel(ns.db.meter.segment))

	wipe(sorted)
	for _, a in pairs(seg.actors) do
		if a[key] > 0 then sorted[#sorted + 1] = a end
	end
	sortKey = key
	table.sort(sorted, ByValue)

	local top = sorted[1] and sorted[1][key] or 1
	local seconds = math.max(1, Duration(seg))
	for i = 1, numRows do
		local row, a = rows[i], sorted[i]
		row.actor = a
		if a then
			Identify(a)
			-- Overhealing shows how much of each player's healing it was
			local detail = key == "overhealing"
				and format("%d%%", OverhealPercent(a.overhealing, a.healing))
				or ShortValue(a[key] / seconds)
			ShowRow(row, a[key], top, ClassColor(a), format("%d. %s", i, a.name or "?"),
				format("%s (%s)", ShortValue(a[key]), detail))
		else
			row:Hide()
		end
	end
end

-- The viewed player's total split by spell, highest first
local function RefreshBreakdown(seg, key, numRows)
	local a = seg.actors[viewGUID]
	local total = a and a[key] or 0
	if a then
		Identify(a)
		CollectSpells(a, key)
	else
		wipe(sorted) -- not in this segment
	end
	window.title:SetFormattedText("< %s - %s", (a and a.name) or "?", MODE_LABELS[key])

	local top = sorted[1] and sorted[1].amount or 1
	for i = 1, numRows do
		local row, e = rows[i], sorted[i]
		row.actor = nil
		if e then
			local name = SpellName(e.id)
			if e.caster ~= "" then name = format("%s (%s)", name, e.caster) end
			-- Share of the player's total, or for overhealing, how much of
			-- that spell's healing was wasted
			local percent
			if key == "overhealing" then
				local healed = a.spells.healing[e.caster]
				percent = OverhealPercent(e.amount, healed and healed[e.id])
			else
				percent = e.amount / total * 100 + 0.5
			end
			ShowRow(row, e.amount, top, ns:GetSchoolColor(spellSchools[e.id]), format("%d. %s", i, name),
				format("%s (%d%%)", ShortValue(e.amount), percent), SpellIcon(e.id))
		else
			row:Hide()
		end
	end
end

-- Redraws the title and rows from the data; does nothing while hidden
function ns:RefreshMeter()
	if not window or not window:IsShown() then return end
	local M = ns.db.meter
	local seg = segments[M.segment]
	window.timer:SetText(FormatTime(Duration(seg)))
	if viewGUID then
		RefreshBreakdown(seg, M.mode, M.rows)
	else
		RefreshList(seg, M.mode, M.rows)
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

local function Row_OnMouseUp(self, button)
	if viewGUID then
		-- Any click in the breakdown goes back to the list
		viewGUID = nil
	elseif button == "LeftButton" and self.actor then
		viewGUID = self.actor.guid
	else
		return
	end
	GameTooltip_Hide()
	ns:RefreshMeter()
end

local function Row_OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	if viewGUID then
		GameTooltip:AddLine("Click: back to everyone", 1, 1, 1)
	elseif self.actor then
		GameTooltip:AddLine("Click: breakdown by spell", 1, 1, 1)
	end
	GameTooltip:Show()
end

local function CreateRow()
	local row = ns.CreateBar(window)
	row:EnableMouse(true)
	row:SetScript("OnMouseUp", Row_OnMouseUp)
	row:SetScript("OnEnter", Row_OnEnter)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row.icon = row:CreateTexture(nil, "ARTWORK", nil, 1) -- above the fill
	row.icon:SetPoint("LEFT")
	ns.CropIcon(row.icon)
	row.icon:Hide()
	row.name = ns.CreateText(row, ns.fonts.normal, "LEFT")
	row.name:SetPoint("LEFT", 3, 0)
	row.value = ns.CreateText(row, ns.fonts.normal, "RIGHT")
	row.value:SetPoint("RIGHT", -3, 0)
	row.name:SetPoint("RIGHT", row.value, "LEFT", -4, 0)
	ns.StyleBar(row, ns.db.meter.texture)
	return row
end

local function WindowHeight(numRows)
	return window.inset * 2 + TITLE_HEIGHT + numRows * (ns.db.meter.rowHeight + ROW_GAP)
end

-- Rows under the title bar; they follow the window's width by anchoring
local function LayoutRows()
	local M = ns.db.meter
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
			row.icon:SetSize(M.rowHeight, M.rowHeight)
		else
			row:Hide()
		end
	end
	ns:RefreshMeter()
end

function ns:LayoutMeter()
	if not window then return end
	local M = ns.db.meter
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
		ns.StyleBar(row, ns.db.meter.texture)
	end
	ns:RefreshMeter() -- texture swaps drop the class colors
end

---------------------------------------------------------------------------
-- Creation
---------------------------------------------------------------------------

local function TitleBar_OnClick(_, button)
	local M = ns.db.meter
	if button == "LeftButton" then
		M.mode = MODES[(tIndexOf(MODES, M.mode) or 0) % #MODES + 1]
	elseif viewGUID then
		viewGUID = nil
	else
		M.segment = M.segment == "current" and "overall" or "current"
	end
	ns:RefreshMeter()
end

-- Enemies sorted by damage taken, for the title tooltip
local enemyNames = {}
local function ByEnemyDamage(x, y)
	local enemies = segments.current.enemies
	return enemies[x].damage > enemies[y].damage
end

local function AddEnemyLines()
	local enemies = segments.current.enemies
	wipe(enemyNames)
	for name in pairs(enemies) do enemyNames[#enemyNames + 1] = name end
	if #enemyNames == 0 then return end
	table.sort(enemyNames, ByEnemyDamage)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Enemies this fight")
	for _, name in ipairs(enemyNames) do
		local e = enemies[name]
		local label = e.count > 1 and format("%s x%d", name, e.count) or name
		GameTooltip:AddDoubleLine(label, ShortValue(e.damage), 1, 1, 1, 1, 1, 1)
	end
end

local function TitleBar_OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:AddLine("KUI meter")
	GameTooltip:AddLine("Left-click: damage / healing / overhealing", 1, 1, 1)
	if viewGUID then
		GameTooltip:AddLine("Right-click: back to everyone", 1, 1, 1)
	else
		GameTooltip:AddLine("Right-click: current fight / overall", 1, 1, 1)
	end
	GameTooltip:AddLine("Drag: move", 1, 1, 1)
	AddEnemyLines()
	GameTooltip:Show()
end

local function SavePosition()
	local point, _, relPoint, x, y = window:GetPoint()
	ns.db.meter.point = { point, relPoint, x, y }
end

local function OnDragStop()
	window:StopMovingOrSizing()
	SavePosition()
end

-- Rows are added or dropped live while dragging the grip
local function OnSizeChanged(self, width, height)
	if not self.sizing then return end
	local M = ns.db.meter
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
	reset:SetScript("OnClick", function() ns:ConfirmResetMeter() end)
	reset:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
	reset:SetScript("OnLeave", function(self) self.text:SetTextColor(0.7, 0.7, 0.7) end)

	window.timer = ns.CreateText(titleBar, ns.fonts.normal, "RIGHT")
	window.timer:SetPoint("RIGHT", reset, "LEFT", -6, 0)
	window.timer:SetTextColor(0.67, 0.67, 0.67)

	-- Cut short with "..." before it runs into the timer
	window.title = ns.CreateText(titleBar, ns.fonts.normal, "LEFT")
	window.title:SetPoint("LEFT", 3, 0)
	window.title:SetPoint("RIGHT", window.timer, "LEFT", -4, 0)

	window:SetScript("OnUpdate", OnUpdate)
	window:SetScript("OnShow", function() ns:RefreshMeter() end)
	window:SetScript("OnEvent", function(_, event)
		if event == "COMBAT_LOG_EVENT_UNFILTERED" then
			OnCombatLog()
		elseif event == "PLAYER_ENTERING_WORLD" then
			OnEnteringWorld()
		else
			ScanPets()
		end
	end)
end

local EVENTS = { "COMBAT_LOG_EVENT_UNFILTERED", "GROUP_ROSTER_UPDATE", "UNIT_PET", "PLAYER_ENTERING_WORLD" }

-- Shows or hides the window; hidden, it records nothing
function ns:ApplyMeter()
	if not window then return end
	local enabled = ns.db.meter.enabled
	-- Nothing would notice the fight ending while switched off
	if not enabled and fightStart then EndFight() end
	for _, event in ipairs(EVENTS) do
		if enabled then window:RegisterEvent(event) else window:UnregisterEvent(event) end
	end
	if enabled then ScanPets() end
	window:SetShown(enabled)
end

-- Always built, so it can be switched on without a /reload
function ns:InitMeter()
	CreateWindow()
	ns:LayoutMeter()
	ns:ApplyMeter()
end
