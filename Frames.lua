local addonName, ns = ...

-- The unit frames: secure click targets (Clique-compatible) with a portrait,
-- health/power bars, name and value text, plus the optional pieces from
-- Auras, Indicators, HealPrediction and Castbar. Also their arrangement on
-- screen and the configuration preview.
--
-- Health is always a secret, and power, class and combo points
-- are in combat. Secrets go straight into the bars and font strings, which
-- accept them; text comes from Blizzard's formatters (AbbreviateLargeNumbers,
-- percentages through a curve) instead of KUI's own math.

---------------------------------------------------------------------------
-- Element updates
---------------------------------------------------------------------------

local ShortValue = ns.ShortValue
local IsSecret = ns.IsSecret

-- Compact number for a value that may be a secret
local function Short(v)
	if IsSecret(v) then return AbbreviateLargeNumbers(v) end
	return ShortValue(v)
end

local DEAD_COLOR = { 0.5, 0.5, 0.5 }
-- Near-white: the bar atlas darkens it to a neutral grey
local TAPPED_COLOR = { 0.9, 0.9, 0.9 }

-- Health color: grey when dead/offline, class color for players, grey when
-- tapped, otherwise by reaction (all configurable in the Colors section)
local function UnitColor(unit)
	if not UnitIsConnected(unit) or (UnitIsDead(unit) and not UnitIsPlayer(unit)) then
		return DEAD_COLOR
	elseif UnitIsPlayer(unit) then
		-- The class can be secret; then the reaction color stands in
		local _, class = UnitClass(unit)
		local c = class and not IsSecret(class) and ns:GetClassColor(class)
		if c then return c end
	elseif UnitIsTapDenied and UnitIsTapDenied(unit) then
		return TAPPED_COLOR
	end
	return ns:GetReactionColor(unit)
end
ns.UnitColor = UnitColor -- tooltips color by it too

-- self.small shows a percentage instead of current / max
function ns.UpdateHealth(self)
	local unit = self.unit
	local cur, max = UnitHealth(unit), UnitHealthMax(unit)
	if not IsSecret(max) and max == 0 then max = 1 end

	self.health:SetMinMaxValues(0, max)
	self.health:SetValue(cur)
	local c = UnitColor(unit)
	self.health:SetStatusBarColor(c[1], c[2], c[3])

	if not UnitIsConnected(unit) then
		self.healthText:SetText("Offline")
	elseif UnitIsGhost(unit) then
		self.healthText:SetText("Ghost")
	elseif UnitIsDead(unit) then
		self.healthText:SetText("Dead")
	elseif self.small then
		if IsSecret(cur) or IsSecret(max) then
			self.healthText:SetFormattedText("%d%%", UnitHealthPercent(unit, true, CurveConstants.ScaleTo100))
		else
			self.healthText:SetFormattedText("%d%%", cur / max * 100)
		end
	else
		self.healthText:SetFormattedText("%s / %s", Short(cur), Short(max))
	end

	ns.UpdateHealPrediction(self)
end

-- One step curve per pip, turning the combo point share (0-1 of
-- MAX_COMBO) into that pip's alpha, for when the count itself is secret
local MAX_COMBO = 5
local comboCurves

local function ComboCurves()
	if not comboCurves then
		comboCurves = {}
		for i = 1, MAX_COMBO do
			local curve = C_CurveUtil.CreateCurve()
			curve:SetType(Enum.LuaCurveType.Step)
			curve:AddPoint(0, 0)
			curve:AddPoint((i - 0.5) / MAX_COMBO, 1)
			comboCurves[i] = curve
		end
	end
	return comboCurves
end

local function UpdateCombo(self)
	local cp = GetComboPoints("player", "target")
	if IsSecret(cp) then
		local curves = ComboCurves()
		for i, pip in ipairs(self.combo) do
			pip:Show()
			pip:SetAlpha(UnitPowerPercent("player", Enum.PowerType.ComboPoints, false, curves[i]))
		end
		return
	end
	cp = cp or 0
	for i, pip in ipairs(self.combo) do
		pip:SetAlpha(1)
		pip:SetShown(i <= cp)
	end
end

