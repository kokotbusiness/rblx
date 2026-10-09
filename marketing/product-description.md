# Store listing text (paste into itch.io / Gumroad / Creator Store)

**Title:** Roblox Creator Starter Kit – Daily Quests, Daily Spin, Shop, Inventory & Currencies (Luau)

**Short description (≤ 140 chars):**
Server-side Luau systems + clean UI: daily quests, free daily spin, gamepass shop, backpack, currencies. One config file.

**Long description:**

Stop rebuilding the same five systems for every Roblox game. This kit gives you working,
connected versions of:

- **Daily quests** – a quest pool, N quests per UTC day, progress from any game event with one line, claim once, reset timer.
- **Daily spin** – a free reward wheel with weighted rewards; odds are computed and shown to players; the roll happens on the server.
- **Shop** – gamepasses with perks (example: VIP doubles quest rewards), developer products with a receipt handler that never grants twice and only confirms after saving, and a soft-currency shop that refunds automatically if the item doesn't fit.
- **Inventory / backpack** – capacity, stack limits, equip, sort by rarity, rarity-coloured grid.
- **Currencies** – multiple currencies, protection against negative/fractional amounts, compact formatting (1.5K, 2.4M), animated currency bar.
- **Saving** – DataStore with UpdateAsync, retries, autosave, save on shutdown, schema reconcile for new fields.

Everything gameplay-related is in one file: `KitConfig.luau`.

**What you download:** full Luau source, a demo place (.rbxlx – open in Studio and press Play),
a Rojo project file, install/customise/API docs, and the unit tests.

**Honest testing status:**
- ✅ 23 unit tests of the game logic pass (open-source Luau runtime)
- ✅ Every script passes a strict type check against the Roblox API definitions (luau-lsp)
- ✅ Demo place builds with Rojo
- ⏳ Roblox Studio play-test: *[OWNER: replace with "✅ Play-tested in Studio on <date>" after mission M001, or keep this line]*

**License:** use in unlimited own games, including commercial ones. No resale or redistribution of the source.

*Roblox is a trademark of Roblox Corporation. Independent product, not affiliated with Roblox.*

**Tags:** roblox, luau, roblox-studio, game-development, ui-kit, scripts, daily-rewards, shop-system, inventory
