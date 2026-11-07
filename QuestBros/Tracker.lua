local _, ns = ...

-- Keeps this character's own entry in step with the game

function ns.InitOwnEntry()
	local entry = ns.GetEntry(ns.me) or ns.CreateEntry(ns.me, GetServerTime())
	entry.mine = true
	ns.TouchOwnEntry()
end

function ns.TouchOwnEntry()
	ns.GetEntry(ns.me).asof = GetServerTime()
end

-- The server's flags decide what's done rather than QUEST_TURNED_IN, so
-- repeatable quests and daily resets come out right
function ns.ScanCompleted()
	local ids = C_QuestLog.GetAllCompletedQuestIDs()
	local done = ns.DoneSet(ns.me)
	-- Not loaded yet, rather than every quest having been unflagged
	if #ids == 0 and next(done) then return end

	table.sort(ids)
	local flagged, ops = {}, {}
	for _, id in ipairs(ids) do
		flagged[id] = true
		if not done[id] then ops[#ops + 1] = id end
	end
	for id in pairs(done) do
		if not flagged[id] then ops[#ops + 1] = -id end
	end

	if #ops > 0 then
		ns.AppendLog(ns.me, #ns.GetEntry(ns.me).log + 1, ops)
		ns.MarkDirty(ns.me)
	end
end

local function QuestProgress(id)
	if C_QuestLog.ReadyForTurnIn(id) or C_QuestLog.IsComplete(id) then
		return "r"
	end
	local fulfilled, required = 0, 0
	for _, objective in ipairs(C_QuestLog.GetQuestObjectives(id) or {}) do
		fulfilled = fulfilled + (objective.numFulfilled or 0)
		required = required + (objective.numRequired or 0)
	end
	return required > 0 and (fulfilled .. "/" .. required) or ""
end

local function SameQuests(a, b)
	for id, progress in pairs(a) do
		if b[id] ~= progress then return false end
	end
	for id in pairs(b) do
		if a[id] == nil then return false end
	end
	return true
end

function ns.ScanActive()
	local entry = ns.GetEntry(ns.me)
	local active = {}
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and not info.isHidden then
			active[info.questID] = QuestProgress(info.questID)
		end
	end
	-- Quests under a collapsed header may not be listed; they stay until
	-- they've really left the log
	for id in pairs(entry.active) do
		if active[id] == nil and C_QuestLog.IsOnQuest(id) then
			active[id] = QuestProgress(id)
		end
	end

	if not SameQuests(active, entry.active) then
		entry.active = active
		entry.rev = entry.rev + 1
		ns.MarkDirty(ns.me)
	end
end
