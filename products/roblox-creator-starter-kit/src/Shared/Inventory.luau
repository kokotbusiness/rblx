--!strict
--[[
	Inventory
	Engine-independent backpack/inventory logic: fixed capacity, stackable items,
	equip slot, sorting. No Roblox APIs.

	Item catalog (shared by client and server):
		{ sword = { name = "Sword", maxStack = 1, rarity = "Rare", order = 10 },
		  apple = { name = "Apple", maxStack = 99, rarity = "Common", order = 50 } }

	Inventory data (save this in player data):
		{ capacity = 20, slots = { { itemId = "apple", count = 12 }, ... }, equipped = "sword" }
]]

local Inventory = {}

export type ItemDef = { name: string, maxStack: number, rarity: string?, order: number? }
export type Catalog = { [string]: ItemDef }
export type Slot = { itemId: string, count: number }
export type Data = { capacity: number, slots: { Slot }, equipped: string? }

local RARITY_RANK: { [string]: number } = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }

function Inventory.new(capacity: number): Data
	assert(type(capacity) == "number" and capacity >= 1 and math.floor(capacity) == capacity, "capacity must be a whole number >= 1")
	return { capacity = capacity, slots = {}, equipped = nil }
end

function Inventory.count(data: Data, itemId: string): number
	local total = 0
	for _, slot in data.slots do
		if slot.itemId == itemId then
			total += slot.count
		end
	end
	return total
end

-- How many of `itemId` would fit right now.
function Inventory.spaceFor(data: Data, catalog: Catalog, itemId: string): number
	local def = catalog[itemId]
	if not def then
		return 0
	end
	local space = 0
	for _, slot in data.slots do
		if slot.itemId == itemId then
			space += def.maxStack - slot.count
		end
	end
	space += (data.capacity - #data.slots) * def.maxStack
	return space
end

-- Adds items, filling existing stacks first. All-or-nothing: if everything
-- does not fit, nothing is added. Returns (ok, errorMessage?).
function Inventory.add(data: Data, catalog: Catalog, itemId: string, amount: number): (boolean, string?)
	local def = catalog[itemId]
	if not def then
		return false, "unknown item"
	end
	if type(amount) ~= "number" or amount < 1 or math.floor(amount) ~= amount then
		return false, "invalid amount"
	end
	if Inventory.spaceFor(data, catalog, itemId) < amount then
		return false, "inventory full"
	end
	local remaining = amount
	for _, slot in data.slots do
		if remaining == 0 then
			break
		end
		if slot.itemId == itemId and slot.count < def.maxStack then
			local added = math.min(def.maxStack - slot.count, remaining)
			slot.count += added
			remaining -= added
		end
	end
	while remaining > 0 do
		local added = math.min(def.maxStack, remaining)
		table.insert(data.slots, { itemId = itemId, count = added })
		remaining -= added
	end
	return true, nil
end

-- Removes items, taking from the last stacks first. All-or-nothing.
function Inventory.remove(data: Data, itemId: string, amount: number): (boolean, string?)
	if type(amount) ~= "number" or amount < 1 or math.floor(amount) ~= amount then
		return false, "invalid amount"
	end
	if Inventory.count(data, itemId) < amount then
		return false, "not enough items"
	end
	local remaining = amount
	for i = #data.slots, 1, -1 do
		local slot = data.slots[i]
		if slot.itemId == itemId then
			local taken = math.min(slot.count, remaining)
			slot.count -= taken
			remaining -= taken
			if slot.count == 0 then
				table.remove(data.slots, i)
			end
			if remaining == 0 then
				break
			end
		end
	end
	if data.equipped == itemId and Inventory.count(data, itemId) == 0 then
		data.equipped = nil
	end
	return true, nil
end

function Inventory.equip(data: Data, itemId: string?): (boolean, string?)
	if itemId == nil then
		data.equipped = nil
		return true, nil
	end
	if Inventory.count(data, itemId :: string) == 0 then
		return false, "item not owned"
	end
	data.equipped = itemId
	return true, nil
end

-- Sorts slots by rarity (highest first), then catalog `order`, then name.
function Inventory.sort(data: Data, catalog: Catalog)
	table.sort(data.slots, function(a: Slot, b: Slot): boolean
		local da, db = catalog[a.itemId], catalog[b.itemId]
		local ra: number = if da then (RARITY_RANK[da.rarity or "Common"] or 0) else 0
		local rb: number = if db then (RARITY_RANK[db.rarity or "Common"] or 0) else 0
		if ra ~= rb then
			return ra > rb
		end
		local oa: number = if da and da.order then da.order else math.huge
		local ob: number = if db and db.order then db.order else math.huge
		if oa ~= ob then
			return oa < ob
		end
		if a.itemId ~= b.itemId then
			return a.itemId < b.itemId
		end
		return a.count > b.count
	end)
end

return Inventory
