--!strict
--[[
	Wallet
	Pure, engine-independent currency logic (no Roblox APIs), so it can be unit
	tested outside Studio and reused on the server.

	A wallet is a plain table: { [currencyName]: integer }.
	All amounts are whole numbers. Balances never go below zero and never exceed
	MAX_BALANCE. Every mutating function returns (ok, errorMessage?).

	Typical server usage:
		local Wallet = require(ReplicatedStorage.StarterKit.Shared.Wallet)
		local ok, err = Wallet.add(profile.wallet, "Coins", 50)
		local ok2, err2 = Wallet.spend(profile.wallet, "Coins", 30)
]]

local Wallet = {}

Wallet.MAX_BALANCE = 1e15 -- well inside the exact-integer range of a double

export type WalletData = { [string]: number }

local function isValidAmount(amount: any): boolean
	return type(amount) == "number"
		and amount == amount -- not NaN
		and amount >= 0
		and amount <= Wallet.MAX_BALANCE
		and math.floor(amount) == amount
end

local function isValidCurrency(currency: any): boolean
	return type(currency) == "string" and #currency > 0 and #currency <= 32
end

function Wallet.new(initial: WalletData?): WalletData
	local wallet: WalletData = {}
	if initial then
		for currency, amount in initial do
			assert(isValidCurrency(currency), "invalid currency name")
			assert(isValidAmount(amount), "invalid starting amount for " .. tostring(currency))
			wallet[currency] = amount
		end
	end
	return wallet
end

function Wallet.get(wallet: WalletData, currency: string): number
	return wallet[currency] or 0
end

function Wallet.canAfford(wallet: WalletData, currency: string, amount: number): boolean
	return isValidAmount(amount) and Wallet.get(wallet, currency) >= amount
end

function Wallet.add(wallet: WalletData, currency: string, amount: number): (boolean, string?)
	if not isValidCurrency(currency) then
		return false, "invalid currency"
	end
	if not isValidAmount(amount) then
		return false, "invalid amount"
	end
	local newBalance = Wallet.get(wallet, currency) + amount
	if newBalance > Wallet.MAX_BALANCE then
		return false, "balance cap reached"
	end
	wallet[currency] = newBalance
	return true, nil
end

function Wallet.spend(wallet: WalletData, currency: string, amount: number): (boolean, string?)
	if not isValidCurrency(currency) then
		return false, "invalid currency"
	end
	if not isValidAmount(amount) then
		return false, "invalid amount"
	end
	local balance = Wallet.get(wallet, currency)
	if balance < amount then
		return false, "insufficient funds"
	end
	wallet[currency] = balance - amount
	return true, nil
end

-- Formats a number for compact UI display: 950 -> "950", 1520 -> "1.5K",
-- 2_400_000 -> "2.4M". Trailing ".0" is removed ("3K", not "3.0K").
local SUFFIXES = { "K", "M", "B", "T", "Qa" }

function Wallet.format(amount: number): string
	local negative = amount < 0
	local value = math.abs(amount)
	if value < 1000 then
		local text = tostring(math.floor(value))
		return if negative then "-" .. text else text
	end
	local index = 0
	while value >= 1000 and index < #SUFFIXES do
		value /= 1000
		index += 1
	end
	value = math.floor(value * 10) / 10 -- round down, never overstate a balance
	local text = string.format("%.1f", value):gsub("%.0$", "")
	text ..= SUFFIXES[index]
	return if negative then "-" .. text else text
end

return Wallet
