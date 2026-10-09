"""SURVIVE2EARN core: ledger, missions, survival rules, worker gating.

Pure Python standard library. All state lives in files under one root folder:
    state.json      derived summary (rewritten by `sync`)
    ledger.json     append-only, hash-chained log of owner-verified money events
    missions/*.json mission definitions and outcomes
    workers.json    the (max two) bounded worker definitions
Nothing in here moves money, creates accounts, publishes, or calls paid APIs.
"""
from __future__ import annotations

import csv
import datetime as dt
import hashlib
import json
import os
import shutil
import subprocess
from decimal import Decimal, InvalidOperation
from pathlib import Path

# ---------------------------------------------------------------- constants
BASE_CURRENCY = "CZK"
INITIAL_CASH_CZK = Decimal("0")
UNLOCK_THRESHOLD_CZK = Decimal("250")
MAX_MISSIONS_BEFORE_SALE = 5      # distinct missions (bootstrap excluded) before mandatory stop
MAX_MISSIONS_HARD = 10            # absolute cap on mission files, sale or not
MAX_WORKERS = 2
MAX_WORKER_TIMEOUT = 1800         # seconds, hard ceiling for any subprocess
DEFAULT_TIMEOUT = 900
MAX_AMOUNT = Decimal("1000000")
ENTRY_TYPES = ("sale", "refund", "expense", "reconcile", "correction")
MISSION_STATUSES = ("planned", "active", "completed", "failed")
FORBIDDEN_FLAGS = ("--dangerously-skip-permissions", "--permission-mode=bypassPermissions", "bypassPermissions")
READ_ONLY_TOOLS = ["Read", "Grep", "Glob"]


class RuleViolation(Exception):
    """Raised when an action would break a survival rule."""


def now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def current_role() -> str:
    """'owner' unless a runner marked this process as an agent/worker."""
    return os.environ.get("S2E_ROLE", "owner").strip().lower() or "owner"


def require_owner(action: str) -> None:
    role = current_role()
    if role != "owner":
        raise RuleViolation(f"{action} is owner-only; refused for role '{role}'.")


def parse_amount(value, allow_negative: bool = False) -> Decimal:
    try:
        amount = Decimal(str(value).strip())
    except (InvalidOperation, AttributeError):
        raise RuleViolation(f"invalid amount: {value!r}")
    if not amount.is_finite():
        raise RuleViolation("amount must be finite")
    if amount.as_tuple().exponent < -2:
        raise RuleViolation("amount may have at most 2 decimal places")
    if abs(amount) > MAX_AMOUNT:
        raise RuleViolation("amount too large")
    if allow_negative:
        if amount == 0:
            raise RuleViolation("amount must not be zero")
    elif amount <= 0:
        raise RuleViolation("amount must be greater than zero")
    return amount.quantize(Decimal("0.01"))


def money(d: Decimal) -> str:
    return str(d.quantize(Decimal("0.01")))


def _canonical(obj) -> str:
    return json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def entry_hash(entry: dict) -> str:
    body = {k: v for k, v in entry.items() if k != "hash"}
    return hashlib.sha256(_canonical(body).encode("utf-8")).hexdigest()


def _read_json(path: Path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _write_json(path: Path, data) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)


