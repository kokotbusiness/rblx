--!strict
--[[
	DailySpin
	Engine-independent logic for a FREE daily reward wheel.

	* The roll always happens on the server. The client only receives the result
	  index so it can animate the wheel to the right segment.
	* Randomness is injected (`random` returns a number in [0, 1)), so the server
	  can pass `function() return rng:NextNumber() end` with a Roblox `Random`
	  object and tests can pass a fixed sequence.
	* Odds are computed from the weights so you can show them to players.

	Policy note: this wheel is designed to be free. If you ever let players pay
	Robux (directly or indirectly) for spins, Roblox's rules on paid random items
	apply (e.g. disclosing odds before purchase). Check the current Roblox
	policies yourself before doing that.

	Segment definition:
		{ id = "coins_small", label = "50 Coins", weight = 40,
		  reward = { currency = "Coins", amount = 50 } }
]]

local DailySpin = {}

export type Reward = { currency: string, amount: number }
export type Segment = { id: string, label: string, weight: number, reward: Reward, color: string? }
export type Config = { segments: { Segment }, cooldownSeconds: number }
export type State = { lastSpinAt: number? }

function DailySpin.validateConfig(config: Config): (boolean, string?)
	if type(config.segments) ~= "table" or #config.segments < 2 then
		return false, "the wheel needs at least two segments"
	end
	if type(config.cooldownSeconds) ~= "number" or config.cooldownSeconds < 0 then
		return false, "cooldownSeconds must be >= 0"
	end
	local total = 0
	local seen: { [string]: boolean } = {}
	for _, segment in config.segments do
		if type(segment.id) ~= "string" or seen[segment.id] then
			return false, "segment ids must be unique strings"
		end
		seen[segment.id] = true
		if type(segment.weight) ~= "number" or segment.weight < 0 or segment.weight ~= segment.weight then
			return false, "segment " .. segment.id .. " has an invalid weight"
		end
		if type(segment.reward) ~= "table" or type(segment.reward.amount) ~= "number" or segment.reward.amount < 0 then
			return false, "segment " .. segment.id .. " has an invalid reward"
		end
		total += segment.weight
	end
	if total <= 0 then
		return false, "total weight must be greater than zero"
	end
	return true, nil
end

-- Seconds the player still has to wait (0 = can spin now).
function DailySpin.secondsUntilNextSpin(state: State, config: Config, now: number): number
	if state.lastSpinAt == nil then
		return 0
	end
	return math.max(0, (state.lastSpinAt :: number) + config.cooldownSeconds - now)
end

function DailySpin.canSpin(state: State, config: Config, now: number): boolean
	return DailySpin.secondsUntilNextSpin(state, config, now) == 0
end

-- Probability of each segment, in segment order. Values sum to 1.
function DailySpin.odds(config: Config): { number }
	local total = 0
	for _, segment in config.segments do
		total += segment.weight
	end
	local result = {}
	for i, segment in config.segments do
		result[i] = segment.weight / total
	end
	return result
end

-- Picks a segment index for a value r in [0, 1).
function DailySpin.pickIndex(config: Config, r: number): number
	assert(r >= 0 and r < 1, "random value must be in [0, 1)")
	local total = 0
	for _, segment in config.segments do
		total += segment.weight
	end
	local threshold = r * total
	local cumulative = 0
	local lastPositive = 1
	for i, segment in config.segments do
		if segment.weight > 0 then
			cumulative += segment.weight
			lastPositive = i
			if threshold < cumulative then
				return i
			end
		end
	end
	return lastPositive -- floating point safety net
end

-- Performs a spin. Returns (segmentIndex?, reward?, errorMessage?).
-- On success, state.lastSpinAt is updated; the caller grants the reward.
function DailySpin.spin(state: State, config: Config, now: number, random: () -> number): (number?, Reward?, string?)
	if not DailySpin.canSpin(state, config, now) then
		return nil, nil, "spin on cooldown"
	end
	local index = DailySpin.pickIndex(config, random())
	local segment = config.segments[index]
	state.lastSpinAt = now
	return index, { currency = segment.reward.currency, amount = segment.reward.amount }, nil
end

return DailySpin
