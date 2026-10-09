# SURVIVE2EARN

A small, local, budget-limited system for building a real digital product and getting to the
**first 250 CZK of owner-verified net revenue**, with hard limits so it can't spend money, spam,
or keep running agents.

**Status right now:** product built, **0 CZK revenue, 0 sales, 0 CZK spent.** Nothing has been
published or sold. Nothing earns money while idle.

> Everything below runs from the repository root.

## What's here

| Path | What it is |
|------|------------|
| `products/roblox-creator-starter-kit/` | **The product.** Luau source, docs, examples, tests, demo place, build script, packaged zip in `dist/` |
| `products/EVALUATION.md` | Why this product was chosen, the evidence actually found, risks, kill criterion |
| `landing-page/index.html` | Responsive sales page (price placeholder, `LISTING_URL` placeholder for the CTA) |
| `marketing/` | Store description, launch post drafts, FAQ, channel list, pricing notes. Nothing is posted automatically |
| `missions/` | M000 bootstrap + M001–M005, each with measurable target, deliverable, acceptance criteria, outcome |
| `ledger.json` | Append-only, hash-chained log of **owner-verified** sales/refunds/expenses (empty) |
| `state.json` | Derived summary (status, revenue, expenses, failed attempts, permitted agents). Rebuilt by `s2e.py sync` |
| `workers.json` | The two possible bounded workers (locked) |
| `dashboard.html` | Local dashboard (static file, data embedded) |
| `s2e.py` / `s2e_core.py` / `dashboard.py` | Control CLI + rules engine (Python 3.9+, standard library only) |
| `tests/` | Rule tests (ledger, verification, spending, shutdown, agents) + product check runner |
| `tools/setup_dev_tools.sh` | Downloads free Luau/Rojo/luau-lsp binaries into `.tools/` (Linux x86_64) |

## Install

Requirements: Python 3.9+ (no packages), git. Optional for the product checks: Linux x86_64 + `curl`, `unzip`.

```bash
git clone https://github.com/kokotbusiness/rblx.git && cd rblx
./tools/setup_dev_tools.sh          # optional: free open-source Luau tools into .tools/
python3 -m unittest discover -s tests -v
```

On macOS/Windows the Python parts work as-is; download the matching Luau/Rojo/luau-lsp release
assets by hand and point `LUAU_BIN`, `LUAU_ANALYZE_BIN`, `ROJO_BIN`, `LUAU_LSP_BIN`, `ROBLOX_DEFS` at
them, or skip the product checks (the test reports them as *skipped*, not passed).

## Operate

```bash
python3 s2e.py status                      # one-screen status
python3 s2e.py dashboard                   # regenerate dashboard.html, then open it in a browser
python3 s2e.py validate                    # ledger chain + mission files + worker config
python3 s2e.py mission list
python3 s2e.py mission run M001            # shows the mission + the human steps (dry-run, changes nothing)
```

### Finish the bootstrap, then start mission M001
M000 (building everything) is waiting for **your** confirmation; only you can mark missions complete.

```bash
python3 s2e.py mission show M000           # read the acceptance criteria, check them
python3 s2e.py mission complete M000 --evidence "products/roblox-creator-starter-kit/dist/RobloxCreatorStarterKit-v1.0.0.zip, tests OK" --all-criteria-met
python3 s2e.py mission start M001
python3 s2e.py mission run M001            # follow the steps (Roblox Studio play-test)
python3 s2e.py mission complete M001 --evidence "checklist + media/*.png" --all-criteria-met
#   or, if it didn't work out:
python3 s2e.py mission fail M001 --reason "what went wrong"
```

### Recording money (owner only)
Only record what you checked in a real order, payout or bank record.

