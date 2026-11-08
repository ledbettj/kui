local addonName, ns = ...

-- Cosmetic restyle of Blizzard's action buttons: border, square icons,
-- fonts, range coloring, lower-rank marker. Layout (size, padding, rows) is
-- left to Edit Mode, which owns the positions of these protected buttons.

local BUTTON_SETS = {
	{ "ActionButton", 12 },
	{ "MultiBarBottomLeftButton", 12 },
	{ "MultiBarBottomRightButton", 12 },
	{ "MultiBarRightButton", 12 },
	{ "MultiBarLeftButton", 12 },
	{ "MultiBar5Button", 12 },
	{ "MultiBar6Button", 12 },
	{ "MultiBar7Button", 12 },
	{ "PetActionButton", 10 },
	{ "StanceButton", 10 },
}

local buttons = {}

-- Icon tint, following ActionBarActionButtonMixin:UpdateUsable plus red
-- when out of range
local function UpdateIconColor(btn)
	if not btn.action or not btn.icon then return end

	if ns.db.actionbars.rangeColor and C_ActionBar.IsActionInRange(btn.action) == false then
		btn.icon:SetVertexColor(0.8, 0.1, 0.1)
		return
	end

	local usable, notEnoughMana = C_ActionBar.IsUsableAction(btn.action)
	if usable then
		btn.icon:SetVertexColor(1, 1, 1)
	elseif notEnoughMana then
		btn.icon:SetVertexColor(0.5, 0.5, 1)
	else
		btn.icon:SetVertexColor(0.4, 0.4, 0.4)
	end
end

-- Active actions (auto attack, stances, pending targeting) recolor our
-- border instead of showing Blizzard's gold checked square
local function UpdateChecked(btn)
	btn.kuiChecked = btn:GetChecked() and true or false
	local c = btn.kuiChecked and ns.db.actionbars.activeColor or ns.db.style.borderColor
	btn.kuiBorder:SetBackdropBorderColor(c[1], c[2], c[3], 1)
end

-- Empty slots (Blizzard hides the icon) get no border; their slot
-- background stays if Edit Mode's "always show buttons" is on
local function UpdateEmpty(btn)
	btn.kuiEmpty = not btn.icon:IsShown()
	btn.kuiBorder:SetShown(not btn.kuiEmpty)
end

-- The engine can flip a CheckButton's state without going through the Lua
-- SetChecked we hook (e.g. its native toggle on click), so also reconcile
-- periodically. GetChecked is a cheap C call.
local CHECK_INTERVAL = 0.1
local checkPoller = CreateFrame("Frame")
local sinceCheck = 0
local function PollChecked(_, elapsed)
	sinceCheck = sinceCheck + elapsed
	if sinceCheck < CHECK_INTERVAL then return end
	sinceCheck = 0
	for btn in pairs(buttons) do
		if (btn:GetChecked() and true or false) ~= btn.kuiChecked then
			UpdateChecked(btn)
		end
		-- Also catches slot contents changing (drag/drop, bar paging)
		if btn.icon:IsShown() == btn.kuiEmpty then
			UpdateEmpty(btn)
		end
	end
end

---------------------------------------------------------------------------
-- Lower-rank marker: a dot in the corner of buttons holding a spell below
-- the highest rank trained, to catch bars not updated after visiting the
-- trainer. Deliberate downranks are marked too.
---------------------------------------------------------------------------

local RANK_MARK_COLOR = { 0.3, 1, 0.3 }

