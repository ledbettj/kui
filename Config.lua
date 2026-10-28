local addonName, ns = ...

-- Settings panel: Options -> AddOns -> KUI (or /kui). A single scrolling
-- canvas of labeled rows. Every frame is shown in preview while it's open.

local LABEL_WIDTH = 140
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

	row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.label:SetPoint("LEFT")
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
	KUIDB.layout[key] = value
	Relayout()
end

-- Style keys that move or resize regions (the border inset decides where
-- bars sit) need a relayout; the rest are a restyle
local STYLE_LAYOUT_KEYS = {
	border = true, borderSize = true, borderColor = true, padding = true,
	bgAlpha = true, powerHeight = true,
}

local function SetStyle(key, value)
	KUIDB.style[key] = value
	if STYLE_LAYOUT_KEYS[key] then
		Relayout()
	else
		ns:ApplyStyle()
	end
end

local function SetCastbar(key, value)
	KUIDB.castbar[key] = value
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
	KUIDB.statusbars[key] = value
	if key == "enabled" then
		NeedsReload("XP/reputation bar")
	elseif key == "texture" then
		ns:StyleStatusBars()
	else
		ns:LayoutStatusBars()
	end
end

local function SetNameplates(key, value)
	KUIDB.nameplates[key] = value
	if key == "enabled" then
		NeedsReload("nameplate")
	else
		-- Layout also re-applies the border, including the target highlight
		ns:LayoutNameplates()
	end
end

local function SetActionBars(key, value)
	KUIDB.actionbars[key] = value
	if key == "enabled" then
		NeedsReload("action bar styling")
	else
		ns:StyleActionBars()
	end
end

-- get/set pair for KUIDB[section][key], for the trailing get, set arguments
-- of the widgets. percent: stored as 0-1, shown as 0-100.
local function Bind(section, key, setter, percent)
	if percent then
		return function() return math.floor(KUIDB[section][key] * 100 + 0.5) end,
			function(v) setter(key, v / 100) end
	end
	return function() return KUIDB[section][key] end,
		function(v) setter(key, v) end
end

-- Color overrides; kind is one of ns.colorKinds, a nil value removes the
-- override
local function SetColor(kind, key, value)
	KUIDB.colors[kind][key] = value
	ns:ApplyStyle()
end

-- Choosing a palette clears individual overrides so it shows as designed
local function SetPalette(name)
	KUIDB.colors.palette = name
	for _, kind in ipairs(ns.colorKinds) do
		wipe(KUIDB.colors[kind])
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
-- Panel
---------------------------------------------------------------------------

-- Width slider labels; units sharing another's width aren't listed
local WIDTH_LABELS = {
	player = "Player",
	target = "Target",
	targettarget = "Focus / Target of Target",
	pet = "Pet",
	party1 = "Party",
}
local REACTION_LABELS = { hostile = "Hostile", neutral = "Neutral", friendly = "Friendly" }
local CAST_LABELS = { cast = "Casting", channel = "Channeling", failed = "Failed / interrupted" }