```bash
# a sale in CZK
python3 s2e.py ledger add --type sale --amount 300 --currency CZK --date 2026-10-20 --evidence "itch.io order #123456"
# a sale in USD: unreconciled (not counted) until you know the CZK that actually arrived
python3 s2e.py ledger add --type sale --amount 14 --currency USD --date 2026-10-20 --evidence "itch.io order #123456"
python3 s2e.py ledger reconcile --refers-to 1 --amount 268.50 --date 2026-11-02 --evidence "bank statement 2026-11 line 7"
# refunds / expenses / corrections
python3 s2e.py ledger add --type refund  --amount 300 --date ... --evidence "refund R-1"
python3 s2e.py ledger add --type expense --amount 25  --date ... --evidence "invoice 2026-14"
python3 s2e.py ledger add --type correction --amount -10 --refers-to 1 --date ... --evidence "typed 310 instead of 300"
python3 s2e.py ledger list | verify | export   # export writes JSON + CSV to backups/
```
Each `add` asks you to type `VERIFIED` (or pass `--confirm VERIFIED` in scripts). A backup is
written to `backups/` before every append. Use `--pending` when the money hasn't settled yet.

## Safety limits (enforced in code and tested)

- **Cash:** starts at 0 CZK. `spend-request` is always denied. The system never buys anything,
  creates accounts, collects credentials, sends email, publishes, or calls paid APIs.
  Expenses you make yourself can be recorded; if they exceed verified revenue the dashboard shows a **budget breach**.
- **Ledger:** append-only and hash-chained; hand edits, deletions and reordering are detected and
  **halt** the system. Entries need evidence. Foreign-currency or `--pending` entries are listed as
  *unreconciled* and never counted. Processes marked as agent/worker (`S2E_ROLE`) cannot write it.
- **Missions:** one bootstrap + at most **5** missions before the first verified sale; one active at a
  time; completion needs evidence and explicit confirmation that all acceptance criteria are met. A
  generated product is not a sale.
- **Shutdown:** when 5 missions have concluded without a verified sale the status becomes
  **DORMANT**: no missions start, no agents run, and `reports/failure-report.md` is written with a
  specific recovery experiment. Hard cap of 10 mission files in total.
- **Agents:** locked until owner-verified net revenue (sales − refunds − expenses) ≥ **250 CZK**
  and the ledger is valid. Then at most **2** workers (`product-improvement`,
  `market-research-distribution`), each enabled by you, each read-only (no Bash/Edit/Write/Agent),
  max 3 runs, timeout ≤ 15 min (hard ceiling 30 min), no nesting, output saved to `worker-output/`.
- **Runner:** every runner is **DRY-RUN by default** and needs `--execute`. It calls the installed
  `claude` CLI with `-p` and a subprocess timeout. It never uses `--dangerously-skip-permissions`
  and never runs in a background loop. No Anthropic API key is used or needed.

```bash
python3 s2e.py agents status
python3 s2e.py agents run product-improvement            # dry-run: prints the exact command
# only after unlock:
python3 s2e.py agents enable product-improvement
python3 s2e.py agents run product-improvement --execute  # one bounded run
```

## Launch (what you do, in order)

1. **M001 – Studio test.** Open `products/roblox-creator-starter-kit/dist/RobloxCreatorStarterKit-v1.0.0.rbxlx`
   in Roblox Studio, work through `docs/STUDIO_TEST_CHECKLIST.md`, take 4 screenshots.
2. **M002 – Publish.** Free itch.io account → new project → upload the zip from `dist/` → paste
   `marketing/product-description.md` → set price (see `marketing/pricing.md`) → publish → put the
   URL in place of `LISTING_URL` in `landing-page/index.html` (optional: host that page on itch.io
   or GitHub Pages yourself).
3. **M003 – Distribute** using `marketing/channels.md` and `marketing/launch-posts.md`.
4. Record any real sale with `s2e.py ledger add`, then `s2e.py dashboard`.

Rebuild the product after any code change:
```bash
python3 products/roblox-creator-starter-kit/tools/build.py
```

## What is NOT available / not simulated

- **Roblox Studio** is not available in the environment that built this; the Studio play-test is M001.
- **Payments**: no integration. You sell through a store account you create; sales are entered by hand.
- **Publishing / posting**: drafts only.
- **Market demand**: unverified. Only competitor listings were found (see `products/EVALUATION.md`).
