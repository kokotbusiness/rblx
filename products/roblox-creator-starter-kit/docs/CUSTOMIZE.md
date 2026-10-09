# Customising

All gameplay data lives in `src/Shared/KitConfig.luau`.

## Add a currency
```lua
{ id = "Tickets", label = "Tickets", color = "#22D3EE", start = 0 },
```
Existing players get it automatically on next join (`PlayerData.reconcile`).

## Add a quest
```lua
{ id = "kill_10", event = "EnemyKilled", target = 10, title = "Defeat 10 enemies",
  reward = { currency = "Coins", amount = 120 } },
```
Then, wherever an enemy dies on the server: `Kit.recordQuestEvent(player, "EnemyKilled", 1)`.
Change `questsPerDay` to show more/fewer quests; change `seed` to reshuffle the rotation.

## Change wheel rewards / odds
Edit `KitConfig.spin.segments`. `weight` is relative (40 vs 10 = 4× more likely). The
UI shows the resulting percentage on each tile. Keep the wheel free; paid random rewards
fall under Roblox's paid random items rules.

## Add an item
```lua
KitConfig.items.bow = { name = "Hunter Bow", maxStack = 1, rarity = "Epic", order = 15 }
KitConfig.shop.offers.bow = { itemId = "bow", amount = 1, name = "Hunter Bow",
  price = { currency = "Gems", amount = 25 } }
```

## Restyle the UI
Change colours, fonts and corner radius in `Components.Theme`
(`src/Client/Components/Components.luau`). Every component reads from it.

## Run the tests after changes
```bash
luau tests/run.luau
```
(Download the free Luau CLI from https://github.com/luau-lang/luau/releases.)
