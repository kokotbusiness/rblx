--[[
	StarterKitClient (LocalScript, StarterPlayer.StarterPlayerScripts)

	Builds the whole kit UI from code: currency bar, side menu, and the
	Quests / Daily Spin / Shop / Backpack panels. The client only DISPLAYS state
	and ASKS the server to do things; the server validates everything.

	NOTE: Uses Roblox APIs; not executed in Roblox Studio by the kit author.
	See docs/STUDIO_TEST_CHECKLIST.md.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local Kit = ReplicatedStorage:WaitForChild("StarterKit")
local Remotes = Kit:WaitForChild("Remotes")
local C = require(Kit:WaitForChild("UI"):WaitForChild("Components"))
local Wallet = require(Kit:WaitForChild("Shared"):WaitForChild("Wallet"))
local Theme = C.Theme

local state: any = nil

local gui = C.create("ScreenGui", {
	Name = "StarterKitUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

local function call(name: string, ...): (boolean, any)
	local ok, success, result = pcall(function(...)
		return Remotes:WaitForChild(name):InvokeServer(...)
	end, ...)
	if not ok then
		return false, "connection error"
	end
	return success, result
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d:%02d", seconds // 3600, (seconds % 3600) // 60, seconds % 60)
end

-- Currency bar ---------------------------------------------------------------
local currencyBar = C.create("Frame", {
	Name = "CurrencyBar",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.fromOffset(320, 40),
	Parent = gui,
})
C.create("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	Padding = UDim.new(0, 10),
	Parent = currencyBar,
})
local pills = {}

-- Panels ---------------------------------------------------------------------
local panelSize = UDim2.fromScale(0.62, 0.7)
local questsPanel, questsContent = C.Panel("Daily Quests", panelSize)
local spinPanel, spinContent = C.Panel("Daily Spin", panelSize)
local shopPanel, shopContent = C.Panel("Shop", panelSize)
local backpackPanel, backpackContent = C.Panel("Backpack", panelSize)
local panels = { questsPanel, spinPanel, shopPanel, backpackPanel }
for _, panel in panels do
	panel.Parent = gui
end

local function openOnly(target: Frame)
	for _, panel in panels do
		if panel ~= target then
			C.hidePanel(panel)
		end
	end
	if target.Visible then
		C.hidePanel(target)
	else
		C.showPanel(target)
	end
end

-- Side menu ------------------------------------------------------------------
local menu = C.create("Frame", {
	Name = "Menu",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.5, 0),
	Size = UDim2.fromOffset(120, 4 * 46),
	Parent = gui,
})
C.listLayout(menu, 8)
local menuEntries: { { any } } = { { "Quests", questsPanel }, { "Spin", spinPanel }, { "Shop", shopPanel }, { "Backpack", backpackPanel } }
for i, entry in menuEntries do
	local button = C.Button(entry[1], "ghost")
	button.LayoutOrder = i
	button.Size = UDim2.new(1, 0, 0, 38)
	button.Parent = menu
	button.Activated:Connect(function()
		openOnly(entry[2])
	end)
end

-- Destroys rendered cards but keeps layouts/padding and any `keep` instance.
local function clear(container: Instance, keep: Instance?)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") and child ~= keep then
			child:Destroy()
		end
	end
end

local function toast(text: string, kind: string?)
	C.Toast(gui, text, kind)
end

-- Quests ---------------------------------------------------------------------
C.listLayout(questsContent, 10)
local questTimer = C.label("", 14, Theme.TextMuted)
questTimer.LayoutOrder = 0

local function renderQuests()
	questTimer.Parent = questsContent
	clear(questsContent, questTimer)
	for i, quest in state.quests do
		local card = C.QuestCard(quest, function(id)
			local ok, result = call("ClaimQuest", id)
			toast(if ok then result else tostring(result), if ok then "success" else "error")
		end)
		card.LayoutOrder = i
		card.Parent = questsContent
	end
end

-- Daily spin (ring of reward tiles with an animated selector) ----------------
local spinTiles = {}
local spinButton = C.Button("Spin!", "success")
spinButton.Size = UDim2.fromOffset(160, 44)
spinButton.AnchorPoint = Vector2.new(0.5, 0.5)
spinButton.Position = UDim2.fromScale(0.5, 0.5)
local spinning = false

local function renderSpin()
	clear(spinContent)
	spinTiles = {}
	local ring = C.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 300),
		Parent = spinContent,
	})
	local count = #state.spin.segments
	for i, segment in state.spin.segments do
		local angle = (i - 1) / count * math.pi * 2 - math.pi / 2
		local tile = C.create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(angle) * 120, 0.5, math.sin(angle) * 120),
			Size = UDim2.fromOffset(96, 56),
			BackgroundColor3 = Color3.fromHex(segment.color or "#5B8CFF"),
			Parent = ring,
		})
		C.create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = tile })
		C.create("UIStroke", { Name = "Highlight", Color = Color3.new(1, 1, 1), Thickness = 0, Parent = tile })
		local text = C.label(segment.label, 14, Theme.Text, true)
		text.TextXAlignment = Enum.TextXAlignment.Center
		text.Size = UDim2.new(1, 0, 0, 18)
		text.Position = UDim2.fromOffset(0, 10)
		text.Parent = tile
		local chance = C.label(string.format("%.1f%%", segment.chance * 100), 12, Theme.Text)
		chance.TextXAlignment = Enum.TextXAlignment.Center
		chance.TextTransparency = 0.25
		chance.Size = UDim2.new(1, 0, 0, 14)
		chance.Position = UDim2.fromOffset(0, 32)
		chance.Parent = tile
		spinTiles[i] = tile
	end
	spinButton.Parent = ring
	local ready = state.spin.secondsLeft <= 0
	spinButton.Text = if ready then "Spin!" else formatTime(state.spin.secondsLeft)
	C.setButtonEnabled(spinButton, ready and not spinning)
	local note = C.label("Free once per day. Odds are shown on each tile.", 14, Theme.TextMuted)
	note.TextXAlignment = Enum.TextXAlignment.Center
	note.Parent = spinContent
