# FAQ (for the store page and for answering questions)

**Do I need Rojo or VS Code?**
No. Open the demo place in Roblox Studio and copy three folders into your game (docs/INSTALL.md). Rojo is optional.

**Has it been tested in Roblox Studio?**
[OWNER: answer truthfully. Until mission M001 is done: "The logic is unit-tested and all scripts pass a strict type check against the Roblox API, but a full Studio play-test is still pending."]

**Is the daily spin a loot box?**
It's free, once per day, and shows its odds. If you make spins purchasable, Roblox's rules on paid random items apply – check them first.

**Can developer products be granted twice?**
The receipt handler remembers purchase IDs, confirms to Roblox only after saving, and has unit tests for duplicate and failed grants.

**Does it support ProfileStore / my own data layer?**
Yes – the game logic modules don't call any Roblox APIs; replace the saving part in StarterKitService.

**Mobile?**
Panels use scale-based sizes with a max size and scroll. Check on Studio's device emulator (checklist step 13).

**Can I resell or share it?**
No. Unlimited use in your own games (also commercial), no redistribution of the source.

**Updates?**
v1.x updates are free through the same store page.

**Refunds?**
[OWNER: define a policy before publishing, e.g. "If it doesn't work as described, message me within 14 days."]
