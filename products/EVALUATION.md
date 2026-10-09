# Product evaluation – Roblox Creator Starter Kit (2026-10-09)

## Decision: GO (as the first experiment), with demand still UNVERIFIED

## Evidence actually obtained (web search on 2026-10-09)
Supply side – comparable paid products exist, which shows people *list* such kits;
it does NOT prove anyone buys them:
- itch.io "Daily Reward System + Ui" (eurydion) – listed at $1+ — https://eurydion.itch.io/dailyrewardsystem
- itch.io "RBLX Essentials Complete Bundle" – $34.99 — https://itch.io/s/180622/rblx-essentials-complete-bundle
- BuiltByBit "Essential STUD UI Pack" (shop + daily rewards, ProfileStore) — https://builtbybit.com/resources/essential-stud-ui-pack.113172/
- BuiltByBit "Cartoony UI Kit 25+ Frames" – $9.99 — https://builtbybit.com/resources/cartoony-ui-kit-25-frames.117327/
- BuiltByBit "High Quality GUI Pack" – UI only, "does NOT have any scripts"
- Gumroad "DevX Essentials: UI Master Bundle" — https://w4rl0ck.gumroad.com/l/dzsnbz
- Roblox Creator Store supports USD-priced models/plugins via a Stripe seller account
  (ID verification required) — https://create.roblox.com/docs/production/publishing/selling-on-the-creator-store

Not obtained: sales numbers, download counts, conversion rates. No demand claim is made.

## Why it is still a reasonable first bet
- Zero cost to build and to list (itch.io / Gumroad free tiers; fees only on sales).
- Price range $1–$35 observed; one sale at ~$12–15 can reach the 250 CZK goal.
- Differentiation we can actually demonstrate: logic + UI together (many packs are
  UI-only), unit tests, strict Roblox API type check, idempotent receipt handling,
  honest "tested / not tested" table.
- It could be built and partially verified in this environment (Luau runtime, Rojo,
  luau-lsp all free and runnable here).

## Risks
- Crowded niche, many cheap/free alternatives (incl. free Creator Store models).
- No Roblox Studio here → the Roblox-facing scripts are unverified until mission M001.
- Selling on Creator Store needs ID verification + Stripe (human action, may not be
  possible depending on owner's country/age).
- No audience/distribution yet: the realistic bottleneck is reaching buyers, not code.

## Kill criterion
If missions M001–M005 end without one verified sale, stop (DORMANT) and run the
recovery experiment in the failure report instead of building more features.
