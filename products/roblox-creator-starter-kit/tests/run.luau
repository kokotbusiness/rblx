--[[
	Unit tests for the engine-independent modules in src/Shared.
	Run with the open-source Luau CLI (NOT Roblox Studio):
		luau tests/run.luau
	Exit code is non-zero when a test fails.
	These tests do not cover the Roblox-only scripts in src/Server and src/Client.
]]

local Wallet = require("../src/Shared/Wallet")
local DailyQuests = require("../src/Shared/DailyQuests")
local DailySpin = require("../src/Shared/DailySpin")
local Inventory = require("../src/Shared/Inventory")
local Shop = require("../src/Shared/Shop")
local PlayerData = require("../src/Shared/PlayerData")
local KitConfig = require("../src/Shared/KitConfig")

local passed, failed = 0, 0
local failures = {}

local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		table.insert(failures, name .. ": " .. tostring(err))
	end
end

local function eq(actual: any, expected: any, msg: string?)
	if actual ~= expected then
		error(string.format("%sexpected %s, got %s", msg and (msg .. ": ") or "", tostring(expected), tostring(actual)), 2)
	end
end

local function truthy(value: any, msg: string?)
	if not value then
		error(msg or "expected truthy value", 2)
	end
end

local DAY = 86400
local T0 = 20000 * DAY + 3600 -- 01:00 UTC on day 20000

-- Wallet ---------------------------------------------------------------------
test("wallet add/spend/insufficient", function()
	local w = Wallet.new({ Coins = 10 })
	truthy(Wallet.add(w, "Coins", 5))
	eq(Wallet.get(w, "Coins"), 15)
	local ok, err = Wallet.spend(w, "Coins", 16)
	eq(ok, false)
	eq(err, "insufficient funds")
	eq(Wallet.get(w, "Coins"), 15, "balance unchanged after failed spend")
	truthy(Wallet.spend(w, "Coins", 15))
	eq(Wallet.get(w, "Coins"), 0)
end)

test("wallet rejects negative, fractional and NaN amounts", function()
	local w = Wallet.new()
	eq((Wallet.add(w, "Coins", -1)), false)
	eq((Wallet.add(w, "Coins", 1.5)), false)
	eq((Wallet.add(w, "Coins", 0 / 0)), false)
	eq((Wallet.spend(w, "Coins", -5)), false, "negative spend must not mint money")
	eq(Wallet.get(w, "Coins"), 0)
end)

test("wallet cap", function()
	local w = Wallet.new({ Coins = Wallet.MAX_BALANCE })
	local ok, err = Wallet.add(w, "Coins", 1)
	eq(ok, false)
	eq(err, "balance cap reached")
end)

test("wallet format", function()
	eq(Wallet.format(950), "950")
	eq(Wallet.format(1000), "1K")
	eq(Wallet.format(1520), "1.5K")
	eq(Wallet.format(2400000), "2.4M")
	eq(Wallet.format(999999), "999.9K")
	eq(Wallet.format(-1500), "-1.5K")
end)

-- Daily quests ---------------------------------------------------------------
test("quest config is valid", function()
	local ok, err = DailyQuests.validateConfig(KitConfig.quests)
	truthy(ok, err)
end)

