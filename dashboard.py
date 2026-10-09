"""Renders dashboard.html: a single static file with the data embedded, so it
opens straight from disk (no server, no network, no JavaScript needed)."""
from __future__ import annotations

from decimal import Decimal
from html import escape

STATUS_TEXT = {
    "AWAITING_NEXT_MISSION": ("Awaiting next mission", "neutral"),
    "MISSION_ACTIVE": ("Mission active", "info"),
    "FIRST_SALE_VERIFIED": ("First sale verified", "good"),
    "UNLOCKED_STAGE_2": ("Stage 2 unlocked", "good"),
    "DORMANT": ("DORMANT - stop and review", "bad"),
    "HALTED_LEDGER_INVALID": ("HALTED - ledger invalid", "bad"),
}
NOT_RECONCILED = '<span class="badge warn">no</span>'
MISSION_BADGE = {"planned": "neutral", "active": "info", "completed": "good", "failed": "bad"}


def _e(v) -> str:
    return escape("" if v is None else str(v))


def render_dashboard(state: dict, ledger: dict, fin: dict) -> str:
    revenue = Decimal(state["verified_net_revenue_czk"])
    goal = Decimal(state["unlock_threshold_czk"])
    pct = 0 if goal <= 0 else max(0, min(100, int(revenue / goal * 100)))
    label, tone = STATUS_TEXT.get(state["status"], (state["status"], "neutral"))
    unlocked = state["agent_spawning_unlocked"]

    mission_rows = "".join(
        f"<tr><td class=mono>{_e(m['id'])}</td><td>{_e(m['title'])}"
        f"<div class=muted>{_e(m.get('measurable_target'))}</div></td>"
        f"<td>{_e(m['executor'])}</td>"
        f"<td><span class='badge {MISSION_BADGE.get(m['status'], 'neutral')}'>{_e(m['status'])}</span></td>"
        f"<td class=muted>{_e(m.get('outcome') or '')}</td></tr>"
        for m in state["missions"]
    )
    failed = "".join(f"<li><b>{_e(f['id'])}</b> {_e(f['title'])} - {_e(f['outcome'])}</li>"
                     for f in state["failed_attempts"]) or "<li class=muted>None</li>"
    entries = ledger.get("entries", [])
    ledger_rows = "".join(
        f"<tr><td class=mono>#{e['id']}</td><td>{_e(e['date'])}</td><td>{_e(e['type'])}</td>"
        f"<td class=num>{_e(e['amount'])} {_e(e['currency'])}</td>"
        f"<td class=num>{_e(e['czk_amount'] or '-')}</td>"
        f"<td>{'yes' if e['reconciled'] else NOT_RECONCILED}</td>"
        f"<td class=muted>{_e(e['evidence'])}</td></tr>"
        for e in reversed(entries)
    ) or "<tr><td colspan=7 class=muted>No verified money events yet. Revenue is 0 CZK until the owner records a real sale.</td></tr>"
    services = "".join(f"<li><b>{_e(k.replace('_', ' '))}:</b> {_e(v)}</li>"
                       for k, v in state["external_services"].items())
    problems = state["ledger_problems"] + state["mission_file_problems"]
    problem_html = ("<div class='alert bad'><b>Problems</b><ul>" +
                    "".join(f"<li>{_e(p)}</li>" for p in problems) + "</ul></div>") if problems else ""
    breach = ("<div class='alert bad'><b>Budget breach:</b> recorded expenses exceed verified revenue. "
              "The zero-cash rule was broken outside this system.</div>") if state["budget_breach"] else ""

    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>SURVIVE2EARN Dashboard</title>
