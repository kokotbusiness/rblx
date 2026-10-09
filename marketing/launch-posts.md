# Launch post drafts (NOT posted automatically – the owner posts by hand)

Before posting anywhere: read that place's current self-promotion rules (see channels.md),
post once, disclose that you made it and that it is paid, and replace the placeholders.
Never post in places whose rules forbid paid promotion.

---

## A. Show-and-tell / feedback post (forums, subreddits that allow it)

**Title:** I built a daily quests + daily spin + shop + backpack kit with unit-tested Luau – feedback welcome

Hi! I've been building a reusable set of systems that most simulator/tycoon games need:
daily quests, a free daily spin (odds shown on every tile), a gamepass/product shop,
an inventory with equip/sort, and multiple currencies – all server-authoritative and
configured from a single `KitConfig` file.

Things I focused on:
- Developer product receipts are idempotent (remembered by PurchaseId, confirmed only after saving)
- The game logic is pure Luau, so it has 23 unit tests that run outside Studio
- Every script passes a strict luau-lsp type check against the Roblox API

[IMAGE/GIF from Studio]

Full disclosure: it's a paid kit ($PRICE) – link: LISTING_URL.
Happy to answer questions about how any part works, and I'd like to hear what's missing.

---

## B. Short post (X / Bluesky / Threads) – max ~280 chars

Made a Roblox starter kit: daily quests, free daily spin with visible odds, gamepass shop,
backpack & currencies. Server-side Luau, one config file, 23 unit tests.
[GIF]  LISTING_URL  #RobloxDev #Luau

---

## C. Short video script (YouTube Shorts / TikTok, 30–45 s, screen recording from Studio)

1. (0–3 s) "Five systems every Roblox simulator needs – in one kit."
2. (3–12 s) Open Quests → collect coins → Claim → currency bar pops.
3. (12–20 s) Spin → highlight stops → toast "You won 75 Coins".
4. (20–28 s) Shop → buy apples → Backpack → sort → equip sword.
5. (28–38 s) Show KitConfig: "Change everything here."
6. (38–45 s) "Link in description." (Paid kit, say so.)

---

## D. Reply template when someone asks "how do I make daily rewards / a shop?"

Only where helpful and allowed. Answer the question first with real advice (e.g. store
`lastClaimedDay = math.floor(os.time()/86400)` on the server; never trust the client).
Then optionally: "I packaged my implementation as a kit if you'd rather not build it:
LISTING_URL (paid, I made it)."