test("quests are deterministic per day and change between days", function()
	local a = DailyQuests.questsForDay(KitConfig.quests, 20000)
	local b = DailyQuests.questsForDay(KitConfig.quests, 20000)
	eq(#a, KitConfig.quests.questsPerDay)
	for i = 1, #a do
		eq(a[i].id, b[i].id)
	end
	local differs = false
	for day = 20001, 20010 do
		local c = DailyQuests.questsForDay(KitConfig.quests, day)
		for i = 1, #a do
			if c[i].id ~= a[i].id then
				differs = true
			end
		end
	end
	truthy(differs, "quests should rotate over 10 days")
end)

test("quests have no duplicates within a day", function()
	for day = 19990, 20100 do
		local seen = {}
		for _, q in DailyQuests.questsForDay(KitConfig.quests, day) do
			truthy(not seen[q.id], "duplicate quest on day " .. day)
			seen[q.id] = true
		end
	end
end)

test("quest progress, claim once, reset next day", function()
	local config = {
		questsPerDay = 1,
		pool = { { id = "c", event = "CoinsCollected", target = 10, title = "x", reward = { currency = "Coins", amount = 5 } } },
	}
	local state = DailyQuests.refresh(nil, config, T0)
	local reward, err = DailyQuests.claim(state, config, "c", T0)
	eq(reward, nil)
	eq(err, "quest not complete")
	eq(#DailyQuests.recordEvent(state, config, "Other", 50, T0), 0)
	eq(#DailyQuests.recordEvent(state, config, "CoinsCollected", 4, T0), 0)
	local done = DailyQuests.recordEvent(state, config, "CoinsCollected", 40, T0)
	eq(#done, 1)
	eq(state.quests[1].progress, 10, "progress is capped at target")
	reward = DailyQuests.claim(state, config, "c", T0)
	eq(reward and reward.amount, 5)
	local _, err2 = DailyQuests.claim(state, config, "c", T0)
	eq(err2, "already claimed")
	local _, err3 = DailyQuests.claim(state, config, "c", T0 + DAY)
	eq(err3, "quests expired")
	local newState, reset = DailyQuests.refresh(state, config, T0 + DAY)
	eq(reset, true)
	eq(newState.quests[1].progress, 0)
	local same, reset2 = DailyQuests.refresh(newState, config, T0 + DAY + 100)
	eq(reset2, false)
	eq(same, newState)
end)

test("quest ignores negative progress", function()
	local state = DailyQuests.refresh(nil, KitConfig.quests, T0)
	for _, q in state.quests do
		local def
		for _, d in KitConfig.quests.pool do
			if d.id == q.id then
				def = d
			end
		end
		DailyQuests.recordEvent(state, KitConfig.quests, def.event, -100, T0)
		eq(q.progress, 0)
	end
end)

test("seconds until reset", function()
	eq(DailyQuests.secondsUntilReset(20000 * DAY), DAY)
	eq(DailyQuests.secondsUntilReset(20000 * DAY + DAY - 1), 1)
end)

test("quest config validation catches problems", function()
	eq((DailyQuests.validateConfig({ pool = {}, questsPerDay = 1 })), false)
	eq((DailyQuests.validateConfig({ pool = KitConfig.quests.pool, questsPerDay = 99 })), false)
	local dup = { questsPerDay = 1, pool = { KitConfig.quests.pool[1], KitConfig.quests.pool[1] } }
	eq((DailyQuests.validateConfig(dup)), false)
end)

-- Daily spin -----------------------------------------------------------------
test("spin config is valid and odds sum to 1", function()
	local ok, err = DailySpin.validateConfig(KitConfig.spin)
	truthy(ok, err)
	local total = 0
	for _, p in DailySpin.odds(KitConfig.spin) do
		total += p
	end
	truthy(math.abs(total - 1) < 1e-9, "odds sum to 1")
end)

test("spin pickIndex boundaries", function()
	local config = {
		cooldownSeconds = 10,
		segments = {
			{ id = "a", label = "a", weight = 1, reward = { currency = "Coins", amount = 1 } },
			{ id = "zero", label = "z", weight = 0, reward = { currency = "Coins", amount = 999 } },
			{ id = "b", label = "b", weight = 3, reward = { currency = "Coins", amount = 2 } },
		},
	}
	eq(DailySpin.pickIndex(config, 0), 1)
	eq(DailySpin.pickIndex(config, 0.2499), 1)
	eq(DailySpin.pickIndex(config, 0.25), 3, "zero-weight segment is never picked")
	eq(DailySpin.pickIndex(config, 0.9999999), 3)
end)

test("spin cooldown", function()
	local state = { lastSpinAt = nil }
	local idx, reward, err = DailySpin.spin(state, KitConfig.spin, T0, function()
		return 0
	end)
	eq(idx, 1)
	eq(reward and reward.amount, 25)
	eq(err, nil)
	local _, _, err2 = DailySpin.spin(state, KitConfig.spin, T0 + 60, function()
		return 0
	end)
	eq(err2, "spin on cooldown")
	eq(DailySpin.secondsUntilNextSpin(state, KitConfig.spin, T0 + 60), DAY - 60)
	truthy(DailySpin.canSpin(state, KitConfig.spin, T0 + DAY))
end)

test("spin distribution roughly matches weights", function()
	local seed = 42
	local function rnd()
		seed = (seed * 48271) % 2147483647
		return seed / 2147483647
	end
	local counts = {}
	local n = 20000
	for _ = 1, n do
		local i = DailySpin.pickIndex(KitConfig.spin, rnd())
		counts[i] = (counts[i] or 0) + 1
	end
	for i, p in DailySpin.odds(KitConfig.spin) do
		local observed = (counts[i] or 0) / n
		truthy(math.abs(observed - p) < 0.02, "segment " .. i .. " observed " .. observed .. " expected " .. p)
	end
end)

-- Inventory ------------------------------------------------------------------
test("inventory stacking and capacity", function()
	local inv = Inventory.new(2)
	truthy(Inventory.add(inv, KitConfig.items, "apple", 150))
	eq(#inv.slots, 2)
	eq(Inventory.count(inv, "apple"), 150)
	local ok, err = Inventory.add(inv, KitConfig.items, "sword", 1)
	eq(ok, false)
	eq(err, "inventory full")
	ok = Inventory.add(inv, KitConfig.items, "apple", 49)
	eq(ok, false, "all-or-nothing when overflowing")
	eq(Inventory.count(inv, "apple"), 150)
	truthy(Inventory.add(inv, KitConfig.items, "apple", 48))
	eq(Inventory.count(inv, "apple"), 198)
end)

test("inventory remove and equip", function()
	local inv = Inventory.new(5)
	truthy(Inventory.add(inv, KitConfig.items, "sword", 1))
	truthy(Inventory.equip(inv, "sword"))
	eq(inv.equipped, "sword")
	eq((Inventory.equip(inv, "shield")), false)
	eq((Inventory.remove(inv, "sword", 2)), false)
	truthy(Inventory.remove(inv, "sword", 1))
	eq(inv.equipped, nil, "unequipped when last copy removed")
	eq(#inv.slots, 0)
	eq((Inventory.add(inv, KitConfig.items, "unknown", 1)), false)
end)

test("inventory sort by rarity", function()
	local inv = Inventory.new(10)
	Inventory.add(inv, KitConfig.items, "apple", 3)
	Inventory.add(inv, KitConfig.items, "shield", 1)
	Inventory.add(inv, KitConfig.items, "sword", 1)
	Inventory.sort(inv, KitConfig.items)
	eq(inv.slots[1].itemId, "sword")
	eq(inv.slots[2].itemId, "shield")
	eq(inv.slots[3].itemId, "apple")
end)

-- Shop -----------------------------------------------------------------------
local testCatalog = {
	gamepasses = { vip = { id = 111, name = "VIP", description = "" } },
	products = { coins = { id = 222, name = "Coins", grant = { currency = "Coins", amount = 1000 } } },
	offers = { apple = { itemId = "apple", amount = 5, price = { currency = "Coins", amount = 50 } } },
}

test("shop catalog validation", function()
	local ok, errors, warnings = Shop.validateCatalog(KitConfig.shop)
	truthy(ok, table.concat(errors, "; "))
	truthy(#warnings > 0, "placeholder ids reported as warnings")
	local ok2 = Shop.validateCatalog({ gamepasses = {}, offers = {}, products = {
		a = { id = 5, name = "a", grant = { currency = "Coins", amount = 1 } },
		b = { id = 5, name = "b", grant = { currency = "Coins", amount = 1 } },
	} })
	eq(ok2, false, "duplicate product ids rejected")
end)

test("receipt processing is idempotent", function()
	local log = Shop.newReceiptLog()
	local granted = 0
	local function grant(product)
		granted += product.grant.amount
		return true
	end
	local receipt = { PurchaseId = "p1", ProductId = 222, PlayerId = 1 }
	eq(Shop.processReceipt(testCatalog, log, receipt, grant), "Granted")
	eq(Shop.processReceipt(testCatalog, log, receipt, grant), "AlreadyGranted")
	eq(granted, 1000, "granted exactly once")
	eq(Shop.processReceipt(testCatalog, log, { PurchaseId = "p2", ProductId = 999, PlayerId = 1 }, grant), "UnknownProduct")
	eq(Shop.processReceipt(testCatalog, log, { PurchaseId = "p3", ProductId = 222, PlayerId = 1 }, function()
		return false
	end), "GrantFailed")
	eq(log.ids["p3"], nil, "failed grant is not remembered, so Roblox can retry")
end)

test("receipt log is bounded", function()
	local log = Shop.newReceiptLog()
	for i = 1, Shop.MAX_REMEMBERED_RECEIPTS + 10 do
		Shop.processReceipt(testCatalog, log, { PurchaseId = "p" .. i, ProductId = 222, PlayerId = 1 }, function()
			return true
		end)
	end
	eq(#log.order, Shop.MAX_REMEMBERED_RECEIPTS)
	eq(log.ids["p1"], nil)
	truthy(log.ids["p" .. (Shop.MAX_REMEMBERED_RECEIPTS + 10)])
end)

test("buyOffer is all-or-nothing", function()
	local wallet = Wallet.new({ Coins = 60 })
	local inv = Inventory.new(1)
	local deps = {
		canAfford = function(c, a)
			return Wallet.canAfford(wallet, c, a)
		end,
		spend = function(c, a)
			return Wallet.spend(wallet, c, a)
		end,
		refund = function(c, a)
			Wallet.add(wallet, c, a)
		end,
		giveItem = function(id, a)
			return Inventory.add(inv, KitConfig.items, id, a)
		end,
	}
	truthy(Shop.buyOffer(testCatalog, "apple", deps))
	eq(Wallet.get(wallet, "Coins"), 10)
	eq(Inventory.count(inv, "apple"), 5)
	local ok, err = Shop.buyOffer(testCatalog, "apple", deps)
	eq(ok, false)
	eq(err, "insufficient funds")
	-- full inventory -> refund
	Wallet.add(wallet, "Coins", 1000)
	Inventory.add(inv, KitConfig.items, "apple", 94) -- slot now full (99)
	local ok2, err2 = Shop.buyOffer(testCatalog, "apple", deps)
	eq(ok2, false)
	eq(err2, "inventory full")
	eq(Wallet.get(wallet, "Coins"), 1010, "refunded")
end)

-- PlayerData -----------------------------------------------------------------
test("player data default and reconcile", function()
	local d = PlayerData.default(KitConfig)
	eq(d.wallet.Coins, 100)
	eq(d.inventory.capacity, KitConfig.inventoryCapacity)
	local old = { wallet = { Coins = 5 } }
	PlayerData.reconcile(old, d)
	eq(old.wallet.Coins, 5, "existing values kept")
	eq(old.wallet.Gems, 0, "missing currency added")
	truthy(old.receipts and old.receipts.order)
end)

print(string.format("%d passed, %d failed", passed, failed))
for _, f in failures do
	print("FAIL " .. f)
end
if failed > 0 then
	error("tests failed", 0)
end
