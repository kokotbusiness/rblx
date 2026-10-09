--!strict
--[[
	Shop
	Engine-independent shop logic:
	  * catalog validation (gamepasses, developer products, soft-currency offers)
	  * idempotent developer-product receipt handling (never grant twice)
	  * soft-currency purchases (all-or-nothing)

	The Roblox-specific parts (MarketplaceService calls, saving data) live in
	src/Server/StarterKitServer.server.luau. This module never talks to Roblox.

	Catalog shape (see src/Shared/KitConfig.luau for a full example):
	{
		gamepasses = { vip = { id = 0, name = "VIP", description = "...", priceLabel = "R$ 99" } },
		products   = { coins_1000 = { id = 0, name = "1,000 Coins", grant = { currency = "Coins", amount = 1000 } } },
		offers     = { apple = { itemId = "apple", amount = 1, price = { currency = "Coins", amount = 25 } } },
	}
	IDs of 0 are placeholders: create the gamepass/product on the Roblox
	Creator Dashboard and paste the real ID.
]]

local Shop = {}

Shop.MAX_REMEMBERED_RECEIPTS = 200

export type Price = { currency: string, amount: number }
export type Gamepass = { id: number, name: string, description: string, priceLabel: string? }
export type Product = { id: number, name: string, grant: Price, priceLabel: string? }
export type Offer = { itemId: string, amount: number, price: Price, name: string? }
export type Catalog = {
	gamepasses: { [string]: Gamepass },
	products: { [string]: Product },
	offers: { [string]: Offer },
}
-- Persist this per player. `order` keeps insertion order so old ids can be trimmed.
export type ReceiptLog = { ids: { [string]: boolean }, order: { string } }
export type Receipt = { PurchaseId: string, ProductId: number, PlayerId: number }

-- Returns (ok, problems). Placeholder ids (0) are reported as warnings, not errors.
function Shop.validateCatalog(catalog: Catalog): (boolean, { string }, { string })
	local errors, warnings = {}, {}
	for _, section in { "gamepasses", "products", "offers" } do
		if type((catalog :: any)[section]) ~= "table" then
			table.insert(errors, "catalog." .. section .. " must be a table (use {} when empty)")
		end
	end
	if #errors > 0 then
		return false, errors, warnings
	end
	local productIds: { [number]: string } = {}
	for key, pass in catalog.gamepasses do
		if type(pass.id) ~= "number" then
			table.insert(errors, "gamepass " .. key .. ": id must be a number")
		elseif pass.id == 0 then
			table.insert(warnings, "gamepass " .. key .. ": placeholder id 0")
		end
	end
	for key, product in catalog.products do
		if type(product.id) ~= "number" then
			table.insert(errors, "product " .. key .. ": id must be a number")
		elseif product.id == 0 then
			table.insert(warnings, "product " .. key .. ": placeholder id 0")
		elseif productIds[product.id] then
			table.insert(errors, "product " .. key .. ": id duplicates " .. productIds[product.id])
		else
			productIds[product.id] = key
		end
		if type(product.grant) ~= "table" or type(product.grant.amount) ~= "number" or product.grant.amount <= 0 then
			table.insert(errors, "product " .. key .. ": grant amount must be > 0")
		end
	end
	for key, offer in catalog.offers do
		if type(offer.price) ~= "table" or type(offer.price.amount) ~= "number" or offer.price.amount < 0 then
			table.insert(errors, "offer " .. key .. ": invalid price")
		end
		if type(offer.amount) ~= "number" or offer.amount < 1 then
			table.insert(errors, "offer " .. key .. ": amount must be >= 1")
		end
	end
	return #errors == 0, errors, warnings
end

function Shop.findProductById(catalog: Catalog, productId: number): (string?, Product?)
	for key, product in catalog.products do
		if product.id == productId and product.id ~= 0 then
			return key, product
		end
	end
	return nil, nil
end

function Shop.newReceiptLog(): ReceiptLog
	return { ids = {}, order = {} }
end

local function remember(log: ReceiptLog, purchaseId: string)
	log.ids[purchaseId] = true
	table.insert(log.order, purchaseId)
	while #log.order > Shop.MAX_REMEMBERED_RECEIPTS do
		local oldest = table.remove(log.order, 1)
		if oldest then
			log.ids[oldest] = nil
		end
	end
end

--[[
	Decides what to do with a developer-product receipt.
	`grant(product)` must apply the reward to the player's in-memory data and
	return true on success. Returns one of:
	  "Granted"         -> reward applied now; SAVE player data, then return PurchaseGranted
	  "AlreadyGranted"  -> duplicate callback; return PurchaseGranted without granting
	  "UnknownProduct"  -> not in catalog; return NotProcessedYet
	  "GrantFailed"     -> return NotProcessedYet so Roblox retries later
]]
function Shop.processReceipt(catalog: Catalog, log: ReceiptLog, receipt: Receipt, grant: (Product) -> boolean): string
	if log.ids[receipt.PurchaseId] then
		return "AlreadyGranted"
	end
	local _, product = Shop.findProductById(catalog, receipt.ProductId)
	if not product then
		return "UnknownProduct"
	end
	local ok = grant(product :: Product)
	if not ok then
		return "GrantFailed"
	end
	remember(log, receipt.PurchaseId)
	return "Granted"
end

export type Deps = {
	canAfford: (currency: string, amount: number) -> boolean,
	spend: (currency: string, amount: number) -> (boolean, string?),
	refund: (currency: string, amount: number) -> (),
	giveItem: (itemId: string, amount: number) -> (boolean, string?),
}

-- Buys a soft-currency offer. All-or-nothing: if giving the item fails, the
-- currency is refunded. Returns (ok, errorMessage?).
function Shop.buyOffer(catalog: Catalog, offerKey: string, deps: Deps): (boolean, string?)
	local offer = catalog.offers[offerKey]
	if not offer then
		return false, "unknown offer"
	end
	if not deps.canAfford(offer.price.currency, offer.price.amount) then
		return false, "insufficient funds"
	end
	local spent, spendErr = deps.spend(offer.price.currency, offer.price.amount)
	if not spent then
		return false, spendErr
	end
	local given, giveErr = deps.giveItem(offer.itemId, offer.amount)
	if not given then
		deps.refund(offer.price.currency, offer.price.amount)
		return false, giveErr
	end
	return true, nil
end

return Shop
