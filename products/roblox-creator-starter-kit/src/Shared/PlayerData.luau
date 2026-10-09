--!strict
--[[
	PlayerData
	Default player profile + `reconcile`, which fills in missing fields when you
	add new features to a game that already has saved players. No Roblox APIs.
]]

local PlayerData = {}

PlayerData.VERSION = 1

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

PlayerData.deepCopy = deepCopy

-- Builds a fresh profile from the kit config.
function PlayerData.default(config: any): { [string]: any }
	local wallet = {}
	for _, currency in config.currencies do
		wallet[currency.id] = currency.start or 0
	end
	return {
		version = PlayerData.VERSION,
		wallet = wallet,
		quests = nil, -- created on first refresh
		spin = { lastSpinAt = nil },
		inventory = { capacity = config.inventoryCapacity, slots = {}, equipped = nil },
		receipts = { ids = {}, order = {} },
	}
end

-- Adds any keys present in `template` but missing in `data` (recursively).
-- Never overwrites existing values. Returns `data`.
function PlayerData.reconcile(data: { [string]: any }, template: { [string]: any }): { [string]: any }
	for key, value in template do
		if data[key] == nil then
			data[key] = deepCopy(value)
		elseif type(data[key]) == "table" and type(value) == "table" then
			PlayerData.reconcile(data[key], value)
		end
	end
	return data
end

return PlayerData
