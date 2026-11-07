local _, ns = ...

-- Gossip between online friends. Addons can't reach an offline player, so
-- everyone keeps a copy of everyone's data and passes it along: Bob can give
-- you Alice's quests while Alice is offline. Friends without the addon never
-- see any of this; addon messages don't show in chat.
--
-- Messages are ;-separated, starting with a type and the protocol version:
--   H                          "send me your digests"
--   D owner epoch seq rev asof a digest: the newest I have of owner's data
--   R owner epoch from         "send owner's log from position `from`, and
--                              their active quests"
--   L owner epoch start ops    part of a log: signed questIDs in base 36
--   A owner epoch rev asof part total items   part of the active quests
--
-- Anyone on your friends list is trusted, along with what they say about
-- characters who are also on your list.

local PREFIX = "QuestBros"
local PROTOCOL = 1
local MAX_MESSAGE = 255

local SEND_INTERVAL = 1 -- well under the game's limit on addon messages
local RETRY_DELAY = 5 -- after the game refuses a message for now
local GOSSIP_DELAY = 15 -- groups the many small changes while questing
local REQUEST_TIMEOUT = 30 -- before asking someone else for the same data

local friends = {} -- name -> online
local peers = {} -- online friends who have answered, so have the addon
local queue = {}
local nextSend = 0
local dirty = {} -- owners changed since the last gossip
local gossipPending = false
local pending = {} -- owner -> GetTime of the last request or data for it
local expected = {} -- owner -> log length we're still fetching
local partial = {} -- owner -> active quest parts being reassembled
local warnedVersion = false

---------------------------------------------------------------------------
-- Encoding
---------------------------------------------------------------------------

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local function EncodeID(n)
	local sign = n < 0 and "-" or ""
	n = math.abs(n)
	local out = ""
	repeat
		local digit = n % 36
		out = DIGITS:sub(digit + 1, digit + 1) .. out
		n = math.floor(n / 36)
	until n == 0
	return sign .. out
end

local function DecodeID(text)
	local sign, digits = text:match("^(%-?)(%w+)$")
	local n = digits and tonumber(digits, 36)
	if not n or n == 0 then return nil end
	return sign == "-" and -n or n
end

local function IsCharacter(name)
	return name:match("^[^%-;,%s]+%-[^%-;,%s]+$") ~= nil
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

local function Enqueue(target, key, ...)
	queue[#queue + 1] = {
		target = target,
		key = key,
		text = table.concat({ select(1, ...) }, ";"),
	}
end

local function DropTarget(target)
	for i = #queue, 1, -1 do
		if queue[i].target == target then table.remove(queue, i) end
	end
end

local function Pump()
	local item = queue[1]
	if not item or GetTime() < nextSend or InCombatLockdown() then return end

	local result = C_ChatInfo.SendAddonMessage(PREFIX, item.text, "WHISPER", item.target)
	local codes = Enum.SendAddonMessageResult
	if result == codes.AddonMessageThrottle or result == codes.ChannelThrottle
		or result == codes.AddOnMessageLockdown then
		nextSend = GetTime() + RETRY_DELAY
		return
	end
	if result == codes.TargetOffline then
		peers[item.target] = nil
		DropTarget(item.target)
		return
	end
	table.remove(queue, 1)
end

local function DigestFor(owner)
	local entry = ns.GetEntry(owner)
	-- We're online, so our own data is current as of right now
	local asof = entry.asof
	if owner == ns.me then asof = GetServerTime() end
	return "D", PROTOCOL, owner, entry.epoch, #entry.log, entry.rev, asof
end

local function SendDigests(target)
	for owner in pairs(ns.db.chars) do
		Enqueue(target, nil, DigestFor(owner))
	end
end

local function Greet(target)
	Enqueue(target, nil, "H", PROTOCOL)
	SendDigests(target)
end

function ns.GreetAll()
	for name, online in pairs(friends) do
		if online then Greet(name) end
	end
end