-- Combo points ride along: they change with the player's power events
local function UpdatePower(self)
	if self.combo then UpdateCombo(self) end
	if not self.power then return end

	local unit = self.unit
	local cur, max = UnitPower(unit), UnitPowerMax(unit)
	local ptype, ptoken = UnitPowerType(unit)
	local c = ns:GetPowerColor(ptoken, ptype)

	self.power:SetMinMaxValues(0, (IsSecret(max) or max > 0) and max or 1)
	self.power:SetValue(cur)
	self.power:SetStatusBarColor(c[1], c[2], c[3])

	if self.powerText then
		self.powerText:SetFormattedText("%s / %s", Short(cur), Short(max))
	end
end

-- Difficulty-colored level and classification before the name. Compact
-- frames skip the level unless they opt in with self.showLevel.
function ns.UpdateName(self)
	local unit = self.unit
	local name, surname = UnitName(unit)
	if not IsSecret(name) then name = name or "" end
	-- The second value is a surname. Either may be a secret, which formatting
	-- accepts but concatenating doesn't.
	local separator = ""
	if not IsSecret(surname) and (surname == nil or surname == "") then
		surname = ""
	else
		separator = Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR
	end

	local levelText = ""
	local level = UnitLevel(unit)
	if unit ~= "player" and (self.showLevel or not self.small) and not IsSecret(level) then
		local c = GetQuestDifficultyColor and GetQuestDifficultyColor(level > 0 and level or 99)
		local hex = c and format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) or "|cffffffff"
		local classification = UnitClassification(unit)
		local suffix = (classification == "elite" or classification == "worldboss") and "+"
			or (classification == "rare" or classification == "rareelite") and "r"
			or ""
		levelText = format("%s%s%s|r ", hex, level > 0 and level or "??", suffix)
	end

	self.nameText:SetFormattedText("%s%s%s%s", levelText, name, separator, surname)
end

-- 3D model of the unit; cleared while it's out of visual range, where the
-- model can't load
function ns.UpdatePortrait(self)
	local portrait = self.portrait
	if not portrait then return end

	local unit = self.unit
	-- Remembered so the party range check can tell when it changes
	self.portraitVisible = UnitIsVisible(unit)
	if self.portraitVisible and UnitIsConnected(unit) then
		portrait:SetUnit(unit)
		portrait:SetPortraitZoom(1)
	else
		-- Out of visual range the model can't load; leave the dark backdrop
		portrait:ClearModel()
	end
end
local UpdatePortrait = ns.UpdatePortrait

-- Stand-in contents for a unit that doesn't exist (preview mode only)
local function ShowPlaceholder(self)
	if self.portrait then self.portrait:ClearModel() end
	ns.UpdateRaidIcon(self)
	ns.UpdateAggro(self)
	ns.UpdateStatusIcons(self)
	ns.HideAuras(self)
	ns.UpdateHealPrediction(self)
	if self.castbar then ns:PreviewCastbar(self.castbar) end
	self.nameText:SetText(self.label)
	self.healthText:SetText("")
	self.health:SetMinMaxValues(0, 1)
	self.health:SetValue(1)
	self.health:SetStatusBarColor(0.3, 0.3, 0.3)
	if self.power then
		self.power:SetMinMaxValues(0, 1)
		self.power:SetValue(0)
	end
	if self.powerText then self.powerText:SetText("") end
end

-- Refreshes every element. A unit that doesn't exist gets placeholder
-- contents, which only show in preview (otherwise the frame is hidden).
function ns.UpdateAll(self)
	if not UnitExists(self.unit) then
		return ShowPlaceholder(self)
	end

	ns.UpdateHealth(self)
	UpdatePower(self)
	ns.UpdateName(self)
	UpdatePortrait(self)
	ns.UpdateRaidIcon(self)
	ns.UpdateStatusIcons(self)
	ns.UpdateAggro(self)
	ns.UpdateAuras(self)
	if self.castbar then ns:RefreshCastbar(self.castbar) end
end
local UpdateAll = ns.UpdateAll

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

-- Unit events, registered for the frame's own unit
local unitEventHandlers = {
	UNIT_HEALTH = ns.UpdateHealth,
	UNIT_MAXHEALTH = ns.UpdateHealth,
	UNIT_CONNECTION = ns.UpdateHealth,
	UNIT_HEAL_PREDICTION = ns.UpdateHealPrediction,
	-- Faction changes also cover PvP flagging
	UNIT_FACTION = function(self)
		ns.UpdateHealth(self)
		ns.UpdateStatusIcons(self)
	end,
	UNIT_POWER_FREQUENT = UpdatePower,
	UNIT_MAXPOWER = UpdatePower,
	UNIT_DISPLAYPOWER = UpdatePower,
	UNIT_NAME_UPDATE = ns.UpdateName,
	UNIT_LEVEL = ns.UpdateName,
	UNIT_MODEL_CHANGED = UpdatePortrait,
	UNIT_PORTRAIT_UPDATE = UpdatePortrait,
	UNIT_AURA = ns.UpdateAuras,
	UNIT_THREAT_SITUATION_UPDATE = ns.UpdateAggro, -- cfg.threat frames only
}

