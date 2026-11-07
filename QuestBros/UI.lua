local _, ns = ...

-- Two displays of the same data:
--   - Counts on each row of the quest log list, with a tooltip of names
--   - A small panel beside each window that shows one quest, including at
--     quest givers. They sit outside Blizzard's windows rather than in their
--     scroll areas, so they can't disturb the layout, and as their children
--     they hide along with them. The windows can be open together, so each
--     gets its own.

local PADDING = 8
local STALE_AFTER = 3600 -- seconds before a name says how old its data is
local BADGE_WIDTH = 46 -- room for four numbers at the end of a quest log row

local COLOR_ZERO = "555555"
local COLOR_AGE = "808080"

-- In the order the counts appear
local CATEGORIES = {
	{ key = "done", label = "Completed", color = "66ff66" },
	{ key = "notdone", label = "Not completed", color = "ff6666" },
	{ key = "active", label = "Active", color = "ffd100" },
	{ key = "unknown", label = "Unknown", color = "a0a0ff" },
}
local CATEGORY_COLOR = {}
for _, category in ipairs(CATEGORIES) do
	CATEGORY_COLOR[category.key] = category.color
end

local panels = {} -- window -> panel
local badges = {} -- quest log row -> badge

function ns.FormatAge(when)
	local age = GetServerTime() - when
	if when == 0 then return "never" end
	if age < 60 then return "just now" end
	if age < 3600 then return format("%dm ago", age / 60) end
	if age < 86400 then return format("%dh ago", age / 3600) end
	return format("%dd ago", age / 86400)
end

-- A character's category for a quest, plus its progress if it's active.
-- Unknown means we've no complete data for them yet, so "not completed"
-- can't be claimed; old data still counts, with its age shown beside the name.
local function Classify(owner, questID)
	local entry = ns.GetEntry(owner)
	local progress = entry.active[questID]
	if progress then return "active", progress end
	if ns.DoneSet(owner)[questID] then return "done" end
	if entry.asof == 0 or ns.IsSyncing(owner) then return "unknown" end
	return "notdone"
end

