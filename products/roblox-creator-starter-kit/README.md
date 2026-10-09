# Roblox Creator Starter Kit (v1.0.0)

Server-authoritative Luau systems + a clean, code-built UI for the features almost every
Roblox simulator/tycoon needs:

| System | What you get |
| --- | --- |
| **Currencies** | Multiple currencies, safe add/spend (no negative or fractional exploits), balance cap, compact number formatting (`1.5K`, `2.4M`), animated currency bar |
| **Daily quests** | Pool of quests, N per UTC day, same for every player (deterministic), progress from any game event in one line, claim-once, reset timer |
| **Daily spin** | Free daily reward wheel, weighted segments, odds computed and shown to players, server-side roll, cooldown timer |
| **Gamepass & product shop** | Gamepass ownership + perks (VIP 2x quest rewards), developer products with **idempotent `ProcessReceipt`** (never grants twice, only confirms after saving), soft-currency shop with automatic refund if the item doesn't fit |
| **Inventory / backpack** | Fixed capacity, stack limits, all-or-nothing add/remove, equip, sort by rarity, rarity-coloured grid |
| **Saving** | DataStore load/save with `UpdateAsync`, retries, autosave, `BindToClose`, schema `reconcile` for new fields |

Everything is configured in **one file**: `src/Shared/KitConfig.luau`.

## What has and has NOT been tested — please read

| Check | Status |
| --- | --- |
| 23 unit tests for all game logic (`tests/run.luau`) using the open-source Luau runtime | ✅ passing |
| Strict type check of the pure logic modules (`luau-analyze --mode=strict`) | ✅ passing |
| Strict type check of **all** scripts against the Roblox API definitions (`luau-lsp`) | ✅ passing |
| Rojo build of the demo place (`.rbxlx`) | ✅ builds |
| **Play-test inside Roblox Studio** | ❌ **not yet performed** — see `docs/STUDIO_TEST_CHECKLIST.md` |

The type check catches misspelled Roblox properties/methods, but it is not a substitute
for actually pressing Play in Studio. Until that checklist is completed, treat the
Roblox-facing scripts (`src/Server`, `src/Client`, `examples`) as unverified.

## Quick start (no extra tools)

1. Open `RobloxCreatorStarterKit-v1.0.0.rbxlx` in Roblox Studio (File → Open from File).
2. *Home → Game Settings → Security →* enable **Enable Studio Access to API Services**
   (only needed if you want saving to work in Studio; the experience must be published).
3. Press **Play**. Use the menu on the left: Quests, Spin, Shop, Backpack. Walk through
   the gold coins to earn Coins and quest progress.

To move it into your own game, see `docs/INSTALL.md`.

## Folder layout

```
src/Shared/        pure logic (no Roblox APIs) -> ReplicatedStorage.StarterKit.Shared
  KitConfig.luau   <- edit this
  Wallet / DailyQuests / DailySpin / Inventory / Shop / PlayerData
src/Server/        DataStore, remotes, receipts -> ServerScriptService.StarterKitServer
src/Client/        UI components + client script
examples/          coin pickups, playtime & jump quest events (demo only)
tests/run.luau     unit tests:  luau tests/run.luau
docs/              INSTALL, CUSTOMIZE, API, STUDIO_TEST_CHECKLIST
```

## License

See `LICENSE.txt`: use in unlimited games (commercial included); do not resell or
redistribute the source as a kit.
