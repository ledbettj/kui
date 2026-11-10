local addonName, ns = ...

-- Settings panel: Options -> AddOns -> KUI (or /kui). One page per area
-- (General, Unit Frames, Colors, ...), each a scrolling canvas of labeled
-- rows in sections. Every frame is shown in preview while any page is open.

local LABEL_WIDTH = 190
local CONTROL_WIDTH = 240
local ROW_HEIGHT = 30

local category
local rows = {} -- every control row, for RefreshAll

local function RefreshAll()
	for _, row in ipairs(rows) do
		row:Refresh()
	end
end

---------------------------------------------------------------------------
-- Widgets. Each takes get/set functions last and returns a row with a
-- Refresh method that re-reads its value.
---------------------------------------------------------------------------

local function CreateRow(parent, text)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(LABEL_WIDTH + CONTROL_WIDTH + 60, ROW_HEIGHT)

	-- Long labels wrap within their column rather than running under the
	-- control; the row fits two lines
	row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.label:SetPoint("LEFT")
	row.label:SetWidth(LABEL_WIDTH - 10)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(true)
	row.label:SetText(text)

	rows[#rows + 1] = row
	return row
end

local function CreateSlider(parent, text, minValue, maxValue, step, get, set)
	local row = CreateRow(parent, text)

	local slider = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")
	slider:SetPoint("LEFT", LABEL_WIDTH, 0)
	slider:SetWidth(CONTROL_WIDTH)
	slider:Init(get(), minValue, maxValue, (maxValue - minValue) / step, {
		[MinimalSliderWithSteppersMixin.Label.Right] = function(v) return tostring(math.floor(v + 0.5)) end,
	})
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		value = math.floor(value + 0.5)
		if value ~= get() then set(value) end
	end, row)

	function row:Refresh()
		slider:SetValue(get())
	end
	return row
end

-- list: function returning the option names (media lists can grow at
-- runtime as LibSharedMedia packs register)
local function CreateDropdown(parent, text, list, get, set)
	local row = CreateRow(parent, text)

	local dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
	dropdown:SetPoint("LEFT", LABEL_WIDTH, 0)
	dropdown:SetWidth(CONTROL_WIDTH)
	dropdown:SetupMenu(function(_, root)
		-- LibSharedMedia packs can add dozens of entries
		if root.SetScrollMode then root:SetScrollMode(400) end
		for _, name in ipairs(list()) do
			root:CreateRadio(name, function(n) return get() == n end, set, name)
		end
	end)

	function row:Refresh()
		dropdown:GenerateMenu()
	end
	return row
end

local function CreateCheckbox(parent, text, get, set)
	local row = CreateRow(parent, text)

	local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	check:SetPoint("LEFT", LABEL_WIDTH - 4, 0)
	check:SetScript("OnClick", function(self)
		set(self:GetChecked())
	end)

	function row:Refresh()
		check:SetChecked(get())
	end
	return row
end

