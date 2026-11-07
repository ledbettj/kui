local addonName, ns = ...

-- Startup, event routing and the slash command. The other files:
--   Store.lua    saved per-character quest data
--   Tracker.lua  keeps this character's own entry up to date
--   Sync.lua     swaps entries with online friends
--   UI.lua       the panel beside the quest windows

function ns.Print(...)
	print("|cff66ccffQuestBros:|r", ...)
end

-- "Name-Realm", the key for every character. Blizzard omits the realm for
-- characters on your own.
function ns.FullName(name)
	if name:find("-", 1, true) then return name end
	return name .. "-" .. GetNormalizedRealmName()
end

local SCAN_DELAY = 2 -- quest flags and the log settle just after their events
local LOGIN_SCAN_DELAY = 5 -- the completed list can be empty right at login

local scanPending = {}
-- Runs a scan once after a burst of events
local function Schedule(scan, delay)
	if scanPending[scan] then return end
	scanPending[scan] = true
	C_Timer.After(delay or SCAN_DELAY, function()
		scanPending[scan] = false
		scan()
	end)
end

local handlers = {}

function handlers.ADDON_LOADED(frame, name)
	if name ~= addonName then return end
	frame:UnregisterEvent("ADDON_LOADED")
	QuestBrosDB = QuestBrosDB or { chars = {} }
	ns.db = QuestBrosDB
end

function handlers.PLAYER_LOGIN(frame)
	ns.me = ns.FullName((UnitName("player")))
	ns.InitOwnEntry()
	ns.InitSync()
	ns.InitUI()

	for event in pairs(handlers) do
		if event ~= "ADDON_LOADED" and event ~= "PLAYER_LOGIN" then
			frame:RegisterEvent(event)
		end
	end

	Schedule(ns.ScanCompleted, LOGIN_SCAN_DELAY)
	Schedule(ns.ScanActive, LOGIN_SCAN_DELAY)
	C_FriendList.ShowFriends()
end

function handlers.PLAYER_LOGOUT()
	ns.TouchOwnEntry()
end

function handlers.QUEST_TURNED_IN()
	Schedule(ns.ScanCompleted)
end

function handlers.QUEST_LOG_UPDATE()
	Schedule(ns.ScanActive)
end

function handlers.FRIENDLIST_UPDATE()
	ns.RefreshFriends()
end

function handlers.CHAT_MSG_ADDON(_, ...)
	ns.OnAddonMessage(...)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, ...)
	handlers[event](self, ...)
end)

SLASH_QUESTBROS1 = "/qb"
SLASH_QUESTBROS2 = "/questbros"
SlashCmdList.QUESTBROS = function(input)
	if strtrim(input):lower() == "sync" then
		ns.GreetAll()
		ns.Print("asking online friends for updates.")
	else
		ns.PrintStatus()
	end
end