local function SortedOwners()
	local owners = {}
	for owner in pairs(ns.db.chars) do
		if owner ~= ns.me then owners[#owners + 1] = owner end
	end
	table.sort(owners)
	return owners
end

local function DisplayName(owner)
	return Ambiguate(owner, "short") .. (ns.GetEntry(owner).mine and " (alt)" or "")
end

local function AgeSuffix(owner)
	local asof = ns.GetEntry(owner).asof
	if GetServerTime() - asof > STALE_AFTER then
		return format(" |cff%s(as of %s)|r", COLOR_AGE, ns.FormatAge(asof))
	end
	return ""
end

local function ActiveText(progress)
	if progress == "r" then return "ready to turn in" end
	if progress == "" then return "on it" end
	return format("on it (%s)", progress)
end

---------------------------------------------------------------------------
-- Quest log rows
---------------------------------------------------------------------------

-- category key -> list of tooltip lines' names, for everyone we know about
function ns.GroupByCategory(questID)
	local groups = {}
	for _, category in ipairs(CATEGORIES) do
		groups[category.key] = {}
	end
	for _, owner in ipairs(SortedOwners()) do
		local key, progress = Classify(owner, questID)
		local name = DisplayName(owner)
		if key == "active" then
			name = format("%s: %s", name, ActiveText(progress))
		end
		local group = groups[key]
		group[#group + 1] = name .. AgeSuffix(owner)
	end
	return groups
end

local function ShowBadgeTooltip(badge)
	local groups = ns.GroupByCategory(badge.questID)
	GameTooltip:SetOwner(badge, "ANCHOR_RIGHT")
	GameTooltip:SetText("Friends on this quest")
	for _, category in ipairs(CATEGORIES) do
		local names = groups[category.key]
		if #names > 0 then
			GameTooltip:AddLine(format("|cff%s%s (%d)|r", category.color, category.label, #names))
			for _, name in ipairs(names) do
				GameTooltip:AddLine(name, 1, 1, 1)
			end
		end
	end
	GameTooltip:Show()
end

local function CreateBadge(row)
	local badge = CreateFrame("Frame", nil, row)
	badge:SetSize(BADGE_WIDTH, 14)
	badge:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -8)
	badge:EnableMouse(true)
	badge:SetScript("OnEnter", ShowBadgeTooltip)
	badge:SetScript("OnLeave", GameTooltip_Hide)

	badge.text = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	badge.text:SetPoint("RIGHT")
	badge.text:SetJustifyH("RIGHT")

	-- Make room. The title, tag and storyline icon all anchor off the
	-- checkbox, so they shift over with it. Titles laid out before this runs
	-- are corrected on the log's next refresh.
	row.Checkbox:SetPoint("TOPRIGHT", -BADGE_WIDTH, -8)
	return badge
end

local function BadgeText(questID)
	local groups = ns.GroupByCategory(questID)
	local parts = {}
	for i, category in ipairs(CATEGORIES) do
		local count = #groups[category.key]
		parts[i] = format("|cff%s%d|r", count > 0 and category.color or COLOR_ZERO, count)
	end
	return table.concat(parts, " ")
end

local function UpdateBadges()
	if #SortedOwners() == 0 then return end
	for row in QuestScrollFrame.titleFramePool:EnumerateActive() do
		local badge = badges[row]
		if not badge then
			badge = CreateBadge(row)
			badges[row] = badge
		end
		badge.questID = row.questID
		badge.text:SetText(BadgeText(row.questID))
	end
end

---------------------------------------------------------------------------
-- Single quest panels
---------------------------------------------------------------------------

local function StatusText(owner, questID)
	local key, progress = Classify(owner, questID)
	local text
	if key == "active" then
		text = ActiveText(progress)
	elseif key == "done" then
		text = "done"
	elseif key == "notdone" then
		text = "not done"
	else
		text = ns.IsSyncing(owner) and "syncing..." or "no data yet"
	end
	return format("|cff%s%s|r", CATEGORY_COLOR[key], text)
end

-- One line per other character we know about, or nil if there are none
function ns.BuildLines(questID)
	local owners = SortedOwners()
	if #owners == 0 then return nil end

	local lines = {}
	for _, owner in ipairs(owners) do
		lines[#lines + 1] = format("%s: %s%s", DisplayName(owner), StatusText(owner, questID), AgeSuffix(owner))
	end
	return lines
end

local function RefreshPanel(panel)
	local lines = panel.questID and ns.BuildLines(panel.questID)
	if not lines then return panel:SetAlpha(0) end
	panel:SetAlpha(1)
	panel.text:SetText(table.concat(lines, "\n"))
	panel:SetSize(panel.text:GetStringWidth() + PADDING * 2, panel.text:GetStringHeight() + PADDING * 2)
end

-- Called whenever quest data changes
function ns.RefreshPanel()
	for _, panel in pairs(panels) do
		if panel:IsShown() then RefreshPanel(panel) end
	end
	if QuestScrollFrame:IsVisible() then UpdateBadges() end
end

local function CreatePanel(window, point, relativePoint)
	local panel = CreateFrame("Frame", nil, window, "BackdropTemplate")
	panel:SetPoint(point, window, relativePoint)
	panel:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	panel:SetBackdropColor(0, 0, 0, 0.85)
	panel:SetBackdropBorderColor(0, 0, 0, 1)
	panel:SetClampedToScreen(true)
	panel:Hide()
	panel:SetScript("OnShow", RefreshPanel)

	panel.text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.text:SetPoint("TOPLEFT", PADDING, -PADDING)
	panel.text:SetJustifyH("LEFT")
	return panel
end

local function ShowFor(window, questID, point, relativePoint)
	local panel = panels[window]
	if not panel then
		panel = CreatePanel(window, point, relativePoint)
		panels[window] = panel
	end
	if not questID or questID == 0 then return panel:Hide() end
	panel.questID = questID
	panel:SetFrameLevel(window:GetFrameLevel() + 50)
	panel:Show()
	RefreshPanel(panel)
end

function ns.InitUI()
	-- Quest givers
	for _, questPanel in ipairs({ QuestFrameDetailPanel, QuestFrameProgressPanel, QuestFrameRewardPanel }) do
		questPanel:HookScript("OnShow", function()
			ShowFor(QuestFrame, GetQuestID(), "TOPLEFT", "TOPRIGHT")
		end)
	end
	QuestFrameGreetingPanel:HookScript("OnShow", function()
		if panels[QuestFrame] then panels[QuestFrame]:Hide() end
	end)

	-- Quest log. To the left of the details, over the map: the log is at the
	-- screen edge when the map is maximized, with no room on its right.
	hooksecurefunc("QuestMapFrame_ShowQuestDetails", function(questID)
		ShowFor(QuestMapFrame.DetailsFrame, questID, "TOPRIGHT", "TOPLEFT")
	end)
	hooksecurefunc(QuestLogPopupDetailFrame, "Update", function(self)
		ShowFor(self, self.questID, "TOPLEFT", "TOPRIGHT")
	end)
	hooksecurefunc("QuestLogQuests_Update", UpdateBadges)
end
