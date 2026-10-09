# Installing the kit in your own game

There are two ways. Pick one.

## A. Copy from the demo place (no tools needed)

1. Open the demo place `RobloxCreatorStarterKit-v1.0.0.rbxlx` and your game side by side.
2. In the demo place Explorer, copy and paste into **the same service** in your game:
   - `ReplicatedStorage › StarterKit` (folder with `Shared` and `UI`)
   - `ServerScriptService › StarterKitServer` (folder with `Main` and `StarterKitService`)
   - `StarterPlayer › StarterPlayerScripts › StarterKitClient`
   - optional: `ServerScriptService › StarterKitExamples` (demo coins, playtime/jump events)
3. Delete the "spawn demo coins" block in `CoinPickup` if you copied the examples.
4. Publish the game, then enable *Game Settings → Security → Enable Studio Access to API
   Services* if you want saving to work while testing in Studio.

## B. Rojo (for developers using VS Code)

```bash
rojo serve default.project.json      # live-sync into Studio with the Rojo plugin
rojo build default.project.json -o StarterKit.rbxlx
```

Merge the `tree` entries of `default.project.json` into your own project file
(skip `Workspace` and `StarterKitExamples` if you don't want the demo bits).

## Monetization setup

1. On https://create.roblox.com → your experience → *Monetization* create the
   gamepasses / developer products you want.
2. Paste their numeric ids into `KitConfig.shop` (ids of `0` are placeholders; the shop
   button tells the player to configure them, and the server prints a warning).
3. Developer products are granted through `ProcessReceipt` in `StarterKitService`.
   Only ONE script in a game may set `MarketplaceService.ProcessReceipt`. If your game
   already has one, merge the logic instead of keeping both.

## Saving notes

- Data store name: `StarterKit_PlayerData_v1`, key `player_<UserId>`.
- Saves on leave, every 120 s, and on server shutdown; purchases save immediately and
  are only confirmed to Roblox after the save succeeds.
- No session locking. For big games consider ProfileStore and call the pure modules
  from it — they don't care where the data is stored.