-- Events meaning the frame's unit is now a different entity
local unitChangedEvents = {
	target = { "PLAYER_TARGET_CHANGED", "COMBO_TARGET_CHANGED" },
	focus = { "PLAYER_FOCUS_CHANGED" },
}

local function OnEvent(self, event)
	if event == "RAID_TARGET_UPDATE" then
		return ns.UpdateRaidIcon(self)
	elseif event == "GROUP_ROSTER_UPDATE" and self.cfg.party then
		-- partyN may now be a different player entirely
		return UpdateAll(self)
	elseif ns.STATUS_EVENTS[event] then
		return ns.UpdateStatusIcons(self)
	end
	local handler = unitEventHandlers[event]
	if handler then
		handler(self)
	else
		-- unitChangedEvents and UNIT_PET
		UpdateAll(self)
	end
end

local POLL_INTERVAL = 0.2

-- Target-of-target gets no reliable events, so poll it while shown
local function OnUpdatePoll(self, elapsed)
	self.elapsed = (self.elapsed or 0) + elapsed
	if self.elapsed > POLL_INTERVAL then
		self.elapsed = 0
		UpdateAll(self)
	end
end

-- Some events may not exist on every client build; don't let one bad
-- registration take the whole addon down
local function SafeRegister(f, event, ...)
	if ... then
		pcall(f.RegisterUnitEvent, f, event, ...)
	else
		pcall(f.RegisterEvent, f, event)
	end
end

local function RegisterEvents(f, unit, cfg)
	for event in pairs(unitEventHandlers) do
		if cfg.combo and event == "UNIT_POWER_FREQUENT" then
			-- Combo points are the player's power
			SafeRegister(f, event, unit, "player")
		elseif cfg.threat or event ~= "UNIT_THREAT_SITUATION_UPDATE" then
			-- (only frames with an aggro border want threat updates)
			SafeRegister(f, event, unit)
		end
	end
	for _, event in ipairs(unitChangedEvents[unit] or {}) do
		SafeRegister(f, event)
	end
	if cfg.owner then
		SafeRegister(f, "UNIT_PET", cfg.owner)
	end
	if cfg.party then
		-- partyN / partypetN can point at a different unit after roster changes
		SafeRegister(f, "GROUP_ROSTER_UPDATE")
	end
	SafeRegister(f, "RAID_TARGET_UPDATE")

	f:SetScript("OnEvent", OnEvent)
	f:SetScript("OnShow", UpdateAll)
	if cfg.poll then
		f:SetScript("OnUpdate", OnUpdatePoll)
	elseif cfg.party then
		f:SetScript("OnUpdate", ns.OnUpdateRange)
	end
end

---------------------------------------------------------------------------
-- Style / layout
---------------------------------------------------------------------------

function ns:StyleFrame(f)
	ns.StyleBar(f.health, ns.db.style.healthTexture)
	ns.StyleHealPrediction(f)
	if f.power then
		ns.StyleBar(f.power, ns.db.style.powerTexture, true)
		f.power.bg:SetColorTexture(ns:GetEmptyColor())
	end
	if f.castbar then
		ns:StyleCastbar(f.castbar)
	end
	-- Swapping textures drops vertex colors, so recolor
	UpdateAll(f)
end

local function ScaledHeight(height)
	return math.floor(height * ns.db.style.frameHeightScale + 0.5)
end

local function PowerHeight(cfg)
	if cfg.powerFromSettings then
		return ns.db.style.powerHeight
	elseif cfg.power then
		return ScaledHeight(cfg.powerHeight or math.floor(cfg.h * 0.25))
	end
	return 0
end

