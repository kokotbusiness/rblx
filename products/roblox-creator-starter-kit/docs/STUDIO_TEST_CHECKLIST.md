# Roblox Studio play-test checklist

Status: **NOT YET PERFORMED.** The kit was built and checked in an environment without
Roblox Studio. Work through this list once in Studio and fill in the Result column.

Open the demo place, press **Play** (single player) unless stated otherwise.

| # | Step | Expected | Result |
|---|------|----------|--------|
| 1 | Press Play, open Output window | No red errors from StarterKit scripts. Yellow warnings about placeholder ids 0 are expected. | |
| 2 | Look at top of screen | Coins (100) and Gems (0) pills | |
| 3 | Click **Quests** | Panel with 3 quest cards, progress bars, timer "New quests in hh:mm:ss" counting down | |
| 4 | Walk through gold coins | Coins increase by 5 per coin, "Collect 100 coins" quest (if active) progresses | |
| 5 | Jump 50 times / wait 15 min (whichever quest is active) | Quest shows Claim; clicking it adds reward, button turns "Claimed" | |
| 6 | Click **Spin** → Spin! | Highlight runs around tiles and stops; toast "You won …"; currency increases; button shows countdown | |
| 7 | Click Spin again | Disabled with countdown (server returns "spin on cooldown" if forced) | |
| 8 | Click **Shop** → buy "5 Apples" | Coins −50, toast "Purchased 5 Apples" | |
| 9 | Click **Backpack** | Apples ×5 in a grid with grey stroke; "Sort" works; clicking Starter Sword (after buying with Gems) equips it with a thick stroke | |
| 10 | Shop → gamepass / product with id 0 | Toast "Set the … id in KitConfig first" | |
| 11 | Create a test developer product, put its id in KitConfig, buy it in Studio (test purchase) | Currency granted once; Output has no errors | |
| 12 | With API access enabled: earn coins, stop, Play again | Coins persisted | |
| 13 | Resize the Studio window / Device emulator (phone) | Panels stay on screen and scroll | |
| 14 | Test → Start 2 players | Each player has own data; actions of one don't change the other | |

If any step fails, write down the Output error text and the step number.
