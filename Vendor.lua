local addonName, ns = ...

-- At a vendor: repairs everything and sells grey items, each optional, and
-- says in chat what it did. Holding Shift while opening the vendor skips
-- both, for buying something back or keeping a grey item.

local POOR = 0 -- item quality of grey items

-- Gold the guild bank will pay toward this repair, or 0
local function GuildRepairFunds(cost)
	if not (IsInGuild() and CanGuildBankRepair and CanGuildBankRepair()) then return 0 end
	local allowed = GetGuildBankWithdrawMoney() -- -1: no limit
	local bank = GetGuildBankMoney()
	if allowed == -1 then allowed = bank end
	return math.min(allowed, bank, cost)
end

local function Repair()
	if not CanMerchantRepair() then return end
	local cost, canRepair = GetRepairAllCost()
	if not canRepair or cost == 0 then return end

	-- The guild only pays for the whole bill: RepairAllItems(true) fails
	-- outright on anything less
	if ns.db.vendor.guildRepair and GuildRepairFunds(cost) >= cost then
		RepairAllItems(true)
		ns.Print("repaired for " .. C_CurrencyInfo.GetCoinTextureString(cost) .. " from the guild bank.")
	elseif GetMoney() >= cost then
		RepairAllItems()
		ns.Print("repaired for " .. C_CurrencyInfo.GetCoinTextureString(cost) .. ".")
	else
		ns.Print("can't afford repairs (" .. C_CurrencyInfo.GetCoinTextureString(cost) .. ").")
	end
end

local function SellGreys()
	local count, total = 0, 0
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.quality == POOR and not info.hasNoValue and not info.isLocked then
				local price = select(11, C_Item.GetItemInfo(info.itemID)) or 0
				C_Container.UseContainerItem(bag, slot)
				count = count + 1
				total = total + price * info.stackCount
			end
		end
	end
	if count > 0 then
		local money = C_CurrencyInfo.GetCoinTextureString(total)
		ns.Print(format("sold %d grey item%s for %s.", count, count == 1 and "" or "s", money))
	end
end

local function OnMerchantShow()
	if IsShiftKeyDown() then return end
	local V = ns.db.vendor
	-- Repair first: selling's gold arrives later than this runs
	if V.autoRepair then Repair() end
	if V.sellGreys then SellGreys() end
end

function ns:InitVendor()
	local f = CreateFrame("Frame")
	f:RegisterEvent("MERCHANT_SHOW")
	f:SetScript("OnEvent", OnMerchantShow)
end
