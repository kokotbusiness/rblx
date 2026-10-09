--[[
	StarterKitService (ModuleScript, ServerScriptService.StarterKitServer)

	Roblox-specific glue around the pure modules in ReplicatedStorage.StarterKit.Shared:
	  * loads/saves player data with DataStoreService (UpdateAsync + retries)
	  * creates the RemoteFunctions/RemoteEvents the client UI uses
	  * validates every client request on the server (client is never trusted)
	  * handles developer-product receipts idempotently and gamepass ownership

	Public API for your own game scripts:
		local Kit = require(game.ServerScriptService.StarterKitServer.StarterKitService)
		Kit.recordQuestEvent(player, "CoinsCollected", 5)
		Kit.addCurrency(player, "Coins", 10)
		Kit.giveItem(player, "apple", 3)
		Kit.ownsGamepass(player, "vip")

	NOTE: This file uses Roblox APIs and was NOT executed in Roblox Studio by
	the author of this kit build. Follow docs/STUDIO_TEST_CHECKLIST.md before
	shipping it in a live game. For large games consider a session-locking
	library (e.g. ProfileStore) instead of the simple saving below.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

local Kit = ReplicatedStorage:WaitForChild("StarterKit")
local Shared = Kit:WaitForChild("Shared")

local KitConfig = require(Shared:WaitForChild("KitConfig"))
local Wallet = require(Shared:WaitForChild("Wallet"))
local DailyQuests = require(Shared:WaitForChild("DailyQuests"))
local DailySpin = require(Shared:WaitForChild("DailySpin"))
local Inventory = require(Shared:WaitForChild("Inventory"))
local Shop = require(Shared:WaitForChild("Shop"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))

local Service = {}

local DATASTORE_NAME = "StarterKit_PlayerData_v1"
local SAVE_RETRIES = 3
local AUTOSAVE_SECONDS = 120
local REQUEST_COOLDOWN = 0.25 -- seconds between remote calls per player

local profiles: { [Player]: any } = {}
local gamepassCache: { [Player]: { [string]: boolean } } = {}
local lastRequest: { [Player]: number } = {}
local remotes: { [string]: any } = {}
local random = Random.new()

local store = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[StarterKit] DataStore unavailable, data will NOT be saved:", result)
	end
end

local function key(player: Player): string
	return "player_" .. player.UserId
end

local function withRetries(fn: () -> any): (boolean, any)
	local ok, result
	for attempt = 1, SAVE_RETRIES do
		ok, result = pcall(fn)
		if ok then
			return true, result
		end
		task.wait(attempt)
	end
	return false, result
end

local function loadProfile(player: Player): any
	local template = PlayerData.default(KitConfig)
	local data = nil
	if store then
		local ok, result = withRetries(function()
			return store:GetAsync(key(player))
		end)
		if not ok and RunService:IsStudio() and string.find(tostring(result), "StudioAccessToApisNotAllowed", 1, true) then
			-- Studio without "Enable Studio Access to API Services": play with unsaved data instead of kicking.
			warn("[StarterKit] Studio has no API access - data will NOT be saved this session (Game Settings > Security to enable)")
			store = nil
			ok, result = true, nil
		end
		if not ok then
			warn("[StarterKit] Load failed for", player.Name, result)
			player:Kick("Could not load your data. Please rejoin.")
			return nil
		end
		data = result
	end
	if type(data) ~= "table" then
		data = PlayerData.deepCopy(template)
	end
	return PlayerData.reconcile(data, template)
end

function Service.save(player: Player): boolean
	local data = profiles[player]
	if not data or not store then
		return store == nil -- nothing to save to counts as "ok" in Studio without API access
	end
	local ok, err = withRetries(function()
		return store:UpdateAsync(key(player), function()
			return data
		end)
	end)
	if not ok then
		warn("[StarterKit] Save failed for", player.Name, err)
	end
	return ok
end

local function refreshGamepasses(player: Player)
	local owned = {}
	for passKey, pass in KitConfig.shop.gamepasses do
		if pass.id ~= 0 then
			local ok, result = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
			end)
			owned[passKey] = ok and result == true
		else
			owned[passKey] = false
		end
	end
	gamepassCache[player] = owned
end

function Service.ownsGamepass(player: Player, passKey: string): boolean
	local cache = gamepassCache[player]
	return cache ~= nil and cache[passKey] == true
end

local function now(): number
	return os.time()
end

-- Snapshot sent to the client. Only display data, never anything secret.
local function snapshot(player: Player): any
	local data = profiles[player]
	if not data then
		return nil
	end
	local t = now()
	data.quests = DailyQuests.refresh(data.quests, KitConfig.quests, t)

	local quests = {}
	for _, progress in data.quests.quests do
		for _, def in KitConfig.quests.pool do
			if def.id == progress.id then
				table.insert(quests, {
					id = def.id,
					title = def.title,
					progress = progress.progress,
					target = def.target,
					claimed = progress.claimed,
					reward = def.reward,
				})
			end
		end
	end

	local odds = DailySpin.odds(KitConfig.spin)
	local segments = {}
	for i, segment in KitConfig.spin.segments do
		table.insert(segments, { id = segment.id, label = segment.label, color = segment.color, chance = odds[i] })
	end

	local slots = {}
	for _, slot in data.inventory.slots do
		local def = KitConfig.items[slot.itemId]
		table.insert(slots, {
			itemId = slot.itemId,
			count = slot.count,
			name = def and def.name or slot.itemId,
			rarity = def and def.rarity or "Common",
		})
	end

	local passes = {}
	for passKey, pass in KitConfig.shop.gamepasses do
		table.insert(passes, {
			key = passKey,
			id = pass.id,
			name = pass.name,
			description = pass.description,
			priceLabel = pass.priceLabel,
			owned = Service.ownsGamepass(player, passKey),
		})
	end
	local products = {}
	for productKey, product in KitConfig.shop.products do
		table.insert(products, { key = productKey, id = product.id, name = product.name, priceLabel = product.priceLabel })
	end
	local offers = {}
	for offerKey, offer in KitConfig.shop.offers do
		table.insert(offers, { key = offerKey, name = offer.name or offerKey, price = offer.price })
	end

	return {
		currencies = KitConfig.currencies,
		wallet = data.wallet,
		quests = quests,
		questResetIn = DailyQuests.secondsUntilReset(t),
		spin = { secondsLeft = DailySpin.secondsUntilNextSpin(data.spin, KitConfig.spin, t), segments = segments },
		inventory = { capacity = data.inventory.capacity, equipped = data.inventory.equipped, slots = slots },
		shop = { gamepasses = passes, products = products, offers = offers },
	}
end

local function pushState(player: Player)
	local state = snapshot(player)
	if state then
		remotes.StateChanged:FireClient(player, state)
	end
end

local function notify(player: Player, text: string, kind: string?)
	remotes.Notify:FireClient(player, text, kind or "info")
end

local function throttled(player: Player): boolean
	local t = os.clock()
	if lastRequest[player] and t - lastRequest[player] < REQUEST_COOLDOWN then
		return true
	end
	lastRequest[player] = t
	return false
end

-- Public helpers -------------------------------------------------------------

function Service.addCurrency(player: Player, currency: string, amount: number): boolean
	local data = profiles[player]
	if not data then
		return false
	end
	local ok = Wallet.add(data.wallet, currency, amount)
	if ok then
		pushState(player)
	end
	return ok
end

function Service.giveItem(player: Player, itemId: string, amount: number): (boolean, string?)
	local data = profiles[player]
	if not data then
		return false, "not loaded"
	end
	local ok, err = Inventory.add(data.inventory, KitConfig.items, itemId, amount)
	if ok then
		pushState(player)
	end
	return ok, err
end

function Service.recordQuestEvent(player: Player, event: string, amount: number)
	local data = profiles[player]
	if not data then
		return
	end
	local t = now()
	data.quests = DailyQuests.refresh(data.quests, KitConfig.quests, t)
	local completed = DailyQuests.recordEvent(data.quests, KitConfig.quests, event, amount, t)
	if #completed > 0 then
		notify(player, "Quest complete! Claim your reward.", "success")
	end
	pushState(player)
end

-- Remote handlers ------------------------------------------------------------

local handlers: { [string]: (Player, ...any) -> (any, any) } = {}

function handlers.GetState(player: Player)
	return snapshot(player)
end

function handlers.ClaimQuest(player: Player, questId: any)
	local data = profiles[player]
	if not data or type(questId) ~= "string" then
		return false, "bad request"
	end
	local t = now()
	data.quests = DailyQuests.refresh(data.quests, KitConfig.quests, t)
	local reward, err = DailyQuests.claim(data.quests, KitConfig.quests, questId, t)
	if not reward then
		return false, err
	end
	local amount = reward.amount
	if Service.ownsGamepass(player, "vip") then
		amount *= KitConfig.vipQuestMultiplier
	end
	Wallet.add(data.wallet, reward.currency, amount)
	pushState(player)
	return true, string.format("+%s %s", Wallet.format(amount), reward.currency)
end

function handlers.Spin(player: Player)
	local data = profiles[player]
	if not data then
		return false, "bad request"
	end
	local index, reward, err = DailySpin.spin(data.spin, KitConfig.spin, now(), function()
		return random:NextNumber()
	end)
	if not index or not reward then
		return false, err
	end
	Wallet.add(data.wallet, reward.currency, reward.amount)
	Service.recordQuestEvent(player, "WheelSpun", 1)
	return true, index
end

function handlers.BuyOffer(player: Player, offerKey: any)
	local data = profiles[player]
	if not data or type(offerKey) ~= "string" then
		return false, "bad request"
	end
	local ok, err = Shop.buyOffer(KitConfig.shop, offerKey, {
		canAfford = function(c, a)
			return Wallet.canAfford(data.wallet, c, a)
		end,
		spend = function(c, a)
			return Wallet.spend(data.wallet, c, a)
		end,
		refund = function(c, a)
			Wallet.add(data.wallet, c, a)
		end,
		giveItem = function(id, a)
			return Inventory.add(data.inventory, KitConfig.items, id, a)
		end,
	})
	if ok then
		Service.recordQuestEvent(player, "ItemBought", 1)
	end
	return ok, err
end

function handlers.Equip(player: Player, itemId: any)
	local data = profiles[player]
	if not data or (itemId ~= nil and type(itemId) ~= "string") then
		return false, "bad request"
	end
	local ok, err = Inventory.equip(data.inventory, itemId)
	pushState(player)
	return ok, err
end

function handlers.SortInventory(player: Player)
	local data = profiles[player]
	if not data then
		return false, "bad request"
	end
	Inventory.sort(data.inventory, KitConfig.items)
	pushState(player)
	return true, nil
end

-- Setup ----------------------------------------------------------------------

local function createRemotes()
	local folder = Kit:FindFirstChild("Remotes") or Instance.new("Folder")
	folder.Name = "Remotes"
	for name in handlers do
		local rf = Instance.new("RemoteFunction")
		rf.Name = name
		rf.Parent = folder
		rf.OnServerInvoke = function(player, ...)
			if throttled(player) and name ~= "GetState" then
				return false, "slow down"
			end
			return handlers[name](player, ...)
		end
		remotes[name] = rf
	end
	for _, name in { "StateChanged", "Notify" } do
		local re = Instance.new("RemoteEvent")
		re.Name = name
		re.Parent = folder
		remotes[name] = re
	end
	folder.Parent = Kit
end

local function onPlayerAdded(player: Player)
	local data = loadProfile(player)
	if not data or not player.Parent then
		return
	end
	profiles[player] = data
	refreshGamepasses(player)
	player:SetAttribute("StarterKitLoaded", true)
	pushState(player)
end

local function onPlayerRemoving(player: Player)
	Service.save(player)
	profiles[player] = nil
	gamepassCache[player] = nil
	lastRequest[player] = nil
end

local function processReceipt(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	local data = player and profiles[player]
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local result = Shop.processReceipt(KitConfig.shop, data.receipts, receiptInfo, function(product)
		return (Wallet.add(data.wallet, product.grant.currency, product.grant.amount))
	end)
	if result == "Granted" or result == "AlreadyGranted" then
		-- Only confirm the purchase once the grant is safely saved.
		if Service.save(player) then
			pushState(player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

local started = false

function Service.start()
	if started then
		return
	end
	started = true

	local ok, errors, warnings = Shop.validateCatalog(KitConfig.shop)
	for _, w in warnings do
		warn("[StarterKit] " .. w)
	end
	assert(ok, "[StarterKit] invalid shop config: " .. table.concat(errors, "; "))
	assert(DailyQuests.validateConfig(KitConfig.quests))
	assert(DailySpin.validateConfig(KitConfig.spin))

	createRemotes()
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased then
			refreshGamepasses(player)
			pushState(player)
		end
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			Service.save(player)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for _, player in Players:GetPlayers() do
				task.spawn(Service.save, player)
			end
		end
	end)
end

return Service