-- One entry of the info bar's readout list: the readout at this position
-- (the label follows reordering), its slot, and buttons to move it within
-- that slot. The list is grouped by slot, so every row can change.
local function CreateReadoutRow(parent, index)
	local row = CreateRow(parent, "")
	local function Id() return ns.db.infobar.order[index] end

	local dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
	dropdown:SetPoint("LEFT", LABEL_WIDTH, 0)
	dropdown:SetWidth(CONTROL_WIDTH - 60)
	dropdown:SetupMenu(function(_, root)
		for _, slot in ipairs(ns.infoBarSlots) do
			root:CreateRadio(slot,
				function() return ns.db.infobar.slots[Id()] == slot end,
				function()
					ns:SetReadoutSlot(Id(), slot)
					RefreshAll()
				end)
		end
	end)

	local arrows = {}

	local function Arrow(direction, step, x)
		local button = CreateFrame("Button", nil, row)
		button:SetSize(24, 24)
		button:SetPoint("LEFT", dropdown, "RIGHT", x, 0)
		button:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-Scroll" .. direction .. "-Up")
		button:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-Scroll" .. direction .. "-Down")
		button:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-Scroll" .. direction .. "-Disabled")
		button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		button.step = step
		arrows[#arrows + 1] = button
		button:SetScript("OnClick", function()
			ns:MoveReadout(index, step)
			RefreshAll() -- every row's label and slot shift
		end)
	end
	Arrow("Up", -1, 6)
	Arrow("Down", 1, 30)

	function row:Refresh()
		row.label:SetText(ns.readouts[Id()].label)
		dropdown:GenerateMenu()
		for _, arrow in ipairs(arrows) do
			arrow:SetEnabled(ns:CanMoveReadout(index, arrow.step))
		end
	end
	return row
end

-- reset: optional; adds a Reset button that calls it
local function CreateColorSwatch(parent, text, get, set, reset)
	local row = CreateRow(parent, text)

	local button = CreateFrame("Button", nil, row)
	button:SetPoint("LEFT", LABEL_WIDTH, 0)
	button:SetSize(22, 22)

	local frame = button:CreateTexture(nil, "BACKGROUND")
	frame:SetAllPoints()
	frame:SetColorTexture(1, 1, 1)

	local swatch = button:CreateTexture(nil, "ARTWORK")
	swatch:SetPoint("TOPLEFT", 2, -2)
	swatch:SetPoint("BOTTOMRIGHT", -2, 2)

	local function Apply(r, g, b)
		-- Always a fresh table: get() may return a shared default
		set({ r, g, b })
		swatch:SetColorTexture(r, g, b)
	end

	button:SetScript("OnClick", function()
		local r, g, b = unpack(get())
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r, g = g, b = b,
			hasOpacity = false,
			swatchFunc = function() Apply(ColorPickerFrame:GetColorRGB()) end,
			cancelFunc = function() Apply(r, g, b) end,
		})
	end)

	if reset then
		local resetButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		resetButton:SetSize(60, 20)
		resetButton:SetPoint("LEFT", button, "RIGHT", 10, 0)
		resetButton:SetText(RESET)
		resetButton:SetScript("OnClick", function()
			reset()
			row:Refresh()
		end)
	end

	function row:Refresh()
		swatch:SetColorTexture(unpack(get()))
	end
	return row
end

