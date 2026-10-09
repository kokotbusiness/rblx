# Roblox Studio play-test checklist

Status: **PARTLY PERFORMED** (2026-10-10, Roblox Studio via Studio MCP, single player, unpublished
place = no DataStore access). Steps marked TODO still need a human (11 and 12 also need the place
published to an experience). Two bugs were found and fixed
in `src/` / `default.project.json` during the test (see notes); `dist/` must be rebuilt with
`tools/build.py` (needs Rojo) before packaging, the old `dist/*.rbxlx` still contains them.

Open the demo place, press **Play** (single player) unless stated otherwise.

| # | Step | Expected | Result |
|---|------|----------|--------|
| 1 | Press Play, open Output window | No red errors from StarterKit scripts. Yellow warnings about placeholder ids 0 are expected. | **FAILED, fixed, PASS after fix.** v1.0.0 threw "The Parent property of TextButton is locked" in `renderSpin` (StarterKitClient) on the first render, so Spin, Shop and Backpack never rendered. Fixed (button is unparented before the old ring is destroyed). After the fix only the expected warnings: DataStore unavailable (unpublished place) + 3 placeholder ids. |
| 2 | Look at top of screen | Coins (100) and Gems (0) pills | PASS (screenshot) |
| 3 | Click **Quests** | Panel with 3 quest cards, progress bars, timer "New quests in hh:mm:ss" counting down | PASS. Timer counted down (01:33:14 → 01:33:08). |
| 4 | Walk through gold coins | Coins increase by 5 per coin, "Collect 100 coins" quest (if active) progresses | **FAILED, fixed, PASS after fix.** In the built place the Baseplate/SpawnLocation were at Y=0 (Rojo ignores `Position`; needs `CFrame`), so the baseplate top was at Y=10 and all 12 coins (Y=3) were buried. Fixed in `default.project.json`. After the fix: 2 coins → 100 → 110, coin hides and respawns. Coin quest was not active that day, its progress was NOT observed. |
| 5 | Jump 50 times / wait 15 min (whichever quest is active) | Quest shows Claim; clicking it adds reward, button turns "Claimed" | PASS for the playtime quest: stayed in Play 15 min, "Play for 15 minutes" went 1 → 6 → 11 → 15/15, showed Claim; clicking it gave toast "+75 Coins" and "Claimed". The jump quest was not active that day, so 50 jumps were NOT done; the server did receive jump events (3 jumps → 3 `Jumping` states). |
| 6 | Click **Spin** → Spin! | Highlight runs around tiles and stops; toast "You won …"; currency increases; button shows countdown | PASS. Highlight ran and stopped, button showed 23:59:51, coins increased. Toast "You won 1,000 Coins!" seen 3.4 s after clicking (second session; coins 100 → 1.1K). Note: the final highlight disappears when another state update re-renders the wheel. |
| 7 | Click Spin again | Disabled with countdown (server returns "spin on cooldown" if forced) | PASS. Button disabled with countdown; forced `Spin` remote returned `false, "spin on cooldown"`. |
| 8 | Click **Shop** → buy "5 Apples" | Coins −50, toast "Purchased 5 Apples" | PASS (345 → 295, toast seen). |
| 9 | Click **Backpack** | Apples ×5 in a grid with grey stroke; "Sort" works; clicking Starter Sword (after buying with Gems) equips it with a thick stroke | PASS. Apple ×5 in the grid with stroke 1.5. Starter Sword bought (to afford it with the 2 quest Gems its price was temporarily set to 2 in the open place only, then set back to 10; a second buy correctly failed with "insufficient funds"). Sort moved the Sword before the Apple; clicking the Sword equipped it with the thick stroke (3). |
| 10 | Shop → gamepass / product with id 0 | Toast "Set the … id in KitConfig first" | PASS for VIP ("Set the gamepass id …") and 1,000 Coins ("Set the product id …"). |
| 11 | Create a test developer product, put its id in KitConfig, buy it in Studio (test purchase) | Currency granted once; Output has no errors | TODO (needs a human: create product). |
| 12 | With API access enabled: earn coins, stop, Play again | Coins persisted | TODO (needs a published place + API access). |
| 13 | Resize the Studio window / Device emulator (phone) | Panels stay on screen and scroll | TODO (needs a human). |
| 14 | Test → Start 2 players | Each player has own data; actions of one don't change the other | TODO (needs a human). |

If any step fails, write down the Output error text and the step number.

Also fixed (code review, not a checklist step): with a *published* place but Studio API access off,
`GetAsync` fails with `StudioAccessToApisNotAllowed` and the server kicked the player. It now plays
with unsaved data and warns. This path was NOT exercised in the test above (the place was unpublished).
