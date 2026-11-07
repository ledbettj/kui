local _, ns = ...

-- QuestBrosDB.chars["Name-Realm"] holds what we know about one character:
--   epoch   when the character's history began; a reinstall starts a new one
--   log     its completed quests as an append-only list of changes: +questID
--           when completed, -questID when no longer flagged (daily resets).
--           Every copy of the log is a prefix of the owner's, so two copies
--           compare by length alone.
--   rev     version of `active`, which only its owner bumps
--   active  [questID] = "r" (ready to turn in), "3/8" or "" for quests in its log
--   asof    server time the owner last vouched for this data
--   mine    this account's own character, kept up to date locally

local doneSets = {} -- owner -> set of completed questIDs, rebuilt from the log

function ns.GetEntry(owner)
	return ns.db.chars[owner]
end

function ns.CreateEntry(owner, epoch)
	local entry = { epoch = epoch, log = {}, rev = 0, active = {}, asof = 0 }
	ns.db.chars[owner] = entry
	doneSets[owner] = nil
	return entry
end

local function Apply(done, op)
	if op > 0 then
		done[op] = true
	else
		done[-op] = nil
	end
end

function ns.DoneSet(owner)
	local done = doneSets[owner]
	if not done then
		done = {}
		for _, op in ipairs(ns.db.chars[owner].log) do
			Apply(done, op)
		end
		doneSets[owner] = done
	end
	return done
end

-- Adds changes that start at log position `start`, skipping any we already
-- have. False if they'd leave a gap.
function ns.AppendLog(owner, start, ops)
	local log = ns.db.chars[owner].log
	if start > #log + 1 then return false end
	local done = ns.DoneSet(owner)
	for i, op in ipairs(ops) do
		if start + i - 1 == #log + 1 then
			log[#log + 1] = op
			Apply(done, op)
		end
	end
	return true
end
