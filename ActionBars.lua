local addonName, ns = ...

-- Cosmetic restyle of Blizzard's action buttons: border, square icons,
-- fonts, range coloring. Layout (size, padding, rows) is left to Edit Mode,
-- which owns the positions of these protected buttons.

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

local ICON_CROP = { 0.08, 0.92, 0.08, 0.92 }

local buttons = {}

-- Icon tint, following ActionBarActionButtonMixin:UpdateUsable plus red
-- when out of range
local function UpdateIconColor(btn)
	if not KUIDB.actionbars.rangeColor or not btn.action or not btn.icon then return end

	if IsActionInRange(btn.action) == false then
		btn.icon:SetVertexColor(0.8, 0.1, 0.1)
		return
	end

	local usable, notEnoughMana = IsUsableAction(btn.action)
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
	local c = btn.kuiChecked and KUIDB.actionbars.activeColor or KUIDB.style.borderColor
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

local function FitToIcon(region, icon)
	if not region then return end
	region:ClearAllPoints()
	region:SetAllPoints(icon)
end

local function StyleButton(btn)
	if InCombatLockdown() then
		ns.pendingLayout = true
		return
	end
	local settings = KUIDB.actionbars
	local icon = btn.icon

	-- Blizzard's square frame art; replaced by our border
	local normal = btn:GetNormalTexture()
	if normal then normal:SetAlpha(0) end

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
	icon:SetTexCoord(unpack(ICON_CROP))

	if btn.SlotBackground then
		btn.SlotBackground:SetColorTexture(ns:GetEmptyColor())
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

	UpdateIconColor(btn)
end

function ns:StyleActionBars()
	if not KUIDB.actionbars.enabled then return end
	for btn in pairs(buttons) do
		StyleButton(btn)
	end
end

function ns:InitActionBars()
	if not KUIDB.actionbars.enabled then return end

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
			end
		end
	end

	hooksecurefunc("ActionButton_UpdateRangeIndicator", function(btn)
		if buttons[btn] then UpdateIconColor(btn) end
	end)
	checkPoller:SetScript("OnUpdate", PollChecked)

	ns:StyleActionBars()
end