end
C.listLayout(spinContent, 10)

local function highlight(index: number)
	for i, tile in spinTiles do
		(tile:FindFirstChild("Highlight") :: UIStroke).Thickness = if i == index then 4 else 0
	end
end

spinButton.Activated:Connect(function()
	if spinning or not spinButton.Active then
		return
	end
	spinning = true
	C.setButtonEnabled(spinButton, false)
	local ok, result = call("Spin")
	if not ok then
		spinning = false
		toast(tostring(result), "error")
		renderSpin()
		return
	end
	-- Animate: a few laps that slow down and stop on the server's result.
	local count = #spinTiles
	local steps = count * 3 + (result - 1)
	for step = 0, steps do
		highlight(step % count + 1)
		task.wait(0.04 + (step / steps) ^ 3 * 0.35)
	end
	spinning = false
	local segment = state.spin.segments[result]
	toast("You won " .. segment.label .. "!", "success")
	renderSpin()
	highlight(result)
end)

-- Shop -----------------------------------------------------------------------
C.create("UIGridLayout", {
	CellSize = UDim2.fromOffset(200, 130),
	CellPadding = UDim2.fromOffset(10, 10),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = shopContent,
})

local function renderShop()
	clear(shopContent)
	local order = 0
	for _, pass in state.shop.gamepasses do
		order += 1
		local card = C.ShopCard(pass.name, pass.description, pass.priceLabel or "Buy", function()
			if pass.id == 0 then
				toast("Set the gamepass id in KitConfig first", "error")
				return
			end
			MarketplaceService:PromptGamePassPurchase(player, pass.id)
		end, if pass.owned then "Owned" else nil)
		card.LayoutOrder = order
		card.Parent = shopContent
	end
	for _, product in state.shop.products do
		order += 1
		local card = C.ShopCard(product.name, "Robux purchase", product.priceLabel or "Buy", function()
			if product.id == 0 then
				toast("Set the product id in KitConfig first", "error")
				return
			end
			MarketplaceService:PromptProductPurchase(player, product.id)
		end)
		card.LayoutOrder = order
		card.Parent = shopContent
	end
	for _, offer in state.shop.offers do
		order += 1
		local card = C.ShopCard(offer.name, "Paid with in-game currency", Wallet.format(offer.price.amount) .. " " .. offer.price.currency, function()
			local ok, err = call("BuyOffer", offer.key)
			toast(if ok then "Purchased " .. offer.name else tostring(err), if ok then "success" else "error")
		end)
		card.LayoutOrder = order
		card.Parent = shopContent
	end
