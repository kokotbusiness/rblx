--[[
	Example: feed "MinutesPlayed" and "Jumped" quest events.
	Shows how any game system reports progress with one line:
		Kit.recordQuestEvent(player, "<EventName>", amount)
	Event names must match the `event` field of quests in KitConfig.
]]
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Kit = require(ServerScriptService:WaitForChild("StarterKitServer"):WaitForChild("StarterKitService"))

local function onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Jumping then
			Kit.recordQuestEvent(player, "Jumped", 1)
		end
	end)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		onCharacter(player, player.Character)
	end
	-- One "MinutesPlayed" tick per minute while the player is in the server.
	task.spawn(function()
		while player.Parent do
			task.wait(60)
			if player.Parent then
				Kit.recordQuestEvent(player, "MinutesPlayed", 1)
			end
		end
	end)
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayer, player)
end