-- The spell an action casts: placed directly, or a macro's current spell
-- (a macro showing a spell reports that spell's ID as its own)
local function ActionSpellID(action)
	local kind, id, subType = GetActionInfo(action)
	if ns.IsSecret(kind) or ns.IsSecret(subType) then return nil end
	if kind == "spell" or (kind == "macro" and subType == "spell") then
		return id
	end
end

-- Unranked spells (Feral Charge, say) report as not the highest rank, so
-- only spells with a rank are checked
local function IsLowerRank(id)
	if not id or ns.IsSecret(id) then return false end
	if not C_Spell.GetSpellSkillLineAbilityRank(id) then return false end
	return not C_ActionBar.IsHighestSpellRank(id)
end

local function UpdateRankMark(btn)
	local show = ns.db.actionbars.markLowRank and btn.action and IsLowerRank(ActionSpellID(btn.action))
	btn.kuiRankMark:SetShown(show and true or false)
end

-- A colored dot with a 1px black outline. Child of the border overlay, so
-- it draws above the cooldown swipe; StyleButton anchors it to the icon.
local function CreateRankMark(btn)
	local mark = CreateFrame("Frame", nil, btn.kuiBorder)
	mark:SetSize(7, 7)
	local outline = mark:CreateTexture(nil, "BACKGROUND")
	outline:SetAllPoints()
	outline:SetColorTexture(0, 0, 0, 1)
	local dot = mark:CreateTexture(nil, "ARTWORK")
	dot:SetPoint("TOPLEFT", 1, -1)
	dot:SetPoint("BOTTOMRIGHT", -1, 1)
	dot:SetColorTexture(unpack(RANK_MARK_COLOR))
	mark:Hide()
	btn.kuiRankMark = mark
end

local rankEvents = CreateFrame("Frame")
rankEvents:SetScript("OnEvent", function()
	for btn in pairs(buttons) do
		if btn.kuiRankMark then UpdateRankMark(btn) end
	end
end)

---------------------------------------------------------------------------
-- Styling
---------------------------------------------------------------------------

local function FitToIcon(region, icon)
	if not region then return end
	region:ClearAllPoints()
	region:SetAllPoints(icon)
end

-- Re-anchors regions of protected buttons, so it can't run in combat;
-- instead it flags a relayout, which ns:ApplyLayout catches up on (and
-- which restyles the action bars) when combat ends
local function StyleButton(btn)
	if InCombatLockdown() then
		ns.pendingLayout = true
		return
	end
	local settings = ns.db.actionbars
	local icon = btn.icon

	-- Blizzard's square frame art; replaced by our border
	local normal = btn:GetNormalTexture()
	if normal then normal:SetAlpha(0) end
	-- The shadow behind the button, drawn past our border
	if btn.SlotArt then btn.SlotArt:SetAlpha(0) end

	-- Square icon instead of the rounded mask
	if btn.IconMask and not btn.kuiUnmasked then
		icon:RemoveMaskTexture(btn.IconMask)
		btn.kuiUnmasked = true
	end

	-- Border on an overlay frame (edges only); the icon sits inside it
	local inset = ns:ApplyBackdrop(btn.kuiBorder, true)
	btn.kuiBorder:SetBackdropColor(0, 0, 0, 0)

	icon:ClearAllPoints()
	icon:SetPoint("TOPLEFT", inset, -inset)
	icon:SetPoint("BOTTOMRIGHT", -inset, inset)
	ns.CropIcon(icon)

	if btn.SlotBackground then
		btn.SlotBackground:SetColorTexture(ns:GetEmptyColor())
		-- Shares the icon's layer and sublevel, so it can draw on top of the
		-- icon and wash it out
		btn.SlotBackground:SetDrawLayer("BACKGROUND", -1)
		FitToIcon(btn.SlotBackground, icon)
	end

	FitToIcon(btn.cooldown, icon)
	FitToIcon(btn:GetHighlightTexture(), icon)
	-- Pressed state: a flat tint of the active color instead of Blizzard's
	-- gold pushed frame (the main bar re-sets that atlas on art updates,
	-- which our UpdateButtonArt hook catches)
	local pushed = btn:GetPushedTexture()
	if pushed then
		local c = settings.activeColor
		pushed:SetColorTexture(c[1], c[2], c[3], 0.35)
		FitToIcon(pushed, icon)
	end
	-- Auto-repeat/auto-attack pulse: Blizzard's art is pinned TOPLEFT at its
	-- atlas size, so it sits offset once the icon is inset. A flat tint over
	-- the icon instead, in the palette's red.
	if btn.Flash then
		local c = ns:GetCastColor("failed")
		btn.Flash:SetColorTexture(c[1], c[2], c[3], 0.4)
		FitToIcon(btn.Flash, icon)
	end

	local checked = btn:GetCheckedTexture()
	if checked then checked:SetAlpha(0) end
	UpdateChecked(btn)
	UpdateEmpty(btn)

	if btn.HotKey then
		btn.HotKey:SetFontObject(ns.fonts.small)
		btn.HotKey:SetAlpha(settings.showHotkeys and 1 or 0)
	end
	if btn.Name then
		btn.Name:SetFontObject(ns.fonts.small)
		btn.Name:SetAlpha(settings.showMacroNames and 1 or 0)
	end
	if btn.Count then
		btn.Count:SetFontObject(ns.fonts.normal)
	end

	if btn.kuiRankMark then
		btn.kuiRankMark:ClearAllPoints()
		btn.kuiRankMark:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
		UpdateRankMark(btn)
	end

	UpdateIconColor(btn)
end

function ns:StyleActionBars()
	if not ns.db.actionbars.enabled then return end
	for btn in pairs(buttons) do
		StyleButton(btn)
	end
end

-- The main bar frames its buttons, divides them and adds paging
-- arrows. Alpha, not its hideBarArt setting: writing that would taint the
-- bar's secure layout.
local function HideDividers(bar)
	for _, pool in ipairs({ bar.HorizontalDividersPool, bar.VerticalDividersPool }) do
		for divider in pool:EnumerateActive() do
			divider:SetAlpha(0)
		end
	end
end

local function HideMainBarArt()
	if MainActionBar.BorderArt then MainActionBar.BorderArt:SetAlpha(0) end
	-- The pools are created by the first UpdateDividers
	hooksecurefunc(MainActionBar, "UpdateDividers", function(bar)
		if bar.HorizontalDividersPool then HideDividers(bar) end
	end)
	if MainActionBar.HorizontalDividersPool then HideDividers(MainActionBar) end
	-- Paging keybinds don't go through these arrows. Reparented because Edit
	-- Mode sets whether they're shown.
	ns.SetHidden(MainActionBar.ActionBarPageNumber, true)
end

-- Only when enabled at login (see the lifecycle notes in Core.lua)
function ns:InitActionBars()
	if not ns.db.actionbars.enabled then return end

	for _, set in ipairs(BUTTON_SETS) do
		local prefix, count = set[1], set[2]
		for i = 1, count do
			local btn = _G[prefix .. i]
			if btn and btn.icon then
				buttons[btn] = true

				btn.kuiBorder = CreateFrame("Frame", nil, btn, "BackdropTemplate")
				btn.kuiBorder:SetAllPoints()
				-- Above the cooldown swipe, below the hotkey/count text overlay
				btn.kuiBorder:SetFrameLevel(btn:GetFrameLevel() + 1)

				-- Blizzard re-applies its art when Edit Mode settings change
				if btn.UpdateButtonArt then
					hooksecurefunc(btn, "UpdateButtonArt", StyleButton)
				end
				if btn.UpdateUsable then
					hooksecurefunc(btn, "UpdateUsable", UpdateIconColor)
				end
				-- Blizzard's state updates go through SetChecked
				hooksecurefunc(btn, "SetChecked", UpdateChecked)

				-- Spell buttons only: Update runs on slot changes and paging
				if btn.Update and btn.action then
					CreateRankMark(btn)
					hooksecurefunc(btn, "Update", UpdateRankMark)
				end
			end
		end
	end

	hooksecurefunc("ActionButton_UpdateRangeIndicator", function(btn)
		if buttons[btn] then UpdateIconColor(btn) end
	end)
	checkPoller:SetScript("OnUpdate", PollChecked)

	HideMainBarArt()

	-- Training a rank changes the spellbook
	rankEvents:RegisterEvent("SPELLS_CHANGED")

	ns:StyleActionBars()
end