end

-- Backpack -------------------------------------------------------------------
local function renderBackpack()
	clear(backpackContent)
	local inv = state.inventory
	local header = C.create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 0, Parent = backpackContent })
	local info = C.label(string.format("%d / %d slots", #inv.slots, inv.capacity), 15, Theme.TextMuted)
	info.Size = UDim2.new(1, -110, 1, 0)
	info.Parent = header
	local sort = C.Button("Sort", "ghost")
	sort.Size = UDim2.fromOffset(100, 32)
	sort.AnchorPoint = Vector2.new(1, 0)
	sort.Position = UDim2.fromScale(1, 0)
	sort.Parent = header
	sort.Activated:Connect(function()
		call("SortInventory")
	end)

	local grid = C.create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = backpackContent })
	C.create("UIGridLayout", {
		CellSize = UDim2.fromOffset(84, 84),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	for i = 1, inv.capacity do
		local slot = inv.slots[i]
		local equipped = slot ~= nil and inv.equipped == slot.itemId
		local cell = C.InventorySlot(slot, equipped, if slot then function()
			call("Equip", if equipped then nil else slot.itemId)
		end else nil)
		cell.LayoutOrder = i
		cell.Parent = grid
	end
end
C.listLayout(backpackContent, 10)

-- State updates --------------------------------------------------------------
local function render()
	if not state then
		return
	end
	for _, currency in state.currencies do
		local pill = pills[currency.id]
		if not pill then
			pill = C.CurrencyPill(currency)
			pill.Parent = currencyBar
			pills[currency.id] = pill
		end
		C.setCurrency(pill, state.wallet[currency.id] or 0, Wallet.format)
	end
	renderQuests()
	if not spinning then
		renderSpin()
	end
	renderShop()
	renderBackpack()
end

Remotes:WaitForChild("StateChanged").OnClientEvent:Connect(function(newState)
	state = newState
	render()
end)
Remotes:WaitForChild("Notify").OnClientEvent:Connect(function(text, kind)
	toast(text, kind)
end)

gui.Parent = player:WaitForChild("PlayerGui")

-- Initial state (retry a few times while the server loads the profile).
for _ = 1, 10 do
	local snapshot = Remotes:WaitForChild("GetState"):InvokeServer()
	if snapshot then
		state = snapshot
		render()
		break
	end
	task.wait(1)
end

-- Countdown labels. Runs while this LocalScript lives (until the player leaves).
while gui.Parent do
	task.wait(1)
	if state then
		state.questResetIn = math.max(0, state.questResetIn - 1)
		questTimer.Text = "New quests in " .. formatTime(state.questResetIn)
		if state.spin.secondsLeft > 0 then
			state.spin.secondsLeft -= 1
			if not spinning then
				spinButton.Text = if state.spin.secondsLeft > 0 then formatTime(state.spin.secondsLeft) else "Spin!"
				C.setButtonEnabled(spinButton, state.spin.secondsLeft <= 0)
			end
		end
	end
end