-- Returns the content height
local function BuildPanel(panel)
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("KUI")

	local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	subtitle:SetText("Unit frame settings. Changes apply immediately; all frames are shown while this panel is open.")

	-- Simple top-down stacking
	local y = -64
	local function Place(region, extraGap)
		region:SetPoint("TOPLEFT", 16, y)
		y = y - (region.GetHeight and region:GetHeight() > 0 and region:GetHeight() or 16) - (extraGap or 0)
	end

	local function Section(text)
		if y < -64 then y = y - 12 end
		Place(CreateHeader(panel, text), 6)
	end
	local function Slider(...) Place(CreateSlider(panel, ...)) end
	local function Dropdown(...) Place(CreateDropdown(panel, ...)) end
	local function Checkbox(...) Place(CreateCheckbox(panel, ...)) end
	local function Swatch(...) Place(CreateColorSwatch(panel, ...)) end
	local function ColorRow(kind, key, label)
		Swatch(label,
			function() return ns:GetColor(kind, key) end,
			function(v) SetColor(kind, key, v) end,
			function() SetColor(kind, key, nil) end)
	end

	Section("Layout")
	Slider("Vertical position", -600, 600, 2, Bind("layout", "y", SetLayout))
	Slider("Distance from center", 0, 400, 1, Bind("layout", "centerGap", SetLayout))
	Slider("Focus / ToT spacing", 0, 100, 1, Bind("layout", "sideGap", SetLayout))

	Section("Party")
	Slider("Horizontal position", 0, 1000, 2, Bind("layout", "partyX", SetLayout))
	Slider("Vertical position", -1000, 0, 2, Bind("layout", "partyY", SetLayout))
	Slider("Spacing", 0, 60, 1, Bind("layout", "partySpacing", SetLayout))
	Slider("Out of range opacity", 0, 100, 5, Bind("style", "outOfRangeAlpha", SetStyle, true))

	Section("Frame width")
	for _, unit in ipairs(ns.unitOrder) do
		if not ns.units[unit].widthFrom then
			Slider(WIDTH_LABELS[unit] or unit, 60, 400, 2,
				function() return ns:GetWidth(unit) end,
				function(v)
					KUIDB.widths[unit] = v
					Relayout()
				end)
		end
	end

	Section("Text")
	Dropdown("Font", FontList, Bind("style", "font", SetStyle))
	Slider("Font size", 8, 16, 1, Bind("style", "fontSize", SetStyle))

	Section("Bars")
	Dropdown("Health bar", StatusbarList, Bind("style", "healthTexture", SetStyle))
	Dropdown("Power bar", StatusbarList, Bind("style", "powerTexture", SetStyle))
	Slider("Power bar height", 2, 20, 1, Bind("style", "powerHeight", SetStyle))
	Swatch("Empty bar color", Bind("style", "emptyColor", SetStyle))
	Slider("Empty bar opacity", 0, 100, 5, Bind("style", "emptyAlpha", SetStyle, true))

	Section("Cast bar")
	Slider("Focus cast bar height", 6, 30, 1, Bind("castbar", "focusHeight", SetCastbar))
	Slider("Height (player/target)", 4, 24, 1, Bind("castbar", "height", SetCastbar))
	Dropdown("Texture", StatusbarList, Bind("castbar", "texture", SetCastbar))
	Checkbox("Show spell icon", Bind("castbar", "showIcon", SetCastbar))

	Section("Color palette")
	Dropdown("Palette", function() return ns.paletteOrder end,
		function() return KUIDB.colors.palette end, SetPalette)

	Section("Class colors (health)")
	for _, class in ipairs(ns.classOrder) do
		ColorRow("class", class, LOCALIZED_CLASS_NAMES_MALE[class] or class)
	end

	Section("Reaction colors (NPC health)")
	for _, key in ipairs(ns.reactionOrder) do
		ColorRow("reaction", key, REACTION_LABELS[key])
	end

	Section("Power colors")
	for _, token in ipairs(ns.powerOrder) do
		ColorRow("power", token, _G[token] or token)
	end

	Section("Cast bar colors")
	for _, key in ipairs(ns.castOrder) do
		ColorRow("cast", key, CAST_LABELS[key])
	end

	Section("XP / reputation bars")
	Checkbox("Replace XP/rep bars", Bind("statusbars", "enabled", SetStatusBars))
	Dropdown("Position", function() return { "Top", "Bottom" } end, Bind("statusbars", "position", SetStatusBars))
	Slider("Width", 100, 1200, 4, Bind("statusbars", "width", SetStatusBars))
	Slider("Height", 4, 30, 1, Bind("statusbars", "height", SetStatusBars))
	Dropdown("Texture", StatusbarList, Bind("statusbars", "texture", SetStatusBars))

	Section("Nameplates")
	Checkbox("Restyle nameplates", Bind("nameplates", "enabled", SetNameplates))
	Slider("Width", 60, 240, 2, Bind("nameplates", "width", SetNameplates))
	Slider("Health height", 6, 30, 1, Bind("nameplates", "height", SetNameplates))
	Slider("Cast bar height", 6, 24, 1, Bind("nameplates", "castHeight", SetNameplates))
	Checkbox("Highlight target", Bind("nameplates", "highlightTarget", SetNameplates))
	Swatch("Target border color", Bind("nameplates", "targetColor", SetNameplates))

	Section("Action bars")
	Checkbox("Restyle action bars", Bind("actionbars", "enabled", SetActionBars))
	Checkbox("Show keybinds", Bind("actionbars", "showHotkeys", SetActionBars))
	Checkbox("Show macro names", Bind("actionbars", "showMacroNames", SetActionBars))
	Checkbox("Red icons out of range", Bind("actionbars", "rangeColor", SetActionBars))
	Swatch("Active border color", Bind("actionbars", "activeColor", SetActionBars))

	Section("Border")
	Dropdown("Style", BorderList, Bind("style", "border", SetStyle))
	Slider("Thickness", 1, 24, 1, Bind("style", "borderSize", SetStyle))
	Swatch("Color", Bind("style", "borderColor", SetStyle))
	Slider("Padding", 0, 6, 1, Bind("style", "padding", SetStyle))
	Slider("Background opacity", 0, 100, 5, Bind("style", "bgAlpha", SetStyle, true))

	y = y - 16
	local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	reset:SetSize(140, 24)
	Place(reset)
	reset:SetText("Reset to defaults")
	reset:SetScript("OnClick", ResetToDefaults)

	return -y + 16
end

function ns:InitConfig()
	local panel = CreateFrame("Frame")

	-- Settings doesn't scroll canvas panels itself, and ours is taller than
	-- the visible area
	local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -4)
	scroll:SetPoint("BOTTOMRIGHT", -28, 4)

	local content = CreateFrame("Frame", nil, scroll)
	content:SetWidth(LABEL_WIDTH + CONTROL_WIDTH + 100)
	content:SetHeight(BuildPanel(content))
	scroll:SetScrollChild(content)

	-- Show every frame while the panel is open so the layout is visible
	panel:SetScript("OnShow", function()
		RefreshAll()
		if not InCombatLockdown() then ns:SetPreview(true) end
	end)
	panel:SetScript("OnHide", function()
		if not InCombatLockdown() then ns:SetPreview(false) end
	end)

	-- Hooks the Settings panel calls for canvas categories
	panel.OnRefresh = RefreshAll
	panel.OnDefault = ResetToDefaults

	category = Settings.RegisterCanvasLayoutCategory(panel, "KUI")
	Settings.RegisterAddOnCategory(category)
end

function ns:OpenConfig()
	if InCombatLockdown() then
		return ns.Print("can't open settings in combat.")
	end
	Settings.OpenToCategory(category:GetID())
end
