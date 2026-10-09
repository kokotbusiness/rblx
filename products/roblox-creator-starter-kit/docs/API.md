# API reference

## Server API (`ServerScriptService.StarterKitServer.StarterKitService`)

```lua
local Kit = require(game.ServerScriptService.StarterKitServer.StarterKitService)

Kit.recordQuestEvent(player, "CoinsCollected", 5) -- progress quests whose event matches
Kit.addCurrency(player, "Coins", 10)               --> boolean
Kit.giveItem(player, "apple", 3)                   --> ok, err ("inventory full", ...)
Kit.ownsGamepass(player, "vip")                    --> boolean (key from KitConfig.shop.gamepasses)
Kit.save(player)                                   --> boolean
```

## Remotes (created by the server in `ReplicatedStorage.StarterKit.Remotes`)

| Name | Type | Args | Returns |
|------|------|------|---------|
| GetState | RemoteFunction | – | state snapshot or nil while loading |
| ClaimQuest | RemoteFunction | questId | ok, message |
| Spin | RemoteFunction | – | ok, segmentIndex \| error |
| BuyOffer | RemoteFunction | offerKey | ok, error? |
| Equip | RemoteFunction | itemId or nil | ok, error? |
| SortInventory | RemoteFunction | – | ok |
| StateChanged | RemoteEvent (server→client) | snapshot | – |
| Notify | RemoteEvent (server→client) | text, kind | – |

All requests are validated on the server and rate-limited (0.25 s per player).

## Pure modules (`ReplicatedStorage.StarterKit.Shared`)

Usable on server or client, no Roblox APIs, unit-tested.

- **Wallet**: `new(initial?)`, `get`, `canAfford`, `add`, `spend` → `(ok, err?)`, `format(n)`.
- **DailyQuests**: `validateConfig`, `dayIndex(now)`, `secondsUntilReset(now)`,
  `questsForDay(config, day)`, `refresh(state?, config, now)` → `(state, didReset)`,
  `recordEvent(state, config, event, amount, now)` → completed ids,
  `claim(state, config, id, now)` → `(reward?, err?)`.
- **DailySpin**: `validateConfig`, `odds(config)`, `pickIndex(config, r)`,
  `secondsUntilNextSpin`, `canSpin`, `spin(state, config, now, random)` → `(index?, reward?, err?)`.
- **Inventory**: `new(capacity)`, `count`, `spaceFor`, `add`/`remove` (all-or-nothing),
  `equip(data, itemId?)`, `sort(data, catalog)`.
- **Shop**: `validateCatalog` → `(ok, errors, warnings)`, `findProductById`,
  `newReceiptLog`, `processReceipt(catalog, log, receipt, grant)` →
  `"Granted" | "AlreadyGranted" | "UnknownProduct" | "GrantFailed"`, `buyOffer(catalog, key, deps)`.
- **PlayerData**: `default(config)`, `reconcile(data, template)`, `deepCopy`.

## UI components (`ReplicatedStorage.StarterKit.UI.Components`)

`Panel`, `Button`, `CurrencyPill` + `setCurrency`, `ProgressBar`, `QuestCard`,
`ShopCard`, `InventorySlot`, `Toast`. Restyle everything via `Components.Theme`.
