--!strict
--[[
	KitConfig
	The ONE file you edit to customise the kit: currencies, quests, wheel,
	items, shop. Everything here is example data - rename freely.

	Gamepass / product ids of 0 are placeholders. Create them on
	https://create.roblox.com (your experience -> Monetization) and paste the ids.
]]

local KitConfig: { [string]: any } = {}

KitConfig.currencies = {
	{ id = "Coins", label = "Coins", color = "#F5C542", start = 100 },
	{ id = "Gems", label = "Gems", color = "#7B61FF", start = 0 },
}

KitConfig.quests = {
	questsPerDay = 3,
	seed = 1234, -- change to reshuffle which quests appear on which day
	pool = {
		{ id = "collect_coins", event = "CoinsCollected", target = 100, title = "Collect 100 coins", reward = { currency = "Coins", amount = 50 } },
		{ id = "play_time", event = "MinutesPlayed", target = 15, title = "Play for 15 minutes", reward = { currency = "Coins", amount = 75 } },
		{ id = "spin_once", event = "WheelSpun", target = 1, title = "Spin the daily wheel", reward = { currency = "Coins", amount = 25 } },
		{ id = "buy_item", event = "ItemBought", target = 1, title = "Buy any item in the shop", reward = { currency = "Gems", amount = 2 } },
		{ id = "jump", event = "Jumped", target = 50, title = "Jump 50 times", reward = { currency = "Coins", amount = 40 } },
	},
}

KitConfig.spin = {
	cooldownSeconds = 24 * 60 * 60,
	segments = {
		{ id = "coins_s", label = "25 Coins", weight = 35, reward = { currency = "Coins", amount = 25 }, color = "#3B82F6" },
		{ id = "coins_m", label = "75 Coins", weight = 25, reward = { currency = "Coins", amount = 75 }, color = "#22C55E" },
		{ id = "coins_l", label = "200 Coins", weight = 15, reward = { currency = "Coins", amount = 200 }, color = "#F59E0B" },
		{ id = "gems_s", label = "1 Gem", weight = 15, reward = { currency = "Gems", amount = 1 }, color = "#8B5CF6" },
		{ id = "gems_l", label = "5 Gems", weight = 8, reward = { currency = "Gems", amount = 5 }, color = "#EC4899" },
		{ id = "jackpot", label = "1,000 Coins", weight = 2, reward = { currency = "Coins", amount = 1000 }, color = "#EF4444" },
	},
}

KitConfig.inventoryCapacity = 24

KitConfig.items = {
	sword = { name = "Starter Sword", maxStack = 1, rarity = "Rare", order = 10 },
	shield = { name = "Wooden Shield", maxStack = 1, rarity = "Uncommon", order = 20 },
	potion = { name = "Speed Potion", maxStack = 10, rarity = "Uncommon", order = 30 },
	apple = { name = "Apple", maxStack = 99, rarity = "Common", order = 50 },
}

KitConfig.shop = {
	gamepasses = {
		vip = { id = 0, name = "VIP", description = "2x daily quest rewards", priceLabel = "R$ 99" },
	},
	products = {
		coins_1000 = { id = 0, name = "1,000 Coins", grant = { currency = "Coins", amount = 1000 }, priceLabel = "R$ 49" },
		gems_25 = { id = 0, name = "25 Gems", grant = { currency = "Gems", amount = 25 }, priceLabel = "R$ 99" },
	},
	offers = {
		apple = { itemId = "apple", amount = 5, name = "5 Apples", price = { currency = "Coins", amount = 50 } },
		potion = { itemId = "potion", amount = 1, name = "Speed Potion", price = { currency = "Coins", amount = 150 } },
		sword = { itemId = "sword", amount = 1, name = "Starter Sword", price = { currency = "Gems", amount = 10 } },
	},
}

-- Multiplier applied to quest rewards for owners of the "vip" gamepass.
KitConfig.vipQuestMultiplier = 2

return KitConfig