<style>
:root {{ --bg:#f6f7fb; --card:#fff; --text:#141826; --muted:#5d6475; --line:#e3e6ee;
  --good:#1f9d5c; --bad:#d23f45; --info:#3f6be0; --warn:#b7791f; --neutral:#6b7280; --bar:#e8ebf3; }}
@media (prefers-color-scheme: dark) {{ :root {{ --bg:#0f1220; --card:#181c2e; --text:#eef1f8; --muted:#9aa3ba;
  --line:#2a3148; --bar:#2a3148; }} }}
* {{ box-sizing:border-box }}
body {{ margin:0; font:15px/1.5 system-ui,-apple-system,Segoe UI,Roboto,sans-serif; background:var(--bg); color:var(--text) }}
main {{ max-width:1100px; margin:0 auto; padding:24px 16px 48px }}
h1 {{ font-size:22px; margin:0 }} h2 {{ font-size:16px; margin:0 0 12px }}
header {{ display:flex; flex-wrap:wrap; gap:12px; align-items:center; justify-content:space-between; margin-bottom:20px }}
.grid {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(220px,1fr)); gap:14px; margin-bottom:14px }}
.card {{ background:var(--card); border:1px solid var(--line); border-radius:14px; padding:16px; margin-bottom:14px; overflow-x:auto }}
.grid .card {{ margin:0 }}
.kpi {{ font-size:28px; font-weight:700; font-variant-numeric:tabular-nums }}
.muted {{ color:var(--muted); font-size:13px }}
.mono {{ font-family:ui-monospace,Menlo,monospace }}
.num {{ text-align:right; font-variant-numeric:tabular-nums; white-space:nowrap }}
.bar {{ height:10px; background:var(--bar); border-radius:99px; overflow:hidden; margin:8px 0 4px }}
.bar > div {{ height:100%; background:var(--good); width:{pct}% }}
.badge {{ display:inline-block; padding:2px 10px; border-radius:99px; font-size:12px; font-weight:600; color:#fff; white-space:nowrap }}
.badge.good {{ background:var(--good) }} .badge.bad {{ background:var(--bad) }} .badge.info {{ background:var(--info) }}
.badge.warn {{ background:var(--warn) }} .badge.neutral {{ background:var(--neutral) }}
.alert {{ border-radius:12px; padding:12px 16px; margin-bottom:14px; border:1px solid var(--bad) }}
table {{ width:100%; border-collapse:collapse; font-size:14px }}
th, td {{ text-align:left; padding:8px 6px; border-bottom:1px solid var(--line); vertical-align:top }}
th {{ font-size:12px; text-transform:uppercase; letter-spacing:.04em; color:var(--muted) }}
ul {{ margin:0; padding-left:18px }}
code {{ font-family:ui-monospace,Menlo,monospace; font-size:13px }}
</style>
</head>
<body><main>
<header>
  <div><h1>SURVIVE2EARN</h1><div class=muted>{_e(state['mission'])}</div></div>
  <span class="badge {tone}" style="font-size:14px;padding:6px 14px">{_e(label)}</span>
</header>
{problem_html}{breach}
<div class=grid>
  <div class=card><div class=muted>Verified net revenue</div>
    <div class=kpi>{_e(state['verified_net_revenue_czk'])} CZK</div>
    <div class=bar><div></div></div>
    <div class=muted>{pct}% of {_e(state['unlock_threshold_czk'])} CZK goal &middot; owner-verified entries only</div></div>
  <div class=card><div class=muted>Actual expenses</div>
    <div class=kpi>{_e(state['actual_expenses_czk'])} CZK</div>
    <div class=muted>Starting business cash: {_e(state['initial_cash_czk'])} CZK</div></div>
  <div class=card><div class=muted>Verified sales</div>
    <div class=kpi>{_e(state['verified_sale_count'])}</div>
    <div class=muted>Unreconciled (not counted): {_e(state['unreconciled_entry_count'])}</div></div>
  <div class=card><div class=muted>Agent spawning</div>
    <div class=kpi>{'Unlocked' if unlocked else 'Locked'}</div>
    <div class=muted>{'Up to 2 bounded workers; owner must enable each.' if unlocked else 'Unlocks at 250 CZK verified net revenue.'}
    Enabled: {_e(', '.join(state['enabled_workers']) or 'none')}</div></div>
</div>
<div class=grid>
  <div class=card><div class=muted>Mission progress</div>
    <div class=kpi>{_e(state['missions_concluded_without_sale'])} / {_e(state['max_missions_before_sale'])}</div>
    <div class=muted>missions concluded without a sale (5 = DORMANT)</div></div>
  <div class=card><div class=muted>Active mission</div>
    <div class=kpi>{_e(state['active_mission'] or '-')}</div>
    <div class=muted>Next planned: {_e(state['next_planned_mission'] or '-')}</div></div>
  <div class=card><div class=muted>Ledger integrity</div>
    <div class=kpi>{'Valid' if state['ledger_valid'] else 'INVALID'}</div>
    <div class=muted>Append-only, hash-chained</div></div>
</div>
<div class=card><h2>Missions</h2>
<table><thead><tr><th>ID</th><th>Mission / target</th><th>Who</th><th>Status</th><th>Outcome</th></tr></thead>
<tbody>{mission_rows}</tbody></table></div>
<div class=card><h2>Failed missions</h2><ul>{failed}</ul></div>
<div class=card><h2>Ledger (newest first)</h2>
<table><thead><tr><th>#</th><th>Date</th><th>Type</th><th class=num>Amount</th><th class=num>CZK</th><th>Reconciled</th><th>Evidence</th></tr></thead>
<tbody>{ledger_rows}</tbody></table></div>
<div class=card><h2>What is not automated</h2><ul>{services}</ul></div>
<p class=muted>Generated {_e(state['updated_at'])} from state.json and ledger.json. Refresh with
<code>python3 s2e.py dashboard</code>. This page is a snapshot; it does not earn money or run anything.</p>
</main></body></html>
"""
