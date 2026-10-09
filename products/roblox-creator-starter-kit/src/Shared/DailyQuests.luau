--!strict
--[[
	DailyQuests
	Engine-independent daily quest logic. No Roblox APIs: time is passed in as a
	Unix timestamp (use os.time() on the server), so the module is unit-testable.

	Each UTC day, every player gets the same `questsPerDay` quests picked from
	the pool (deterministic per day + seed, so it's fair and reproducible).
	Progress is reported with events, e.g. Quests.recordEvent(state, def, "CoinsCollected", 5, now).

	Quest definition:
		{ id = "collect_coins", event = "CoinsCollected", target = 100,
		  title = "Collect 100 coins", reward = { currency = "Coins", amount = 50 } }

	Player state (save this in your player data):
		{ day = 20000, quests = { { id = "...", progress = 0, claimed = false }, ... } }
]]

local DailyQuests = {}

local SECONDS_PER_DAY = 86400

export type Reward = { currency: string, amount: number }
export type QuestDef = { id: string, event: string, target: number, title: string, reward: Reward }
export type Config = { pool: { QuestDef }, questsPerDay: number, seed: number? }
export type QuestProgress = { id: string, progress: number, claimed: boolean }
export type State = { day: number, quests: { QuestProgress } }

function DailyQuests.dayIndex(now: number): number
	return math.floor(now / SECONDS_PER_DAY)
end

function DailyQuests.secondsUntilReset(now: number): number
	return SECONDS_PER_DAY - (math.floor(now) % SECONDS_PER_DAY)
end

-- Validates a config and returns (ok, errorMessage?). Call once at startup.
function DailyQuests.validateConfig(config: Config): (boolean, string?)
	if type(config.pool) ~= "table" or #config.pool == 0 then
		return false, "pool must contain at least one quest"
	end
	if type(config.questsPerDay) ~= "number" or config.questsPerDay < 1 or config.questsPerDay > #config.pool then
		return false, "questsPerDay must be between 1 and the pool size"
	end
	local seen: { [string]: boolean } = {}
	for _, quest in config.pool do
		if type(quest.id) ~= "string" or seen[quest.id] then
			return false, "quest ids must be unique strings"
		end
		seen[quest.id] = true
		if type(quest.target) ~= "number" or quest.target < 1 or math.floor(quest.target) ~= quest.target then
			return false, "quest " .. quest.id .. " needs a whole-number target >= 1"
		end
		if type(quest.reward) ~= "table" or type(quest.reward.amount) ~= "number" or quest.reward.amount < 0 then
			return false, "quest " .. quest.id .. " has an invalid reward"
		end
	end
	return true, nil
end

-- Small deterministic PRNG (LCG) so quest selection is identical on every
-- server and in tests. Not for anything security sensitive.
local function lcg(seed: number): () -> number
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function(): number
		state = (state * 48271) % 2147483647
		return state
	end
end

-- Returns the quest definitions active on the given day.
function DailyQuests.questsForDay(config: Config, day: number): { QuestDef }
	local indices = {}
	for i = 1, #config.pool do
		indices[i] = i
	end
	local nextRandom = lcg(day * 7919 + (config.seed or 0) + 1)
	-- Fisher-Yates shuffle
	for i = #indices, 2, -1 do
		local j = (nextRandom() % i) + 1
		indices[i], indices[j] = indices[j], indices[i]
	end
	local result = {}
	for i = 1, config.questsPerDay do
		table.insert(result, config.pool[indices[i]])
	end
	return result
end

local function findDef(config: Config, id: string): QuestDef?
	for _, quest in config.pool do
		if quest.id == id then
			return quest
		end
	end
	return nil
end

-- Makes sure state belongs to today; resets it on a new day.
-- Returns the (possibly new) state and whether a reset happened.
function DailyQuests.refresh(state: State?, config: Config, now: number): (State, boolean)
	local today = DailyQuests.dayIndex(now)
	if state and state.day == today then
		return state, false
	end
	local fresh: State = { day = today, quests = {} }
	for _, quest in DailyQuests.questsForDay(config, today) do
		table.insert(fresh.quests, { id = quest.id, progress = 0, claimed = false })
	end
	return fresh, true
end

-- Adds progress to every active quest listening to `event`.
-- Returns the ids of quests that became complete because of this event.
function DailyQuests.recordEvent(state: State, config: Config, event: string, amount: number, now: number): { string }
	assert(state.day == DailyQuests.dayIndex(now), "state is stale; call refresh first")
	if type(amount) ~= "number" or amount <= 0 or amount ~= amount then
		return {}
	end
	local completed = {}
	for _, progress in state.quests do
		local def = findDef(config, progress.id)
		if def and def.event == event and progress.progress < def.target then
			progress.progress = math.min(def.target, progress.progress + amount)
			if progress.progress >= def.target then
				table.insert(completed, def.id)
			end
		end
	end
	return completed
end

-- Claims a finished quest. Returns (reward?, errorMessage?).
-- The caller (server) must then add the reward to the player's wallet.
function DailyQuests.claim(state: State, config: Config, questId: string, now: number): (Reward?, string?)
	if state.day ~= DailyQuests.dayIndex(now) then
		return nil, "quests expired"
	end
	for _, progress in state.quests do
		if progress.id == questId then
			local def = findDef(config, questId)
			if not def then
				return nil, "unknown quest"
			end
			if progress.claimed then
				return nil, "already claimed"
			end
			if progress.progress < def.target then
				return nil, "quest not complete"
			end
			progress.claimed = true
			return { currency = def.reward.currency, amount = def.reward.amount }, nil
		end
	end
	return nil, "quest not active today"
end

return DailyQuests
