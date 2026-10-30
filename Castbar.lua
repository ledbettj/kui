local addonName, ns = ...

-- Cast bar component: spell icon, progress bar with spark, spell name and
-- remaining time. Used as a row inside the player/target frames (empty when
-- idle) and in standalone holders under the focus frame and nameplates
-- (hidden when idle, via cb.container).
--
-- The owner positions the bar and calls LayoutCastbar/StyleCastbar; this
-- file handles the spellcast events. OnUpdate only runs while a cast is in
-- progress or a failure is being held on screen.

local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"
local PREVIEW_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local HOLD_TIME = 0.6 -- how long a failed/interrupted cast stays red

local function SetColor(cb, key)
	local c = ns:GetCastColor(key)
	cb.status:SetStatusBarColor(c[1], c[2], c[3])
end

local function SetSpark(cb, fraction)
	cb.spark:SetPoint("CENTER", cb.status, "LEFT", fraction * cb.status:GetWidth(), 0)
	cb.spark:Show()
end

local function ShowIcon(cb, texture)
	cb.icon:SetTexture(texture)
	cb.icon:SetShown(KUIDB.castbar.showIcon)
end

-- cb.container (optional): a frame shown only while there's something to
-- show; nameplates use it to hide the cast bar when idle
local function SetVisible(cb, visible)
	if cb.container then cb.container:SetShown(visible) end
end

local OnUpdate -- defined below; set as the script only while needed

local function Idle(cb)
	cb:SetScript("OnUpdate", nil)
	SetVisible(cb, false)
	cb.active, cb.holdUntil = false, nil
	cb.status:SetMinMaxValues(0, 1)
	cb.status:SetValue(0)
	cb.text:SetText("")
	cb.time:SetText("")
	cb.spark:Hide()
	cb.icon:Hide()
end

-- Many tradeskill spells carry the placeholder grinning-face icon; the
-- crafted item's icon is what the profession window shows. Name lookup only
-- resolves items the client has cached, which crafted items usually are.
local function TradeSkillIcon(name, fallback)
	local _, _, _, _, icon = GetItemInfoInstant(name)
	return icon or fallback
end

local function Start(cb, isChannel)
	local name, text, texture, startMs, endMs, isTradeSkill, castID
	if isChannel then
		name, text, texture, startMs, endMs, isTradeSkill = UnitChannelInfo(cb.unit)
	else
		name, text, texture, startMs, endMs, isTradeSkill, castID = UnitCastingInfo(cb.unit)
	end
	if not name then return end
	if isTradeSkill then texture = TradeSkillIcon(name, texture) end

	cb.channel = isChannel
	cb.castID = castID
	cb.startTime, cb.endTime = startMs / 1000, endMs / 1000
	cb.status:SetMinMaxValues(0, cb.endTime - cb.startTime)
	cb.text:SetText(text ~= "" and text or name)
	ShowIcon(cb, texture)
	SetColor(cb, isChannel and "channel" or "cast")
	cb.active, cb.holdUntil = true, nil
	SetVisible(cb, true)
	cb:SetScript("OnUpdate", OnUpdate)
end

local function Fail(cb, text)
	cb.active = false
	cb.holdUntil = GetTime() + HOLD_TIME
	local _, max = cb.status:GetMinMaxValues()
	cb.status:SetValue(max)
	SetColor(cb, "failed")
	cb.text:SetText(text)
	cb.time:SetText("")
	cb.spark:Hide()
	SetVisible(cb, true)
	cb:SetScript("OnUpdate", OnUpdate)
end

function OnUpdate(cb)
	local now = GetTime()
	if cb.active then
		if now >= cb.endTime then
			-- Normally STOP/CHANNEL_STOP gets here first; this is a safety net
			return Idle(cb)
		end
		local duration = cb.endTime - cb.startTime
		local value = cb.channel and (cb.endTime - now) or (now - cb.startTime)
		cb.status:SetValue(value)
		cb.time:SetFormattedText("%.1f", cb.endTime - now)
		SetSpark(cb, value / duration)
	elseif cb.holdUntil and now >= cb.holdUntil then
		Idle(cb)
	end
end

local function OnEvent(cb, event, _, castID)
	if cb.preview then return end

	if event == "UNIT_SPELLCAST_START" then
		Start(cb, false)
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
		Start(cb, true)
	elseif event == "UNIT_SPELLCAST_DELAYED" then
		if cb.active and not cb.channel then Start(cb, false) end
	elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
		if cb.active and cb.channel then Start(cb, true) end
	elseif event == "UNIT_SPELLCAST_STOP" then
		if cb.active and not cb.channel and castID == cb.castID then Idle(cb) end
	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		if cb.active and cb.channel then Idle(cb) end
	elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
		-- castID check: pressing a spell on cooldown fires FAILED for a cast
		-- that never started
		if castID and castID == cb.castID then
			Fail(cb, event == "UNIT_SPELLCAST_FAILED" and FAILED or INTERRUPTED)
		end
	end
end

