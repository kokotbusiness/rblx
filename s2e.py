#!/usr/bin/env python3
"""SURVIVE2EARN command line. Run `python3 s2e.py --help`.

Every command is local. Nothing here charges money, posts publicly, sends
email, creates accounts or calls paid APIs. Runners are DRY-RUN by default.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from s2e_core import RuleViolation, System, UNLOCK_THRESHOLD_CZK
from dashboard import render_dashboard

ROOT = Path(__file__).resolve().parent


def confirm_owner(args, what: str) -> None:
    """Human-in-the-loop check before writing verified money records."""
    if args.confirm == "VERIFIED":
        return
    if not sys.stdin.isatty():
        raise RuleViolation("non-interactive session: pass --confirm VERIFIED only if YOU, the owner, "
                            "checked the real payment/order record")
    print(f"You are about to record: {what}")
    print("Only continue if you personally checked a real payment, order or bank record.")
    if input("Type VERIFIED to continue: ").strip() != "VERIFIED":
        raise RuleViolation("not confirmed; nothing recorded")


def print_json(obj) -> None:
    print(json.dumps(obj, indent=2, ensure_ascii=False))


def cmd_status(sysm: System, args) -> int:
    s = sysm.sync()
    print(f"Status:                 {s['status']}")
    print(f"Verified net revenue:   {s['verified_net_revenue_czk']} CZK (goal {s['unlock_threshold_czk']} CZK)")
    print(f"Actual expenses:        {s['actual_expenses_czk']} CZK")
    print(f"Verified sales:         {s['verified_sale_count']}   unreconciled entries: {s['unreconciled_entry_count']}")
    print(f"Ledger valid:           {s['ledger_valid']}")
    print(f"Active mission:         {s['active_mission'] or '-'}   next planned: {s['next_planned_mission'] or '-'}")
    print(f"Missions w/o sale:      {s['missions_concluded_without_sale']} / {s['max_missions_before_sale']}")
    print(f"Agent spawning:         {'UNLOCKED' if s['agent_spawning_unlocked'] else 'LOCKED'} "
          f"(permitted workers: {s['permitted_worker_agents']})")
    for p in s["ledger_problems"] + s["mission_file_problems"]:
        print(f"  ! {p}")
    if s["budget_breach"]:
        print("  ! BUDGET BREACH: recorded expenses exceed verified revenue (zero-cash rule)")
    return 0


def cmd_validate(sysm: System, args) -> int:
    problems = sysm.verify_ledger() + sysm.validate_missions() + sysm.validate_workers()
    for p in problems:
        print("PROBLEM:", p)
    print("OK" if not problems else f"{len(problems)} problem(s)")
    return 1 if problems else 0


def cmd_dashboard(sysm: System, args) -> int:
    state = sysm.sync()
    html = render_dashboard(state, sysm.load_ledger(), sysm.finances())
    out = ROOT / "dashboard.html"
    out.write_text(html, encoding="utf-8")
    print(f"Wrote {out}  (open it in a browser)")
    return 0


def cmd_ledger(sysm: System, args) -> int:
    if args.action == "verify":
        problems = sysm.verify_ledger()
        for p in problems:
            print("PROBLEM:", p)
        print("Ledger OK" if not problems else "Ledger INVALID")
        return 1 if problems else 0
    if args.action == "list":
        for e in sysm.load_ledger()["entries"]:
            flag = "" if e["reconciled"] else "  [UNRECONCILED]"
            print(f"#{e['id']} {e['date']} {e['type']:<10} {e['amount']} {e['currency']} "
                  f"(CZK {e['czk_amount']}) ref={e['refers_to']} evidence={e['evidence']}{flag}")
        print_json(sysm.finances())
        return 0
    if args.action == "export":
        j, c = sysm.export_ledger()
        print(f"Exported {j}\nExported {c}")
        return 0
    if args.action in ("add", "reconcile"):
        etype = "reconcile" if args.action == "reconcile" else args.type
        if not etype:
            raise RuleViolation("--type is required (sale, refund, expense, correction)")
        what = f"{etype} {args.amount} {args.currency if etype != 'reconcile' else 'CZK'} on {args.date} (evidence: {args.evidence})"
        confirm_owner(args, what)
        e = sysm.append_entry(type=etype, amount=args.amount, currency=args.currency, date=args.date,
                              evidence=args.evidence, description=args.description or "",
                              czk_amount=args.czk_amount, pending=args.pending, refers_to=args.refers_to)
        print(f"Recorded entry #{e['id']} ({'reconciled' if e['reconciled'] else 'UNRECONCILED - not counted yet'})")
        return cmd_status(sysm, args)
    return 2


def cmd_spend(sysm: System, args) -> int:
    print_json(sysm.request_spend(args.amount, args.purpose))
    return 3  # always denied


def cmd_mission(sysm: System, args) -> int:
    if args.action == "list":
        for m in sysm.load_missions():
            print(f"{m['id']}  [{m['status']:<9}] ({m['executor']}) {m['title']}")
        return 0
    if not args.id:
        raise RuleViolation("mission id required")
    if args.action == "show":
        m = sysm._get_mission(args.id)
        m.pop("_path", None)
        print_json(m)
        return 0
    if args.action == "start":
        m = sysm.start_mission(args.id)
        print(f"{m['id']} is now ACTIVE. Run: python3 s2e.py mission run {m['id']}")
        return 0
    if args.action == "complete":
        m = sysm.complete_mission(args.id, args.evidence or "", args.all_criteria_met, args.outcome or "")
        print(f"{m['id']} completed.")
        return cmd_status(sysm, args)
    if args.action == "fail":
        m = sysm.fail_mission(args.id, args.reason or "")
        print(f"{m['id']} marked FAILED.")
        return cmd_status(sysm, args)
    if args.action == "run":
        res = sysm.run_mission_agent(args.id, execute=args.execute)
        m = res["mission"]
        print(f"Mission {m['id']}: {m['title']}  [{m['status']}]")
        print(f"Goal: {m['goal']}\nTarget: {m['measurable_target']}\nDeliverable: {m['deliverable']}")
        print("Acceptance criteria:")
        for i, c in enumerate(m["acceptance_criteria"], 1):
            print(f"  {i}. {c}")
        if res["kind"] == "human":
            print("\nThis mission needs YOU (the system cannot do it). Steps:")
            for i, step in enumerate(res["steps"], 1):
                print(f"  {i}. {step}")
            print(f"\nWhen done: python3 s2e.py mission complete {m['id']} --evidence \"...\" --all-criteria-met")
            print(f"If it fails: python3 s2e.py mission fail {m['id']} --reason \"...\"")
        elif res["mode"] == "dry-run":
            print(f"\nDRY-RUN. Would run (timeout {res['timeout']}s, read-only tools):")
            print("  " + " ".join(repr(p) if " " in p else p for p in res["cmd"]))
            print("Add --execute to run it once (mission must be active).")
        else:
            print(f"\nAgent exited with {res['exit_code']}; report: {res['output_file']}")
        return 0
    return 2


def cmd_agents(sysm: System, args) -> int:
    if args.action == "status":
        s = sysm.sync()
        cfg = sysm.load_workers()
        print(f"Unlocked: {s['agent_spawning_unlocked']} (needs >= {UNLOCK_THRESHOLD_CZK} CZK verified net revenue; "
              f"now {s['verified_net_revenue_czk']} CZK)")
        for name, w in cfg["workers"].items():
            on = "ENABLED" if name in cfg.get("enabled", []) else "disabled"
            used = cfg.get("runs", {}).get(name, 0)
            print(f"  {name}: {on}, runs {used}/{w['max_runs']}, timeout {w['timeout_seconds']}s - {w['assignment']}")
        return 0
    if not args.name:
        raise RuleViolation("worker name required")
    if args.action in ("enable", "disable"):
        sysm.enable_worker(args.name, enable=(args.action == "enable"))
        print(f"{args.name} {args.action}d.")
        return 0
    if args.action == "run":
        res = sysm.run_worker(args.name, execute=args.execute)
        if res["mode"] == "dry-run":
            print(f"DRY-RUN for worker {args.name} (runs used {res['runs_used']}/{res['max_runs']}, timeout {res['timeout']}s):")
            print("  " + " ".join(repr(p) if " " in p else p for p in res["cmd"]))
            print("Executing requires: unlock (>= 250 CZK verified), owner enable, and --execute.")
        else:
            print(f"Worker exited with {res['exit_code']}; report: {res['output_file']}")
        return 0
    return 2


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="s2e.py", description="SURVIVE2EARN local control panel")
    p.add_argument("--root", default=str(ROOT), help=argparse.SUPPRESS)
    sub = p.add_subparsers(dest="command", required=True)

    sub.add_parser("status", help="show current status")
    sub.add_parser("sync", help="recompute state.json")
    sub.add_parser("validate", help="check ledger, missions, workers")
    sub.add_parser("dashboard", help="regenerate dashboard.html")

    lg = sub.add_parser("ledger", help="owner-verified money records")
    lg.add_argument("action", choices=["add", "reconcile", "verify", "list", "export"])
    lg.add_argument("--type", choices=["sale", "refund", "expense", "correction"])
    lg.add_argument("--amount")
    lg.add_argument("--currency", default="CZK")
    lg.add_argument("--czk-amount", dest="czk_amount", help="actual CZK value if currency is not CZK")
    lg.add_argument("--date", help="YYYY-MM-DD of the real transaction")
    lg.add_argument("--evidence", help="order id / payout id / statement reference")
    lg.add_argument("--description")
    lg.add_argument("--pending", action="store_true", help="money not settled yet -> not counted")
    lg.add_argument("--refers-to", dest="refers_to", type=int)
    lg.add_argument("--confirm", help="type VERIFIED (owner only) for non-interactive use")

    sp = sub.add_parser("spend-request", help="ask to spend money (always denied)")
    sp.add_argument("--amount", required=True)
    sp.add_argument("--purpose", required=True)

    ms = sub.add_parser("mission", help="list/show/start/run/complete/fail missions")
    ms.add_argument("action", choices=["list", "show", "start", "run", "complete", "fail"])
    ms.add_argument("id", nargs="?")
    ms.add_argument("--evidence")
    ms.add_argument("--outcome")
    ms.add_argument("--reason")
    ms.add_argument("--all-criteria-met", action="store_true")
    ms.add_argument("--execute", action="store_true", help="actually run an agent mission (default dry-run)")

    ag = sub.add_parser("agents", help="bounded worker agents (locked until 250 CZK)")
    ag.add_argument("action", choices=["status", "enable", "disable", "run"])
    ag.add_argument("name", nargs="?")
    ag.add_argument("--execute", action="store_true", help="actually run (default dry-run)")
    return p


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    sysm = System(args.root)
    handlers = {
        "status": cmd_status, "sync": lambda s, a: (s.sync(), print("state.json updated"))[1] or 0,
        "validate": cmd_validate, "dashboard": cmd_dashboard, "ledger": cmd_ledger,
        "spend-request": cmd_spend, "mission": cmd_mission, "agents": cmd_agents,
    }
    try:
        return handlers[args.command](sysm, args)
    except RuleViolation as e:
        print(f"REFUSED: {e}", file=sys.stderr)
        return 4


if __name__ == "__main__":
    sys.exit(main())