-- Border, background and everything inside it. The border's inset decides
-- where the portrait and bars sit, so they're anchored here too.
local function LayoutContents(f)
	local cfg = f.cfg
	local inset = ns:ApplyBackdrop(f, f.small)
	local gap = 1
	local left = inset

	-- 3D portrait, square, filling the inner height on the left
	if f.portrait then
		local size = ScaledHeight(cfg.h) - inset * 2
		f.portrait:ClearAllPoints()
		f.portrait:SetPoint("TOPLEFT", inset, -inset)
		f.portrait:SetSize(size, size)
		left = inset + size + gap
	end

	-- Stacked bottom-up beside the portrait: cast bar, power, then health
	-- takes whatever height is left
	local bottom = inset
	local function Row(region, height)
		region:ClearAllPoints()
		region:SetPoint("BOTTOMLEFT", left, bottom)
		region:SetPoint("BOTTOMRIGHT", -inset, bottom)
		region:SetHeight(height)
		bottom = bottom + height + gap
	end

	if f.castbar and not f.castbar.container then
		Row(f.castbar, ns.db.castbar.height)
		ns:LayoutCastbar(f.castbar)
	end
	if f.power then
		Row(f.power, PowerHeight(cfg))
	end

	f.health:ClearAllPoints()
	f.health:SetPoint("TOPLEFT", left, -inset)
	f.health:SetPoint("TOPRIGHT", -inset, -inset)
	f.health:SetPoint("BOTTOM", 0, bottom)

	if f.castbar and f.castbar.container then
		ns:LayoutDetachedCastbar(f.castbar, f, ns.db.castbar.focusHeight)
	end
end

-- Resizes a secure frame; ns:ApplyLayout handles combat deferral
function ns:LayoutFrame(f)
	local w = ns:GetWidth(f.unit)
	f:SetSize(w, ScaledHeight(f.cfg.h))
	LayoutContents(f)
	-- Segment widths are in pixels of the health bar
	ns.UpdateHealPrediction(f)
	ns.UpdateAggro(f) -- the backdrop was just reset
	if f.auras then
		ns.SizeAuras(f.auras, w)
		ns.UpdateAuras(f)
	end
end

---------------------------------------------------------------------------
-- Creation
---------------------------------------------------------------------------

local function CreateCastbar(f, cfg)
	if cfg.castbar then
		f.castbar = ns:CreateCastbar(f)
	elseif cfg.detachedCastbar then
		f.castbar = ns:CreateDetachedCastbar(f)
	end
end

local AURA_GAP = 3 -- between a frame and auras below it

local function CreateAuras(f, cfg)
	if not cfg.auras then return end
	local auras = ns.CreateAuras(f, cfg.auras)
	if auras.layout.growUp then
		auras:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 4)
	else
		auras:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -AURA_GAP)
	end
end

local function CreateTexts(f)
	f.nameText = ns.CreateText(f.health, f.small and ns.fonts.nameSmall or ns.fonts.name, "LEFT")
	f.nameText:SetPoint("LEFT", ns.NAME_INSET, 0)
	f.healthText = ns.CreateText(f.health, f.small and ns.fonts.barSmall or ns.fonts.bar, "RIGHT")
	f.healthText:SetPoint("RIGHT", -4, 0)
	f.nameText:SetPoint("RIGHT", f.healthText, "LEFT", -4, 0)

	-- Player power numbers, right-aligned under the health numbers
	if f.unit == "player" and f.power then
		f.powerText = ns.CreateText(f.power, ns.fonts.barSmall, "RIGHT")
		f.powerText:SetPoint("RIGHT", -4, 0)
	end
end

local function CreateComboPips(f)
	f.combo = {}
	for i = 1, 5 do
		local pip = f.overlay:CreateTexture(nil, "OVERLAY")
		pip:SetTexture(ns.FLAT_TEXTURE)
		pip:SetVertexColor(1, 0.8, 0.1)
		pip:SetSize(12, 4)
		pip:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 4 + (i - 1) * 14, -1)
		pip:Hide()
		f.combo[i] = pip
	end
end

