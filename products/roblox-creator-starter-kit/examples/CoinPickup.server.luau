--[[
	Example: coins that give currency and quest progress.
	Any BasePart tagged "StarterKitCoin" (Tag Editor / CollectionService) becomes
	a coin. For the demo place, this script also spawns a ring of 12 coins.
	Delete the "spawn demo coins" block in your own game.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Kit = require(ServerScriptService:WaitForChild("StarterKitServer"):WaitForChild("StarterKitService"))

local COIN_TAG = "StarterKitCoin"
local COIN_VALUE = 5
local RESPAWN_SECONDS = 8

-- spawn demo coins -------------------------------------------------------
for i = 1, 12 do
	local angle = i / 12 * math.pi * 2
	local coin = Instance.new("Part")
	coin.Name = "Coin"
	coin.Shape = Enum.PartType.Cylinder
	coin.Size = Vector3.new(0.4, 2.5, 2.5)
	coin.Color = Color3.fromHex("#F5C542")
	coin.Material = Enum.Material.Neon
	coin.Anchored = true
	coin.CanCollide = false
	coin.CFrame = CFrame.new(math.cos(angle) * 20, 3, math.sin(angle) * 20) * CFrame.Angles(0, 0, math.rad(90))
	coin.Parent = workspace
	CollectionService:AddTag(coin, COIN_TAG)
end
-- end demo coins -----------------------------------------------------------

local function setupCoin(coin: Instance)
	if not coin:IsA("BasePart") then
		return
	end
	local available = true
	coin.Touched:Connect(function(hit)
		if not available then
			return
		end
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end
		available = false
		coin.Transparency = 1
		Kit.addCurrency(player, "Coins", COIN_VALUE)
		Kit.recordQuestEvent(player, "CoinsCollected", COIN_VALUE)
		task.delay(RESPAWN_SECONDS, function()
			coin.Transparency = 0
			available = true
		end)
	end)
end

for _, coin in CollectionService:GetTagged(COIN_TAG) do
	setupCoin(coin)
end
CollectionService:GetInstanceAddedSignal(COIN_TAG):Connect(setupCoin)