---------------------------------------------------------------------------
-- Driven by the owning unit frame
---------------------------------------------------------------------------

-- Re-sync with whatever the unit is doing now (unit frame changed target,
-- came back from preview, etc).
function ns:RefreshCastbar(cb)
	cb.preview = false
	if UnitCastingInfo(cb.unit) then
		Start(cb, false)
	elseif UnitChannelInfo(cb.unit) then
		Start(cb, true)
	else
		Idle(cb)
	end
end

-- Static sample cast for the config preview; ignores events until the
-- next RefreshCastbar
function ns:PreviewCastbar(cb)
	cb.preview = true
	cb:SetScript("OnUpdate", nil)
	cb.active, cb.holdUntil = false, nil
	cb.status:SetMinMaxValues(0, 1)
	cb.status:SetValue(0.6)
	cb.text:SetText("Casting")
	cb.time:SetText("1.2")
	ShowIcon(cb, PREVIEW_ICON)
	SetColor(cb, "cast")
	SetSpark(cb, 0.6)
	SetVisible(cb, true)
end

-- Arranges the icon and bar within the row; the row itself is positioned by
-- the unit frame's layout.
function ns:LayoutCastbar(cb)
	local h = cb:GetHeight()

	cb.icon:ClearAllPoints()
	cb.icon:SetPoint("TOPLEFT")
	cb.icon:SetSize(h, h)

	cb.status:ClearAllPoints()
	cb.status:SetPoint("TOPLEFT", KUIDB.castbar.showIcon and (h + 1) or 0, 0)
	cb.status:SetPoint("BOTTOMRIGHT")
	cb.spark:SetSize(12, h * 2.2)

	if cb.preview then
		ns:PreviewCastbar(cb)
	elseif not KUIDB.castbar.showIcon then
		cb.icon:Hide()
	end
end

local EVENTS = {
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
}

-- Point the cast bar at a different unit (nameplates are recycled); nil
-- detaches it
function ns:SetCastbarUnit(cb, unit)
	cb:UnregisterAllEvents()
	cb.unit = unit
	if not unit then return Idle(cb) end
	for _, event in ipairs(EVENTS) do
		cb:RegisterUnitEvent(event, unit)
	end
end

-- Detached cast bars (focus, nameplates) live in their own bordered holder
-- (cb.container) under the owner, shown only while casting
function ns:CreateDetachedCastbar(owner)
	local holder = CreateFrame("Frame", nil, owner, "BackdropTemplate")
	holder.unit = owner.unit
	local cb = ns:CreateCastbar(holder)
	cb.container = holder
	holder:Hide()
	return cb
end

-- Sizes a detached cast bar's holder and attaches it under anchor. The
-- holder is usually hidden when this runs, so the bar gets an explicit
-- height for LayoutCastbar to size the icon from.
function ns:LayoutDetachedCastbar(cb, anchor, height)
	local holder = cb.container
	holder:ClearAllPoints()
	holder:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	holder:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
	holder:SetHeight(height)
	local inset = ns:ApplyBackdrop(holder, true)
	cb:ClearAllPoints()
	cb:SetPoint("TOPLEFT", inset, -inset)
	cb:SetPoint("TOPRIGHT", -inset, -inset)
	cb:SetHeight(math.max(1, height - inset * 2))
	ns:LayoutCastbar(cb)
end

function ns:StyleCastbar(cb)
	ns.StyleBar(cb.status, KUIDB.castbar.texture, true)
	cb.bg:SetColorTexture(ns:GetEmptyColor())
end

-- f: the frame the bar belongs to; its unit (if any) is watched
function ns:CreateCastbar(f)
	local cb = CreateFrame("Frame", nil, f)
	cb.unit = f.unit

	cb.icon = cb:CreateTexture(nil, "ARTWORK")
	ns.CropIcon(cb.icon)

	-- Empty background spans the whole row, icon slot included, so an idle
	-- row reads as one even strip
	cb.bg = cb:CreateTexture(nil, "BACKGROUND")
	cb.bg:SetAllPoints()

	cb.status = CreateFrame("StatusBar", nil, cb)
	cb.status:SetStatusBarTexture(ns.FLAT_TEXTURE)

	cb.spark = cb.status:CreateTexture(nil, "OVERLAY")
	cb.spark:SetTexture(SPARK)
	cb.spark:SetBlendMode("ADD")

	cb.text = cb.status:CreateFontString(nil, "OVERLAY")
	cb.text:SetFontObject(ns.fonts.small)
	cb.text:SetPoint("LEFT", 3, 0)
	cb.text:SetJustifyH("LEFT")
	cb.text:SetWordWrap(false)

	cb.time = cb.status:CreateFontString(nil, "OVERLAY")
	cb.time:SetFontObject(ns.fonts.small)
	cb.time:SetPoint("RIGHT", -3, 0)
	cb.text:SetPoint("RIGHT", cb.time, "LEFT", -3, 0)

	ns:SetCastbarUnit(cb, cb.unit)
	cb:SetScript("OnEvent", OnEvent)

	Idle(cb)
	return cb
end