local function SendLog(target, owner, from)
	local entry = ns.GetEntry(owner)
	local log = entry.log
	local i = from
	while i <= #log do
		local header = table.concat({ "L", PROTOCOL, owner, entry.epoch, i }, ";") .. ";"
		local tokens, length = {}, #header
		while i <= #log do
			local token = EncodeID(log[i])
			if length + #token + 1 > MAX_MESSAGE then break end
			tokens[#tokens + 1] = token
			length = length + #token + 1
			i = i + 1
		end
		queue[#queue + 1] = { target = target, key = owner, text = header .. table.concat(tokens, ",") }
	end
end

local function SendActive(target, owner)
	local entry = ns.GetEntry(owner)
	local asof = entry.asof
	if owner == ns.me then asof = GetServerTime() end

	local header = table.concat({ "A", PROTOCOL, owner, entry.epoch, entry.rev, asof }, ";")
	local room = MAX_MESSAGE - #header - 10 -- leaves space for part and total
	local chunks, current = {}, ""
	for id, progress in pairs(entry.active) do
		local item = EncodeID(id) .. "=" .. progress
		if #current + #item + 1 > room then
			chunks[#chunks + 1] = current
			current = ""
		end
		current = current == "" and item or (current .. "," .. item)
	end
	chunks[#chunks + 1] = current

	for part, chunk in ipairs(chunks) do
		Enqueue(target, owner, header, part, #chunks, chunk)
	end
end

local function Gossip()
	gossipPending = false
	for owner in pairs(dirty) do
		for peer in pairs(peers) do
			Enqueue(peer, nil, DigestFor(owner))
		end
	end
	dirty = {}
end

function ns.MarkDirty(owner)
	dirty[owner] = true
	if not gossipPending then
		gossipPending = true
		C_Timer.After(GOSSIP_DELAY, Gossip)
	end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

-- The entry to update with data about owner, or nil if we shouldn't take it:
-- it's from before the owner's newest reinstall, about one of our own
-- characters, or about a stranger.
local function WritableEntry(owner, epoch)
	if not IsCharacter(owner) or friends[owner] == nil then return nil end
	local entry = ns.GetEntry(owner)
	if entry and entry.mine then return nil end
	if not entry or epoch > entry.epoch then
		partial[owner] = nil
		return ns.CreateEntry(owner, epoch)
	end
	if epoch == entry.epoch then return entry end
	return nil
end

local function FinishIfCaughtUp(owner)
	local entry = ns.GetEntry(owner)
	if expected[owner] and #entry.log >= expected[owner] then
		expected[owner] = nil
	end
	ns.RefreshPanel()
end

local handlers = {}

function handlers.H(sender)
	SendDigests(sender)
end

function handlers.D(sender, owner, epoch, seq, rev, asof)
	epoch, seq, rev, asof = tonumber(epoch), tonumber(seq), tonumber(rev), tonumber(asof)
	if not (owner and epoch and seq and rev and asof) then return end
	if not IsCharacter(owner) or friends[owner] == nil then return end

	local entry = ns.GetEntry(owner)
	if entry and (entry.mine or epoch < entry.epoch) then return end

	local have = entry and entry.epoch == epoch
	local logLength = have and #entry.log or 0
	if have and seq <= logLength and rev <= entry.rev then
		-- Nothing new, but the owner has vouched for it more recently
		if asof > entry.asof then
			entry.asof = asof
			ns.RefreshPanel()
		end
		return
	end

	-- Only their active quests may be new, which isn't worth a "syncing" row
	expected[owner] = seq > logLength and seq or nil
	if GetTime() - (pending[owner] or -REQUEST_TIMEOUT) < REQUEST_TIMEOUT then return end
	pending[owner] = GetTime()
	Enqueue(sender, nil, "R", PROTOCOL, owner, epoch, logLength + 1)
	ns.RefreshPanel()
end

function handlers.R(sender, owner, epoch, from)
	epoch, from = tonumber(epoch), tonumber(from)
	if not (owner and epoch and from) or from < 1 then return end
	local entry = ns.GetEntry(owner)
	if not entry or entry.epoch ~= epoch then return end

	-- Already on its way to them
	for _, item in ipairs(queue) do
		if item.target == sender and item.key == owner then return end
	end
	SendLog(sender, owner, from)
	SendActive(sender, owner)
end

function handlers.L(_, owner, epoch, start, payload)
	epoch, start = tonumber(epoch), tonumber(start)
	if not (owner and epoch and start and payload) or start < 1 then return end

	local ops = {}
	for token in payload:gmatch("[^,]+") do
		local op = DecodeID(token)
		if not op then return end
		ops[#ops + 1] = op
	end

	if not WritableEntry(owner, epoch) then return end
	pending[owner] = GetTime()
	ns.AppendLog(owner, start, ops)
	dirty[owner] = true
	FinishIfCaughtUp(owner)
end

function handlers.A(sender, owner, epoch, rev, asof, part, total, payload)
	epoch, rev, asof = tonumber(epoch), tonumber(rev), tonumber(asof)
	part, total = tonumber(part), tonumber(total)
	if not (owner and epoch and rev and asof and part and total and payload) then return end
	if part < 1 or part > total then return end

	local entry = WritableEntry(owner, epoch)
	if not entry then return end

	-- Per sender: each one splits the same quests into parts differently
	local parts = partial[owner]
	if not parts or parts.rev ~= rev or parts.sender ~= sender then
		parts = { rev = rev, sender = sender }
		partial[owner] = parts
	end
	parts[part] = payload
	pending[owner] = GetTime()
	for i = 1, total do
		if not parts[i] then return end
	end
	partial[owner] = nil

	-- The last message of a transfer, so the data is now as good as the asof
	pending[owner] = nil
	if rev > entry.rev then
		local active = {}
		for i = 1, total do
			for item in parts[i]:gmatch("[^,]+") do
				local idText, progress = item:match("^(%w+)=([%d/r]*)$")
				local id = idText and DecodeID(idText)
				if not id then return end
				active[id] = progress
			end
		end
		entry.active = active
		entry.rev = rev
		dirty[owner] = true
	end
	if asof > entry.asof then entry.asof = asof end
	FinishIfCaughtUp(owner)

	-- Pass it on to anyone else who's online
	if next(dirty) and not gossipPending then
		gossipPending = true
		C_Timer.After(GOSSIP_DELAY, Gossip)
	end
end

function ns.OnAddonMessage(prefix, text, channel, sender)
	if issecretvalue(prefix) or issecretvalue(text) or issecretvalue(sender) then return end
	if prefix ~= PREFIX or channel ~= "WHISPER" then return end

	sender = ns.FullName(sender)
	if sender == ns.me or friends[sender] == nil then return end

	local kind, version = text:match("^(%a);(%d+)")
	version = tonumber(version)
	local handler = kind and handlers[kind]
	if not handler then return end
	if version ~= PROTOCOL then
		if version > PROTOCOL and not warnedVersion then
			warnedVersion = true
			ns.Print(sender, "has a newer QuestBros, so update to keep syncing.")
		end
		return
	end

	peers[sender] = true
	handler(sender, select(3, strsplit(";", text)))
end

---------------------------------------------------------------------------
-- Friends list and setup
---------------------------------------------------------------------------

function ns.RefreshFriends()
	local seen = {}
	for i = 1, C_FriendList.GetNumFriends() do
		local info = C_FriendList.GetFriendInfoByIndex(i)
		if info and info.name then
			local name = ns.FullName(info.name)
			seen[name] = info.connected and true or false
			if seen[name] and not friends[name] then
				Greet(name)
			elseif not seen[name] then
				peers[name] = nil
				DropTarget(name)
			end
		end
	end
	-- Removed from the list altogether, so they stop getting our updates
	for name in pairs(peers) do
		if seen[name] == nil then
			peers[name] = nil
			DropTarget(name)
		end
	end
	friends = seen
end

function ns.InitSync()
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
	C_Timer.NewTicker(SEND_INTERVAL, Pump)
end

-- True while part of this character's completed list is still arriving. Gives
-- up once data stops coming, as when the friend sending it logs off.
function ns.IsSyncing(owner)
	return expected[owner] ~= nil and pending[owner] ~= nil
		and GetTime() - pending[owner] < REQUEST_TIMEOUT
end

function ns.PrintStatus()
	local names = {}
	for peer in pairs(peers) do names[#names + 1] = Ambiguate(peer, "short") end
	table.sort(names)
	ns.Print("connected: " .. (#names > 0 and table.concat(names, ", ") or "nobody")
		.. ", " .. #queue .. " messages waiting")

	local owners = {}
	for owner in pairs(ns.db.chars) do owners[#owners + 1] = owner end
	table.sort(owners)
	for _, owner in ipairs(owners) do
		local entry = ns.GetEntry(owner)
		local count = 0
		for _ in pairs(ns.DoneSet(owner)) do count = count + 1 end
		local active = 0
		for _ in pairs(entry.active) do active = active + 1 end
		ns.Print(format("%s: %d done, %d active, updated %s",
			Ambiguate(owner, "short"), count, active, ns.FormatAge(entry.asof)))
	end
end
