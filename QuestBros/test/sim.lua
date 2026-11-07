-- Runs simulated clients against each other, with the WoW API stubbed and
-- messages delivered through a fake network. Run: lua5.1 test/sim.lua

local ADDON_FILES = { "Core.lua", "Store.lua", "Tracker.lua", "Sync.lua", "UI.lua" }

local clock = 1000000
local timers = {}
local clients = {}
local longest = 0

local function NoOp() end

local function Stub()
	return setmetatable({ GetFrameLevel = function() return 1 end }, { __index = function() return NoOp end })
end

local function After(delay, fn)
	timers[#timers + 1] = { at = clock + delay, fn = fn }
end

local function Tick(seconds)
	for _ = 1, seconds do
		clock = clock + 1
		local due = timers
		timers = {}
		for _, timer in ipairs(due) do
			if not timer.owner or timer.owner.online then
				if timer.at <= clock then
					timer.fn()
					if timer.every then
						timer.at = clock + timer.every
						timers[#timers + 1] = timer
					end
				else
					timers[#timers + 1] = timer
				end
			end
		end
	end
end

local function Split(sep, text)
	local out, from = {}, 1
	while true do
		local at = text:find(sep, from, true)
		if not at then
			out[#out + 1] = text:sub(from)
			return unpack(out)
		end
		out[#out + 1] = text:sub(from, at - 1)
		from = at + 1
	end
end

local Codes = { Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8, AddOnMessageLockdown = 11, TargetOffline = 12 }

local function NewClient(name, friendNames)
	local client = {
		name = name,
		friends = friendNames,
		completed = {},
		log = {},
		online = false,
		sv = nil,
		printed = {},
		hooks = {},
		rows = {},
	}
	clients[name] = client
	return client
end

-- Loads the addon fresh, as logging in does, keeping saved variables
local function Login(client)
	client.online = true
	local ns = {}
	local eventFrame
	local env = {
		print = function(...) client.printed[#client.printed + 1] = table.concat({ ... }, " ") end,
		format = string.format,
		strtrim = function(s) return s:match("^%s*(.-)%s*$") end,
		strsplit = Split,
		issecretvalue = function() return false end,
		Ambiguate = function(n) return (n:match("^[^-]+")) end,
		GetTime = function() return clock end,
		GetServerTime = function() return clock end,
		GetNormalizedRealmName = function() return "Realm" end,
		UnitName = function() return client.name end,
		InCombatLockdown = function() return false end,
		QuestBrosDB = client.sv,
		SlashCmdList = {},
		UIParent = Stub(),
		Enum = { SendAddonMessageResult = Codes },
		C_Timer = {
			After = function(delay, fn)
				timers[#timers + 1] = { at = clock + delay, fn = fn, owner = client }
			end,
			NewTicker = function(every, fn)
				timers[#timers + 1] = { at = clock + every, every = every, fn = fn, owner = client }
			end,
		},
		C_ChatInfo = {
			RegisterAddonMessagePrefix = NoOp,
			SendAddonMessage = function(prefix, text, channel, target)
				assert(#text <= 255, "message too long: " .. #text)
				longest = math.max(longest, #text)
				local peer = clients[target:match("^[^-]+")]
				if not (peer and peer.online) then return Codes.TargetOffline end
				After(0, function()
					if peer.online then
						peer.fire("CHAT_MSG_ADDON", prefix, text, channel, client.name .. "-Realm")
					end
				end)
				return Codes.Success
			end,
		},
		C_FriendList = {
			ShowFriends = NoOp,
			GetNumFriends = function() return #client.friends end,
			GetFriendInfoByIndex = function(i)
				local friend = client.friends[i]
				return { name = friend, connected = clients[friend] and clients[friend].online }
			end,
		},
		C_QuestLog = {
			GetAllCompletedQuestIDs = function()
				local ids = {}
				for id in pairs(client.completed) do ids[#ids + 1] = id end
				return ids
			end,
			GetNumQuestLogEntries = function() return #client.log end,
			GetInfo = function(i) return { questID = client.log[i].id } end,
			ReadyForTurnIn = function(id)
				for _, q in ipairs(client.log) do
					if q.id == id then return q.ready end
				end
			end,
			IsComplete = function() return false end,
			IsOnQuest = function(id)
				for _, q in ipairs(client.log) do
					if q.id == id then return true end
				end
				return false
			end,
			GetQuestObjectives = function(id)
				for _, q in ipairs(client.log) do
					if q.id == id and q.required then
						return { { numFulfilled = q.fulfilled, numRequired = q.required } }
					end
				end
				return {}
			end,
		},
		CreateFrame = function()
			local frame = Stub()
			frame.SetScript = function(self, script, fn)
				if script == "OnEvent" then eventFrame = { frame = self, fn = fn } end
				if script == "OnEnter" then client.lastEnter = function() fn(self) end end
			end
			frame.CreateFontString = function()
				return setmetatable({
					GetStringWidth = function() return 1 end,
					GetStringHeight = function() return 1 end,
					SetText = function(_, text) client.lastText = text end,
				}, getmetatable(frame))
			end
			frame.IsShown = function() return true end
			return frame
		end,
		hooksecurefunc = function(target, method)
			if type(target) == "string" then client.hooks[target] = method end
		end,
		QuestFrame = Stub(),
		QuestMapFrame = { DetailsFrame = Stub() },
		QuestScrollFrame = {
			IsVisible = function() return true end,
			titleFramePool = {
				EnumerateActive = function()
					local i = 0
					return function()
						i = i + 1
						return client.rows[i]
					end
				end,
			},
		},
		GameTooltip = {
			SetOwner = NoOp,
			SetText = function(_, text) client.tooltip = { text } end,
			AddLine = function(_, text) client.tooltip[#client.tooltip + 1] = text end,
			Show = NoOp,
		},
		GameTooltip_Hide = NoOp,
		QuestFrameDetailPanel = Stub(), QuestFrameProgressPanel = Stub(), QuestFrameRewardPanel = Stub(),
		QuestFrameGreetingPanel = Stub(), QuestLogPopupDetailFrame = Stub(),
	}
	env._G = env
	setmetatable(env, { __index = _G })

	for _, file in ipairs(ADDON_FILES) do
		local chunk = assert(loadfile(file))
		setfenv(chunk, env)
		chunk("QuestBros", ns)
	end

	client.ns = ns
	client.fire = function(event, ...)
		if client.online then eventFrame.fn(eventFrame.frame, event, ...) end
	end
	client.fire("ADDON_LOADED", "QuestBros")
	client.fire("PLAYER_LOGIN")
	client.sv = env.QuestBrosDB
	client.env = env
	client.fire("FRIENDLIST_UPDATE")
	-- Friends already online see this one arrive
	for _, other in pairs(clients) do
		if other ~= client and other.online then other.fire("FRIENDLIST_UPDATE") end
	end
end

local function Logout(client)
	client.fire("PLAYER_LOGOUT")
	client.online = false
	for _, other in pairs(clients) do
		if other ~= client and other.online then other.fire("FRIENDLIST_UPDATE") end
	end
end

local failures = 0
local function Check(label, actual, expected)
	if actual ~= expected then
		failures = failures + 1
		print(("FAIL %s: expected %q, got %q"):format(label, tostring(expected), tostring(actual)))
	else
		print("ok   " .. label)
	end
end

-- Status text of `owner` as seen by `viewer`, without its color codes
local function Status(viewer, owner, quest)
	for _, line in ipairs(viewer.ns.BuildLines(quest) or {}) do
		local who, rest = line:match("^([^:]+): (.*)$")
		if who == owner then
			return (rest:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub(" %(as of .*$", ""))
		end
	end
	return nil
end

local alice = NewClient("Alice", { "Bob", "Carol" })
local bob = NewClient("Bob", { "Alice", "Carol" })
local carol = NewClient("Carol", { "Alice", "Bob" })

-- Alice and Bob overlap; Carol hasn't played yet
alice.completed = { [101] = true, [102] = true }
alice.log = { { id = 201, fulfilled = 3, required = 8 }, { id = 202, ready = true } }
Login(alice)
Login(bob)
Tick(60)
Check("direct: done", Status(bob, "Alice", 101), "done")
Check("direct: in progress", Status(bob, "Alice", 201), "on it (3/8)")
Check("direct: ready", Status(bob, "Alice", 202), "ready to turn in")
Check("direct: not done", Status(bob, "Alice", 999), "not done")

-- The point of it all: Alice leaves, then Carol hears about her from Bob
Logout(alice)
Login(carol)
Tick(60)
Check("gossip: done, owner offline", Status(carol, "Alice", 102), "done")
Check("gossip: in progress, owner offline", Status(carol, "Alice", 201), "on it (3/8)")

-- Saved data survives logging out with nobody else around
Logout(bob)
Logout(carol)
Login(carol)
Tick(10)
Check("saved: survives a relog", Status(carol, "Alice", 101), "done")
Logout(carol)

-- Changes while connected, sent as deltas, then relayed to a third client
Login(alice)
Login(bob)
Tick(60)
alice.completed[103] = true
alice.log[1].fulfilled = 5
alice.fire("QUEST_TURNED_IN")
alice.fire("QUEST_LOG_UPDATE")
Tick(60)
Check("update: new completion", Status(bob, "Alice", 103), "done")
Check("update: new progress", Status(bob, "Alice", 201), "on it (5/8)")
Check("update: sent only the change", #bob.sv.chars["Alice-Realm"].log, 3)
Login(carol)
Tick(60)
Check("relay: reaches the third client", Status(carol, "Alice", 103), "done")

-- A daily resetting unflags the quest
alice.completed[103] = nil
alice.fire("QUEST_TURNED_IN")
Tick(60)
Check("reset: unflagged quest", Status(bob, "Alice", 103), "not done")

-- An empty completed list at login isn't taken as everything being undone
alice.completed = {}
alice.fire("QUEST_TURNED_IN")
Tick(60)
Check("guard: empty list ignored", Status(bob, "Alice", 101), "done")
alice.completed = { [101] = true, [102] = true }

-- A full history, big enough to span many messages
Logout(carol)
for id = 5000, 8000 do alice.completed[id] = true end
alice.fire("QUEST_TURNED_IN")
Tick(30)
Check("large: partly through while syncing", bob.ns.IsSyncing("Alice-Realm"), true)
Tick(300)
Check("large: first id", Status(bob, "Alice", 5000), "done")
Check("large: last id", Status(bob, "Alice", 8000), "done")
Check("large: finished syncing", bob.ns.IsSyncing("Alice-Realm"), false)
print("     longest message: " .. longest .. " bytes")

-- A long quest log spans several messages
alice.log = {}
for id = 300000, 300034 do alice.log[#alice.log + 1] = { id = id, fulfilled = 10, required = 20 } end
alice.fire("QUEST_LOG_UPDATE")
Tick(60)
Check("active: multi-part snapshot", Status(bob, "Alice", 300034), "on it (10/20)")

-- Reinstalling starts a new history, which replaces the old copies
Logout(alice)
alice.sv = nil
alice.completed = { [777] = true }
alice.log = {}
clock = clock + 100
Login(alice)
Tick(60)
Check("reinstall: new data", Status(bob, "Alice", 777), "done")
Check("reinstall: old data gone", Status(bob, "Alice", 101), "not done")

-- Friends can't feed in data about strangers
local function Send(from, to, text)
	to.fire("CHAT_MSG_ADDON", "QuestBros", text, "WHISPER", from .. "-Realm")
end
Send("Alice", bob, "D;1;Mallory-Realm;1;5;1;" .. clock)
Send("Alice", bob, "L;1;Mallory-Realm;1;1;2s")
Check("trust: stranger as subject", bob.sv.chars["Mallory-Realm"], nil)
Send("Mallory", bob, "L;1;Alice-Realm;" .. bob.sv.chars["Alice-Realm"].epoch .. ";1;zzz")
Check("trust: stranger as sender", Status(bob, "Alice", tonumber("zzz", 36)), "not done")

-- Our own characters' data can't be overwritten by anyone, even for an alt
-- that's on our friends list and so passes the trust check
bob.sv.chars["Bobalt-Realm"] = { epoch = 1, log = {}, rev = 0, active = {}, asof = 0, mine = true }
bob.friends[#bob.friends + 1] = "Bobalt"
bob.fire("FRIENDLIST_UPDATE")
Send("Alice", bob, "A;1;Bobalt-Realm;1;99;1;1;1;zz=r")
Check("trust: own alt protected", bob.sv.chars["Bobalt-Realm"].rev, 0)

-- Parts from two senders don't combine, since each splits the quests differently
local epoch = bob.sv.chars["Alice-Realm"].epoch
local rev = bob.sv.chars["Alice-Realm"].rev
local header = "A;1;Alice-Realm;" .. epoch .. ";" .. (rev + 1) .. ";" .. clock
Send("Carol", bob, header .. ";1;2;zz=r")
Send("Alice", bob, header .. ";2;2;zy=r")
Check("parts: two senders don't combine", bob.sv.chars["Alice-Realm"].rev, rev)
Send("Alice", bob, header .. ";1;2;zz=r")
Check("parts: one sender completes", bob.sv.chars["Alice-Realm"].rev, rev + 1)

-- Garbage must not raise errors
for _, text in ipairs({
	"", "x", "D", "D;1", "D;1;;;;", "D;1;Alice-Realm;a;b;c;d", "L;1;Alice-Realm;1;1;!!!", "A;1;Alice-Realm;1;1;1;0;1;x",
	"A;1;Alice-Realm;1;2;1;1;1;bad", "R;1;Alice-Realm;1;0", "R;1", ";;;;;", "H", "H;x", "H;999",
}) do
	Send("Alice", bob, text)
end
Check("version: warns about newer", #bob.printed > 0, true)
Tick(60)

-- Quest log rows, as Bob sees quest 1295: Alice is active (from the parts test
-- above), Carol hasn't done it, and his alt has no data yet
local function Plain(text)
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
local row = { questID = tonumber("zz", 36), Checkbox = { SetPoint = NoOp } }
local moved
row.Checkbox.SetPoint = function(_, _, x) moved = x end
bob.rows = { row }
bob.hooks.QuestLogQuests_Update()
Check("rows: counts are done, not done, active, unknown", Plain(bob.lastText), "0 1 1 1")
Check("rows: makes room for the counts", moved, -46)

bob.lastEnter()
local tooltip = Plain(table.concat(bob.tooltip, "\n")):gsub(" %(as of [^)]*%)", "")
Check("rows: tooltip names everyone by category", tooltip, table.concat({
	"Friends on this quest",
	"Not completed (1)", "Carol",
	"Active (1)", "Alice: ready to turn in",
	"Unknown (1)", "Bobalt (alt)",
}, "\n"))

row.questID = 777
bob.hooks.QuestLogQuests_Update()
Check("rows: a reused row shows its new quest", Plain(bob.lastText), "1 1 0 1")

-- The single quest panel and its data refreshes
bob.hooks.QuestMapFrame_ShowQuestDetails(777)
Check("panel: lists everyone", Plain(bob.lastText):match("^[^\n]+"), "Alice: done")
bob.ns.RefreshPanel()

print(failures == 0 and "\nall passed" or ("\n" .. failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