-- Builds the secure frame for unit from its ns.units entry. Secure frames
-- can only be created out of combat, so this runs at ADDON_LOADED.
function ns:CreateUnitFrame(unit, cfg)
	local f = CreateFrame("Button", "KUI_" .. unit, UIParent, "SecureUnitButtonTemplate,BackdropTemplate")
	f.unit = unit
	f.cfg = cfg
	f.label = cfg.label
	f.small = cfg.h < 30 -- by frame type: scaling its height doesn't change this
	f:SetHeight(ScaledHeight(cfg.h))

	-- Secure click handling: left = target, right = unit menu
	f:SetAttribute("unit", unit)
	f:SetAttribute("*type1", "target")
	f:SetAttribute("*type2", "togglemenu")
	f:RegisterForClicks("AnyUp")
	f:SetScript("OnEnter", UnitFrame_OnEnter)
	f:SetScript("OnLeave", UnitFrame_OnLeave)

	-- Portrait and bars; positioned by LayoutContents
	if cfg.portrait then
		f.portrait = CreateFrame("PlayerModel", nil, f)
	end
	f.health = ns.CreateBar(f)
	ns.CreateHealPrediction(f)
	if cfg.power then
		f.power = ns.CreateBar(f)
	end
	CreateCastbar(f, cfg)
	CreateAuras(f, cfg)

	-- Child frame above the bars for icons and pips; textures on f itself
	-- would render underneath the bars
	f.overlay = CreateFrame("Frame", nil, f)
	f.overlay:SetAllPoints()
	f.overlay:SetFrameLevel(f:GetFrameLevel() + 5)

	CreateTexts(f)
	ns.CreateRaidIcon(f)
	if cfg.status then ns.CreateStatusIcons(f, f.overlay, cfg.status) end
	if cfg.combo then CreateComboPips(f) end

	RegisterEvents(f, unit, cfg)

	ns:LayoutFrame(f)
	ns:StyleFrame(f)
	ns:WatchFrame(f)

	-- Click-cast support (Clique et al). Must come after OnEnter/OnLeave are
	-- set, since Clique hooks those rather than replacing them.
	ClickCastFrames = ClickCastFrames or {}
	ClickCastFrames[f] = true

	return f
end

---------------------------------------------------------------------------
-- Arrangement
---------------------------------------------------------------------------

-- Width setting, following widthFrom so linked units always match
function ns:GetWidth(unit)
	local key = ns.units[unit].widthFrom or unit
	return ns.db.widths[key] or ns.units[key].w
end

--   [focus] [player] - - | - - [target] [tot]
-- pet under the player; party column at the top left, each member with its
-- pet to the right and its auras underneath
function ns:ApplyPositions()
	local L, F = ns.db.layout, ns.frames
	for _, f in pairs(F) do
		f:ClearAllPoints()
	end

	F.player:SetPoint("RIGHT", UIParent, "CENTER", -L.centerGap, L.y)
	F.target:SetPoint("LEFT", UIParent, "CENTER", L.centerGap, L.y)
	F.focus:SetPoint("RIGHT", F.player, "LEFT", -L.sideGap, 0)
	F.targettarget:SetPoint("LEFT", F.target, "RIGHT", L.sideGap, 0)
	F.pet:SetPoint("TOPLEFT", F.player, "BOTTOMLEFT", 0, -4)

	-- Room for a full set of auras stays reserved under each member, since
	-- the secure frames can't move in combat as auras come and go
	local auraSpace = AURA_GAP + ns.AurasMaxHeight(F.party1.auras)
	F.party1:SetPoint("TOPLEFT", UIParent, "TOPLEFT", L.partyX, L.partyY)
	for i = 1, 4 do
		local member, pet = F["party" .. i], F["partypet" .. i]
		if i > 1 then
			member:SetPoint("TOPLEFT", F["party" .. (i - 1)], "BOTTOMLEFT", 0, -(auraSpace + L.partySpacing))
		end
		pet:SetPoint("TOPLEFT", member, "TOPRIGHT", 4, 0)
	end
end

-- Secure visibility. Party frames hide in raids (Grid handles those);
-- everything else just follows unit existence.
function ns:WatchFrame(f)
	if f.cfg.party then
		RegisterStateDriver(f, "visibility", "[group:raid] hide; [@" .. f.unit .. ",exists] show; hide")
	else
		RegisterUnitWatch(f)
	end
end

local function UnwatchFrame(f)
	if f.cfg.party then
		UnregisterStateDriver(f, "visibility")
	else
		UnregisterUnitWatch(f)
	end
end

-- Preview shows every frame, even for units that don't exist, so the
-- layout can be judged while configuring
function ns:SetPreview(on)
	if not ns.supported.unitframes or on == ns.preview then return end
	if InCombatLockdown() then
		-- Secure frames can't be shown/hidden manually in combat
		return ns.Print("can't toggle preview in combat.")
	end
	ns.preview = on
	for _, f in pairs(ns.frames) do
		if on then
			UnwatchFrame(f)
			f:Show()
		else
			ns:WatchFrame(f)
		end
		UpdateAll(f)
	end
end