# ---------------------------------------------------------------- the system
class System:
    def __init__(self, root: Path | str):
        self.root = Path(root)
        self.ledger_path = self.root / "ledger.json"
        self.state_path = self.root / "state.json"
        self.missions_dir = self.root / "missions"
        self.workers_path = self.root / "workers.json"
        self.backups_dir = self.root / "backups"
        self.reports_dir = self.root / "reports"
        self.worker_output_dir = self.root / "worker-output"

    # ------------------------------------------------------------ ledger
    def load_ledger(self) -> dict:
        if not self.ledger_path.exists():
            return {"schema": 1, "base_currency": BASE_CURRENCY, "entries": []}
        return _read_json(self.ledger_path)

    def verify_ledger(self, ledger: dict | None = None) -> list[str]:
        """Returns a list of problems; empty list = ledger intact."""
        ledger = ledger if ledger is not None else self.load_ledger()
        problems = []
        if ledger.get("base_currency") != BASE_CURRENCY:
            problems.append("base_currency must be CZK")
        prev = "GENESIS"
        ids = set()
        for i, e in enumerate(ledger.get("entries", []), start=1):
            where = f"entry #{i}"
            if e.get("id") != i:
                problems.append(f"{where}: id must be {i} (entries are append-only, never deleted or reordered)")
            if e.get("prev_hash") != prev:
                problems.append(f"{where}: prev_hash mismatch (ledger edited by hand?)")
            if e.get("hash") != entry_hash(e):
                problems.append(f"{where}: hash mismatch (entry modified after recording)")
            if e.get("type") not in ENTRY_TYPES:
                problems.append(f"{where}: unknown type {e.get('type')!r}")
            if e.get("verified_by") != "owner":
                problems.append(f"{where}: not owner-verified")
            if not str(e.get("evidence", "")).strip():
                problems.append(f"{where}: missing evidence reference")
            if e.get("type") in ("reconcile", "correction") and e.get("refers_to") not in ids:
                problems.append(f"{where}: refers_to must point to an earlier entry")
            ids.add(e.get("id"))
            prev = e.get("hash")
        return problems

    def backup_ledger(self, tag: str = "auto") -> Path | None:
        if not self.ledger_path.exists():
            return None
        self.backups_dir.mkdir(exist_ok=True)
        stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        dest = self.backups_dir / f"ledger-{stamp}-{tag}.json"
        shutil.copy2(self.ledger_path, dest)
        return dest

    def append_entry(self, *, type: str, amount, currency: str, date: str, evidence: str,
                     description: str = "", czk_amount=None, pending: bool = False,
                     refers_to: int | None = None) -> dict:
        """The ONLY way money events enter the ledger. Owner-only."""
        require_owner("Recording ledger entries")
        if type not in ENTRY_TYPES:
            raise RuleViolation(f"type must be one of {ENTRY_TYPES}")
        ledger = self.load_ledger()
        problems = self.verify_ledger(ledger)
        if problems:
            raise RuleViolation("ledger failed verification, fix before appending: " + "; ".join(problems))
        evidence = (evidence or "").strip()
        if len(evidence) < 4:
            raise RuleViolation("evidence reference required (order id, payout id, bank statement line...)")
        currency = (currency or "").strip().upper()
        if len(currency) != 3 or not currency.isalpha():
            raise RuleViolation("currency must be a 3-letter code, e.g. CZK, USD, EUR")
        try:
            day = dt.date.fromisoformat(date)
        except (TypeError, ValueError):
            raise RuleViolation("date must be YYYY-MM-DD")
        if day > dt.date.today() + dt.timedelta(days=1):
            raise RuleViolation("date is in the future; only record events that happened")
        amt = parse_amount(amount, allow_negative=(type == "correction"))
        existing_ids = {e["id"] for e in ledger["entries"]}
        if type in ("reconcile", "correction"):
            if refers_to not in existing_ids:
                raise RuleViolation(f"{type} must refer to an existing entry id")
        elif refers_to is not None and refers_to not in existing_ids:
            raise RuleViolation("refers_to points to a missing entry")
        if type == "reconcile":
            # amount = the final CZK amount actually received/paid for the referred entry
            currency, czk, pending = BASE_CURRENCY, amt, False
        elif currency == BASE_CURRENCY:
            czk = amt
        elif czk_amount is not None:
            czk = parse_amount(czk_amount, allow_negative=(type == "correction"))
        else:
            czk = None  # unknown CZK value -> unreconciled until a reconcile entry
        entries = ledger["entries"]
        entry = {
            "id": len(entries) + 1,
            "recorded_at": now_iso(),
            "date": day.isoformat(),
            "type": type,
            "amount": money(amt),
            "currency": currency,
            "czk_amount": money(czk) if czk is not None else None,
            "reconciled": (czk is not None) and not pending,
            "refers_to": refers_to,
            "evidence": evidence,
            "description": (description or "").strip(),
            "verified_by": "owner",
            "prev_hash": entries[-1]["hash"] if entries else "GENESIS",
        }
        entry["hash"] = entry_hash(entry)
        self.backup_ledger("pre-append")
        entries.append(entry)
        _write_json(self.ledger_path, ledger)
        self.sync()
        return entry

    def finances(self, ledger: dict | None = None) -> dict:
        """Verified figures in CZK. Unreconciled entries are listed, never counted."""
        ledger = ledger if ledger is not None else self.load_ledger()
        entries = ledger.get("entries", [])
        reconciled_value: dict[int, Decimal] = {}
        for e in entries:
            if e["type"] == "reconcile":
                reconciled_value[e["refers_to"]] = Decimal(e["czk_amount"])
        totals = {t: Decimal("0") for t in ("sale", "refund", "expense", "correction")}
        sale_count = 0
        unreconciled = []
        for e in entries:
            t = e["type"]
            if t == "reconcile":
                continue
            if e["id"] in reconciled_value:
                value = reconciled_value[e["id"]]
            elif e.get("reconciled") and e.get("czk_amount") is not None:
                value = Decimal(e["czk_amount"])
            else:
                unreconciled.append({"id": e["id"], "type": t, "amount": e["amount"],
                                     "currency": e["currency"], "date": e["date"]})
                continue
            totals[t] += value
            if t == "sale":
                sale_count += 1
        net_revenue = totals["sale"] - totals["refund"] + totals["correction"]
        cash = INITIAL_CASH_CZK + net_revenue - totals["expense"]
        return {
            "gross_sales_czk": money(totals["sale"]),
            "refunds_czk": money(totals["refund"]),
            "corrections_czk": money(totals["correction"]),
            "actual_expenses_czk": money(totals["expense"]),
            # "net revenue" for the unlock rule = sales - refunds - expenses (+corrections)
            "verified_net_revenue_czk": money(net_revenue - totals["expense"]),
            "available_cash_czk": money(cash),
            "verified_sale_count": sale_count,
            "unreconciled_entries": unreconciled,
            "budget_breach": cash < 0,
        }

    def export_ledger(self) -> tuple[Path, Path]:
        ledger = self.load_ledger()
        self.backups_dir.mkdir(exist_ok=True)
        stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
        jpath = self.backups_dir / f"ledger-export-{stamp}.json"
        cpath = self.backups_dir / f"ledger-export-{stamp}.csv"
        _write_json(jpath, ledger)
        fields = ["id", "date", "type", "amount", "currency", "czk_amount", "reconciled",
                  "refers_to", "evidence", "description", "recorded_at", "hash"]
        with open(cpath, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
            w.writeheader()
            for e in ledger["entries"]:
                w.writerow(e)
        return jpath, cpath

    # ------------------------------------------------------------ spending
    def request_spend(self, amount, purpose: str) -> dict:
        """Agents can never spend. This only produces a denial the owner can read."""
        amt = parse_amount(amount)
        return {
            "approved": False,
            "amount_czk": money(amt),
            "purpose": purpose,
            "reason": ("Autonomous purchases are prohibited. Business cash starts at 0 CZK; "
                       "any spending is a human decision made outside this system and must be "
                       "recorded afterwards as an owner-verified expense with evidence."),
        }

    # ------------------------------------------------------------ missions
    def load_missions(self) -> list[dict]:
        missions = []
        for p in sorted(self.missions_dir.glob("M*.json")):
            m = _read_json(p)
            m["_path"] = str(p)
            missions.append(m)
        return missions

    def _save_mission(self, m: dict) -> None:
        path = Path(m.pop("_path"))
        _write_json(path, m)
        m["_path"] = str(path)

    def validate_missions(self, missions: list[dict] | None = None) -> list[str]:
        missions = missions if missions is not None else self.load_missions()
        problems = []
        seen = set()
        required = ("id", "title", "kind", "executor", "goal", "measurable_target",
                    "deliverable", "acceptance_criteria", "status")
        for m in missions:
            for k in required:
                if k not in m:
                    problems.append(f"{m.get('id', m['_path'])}: missing '{k}'")
            if m.get("id") in seen:
                problems.append(f"duplicate mission id {m.get('id')}")
            seen.add(m.get("id"))
            if m.get("status") not in MISSION_STATUSES:
                problems.append(f"{m.get('id')}: invalid status {m.get('status')!r}")
            if not m.get("acceptance_criteria"):
                problems.append(f"{m.get('id')}: needs at least one acceptance criterion")
        bootstraps = [m for m in missions if m.get("kind") == "bootstrap"]
        if len(bootstraps) > 1:
            problems.append("only one bootstrap experiment is permitted")
        regular = [m for m in missions if m.get("kind") != "bootstrap"]
        if len(missions) > MAX_MISSIONS_HARD:
            problems.append(f"more than {MAX_MISSIONS_HARD} mission files (hard cap)")
        if self.finances()["verified_sale_count"] == 0 and len(regular) > MAX_MISSIONS_BEFORE_SALE:
            problems.append(f"{len(regular)} missions defined but only {MAX_MISSIONS_BEFORE_SALE} "
                            "are permitted before the first verified sale")
        return problems

    def _get_mission(self, mission_id: str) -> dict:
        for m in self.load_missions():
            if m["id"] == mission_id:
                return m
        raise RuleViolation(f"unknown mission {mission_id}")

    def concluded_regular_missions(self, missions=None) -> list[dict]:
        missions = missions if missions is not None else self.load_missions()
        return [m for m in missions if m.get("kind") != "bootstrap" and m["status"] in ("completed", "failed")]

    def is_dormant(self, missions=None, fin=None) -> bool:
        fin = fin or self.finances()
        if fin["verified_sale_count"] > 0:
            return False
        return len(self.concluded_regular_missions(missions)) >= MAX_MISSIONS_BEFORE_SALE

    def start_mission(self, mission_id: str) -> dict:
        require_owner("Starting a mission")
        missions = self.load_missions()
        problems = self.validate_missions(missions)
        if problems:
            raise RuleViolation("mission files invalid: " + "; ".join(problems))
        if self.verify_ledger():
            raise RuleViolation("ledger failed verification; stop and fix it first")
        if self.is_dormant(missions):
            raise RuleViolation("system is DORMANT (5 missions without a verified sale). "
                                "Read reports/failure-report.md; no further missions.")
        active = [m for m in missions if m["status"] == "active"]
        if active:
            raise RuleViolation(f"mission {active[0]['id']} is still active; finish or fail it first")
        m = next((m for m in missions if m["id"] == mission_id), None)
        if m is None:
            raise RuleViolation(f"unknown mission {mission_id}")
        if m["status"] != "planned":
            raise RuleViolation(f"{mission_id} is {m['status']}, only planned missions can start")
        m["status"] = "active"
        m["started_at"] = now_iso()
        self._save_mission(m)
        self.sync()
        return m

    def complete_mission(self, mission_id: str, evidence: str, criteria_confirmed: bool, outcome: str = "") -> dict:
        require_owner("Completing a mission")
        m = self._get_mission(mission_id)
        if m["status"] != "active":
            raise RuleViolation(f"{mission_id} is {m['status']}; only active missions can complete")
        if not criteria_confirmed:
            raise RuleViolation("a mission only counts as completed when ALL acceptance criteria are met; "
                                "confirm explicitly or fail the mission")
        if len((evidence or "").strip()) < 4:
            raise RuleViolation("evidence required (file path, URL, screenshot name...)")
        m["status"] = "completed"
        m["ended_at"] = now_iso()
        m["evidence"] = evidence.strip()
        m["outcome"] = outcome.strip() or "Acceptance criteria met (owner-confirmed)."
        self._save_mission(m)
        self._after_conclusion()
        return m

    def fail_mission(self, mission_id: str, reason: str) -> dict:
        require_owner("Failing a mission")
        m = self._get_mission(mission_id)
        if m["status"] not in ("active", "planned"):
            raise RuleViolation(f"{mission_id} is already {m['status']}")
        if len((reason or "").strip()) < 4:
            raise RuleViolation("a failure reason is required (it feeds the failure report)")
        m["status"] = "failed"
        m["ended_at"] = now_iso()
        m["outcome"] = "FAILED: " + reason.strip()
        self._save_mission(m)
        self._after_conclusion()
        return m

    def _after_conclusion(self) -> None:
        state = self.sync()
        if state["status"] == "DORMANT":
            self.write_failure_report()

    def write_failure_report(self) -> Path:
        self.reports_dir.mkdir(exist_ok=True)
        missions = self.load_missions()
        fin = self.finances()
        lines = [
            "# SURVIVE2EARN failure report",
            "",
            f"Generated: {now_iso()}",
            "",
            "Status: **DORMANT** - five missions concluded without a single owner-verified sale.",
            "No further missions may start and no agents may be spawned.",
            "",
            "## Money (owner-verified only)",
            f"- Verified net revenue: {fin['verified_net_revenue_czk']} CZK",
            f"- Actual expenses: {fin['actual_expenses_czk']} CZK",
            f"- Unreconciled entries: {len(fin['unreconciled_entries'])}",
            "",
            "## Missions",
        ]
        for m in missions:
            lines.append(f"- **{m['id']} {m['title']}** - {m['status']}: {m.get('outcome') or 'no outcome recorded'}")
        lines += [
            "",
            "## Likely causes to check (fill in with evidence, do not guess)",
            "- Did anyone see the listing? (store analytics: views, clicks)",
            "- Did viewers click buy but not pay? (price / trust / payment method)",
            "- Did the product fail its Studio verification or receive negative feedback?",
            "",
            "## Recovery experiment (one, bounded, zero cost)",
            "**Concierge pre-sale test - 14 days.** Instead of building more features, offer",
            "a done-for-you install of the daily-rewards + shop systems into 5 small Roblox",
            "developers' existing games for a fixed price (e.g. 300 CZK / $13), paid only after",
            "they see it working in their place. Use only venues that allow paid-service offers",
            "(e.g. the hiring/collaboration sections of Roblox developer communities, following",
            "their rules). Success = 1 paid order recorded in the ledger with evidence.",
            "Failure = 0 paid orders from 5 real conversations -> the niche is not worth more",
            "time; pick a different product category before writing any new code.",
            "",
            "Restarting requires the owner to review this report, decide explicitly, and create",
            "a new mission set in a new phase. The system will not do that by itself.",
        ]
        path = self.reports_dir / "failure-report.md"
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return path

    # ------------------------------------------------------------ workers
    def load_workers(self) -> dict:
        return _read_json(self.workers_path)

    def workers_unlocked(self, fin=None) -> bool:
        fin = fin or self.finances()
        return (not self.verify_ledger()) and Decimal(fin["verified_net_revenue_czk"]) >= UNLOCK_THRESHOLD_CZK

    def validate_workers(self, cfg: dict | None = None) -> list[str]:
        cfg = cfg if cfg is not None else self.load_workers()
        problems = []
        workers = cfg.get("workers", {})
        if len(workers) > MAX_WORKERS:
            problems.append(f"at most {MAX_WORKERS} workers may be defined")
        for name, w in workers.items():
            if not w.get("assignment"):
                problems.append(f"{name}: needs a narrow assignment")
            t = w.get("timeout_seconds", 0)
            if not isinstance(t, int) or not 0 < t <= MAX_WORKER_TIMEOUT:
                problems.append(f"{name}: timeout_seconds must be 1..{MAX_WORKER_TIMEOUT}")
            r = w.get("max_runs", 0)
            if not isinstance(r, int) or not 0 < r <= 10:
                problems.append(f"{name}: max_runs must be 1..10")
            for tool in w.get("allowed_tools", []):
                if tool in ("Bash", "Edit", "Write", "NotebookEdit", "Agent", "Task"):
                    problems.append(f"{name}: tool {tool} not permitted for workers")
        if len(cfg.get("enabled", [])) > MAX_WORKERS:
            problems.append("too many enabled workers")
        return problems

    def enable_worker(self, name: str, enable: bool = True) -> dict:
        require_owner("Enabling workers")
        cfg = self.load_workers()
        if name not in cfg["workers"]:
            raise RuleViolation(f"unknown worker {name}")
        enabled = set(cfg.get("enabled", []))
        if enable:
            if not self.workers_unlocked():
                raise RuleViolation(f"workers are locked until verified net revenue >= {UNLOCK_THRESHOLD_CZK} CZK")
            enabled.add(name)
            if len(enabled) > MAX_WORKERS:
                raise RuleViolation(f"at most {MAX_WORKERS} workers")
        else:
            enabled.discard(name)
        cfg["enabled"] = sorted(enabled)
        _write_json(self.workers_path, cfg)
        self.sync()
        return cfg

    def build_claude_command(self, prompt: str, allowed_tools: list[str]) -> list[str]:
        claude = shutil.which("claude") or "claude"
        cmd = [claude, "-p", prompt, "--permission-mode", "default",
               "--allowedTools", ",".join(allowed_tools),
               "--disallowedTools", "Bash,Edit,Write,NotebookEdit,Agent,Task"]
        for flag in FORBIDDEN_FLAGS:
            if any(flag in part for part in cmd[3:]):
                raise RuleViolation("refusing to build a command with a permission-bypass flag")
        return cmd

    def plan_worker_run(self, name: str) -> dict:
        cfg = self.load_workers()
        problems = self.validate_workers(cfg)
        if problems:
            raise RuleViolation("; ".join(problems))
        if name not in cfg["workers"]:
            raise RuleViolation(f"unknown worker {name}")
        w = cfg["workers"][name]
        prompt = (
            f"You are the bounded worker '{name}' of the SURVIVE2EARN project in this directory.\n"
            f"Assignment (do only this): {w['assignment']}\n"
            "Rules: you are read-only. Do not try to edit files, run commands, spend money, "
            "create accounts, publish, send messages, spawn agents, or touch ledger.json. "
            "Never claim sales or results. Output a concise markdown report with concrete, "
            "evidence-based recommendations for the owner to review."
        )
        tools = list(w.get("allowed_tools", READ_ONLY_TOOLS))
        return {"name": name, "cmd": self.build_claude_command(prompt, tools),
                "timeout": min(int(w["timeout_seconds"]), MAX_WORKER_TIMEOUT),
                "max_runs": w["max_runs"], "runs_used": cfg.get("runs", {}).get(name, 0)}

    def run_worker(self, name: str, execute: bool = False, runner=subprocess.run) -> dict:
        """DRY-RUN by default. With execute=True, runs ONE bounded worker session."""
        plan = self.plan_worker_run(name)
        if not execute:
            return {"mode": "dry-run", **plan}
        require_owner("Running a worker")  # also blocks nested spawning from inside a worker
        cfg = self.load_workers()
        if not self.workers_unlocked():
            raise RuleViolation(f"workers are locked until verified net revenue >= {UNLOCK_THRESHOLD_CZK} CZK")
        if self.is_dormant():
            raise RuleViolation("system is DORMANT")
        if name not in cfg.get("enabled", []):
            raise RuleViolation(f"worker {name} is not enabled by the owner (s2e.py agents enable {name})")
        if plan["runs_used"] >= plan["max_runs"]:
            raise RuleViolation(f"worker {name} used all {plan['max_runs']} runs")
        if not shutil.which("claude"):
            raise RuleViolation("claude CLI not found; cannot execute (dry-run still works)")
        cfg.setdefault("runs", {})[name] = plan["runs_used"] + 1  # count before running
        _write_json(self.workers_path, cfg)
        env = dict(os.environ, S2E_ROLE="worker")
        try:
            proc = runner(plan["cmd"], cwd=self.root, env=env, capture_output=True,
                          text=True, timeout=plan["timeout"])
            output, code = proc.stdout, proc.returncode
        except subprocess.TimeoutExpired:
            output, code = f"(worker stopped after {plan['timeout']}s timeout)", -1
        self.worker_output_dir.mkdir(exist_ok=True)
        out = self.worker_output_dir / f"{name}-{dt.datetime.now().strftime('%Y%m%d-%H%M%S')}.md"
        out.write_text(output or "(no output)", encoding="utf-8")
        return {"mode": "executed", "exit_code": code, "output_file": str(out), **plan}

    def plan_mission_run(self, mission_id: str) -> dict:
        m = self._get_mission(mission_id)
        if m["executor"] == "human" or not m.get("agent_prompt"):
            return {"mission": m, "kind": "human", "steps": m.get("human_steps", [])}
        prompt = (f"SURVIVE2EARN mission {m['id']}: {m['title']}\nGoal: {m['goal']}\n"
                  f"Task: {m['agent_prompt']}\nYou are read-only: produce a markdown report only. "
                  "Never claim sales, never spend, publish or contact anyone.")
        cmd = self.build_claude_command(prompt, m.get("allowed_tools", READ_ONLY_TOOLS))
        return {"mission": m, "kind": "agent", "cmd": cmd,
                "timeout": min(int(m.get("timeout_seconds", DEFAULT_TIMEOUT)), MAX_WORKER_TIMEOUT)}

    def run_mission_agent(self, mission_id: str, execute: bool = False, runner=subprocess.run) -> dict:
        plan = self.plan_mission_run(mission_id)
        if plan["kind"] == "human" or not execute:
            return {"mode": "dry-run", **plan}
        require_owner("Running a mission agent")
        if plan["mission"]["status"] != "active":
            raise RuleViolation("start the mission first (s2e.py mission start ID)")
        if self.is_dormant():
            raise RuleViolation("system is DORMANT")
        if not shutil.which("claude"):
            raise RuleViolation("claude CLI not found; cannot execute (dry-run still works)")
        env = dict(os.environ, S2E_ROLE="agent")
        try:
            proc = runner(plan["cmd"], cwd=self.root, env=env, capture_output=True,
                          text=True, timeout=plan["timeout"])
            output, code = proc.stdout, proc.returncode
        except subprocess.TimeoutExpired:
            output, code = f"(stopped after {plan['timeout']}s timeout)", -1
        self.worker_output_dir.mkdir(exist_ok=True)
        out = self.worker_output_dir / f"{mission_id}-{dt.datetime.now().strftime('%Y%m%d-%H%M%S')}.md"
        out.write_text(output or "(no output)", encoding="utf-8")
        return {"mode": "executed", "exit_code": code, "output_file": str(out), **plan}

    # ------------------------------------------------------------ state
    def compute_state(self) -> dict:
        ledger_problems = self.verify_ledger()
        fin = self.finances()
        missions = self.load_missions()
        mission_problems = self.validate_missions(missions)
        cfg = self.load_workers() if self.workers_path.exists() else {"workers": {}, "enabled": []}
        unlocked = self.workers_unlocked(fin)
        dormant = self.is_dormant(missions, fin)
        regular = [m for m in missions if m.get("kind") != "bootstrap"]
        active = next((m for m in missions if m["status"] == "active"), None)
        if ledger_problems:
            status = "HALTED_LEDGER_INVALID"
        elif dormant:
            status = "DORMANT"
        elif unlocked:
            status = "UNLOCKED_STAGE_2"
        elif active:
            status = "MISSION_ACTIVE"
        elif fin["verified_sale_count"] > 0:
            status = "FIRST_SALE_VERIFIED"
        else:
            status = "AWAITING_NEXT_MISSION"
        nxt = next((m for m in sorted(regular, key=lambda m: m["id"]) if m["status"] == "planned"), None)
        return {
            "project": "SURVIVE2EARN",
            "mission": "Create a real, sellable digital product and reach the first "
                       "250 CZK of owner-verified net revenue.",
            "product": "Roblox Creator Starter Kit (products/roblox-creator-starter-kit)",
            "status": status,
            "updated_at": now_iso(),
            "initial_cash_czk": money(INITIAL_CASH_CZK),
            "unlock_threshold_czk": money(UNLOCK_THRESHOLD_CZK),
            **{k: fin[k] for k in ("verified_net_revenue_czk", "gross_sales_czk", "refunds_czk",
                                   "actual_expenses_czk", "available_cash_czk",
                                   "verified_sale_count", "budget_breach")},
            "unreconciled_entry_count": len(fin["unreconciled_entries"]),
            "ledger_valid": not ledger_problems,
            "ledger_problems": ledger_problems,
            "mission_file_problems": mission_problems,
            "active_mission": active["id"] if active else None,
            "next_planned_mission": nxt["id"] if nxt else None,
            "missions_concluded_without_sale": 0 if fin["verified_sale_count"] else len(self.concluded_regular_missions(missions)),
            "max_missions_before_sale": MAX_MISSIONS_BEFORE_SALE,
            "missions": [{k: m.get(k) for k in ("id", "title", "kind", "executor", "status",
                                                  "measurable_target", "outcome")} for m in missions],
            "failed_attempts": [{"id": m["id"], "title": m["title"], "outcome": m.get("outcome")}
                                for m in missions if m["status"] == "failed"],
            "agent_spawning_unlocked": unlocked,
            "permitted_worker_agents": MAX_WORKERS if unlocked else 0,
            "enabled_workers": cfg.get("enabled", []) if unlocked else [],
            "external_services": {
                "payments": "NOT INTEGRATED - owner sells via a store account they create; sales are entered manually",
                "publishing": "NOT AUTOMATED - owner posts drafts from marketing/ by hand",
                "roblox_studio": "NOT AVAILABLE in build environment - Studio test is mission M001",
                "paid_apis": "NONE USED",
            },
        }

    def sync(self) -> dict:
        state = self.compute_state()
        _write_json(self.state_path, state)
        return state