-- A dropdown for picking something to act on rather than a setting: it
-- shows placeholder until opened, and greys out while list() is empty
local function CreatePicker(parent, text, placeholder, list, onPick)
	local row = CreateRow(parent, text)

	local dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
	dropdown:SetPoint("LEFT", LABEL_WIDTH, 0)
	dropdown:SetWidth(CONTROL_WIDTH)
	dropdown:SetDefaultText(placeholder)
	dropdown:SetupMenu(function(_, root)
		for _, name in ipairs(list()) do
			root:CreateButton(name, onPick, name)
		end
	end)

	function row:Refresh()
		dropdown:GenerateMenu()
		dropdown:SetEnabled(#list() > 0)
	end
	return row
end

-- Read-only text in the control column
local function CreateInfo(parent, text, get)
	local row = CreateRow(parent, text)

	local value = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	value:SetPoint("LEFT", LABEL_WIDTH, 0)
	value:SetWidth(CONTROL_WIDTH)
	value:SetJustifyH("LEFT")
	value:SetWordWrap(true)

	function row:Refresh()
		value:SetText(get())
	end
	return row
end

local function CreateHeader(parent, text)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fs:SetText(text)
	return fs
end

---------------------------------------------------------------------------
-- Setters: store the value, then apply it the cheapest correct way
---------------------------------------------------------------------------

-- Layout goes through ns:ApplyLayout, which waits for combat to end
local function Relayout()
	if not ns:ApplyLayout() then
		ns.Print("frame layout will update after combat.")
	end
end

local function SetLayout(key, value)
	ns.db.layout[key] = value
	Relayout()
end

-- Style keys that move or resize regions (the border inset decides where
-- bars sit) need a relayout; the rest are a restyle
local STYLE_LAYOUT_KEYS = {
	border = true, borderSize = true, borderColor = true, padding = true,
	bgAlpha = true, powerHeight = true, frameHeightScale = true, auraScale = true,
}

local function SetStyle(key, value)
	ns.db.style[key] = value
	if STYLE_LAYOUT_KEYS[key] then
		Relayout()
	else
		ns:ApplyStyle()
	end
end

local function SetCastbar(key, value)
	ns.db.castbar[key] = value
	if key == "texture" then
		ns:ApplyStyle()
	else
		Relayout()
	end
end

-- Modules that are only built at login when enabled
local function NeedsReload(what)
	ns.Print(what .. " change takes effect after /reload.")
end

-- Not secure frames, so these apply immediately, even in combat
local function SetStatusBars(key, value)
	ns.db.statusbars[key] = value
	if key == "enabled" then
		NeedsReload("XP/reputation bar")
	elseif key == "texture" then
		ns:StyleStatusBars()
	else
		ns:LayoutStatusBars()
	end
end

local function SetNameplates(key, value)
	ns.db.nameplates[key] = value
	if key == "enabled" then
		NeedsReload("nameplate")
	else
		-- Layout also re-applies the border, including the target highlight
		ns:LayoutNameplates()
	end
end

local function SetHealPrediction(key, value)
	ns.db.healPrediction[key] = value
	ns:ApplyStyle()
end

local function SetAggro(key, value)
	ns.db.aggro[key] = value
	ns:ApplyStyle()
end

local function SetBuffs(key, value)
	ns.db.buffs[key] = value
	NeedsReload("buff bar styling")
end

local function SetBuffScale(key, value)
	ns.db.buffs[key] = value
	ns:StyleBuffs()
end

local function SetInfoBar(key, value)
	ns.db.infobar[key] = value
	ns:LayoutInfoBar()
	ns:LayoutStatusBars() -- they sit on top of it
end

local function SetUIFont(key, value)
	ns.db.uifont[key] = value
	ns:ApplyUIFont()
end

local function SetMinimap(key, value)
	ns.db.minimap[key] = value
	ns:LayoutMinimap()
end

local function SetMenuBar(key, value)
	ns.db.menubar[key] = value
	ns:ApplyMenuBar()
end

local function SetChat(key, value)
	ns.db.chat[key] = value
	ns:ApplyChat()
end

local function SetTooltip(key, value)
	ns.db.tooltip[key] = value
	if key == "enabled" then NeedsReload("tooltip styling") end
end

-- Read at the vendor
local function SetVendor(key, value)
	ns.db.vendor[key] = value
end

local function SetActionBars(key, value)
	ns.db.actionbars[key] = value
	if key == "enabled" then
		NeedsReload("action bar styling")
	else
		ns:StyleActionBars()
	end
end

-- get/set pair for ns.db[section][key], for the trailing get, set arguments
-- of the widgets. percent: stored as 0-1, shown as 0-100.
local function Bind(section, key, setter, percent)
	if percent then
		return function() return math.floor(ns.db[section][key] * 100 + 0.5) end,
			function(v) setter(key, v / 100) end
	end
	return function() return ns.db[section][key] end,
		function(v) setter(key, v) end
end

-- Color overrides; kind is one of ns.colorKinds, a nil value removes the
-- override
local function SetColor(kind, key, value)
	ns.db.colors[kind][key] = value
	ns:ApplyStyle()
end

-- Choosing a palette clears individual overrides so it shows as designed
local function SetPalette(name)
	ns.db.colors.palette = name
	for _, kind in ipairs(ns.colorKinds) do
		wipe(ns.db.colors[kind])
	end
	ns:ApplyStyle()
	RefreshAll()
end

local function ResetToDefaults()
	ns:ResetSettings()
	RefreshAll()
end

local function StatusbarList() return ns:ListMedia("statusbar") end
local function FontList() return ns:ListMedia("font") end
local function BorderList() return ns:ListMedia("border") end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------

-- Width slider labels; units sharing another's width aren't listed
local WIDTH_LABELS = {
	player = "Player",
	target = "Target",
	targettarget = "Focus / ToT / party pets",
	pet = "Pet",
	party1 = "Party",
}
local REACTION_LABELS = { hostile = "Hostile", neutral = "Neutral", friendly = "Friendly" }
local CAST_LABELS = { cast = "Casting", channel = "Channeling", failed = "Failed / interrupted" }
local HEAL_LABELS = { mine = "Your heals", others = "Others' heals" }
local THREAT_LABELS = { pulling = "About to pull aggro", insecure = "Tanking, losing it", tanking = "Tanking" }

local PAGE_TOP = -72 -- below the title and (up to two lines of) description

-- Whether a feature (or any of a list of them) runs on this client; nil
-- means the setting isn't tied to one
local function Supported(feature)
	if feature == nil then return true end
	if type(feature) == "string" then return ns.supported[feature] end
	for _, f in ipairs(feature) do
		if ns.supported[f] then return true end
	end
	return false
end

-- A page's widgets, stacked top-down in sections. Each method places one
-- row; the widget arguments are passed straight through. Sections (and
-- rows after b.Feature) for features this client doesn't run are left out
-- entirely; b.rowCount says whether anything was placed.
local function NewBuilder(content)
	local b = { y = PAGE_TOP, rowCount = 0 }
	local sectionShown, rowsShown = true, true

	local function Place(region, extraGap)
		region:SetPoint("TOPLEFT", 16, b.y)
		b.y = b.y - (region.GetHeight and region:GetHeight() > 0 and region:GetHeight() or 16) - (extraGap or 0)
	end

	-- A widget constructor wrapped to skip hidden rows
	local function Row(create)
		return function(...)
			if not (sectionShown and rowsShown) then return end
			Place(create(content, ...))
			b.rowCount = b.rowCount + 1
		end
	end

	function b.Section(text, feature)
		sectionShown, rowsShown = Supported(feature), true
		if not sectionShown then return end
		if b.y < PAGE_TOP then b.y = b.y - 12 end
		Place(CreateHeader(content, text), 6)
	end
	-- The rows after this belong to feature (nil: back to the section's)
	function b.Feature(feature)
		rowsShown = Supported(feature)
	end
	b.Slider = Row(CreateSlider)
	b.Dropdown = Row(CreateDropdown)
	b.Checkbox = Row(CreateCheckbox)
	b.ReadoutRow = Row(CreateReadoutRow)
	b.Swatch = Row(CreateColorSwatch)
	b.Picker = Row(CreatePicker)
	b.Info = Row(CreateInfo)
	function b.ColorRow(kind, key, label)
		b.Swatch(label,
			function() return ns:GetColor(kind, key) end,
			function(v) SetColor(kind, key, v) end,
			function() SetColor(kind, key, nil) end)
	end
	function b.Button(text, onClick)
		if not (sectionShown and rowsShown) then return end
		b.rowCount = b.rowCount + 1
		b.y = b.y - 16
		local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
		button:SetSize(140, 24)
		button:SetText(text)
		button:SetScript("OnClick", onClick)
		Place(button)
	end

	return b
end

local function BuildGeneral(b)
	b.Section("Text")
	b.Dropdown("Font", FontList, Bind("style", "font", SetStyle))
	b.Feature("uifont")
	b.Checkbox("Use one font for the whole UI", Bind("uifont", "enabled", SetUIFont))
	b.Dropdown("Whole UI font", FontList, Bind("uifont", "font", SetUIFont))
	b.Feature(nil)
	b.Slider("Font size", 8, 20, 1, Bind("style", "fontSize", SetStyle))
	b.Feature("unitframes")
	b.Slider("Unit names", 8, 20, 1, Bind("style", "nameFontSize", SetStyle))
	b.Slider("Bar text (health, power, cast, XP)", 8, 20, 1, Bind("style", "barFontSize", SetStyle))
	b.Feature("infobar")
	b.Slider("Info bar", 8, 20, 1, Bind("style", "infobarFontSize", SetStyle))
	b.Feature(nil)

	b.Section("Bar textures")
	b.Dropdown("Health bar", StatusbarList, Bind("style", "healthTexture", SetStyle))
	b.Dropdown("Power bar", StatusbarList, Bind("style", "powerTexture", SetStyle))
	b.Swatch("Empty bar color", Bind("style", "emptyColor", SetStyle))
	b.Slider("Empty bar opacity", 0, 100, 5, Bind("style", "emptyAlpha", SetStyle, true))

	b.Section("Border")
	b.Dropdown("Style", BorderList, Bind("style", "border", SetStyle))
	b.Slider("Thickness", 1, 24, 1, Bind("style", "borderSize", SetStyle))
	b.Swatch("Color", Bind("style", "borderColor", SetStyle))
	b.Slider("Padding", 0, 6, 1, Bind("style", "padding", SetStyle))
	b.Slider("Background opacity", 0, 100, 5, Bind("style", "bgAlpha", SetStyle, true))

	b.Button("Reset profile", ResetToDefaults)
end

local function BuildUnitFrames(b)
	b.Section("Layout", "unitframes")
	b.Slider("Vertical position", -600, 600, 2, Bind("layout", "y", SetLayout))
	b.Slider("Distance from center", 0, 400, 1, Bind("layout", "centerGap", SetLayout))
	b.Slider("Focus / ToT spacing", 0, 100, 1, Bind("layout", "sideGap", SetLayout))

	b.Section("Frame width", "unitframes")
	for _, unit in ipairs(ns.unitOrder) do
		if not ns.units[unit].widthFrom then
			b.Slider(WIDTH_LABELS[unit] or unit, 60, 400, 2,
				function() return ns:GetWidth(unit) end,
				function(v)
					ns.db.widths[unit] = v
					Relayout()
				end)
		end
	end
	b.Slider("Frame height (%)", 100, 200, 5, Bind("style", "frameHeightScale", SetStyle, true))
	b.Slider("Buff and debuff icons (%)", 50, 200, 5, Bind("style", "auraScale", SetStyle, true))
	b.Slider("Power bar height (player/target)", 2, 20, 1, Bind("style", "powerHeight", SetStyle))

	b.Section("Party", "unitframes")
	b.Slider("Horizontal position", 0, 1000, 2, Bind("layout", "partyX", SetLayout))
	b.Slider("Vertical position", -1000, 0, 2, Bind("layout", "partyY", SetLayout))
	b.Slider("Spacing", 0, 60, 1, Bind("layout", "partySpacing", SetLayout))
	b.Slider("Out of range opacity", 0, 100, 5, Bind("style", "outOfRangeAlpha", SetStyle, true))

	b.Section("Cast bars", "unitframes")
	b.Slider("Height (player/target)", 4, 24, 1, Bind("castbar", "height", SetCastbar))
	b.Slider("Height (focus)", 6, 30, 1, Bind("castbar", "focusHeight", SetCastbar))
	b.Dropdown("Texture", StatusbarList, Bind("castbar", "texture", SetCastbar))
	b.Checkbox("Show spell icon", Bind("castbar", "showIcon", SetCastbar))

	b.Section("Incoming heals", "unitframes")
	b.Checkbox("Show incoming heals", Bind("healPrediction", "enabled", SetHealPrediction))

	b.Section("Aggro", "unitframes")
	b.Checkbox("Threat border (player, pet, party)", Bind("aggro", "enabled", SetAggro))
end

local function BuildColors(b)
	b.Section("Palette", { "unitframes", "nameplates" })
	b.Dropdown("Palette", function() return ns.paletteOrder end,
		function() return ns.db.colors.palette end, SetPalette)

	b.Section("Class (player health)", { "unitframes", "nameplates" })
	for _, class in ipairs(ns.classOrder) do
		b.ColorRow("class", class, LOCALIZED_CLASS_NAMES_MALE[class] or class)
	end

	b.Section("Reaction (NPC health)", { "unitframes", "nameplates" })
	for _, key in ipairs(ns.reactionOrder) do
		b.ColorRow("reaction", key, REACTION_LABELS[key])
	end

	b.Section("Power", { "unitframes", "nameplates" })
	for _, token in ipairs(ns.powerOrder) do
		b.ColorRow("power", token, _G[token] or token)
	end

	b.Section("Cast bars", { "unitframes", "nameplates" })
	for _, key in ipairs(ns.castOrder) do
		b.ColorRow("cast", key, CAST_LABELS[key])
	end

	b.Section("Incoming heals", "unitframes")
	for _, key in ipairs(ns.healOrder) do
		b.ColorRow("heal", key, HEAL_LABELS[key])
	end

	b.Section("Threat", { "unitframes", "nameplates" })
	for _, key in ipairs(ns.threatOrder) do
		b.ColorRow("threat", key, THREAT_LABELS[key])
	end
end

local function BuildNameplates(b)
	b.Section("Nameplates", "nameplates")
	b.Checkbox("Restyle nameplates", Bind("nameplates", "enabled", SetNameplates))
	b.Slider("Width", 60, 240, 2, Bind("nameplates", "width", SetNameplates))
	b.Slider("Health height", 6, 30, 1, Bind("nameplates", "height", SetNameplates))
	b.Slider("Cast bar height", 6, 24, 1, Bind("nameplates", "castHeight", SetNameplates))
	b.Checkbox("Rare/elite icon", Bind("nameplates", "classification", SetNameplates))

	b.Section("Target", "nameplates")
	b.Checkbox("Highlight target", Bind("nameplates", "highlightTarget", SetNameplates))
	b.Swatch("Target border color", Bind("nameplates", "targetColor", SetNameplates))

	b.Section("Threat", "nameplates")
	b.Checkbox("Threat border", Bind("nameplates", "threatBorder", SetNameplates))
	b.Checkbox("Threat percentage", Bind("nameplates", "threatPercent", SetNameplates))
end

local function BuildActionBars(b)
	b.Section("Action bars", "actionbars")
	b.Checkbox("Restyle action bars", Bind("actionbars", "enabled", SetActionBars))
	b.Checkbox("Show keybinds", Bind("actionbars", "showHotkeys", SetActionBars))
	b.Checkbox("Show macro names", Bind("actionbars", "showMacroNames", SetActionBars))
	b.Checkbox("Red icons out of range", Bind("actionbars", "rangeColor", SetActionBars))
	b.Checkbox("Mark lower-rank spells", Bind("actionbars", "markLowRank", SetActionBars))
	b.Swatch("Active border color", Bind("actionbars", "activeColor", SetActionBars))

	b.Section("Bags & menu", "menubar")
	b.Dropdown("Bag buttons", function() return ns.bagOptions end, Bind("menubar", "bags", SetMenuBar))
	b.Checkbox("Hide the micro menu", Bind("menubar", "hideMicroMenu", SetMenuBar))

	b.Section("Buff bar", "buffs")
	b.Checkbox("Restyle buff bar", Bind("buffs", "enabled", SetBuffs))
	b.Slider("Size (%)", 50, 200, 5, Bind("buffs", "scale", SetBuffScale, true))
end

local function BuildOther(b)
	b.Section("XP / reputation bars", "statusbars")
	b.Checkbox("Replace XP/rep bars", Bind("statusbars", "enabled", SetStatusBars))
	b.Dropdown("Position", function() return { "Top", "Bottom" } end, Bind("statusbars", "position", SetStatusBars))
	b.Slider("Width", 100, 1200, 4, Bind("statusbars", "width", SetStatusBars))
	b.Slider("Height", 4, 30, 1, Bind("statusbars", "height", SetStatusBars))
	b.Dropdown("Texture", StatusbarList, Bind("statusbars", "texture", SetStatusBars))

	b.Section("Info bar", "infobar")
	b.Checkbox("Show info bar", Bind("infobar", "enabled", SetInfoBar))
	b.Slider("Height", 10, 40, 1, Bind("infobar", "height", SetInfoBar))
	b.Slider("Spacing between readouts", 0, 60, 1, Bind("infobar", "spacing", SetInfoBar))
	b.Slider("Padding from screen edges", 0, 100, 1, Bind("infobar", "edgePadding", SetInfoBar))
	-- One row per readout; the list order is the left-to-right order
	for i = 1, #ns.settingsDefaults.infobar.order do
		b.ReadoutRow(i)
	end

	b.Section("Tooltips", "tooltips")
	b.Checkbox("Restyle tooltips", Bind("tooltip", "enabled", SetTooltip))
	b.Checkbox("Class-colored player names", Bind("tooltip", "classColors", SetTooltip))
	b.Checkbox("Show what units are targeting", Bind("tooltip", "showTarget", SetTooltip))
	b.Checkbox("Hide unit tooltips in combat", Bind("tooltip", "hideInCombat", SetTooltip))

	b.Section("Vendors (hold Shift to skip)", "vendor")
	b.Checkbox("Repair automatically", Bind("vendor", "autoRepair", SetVendor))
	b.Checkbox("Use guild bank funds for repairs", Bind("vendor", "guildRepair", SetVendor))
	b.Checkbox("Sell grey items", Bind("vendor", "sellGreys", SetVendor))

	b.Section("Minimap", "minimap")
	b.Dropdown("Style", function() return { "Blizzard", "Square" } end, Bind("minimap", "style", SetMinimap))

	b.Section("Chat", "chat")
	b.Checkbox("Hide chat buttons", Bind("chat", "hideButtons", SetChat))
end

---------------------------------------------------------------------------
-- Profiles. Switching, copying or resetting replaces every setting at once,
-- so each refreshes the whole panel.
---------------------------------------------------------------------------

local function CreateProfile(name)
	local err = ns:CreateProfile(name)
	if err then ns.Print(err) end
	RefreshAll()
end

StaticPopupDialogs.KUI_NEW_PROFILE = {
	text = "Name for the new profile. It starts as a copy of your current settings.",
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 32,
	OnShow = function(dialog)
		local editBox = dialog:GetEditBox()
		editBox:SetText(UnitName("player"))
		editBox:HighlightText()
		editBox:SetFocus()
	end,
	OnAccept = function(dialog) CreateProfile(dialog:GetEditBox():GetText()) end,
	EditBoxOnEnterPressed = function(editBox)
		CreateProfile(editBox:GetText())
		editBox:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

-- data: the profile picked
StaticPopupDialogs.KUI_COPY_PROFILE = {
	text = "Replace every setting in %s with a copy of %s?",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, from)
		ns:CopyProfile(from)
		RefreshAll()
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

StaticPopupDialogs.KUI_DELETE_PROFILE = {
	text = "Delete the profile %s? Characters using it go back to Default.",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, name)
		ns:DeleteProfile(name)
		RefreshAll()
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

local function OtherProfiles()
	local list = {}
	for _, name in ipairs(ns:ProfileList()) do
		if name ~= ns:ProfileName() then list[#list + 1] = name end
	end
	return list
end

local function DeletableProfiles()
	local list = {}
	for _, name in ipairs(ns:ProfileList()) do
		if ns:CanDeleteProfile(name) then list[#list + 1] = name end
	end
	return list
end

local function BuildProfiles(b)
	b.Section("This character")
	b.Dropdown("Profile", function() return ns:ProfileList() end,
		function() return ns:ProfileName() end,
		function(name)
			ns:SetProfile(name)
			RefreshAll()
		end)
	b.Info("Used by", function() return table.concat(ns:ProfileUsers(ns:ProfileName()), ", ") end)
	b.Button("New profile...", function() StaticPopup_Show("KUI_NEW_PROFILE") end)

	b.Section("Other profiles")
	b.Picker("Copy settings from", "Choose a profile", OtherProfiles, function(from)
		StaticPopup_Show("KUI_COPY_PROFILE", ns:ProfileName(), from, from)
	end)
	b.Picker("Delete", "Choose a profile", DeletableProfiles, function(name)
		StaticPopup_Show("KUI_DELETE_PROFILE", name, nil, name)
	end)
end

-- Order is the sidebar order; the first page is the KUI category itself
local PAGES = {
	{ name = "KUI", title = "KUI", build = BuildGeneral,
		description = "Shared look for everything KUI draws. All unit frames are shown while any KUI page is open." },
	{ name = "Unit Frames", build = BuildUnitFrames,
		description = "Position and size of the player, target, focus, pet and party frames." },
	{ name = "Colors", build = BuildColors,
		description = "Choosing a palette clears individual overrides; Reset returns a row to the palette." },
	{ name = "Nameplates", build = BuildNameplates,
		description = "Enemy plates show your debuffs; friendly plates your own buffs." },
	{ name = "Action Bars & Buffs", build = BuildActionBars,
		description = "Cosmetic only: positions and sizes stay with Edit Mode." },
	{ name = "Other", build = BuildOther,
		description = "XP/reputation bars, info bar, tooltips, vendors, minimap and chat window tweaks." },
	{ name = "Profiles", build = BuildProfiles,
		description = "Profiles are shared by all your characters, and each character uses one. "
			.. "New characters start on Default; make a new profile to give one its own settings." },
}

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

local panels = {}

local function AnyPageVisible()
	for _, panel in ipairs(panels) do
		if panel:IsVisible() then return true end
	end
	return false
end

local function OnPageShow()
	RefreshAll()
	if not InCombatLockdown() then ns:SetPreview(true) end
end

-- Preview stays on while moving between KUI pages: a page hiding only turns
-- it off if no other KUI page is showing by the next frame
local function OnPageHide()
	C_Timer.After(0, function()
		if not AnyPageVisible() and not InCombatLockdown() then ns:SetPreview(false) end
	end)
end

local function CreatePage(page)
	-- Hidden until Settings displays it: a shown frame without a parent
	-- counts as visible, which would keep AnyPageVisible true forever
	local panel = CreateFrame("Frame")
	panel:Hide()

	-- Settings doesn't scroll canvas panels itself
	local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -4)
	scroll:SetPoint("BOTTOMRIGHT", -28, 4)

	local content = CreateFrame("Frame", nil, scroll)
	content:SetWidth(LABEL_WIDTH + CONTROL_WIDTH + 100)
	scroll:SetScrollChild(content)

	local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(page.title or ("KUI - " .. page.name))

	local description = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	description:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	description:SetJustifyH("LEFT")
	description:SetText(page.description)

	local builder = NewBuilder(content)
	page.build(builder)
	content:SetHeight(-builder.y + 16)

	panel:SetScript("OnShow", OnPageShow)
	panel:SetScript("OnHide", OnPageHide)
	-- Hook the Settings panel calls when a canvas is shown
	panel.OnRefresh = RefreshAll
	return panel, builder.rowCount
end

function ns:InitConfig()
	for i, page in ipairs(PAGES) do
		local panel, rowCount = CreatePage(page)
		if i == 1 then
			-- Settings' Defaults button calls OnDefault on the shown canvas, or on
			-- every canvas for "all settings". Resetting is all-or-nothing in
			-- KUI, so only the top page carries it.
			panel.OnDefault = ResetToDefaults
			category = Settings.RegisterCanvasLayoutCategory(panel, page.name)
			panels[#panels + 1] = panel
		elseif rowCount > 0 then
			-- Pages with nothing that runs on this client are left out
			Settings.RegisterCanvasLayoutSubcategory(category, panel, page.name)
			panels[#panels + 1] = panel
		end
	end
	Settings.RegisterAddOnCategory(category)
end

function ns:OpenConfig()
	if InCombatLockdown() then
		return ns.Print("can't open settings in combat.")
	end
	Settings.OpenToCategory(category:GetID())
end
