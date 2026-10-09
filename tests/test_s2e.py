"""Tests for the SURVIVE2EARN rules. Run from the repository root:
    python3 -m unittest discover -s tests -v
Each test works in a temporary copy, never on the real ledger.
"""
import datetime as dt
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import s2e  # noqa: E402
from s2e_core import (MAX_WORKERS, RuleViolation, System, entry_hash)  # noqa: E402

TODAY = dt.date.today().isoformat()


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        shutil.copytree(ROOT / "missions", self.tmp / "missions")
        shutil.copy(ROOT / "workers.json", self.tmp / "workers.json")
        (self.tmp / "ledger.json").write_text(json.dumps({"schema": 1, "base_currency": "CZK", "entries": []}))
        # reset worker enablement/run counters in the copy
        cfg = json.loads((self.tmp / "workers.json").read_text())
        cfg["enabled"], cfg["runs"] = [], {}
        (self.tmp / "workers.json").write_text(json.dumps(cfg))
        # make all missions planned except bootstrap
        for p in (self.tmp / "missions").glob("M*.json"):
            m = json.loads(p.read_text())
            m["status"] = "completed" if m["kind"] == "bootstrap" else "planned"
            p.write_text(json.dumps(m))
        self.sys = System(self.tmp)
        self.env = mock.patch.dict(os.environ, {"S2E_ROLE": "owner"})
        self.env.start()

    def tearDown(self):
        self.env.stop()
        shutil.rmtree(self.tmp)

    def sale(self, amount="300", currency="CZK", **kw):
        return self.sys.append_entry(type="sale", amount=amount, currency=currency, date=TODAY,
                                     evidence=kw.pop("evidence", "itch order 12345"), **kw)


# ------------------------------------------------------------------ ledger
class LedgerTests(Base):
    def test_empty_ledger_is_valid_and_zero(self):
        self.assertEqual(self.sys.verify_ledger(), [])
        f = self.sys.finances()
        self.assertEqual(f["verified_net_revenue_czk"], "0.00")
        self.assertEqual(f["verified_sale_count"], 0)

    def test_append_creates_hash_chain(self):
        a = self.sale("100")
        b = self.sale("50")
        self.assertEqual(a["id"], 1)
        self.assertEqual(b["prev_hash"], a["hash"])
        self.assertEqual(b["hash"], entry_hash(b))
        self.assertEqual(self.sys.verify_ledger(), [])

    def test_hand_edit_is_detected(self):
        self.sale("100")
        data = json.loads(self.sys.ledger_path.read_text())
        data["entries"][0]["amount"] = "10000.00"
        data["entries"][0]["czk_amount"] = "10000.00"
        self.sys.ledger_path.write_text(json.dumps(data))
        self.assertTrue(any("hash mismatch" in p for p in self.sys.verify_ledger()))
        self.assertEqual(self.sys.compute_state()["status"], "HALTED_LEDGER_INVALID")
        with self.assertRaises(RuleViolation):
            self.sale("1")

    def test_deleting_an_entry_is_detected(self):
        self.sale("100")
        self.sale("200")
        data = json.loads(self.sys.ledger_path.read_text())
        del data["entries"][0]
        self.sys.ledger_path.write_text(json.dumps(data))
        self.assertTrue(self.sys.verify_ledger())

    def test_validation_rejects_bad_input(self):
        bad = [
            dict(amount="-5"), dict(amount="0"), dict(amount="abc"), dict(amount="1.234"),
            dict(amount="NaN"), dict(amount="99999999"), dict(currency="KC"),
            dict(evidence=""), dict(date="2026-13-01"),
            dict(date=(dt.date.today() + dt.timedelta(days=5)).isoformat()),
        ]
        for override in bad:
            kw = dict(type="sale", amount="100", currency="CZK", date=TODAY, evidence="order 1")
            kw.update(override)
            with self.subTest(override=override), self.assertRaises(RuleViolation):
                self.sys.append_entry(**kw)
        self.assertEqual(self.sys.load_ledger()["entries"], [])

    def test_backup_before_append_and_export(self):
        self.sale("100")
        self.sale("100")
        self.assertTrue(list((self.tmp / "backups").glob("ledger-*-pre-append.json")))
        j, c = self.sys.export_ledger()
        self.assertTrue(j.exists() and c.exists())
        self.assertIn("itch order 12345", c.read_text())


# ------------------------------------------------- revenue verification workflow
class RevenueVerificationTests(Base):
    def test_foreign_currency_without_czk_is_unreconciled(self):
        self.sale("14", currency="USD")
        f = self.sys.finances()
        self.assertEqual(f["verified_net_revenue_czk"], "0.00")
        self.assertEqual(len(f["unreconciled_entries"]), 1)

    def test_reconcile_entry_makes_it_count(self):
        s = self.sale("14", currency="USD")
        self.sys.append_entry(type="reconcile", amount="281.40", currency="CZK", date=TODAY,
                              evidence="bank statement 2026-10 line 4", refers_to=s["id"])
        f = self.sys.finances()
        self.assertEqual(f["verified_net_revenue_czk"], "281.40")
        self.assertEqual(f["unreconciled_entries"], [])

    def test_pending_payout_not_counted(self):
        self.sale("300", pending=True)
        self.assertEqual(self.sys.finances()["verified_net_revenue_czk"], "0.00")

    def test_refunds_and_expenses_are_netted(self):
        self.sale("300")
        self.sys.append_entry(type="refund", amount="100", currency="CZK", date=TODAY, evidence="refund R-1")
        self.sys.append_entry(type="expense", amount="20", currency="CZK", date=TODAY, evidence="fee invoice 7")
        f = self.sys.finances()
        self.assertEqual(f["gross_sales_czk"], "300.00")
        self.assertEqual(f["verified_net_revenue_czk"], "180.00")
        self.assertEqual(f["actual_expenses_czk"], "20.00")

    def test_correction_requires_reference(self):
        with self.assertRaises(RuleViolation):
            self.sys.append_entry(type="correction", amount="-10", currency="CZK", date=TODAY, evidence="typo fix")
        s = self.sale("310")
        self.sys.append_entry(type="correction", amount="-10", currency="CZK", date=TODAY,
                              evidence="entered 310 instead of 300", refers_to=s["id"])
        self.assertEqual(self.sys.finances()["verified_net_revenue_czk"], "300.00")

    def test_worker_and_agent_roles_cannot_write_ledger(self):
        for role in ("worker", "agent"):
            with self.subTest(role=role), mock.patch.dict(os.environ, {"S2E_ROLE": role}):
                with self.assertRaises(RuleViolation):
                    self.sale("1000")
        self.assertEqual(self.sys.load_ledger()["entries"], [])

    def test_cli_requires_explicit_owner_confirmation(self):
        args = ["--root", str(self.tmp), "ledger", "add", "--type", "sale", "--amount", "300",
                "--date", TODAY, "--evidence", "order 9"]
        with mock.patch("sys.stdin", io.StringIO("")), redirect_stderr(io.StringIO()), redirect_stdout(io.StringIO()):
            self.assertEqual(s2e.main(args), 4)  # non-interactive without --confirm -> refused
        self.assertEqual(self.sys.load_ledger()["entries"], [])
        with redirect_stdout(io.StringIO()):
            self.assertEqual(s2e.main(args + ["--confirm", "VERIFIED"]), 0)
        self.assertEqual(len(self.sys.load_ledger()["entries"]), 1)

    def test_generated_product_is_not_a_sale(self):
        m = self.sys.start_mission("M001")
        self.sys.complete_mission(m["id"], "checklist done, media/ screenshots", criteria_confirmed=True)
        self.assertEqual(self.sys.finances()["verified_sale_count"], 0)
        self.assertEqual(self.sys.finances()["verified_net_revenue_czk"], "0.00")


# ------------------------------------------------------------- spending
class SpendingTests(Base):
    def test_spend_requests_are_always_denied(self):
        for amount in ("1", "250", "99999"):
            self.assertFalse(self.sys.request_spend(amount, "ads")["approved"])

    def test_cli_spend_request_exit_code_signals_denial(self):
        with redirect_stdout(io.StringIO()):
            self.assertEqual(s2e.main(["--root", str(self.tmp), "spend-request", "--amount", "100", "--purpose", "ads"]), 3)

    def test_expense_beyond_revenue_flags_budget_breach(self):
        self.sys.append_entry(type="expense", amount="50", currency="CZK", date=TODAY, evidence="receipt A1")
        st = self.sys.compute_state()
        self.assertTrue(st["budget_breach"])
        self.assertEqual(st["available_cash_czk"], "-50.00")

    def test_initial_cash_is_zero(self):
        self.assertEqual(self.sys.compute_state()["initial_cash_czk"], "0.00")


# ------------------------------------------------------- shutdown conditions
class ShutdownTests(Base):
    def conclude_all(self, fail=True):
        for mid in ("M001", "M002", "M003", "M004", "M005"):
            self.sys.start_mission(mid)
            if fail:
                self.sys.fail_mission(mid, "no buyers yet")
            else:
                self.sys.complete_mission(mid, "evidence file x", criteria_confirmed=True)

    def test_five_failed_missions_make_system_dormant(self):
        self.conclude_all()
        st = self.sys.compute_state()
        self.assertEqual(st["status"], "DORMANT")
        self.assertEqual(len(st["failed_attempts"]), 5)
        self.assertTrue((self.tmp / "reports" / "failure-report.md").exists())
        self.assertIn("Recovery experiment", (self.tmp / "reports" / "failure-report.md").read_text())

    def test_five_missions_without_sale_also_force_stop(self):
        self.conclude_all(fail=False)
        self.assertEqual(self.sys.compute_state()["status"], "DORMANT")

    def test_dormant_blocks_new_missions(self):
        self.conclude_all()
        p = self.tmp / "missions" / "M006-extra.json"
        m = json.loads(next((self.tmp / "missions").glob("M005-*.json")).read_text())
        m.update(id="M006", status="planned")
        p.write_text(json.dumps(m))
        with self.assertRaises(RuleViolation):
            self.sys.start_mission("M006")

    def test_more_than_five_missions_before_sale_is_invalid(self):
        m = json.loads(next((self.tmp / "missions").glob("M005-*.json")).read_text())
        m.update(id="M006")
        (self.tmp / "missions" / "M006-extra.json").write_text(json.dumps(m))
        self.assertTrue(self.sys.validate_missions())
        with self.assertRaises(RuleViolation):
            self.sys.start_mission("M001")

    def test_one_active_mission_at_a_time(self):
        self.sys.start_mission("M001")
        with self.assertRaises(RuleViolation):
            self.sys.start_mission("M002")

    def test_completion_requires_criteria_and_evidence(self):
        self.sys.start_mission("M001")
        with self.assertRaises(RuleViolation):
            self.sys.complete_mission("M001", "evidence", criteria_confirmed=False)
        with self.assertRaises(RuleViolation):
            self.sys.complete_mission("M001", "", criteria_confirmed=True)

    def test_verified_sale_prevents_dormancy(self):
        self.sale("300")
        self.conclude_all()
        self.assertNotEqual(self.sys.compute_state()["status"], "DORMANT")

    def test_only_one_bootstrap(self):
        m = json.loads(next((self.tmp / "missions").glob("M000-*.json")).read_text())
        m.update(id="M000b")
        (self.tmp / "missions" / "M000b.json").write_text(json.dumps(m))
        self.assertTrue(any("bootstrap" in p for p in self.sys.validate_missions()))


# ------------------------------------------------------- agent spawning rules
class AgentRuleTests(Base):
    def fake_runner(self, calls):
        def run(cmd, **kw):
            calls.append((cmd, kw))
            return subprocess.CompletedProcess(cmd, 0, stdout="report", stderr="")
        return run

    def test_locked_below_threshold(self):
        self.sale("249.99")
        self.assertFalse(self.sys.workers_unlocked())
        self.assertEqual(self.sys.compute_state()["permitted_worker_agents"], 0)
        with self.assertRaises(RuleViolation):
            self.sys.enable_worker("product-improvement")

    def test_unlocks_at_250_net_but_expenses_count(self):
        self.sale("260")
        self.sys.append_entry(type="expense", amount="20", currency="CZK", date=TODAY, evidence="fee 1")
        self.assertFalse(self.sys.workers_unlocked())  # 240 net
        self.sale("10")
        self.assertTrue(self.sys.workers_unlocked())   # 250 net
        st = self.sys.compute_state()
        self.assertEqual(st["status"], "UNLOCKED_STAGE_2")
        self.assertEqual(st["permitted_worker_agents"], MAX_WORKERS)

    def test_invalid_ledger_keeps_workers_locked(self):
        self.sale("500")
        data = json.loads(self.sys.ledger_path.read_text())
        data["entries"][0]["evidence"] = "changed"
        self.sys.ledger_path.write_text(json.dumps(data))
        self.assertFalse(self.sys.workers_unlocked())

    def test_dry_run_is_default_and_never_executes(self):
        calls = []
        res = self.sys.run_worker("product-improvement", runner=self.fake_runner(calls))
        self.assertEqual(res["mode"], "dry-run")
        self.assertEqual(calls, [])

    def test_execute_requires_unlock_and_owner_enable(self):
        calls = []
        with self.assertRaises(RuleViolation):
            self.sys.run_worker("product-improvement", execute=True, runner=self.fake_runner(calls))
        self.sale("300")
        with self.assertRaises(RuleViolation):  # unlocked but not enabled
            self.sys.run_worker("product-improvement", execute=True, runner=self.fake_runner(calls))
        self.assertEqual(calls, [])

    def test_bounded_execution(self):
        self.sale("300")
        self.sys.enable_worker("product-improvement")
        calls = []
        with mock.patch("shutil.which", return_value="/usr/bin/claude"):
            res = self.sys.run_worker("product-improvement", execute=True, runner=self.fake_runner(calls))
            self.assertEqual(res["mode"], "executed")
            cmd, kw = calls[0]
            self.assertLessEqual(kw["timeout"], 1800)
            self.assertEqual(kw["env"]["S2E_ROLE"], "worker")
            self.assertTrue(Path(res["output_file"]).exists())
            for _ in range(2):
                self.sys.run_worker("product-improvement", execute=True, runner=self.fake_runner(calls))
            with self.assertRaises(RuleViolation):  # max_runs = 3
                self.sys.run_worker("product-improvement", execute=True, runner=self.fake_runner(calls))

    def test_timeout_is_handled(self):
        self.sale("300")
        self.sys.enable_worker("product-improvement")

        def slow(cmd, **kw):
            raise subprocess.TimeoutExpired(cmd, kw["timeout"])
        with mock.patch("shutil.which", return_value="/usr/bin/claude"):
            res = self.sys.run_worker("product-improvement", execute=True, runner=slow)
        self.assertEqual(res["exit_code"], -1)

    def test_no_permission_bypass_and_read_only_tools(self):
        for name in ("product-improvement", "market-research-distribution"):
            cmd = self.sys.plan_worker_run(name)["cmd"]
            joined = " ".join(cmd)
            self.assertNotIn("dangerously-skip-permissions", joined)
            self.assertNotIn("bypassPermissions", joined)
            allowed = cmd[cmd.index("--allowedTools") + 1].split(",")
            for t in ("Bash", "Edit", "Write", "Agent", "Task"):
                self.assertNotIn(t, allowed)

    def test_no_recursive_spawning_from_worker(self):
        self.sale("300")
        self.sys.enable_worker("product-improvement")
        with mock.patch.dict(os.environ, {"S2E_ROLE": "worker"}), self.assertRaises(RuleViolation):
            self.sys.run_worker("product-improvement", execute=True, runner=self.fake_runner([]))

    def test_at_most_two_workers_and_no_write_tools(self):
        cfg = self.sys.load_workers()
        cfg["workers"]["third"] = dict(cfg["workers"]["product-improvement"])
        self.assertTrue(self.sys.validate_workers(cfg))
        cfg = self.sys.load_workers()
        cfg["workers"]["product-improvement"]["allowed_tools"].append("Bash")
        self.assertTrue(self.sys.validate_workers(cfg))
        cfg = self.sys.load_workers()
        cfg["workers"]["product-improvement"]["timeout_seconds"] = 999999
        self.assertTrue(self.sys.validate_workers(cfg))

    def test_dormant_blocks_workers_even_after_unlock_attempt(self):
        for mid in ("M001", "M002", "M003", "M004", "M005"):
            self.sys.start_mission(mid)
            self.sys.fail_mission(mid, "no buyers")
        self.assertFalse(self.sys.workers_unlocked())
        with self.assertRaises(RuleViolation):
            self.sys.run_worker("product-improvement", execute=True, runner=self.fake_runner([]))

    def test_mission_agent_dry_run_and_human_missions(self):
        res = self.sys.run_mission_agent("M004")
        self.assertEqual(res["mode"], "dry-run")
        self.assertEqual(res["kind"], "agent")
        self.assertEqual(self.sys.run_mission_agent("M001")["kind"], "human")
        with self.assertRaises(RuleViolation):  # not active yet
            self.sys.run_mission_agent("M004", execute=True, runner=self.fake_runner([]))


class RealRepoFilesTests(unittest.TestCase):
    """Sanity checks on the committed files themselves."""

    def test_committed_state_is_consistent(self):
        sysm = System(ROOT)
        self.assertEqual(sysm.verify_ledger(), [])
        self.assertEqual(sysm.validate_missions(), [])
        self.assertEqual(sysm.validate_workers(), [])
        self.assertEqual(sysm.load_workers()["enabled"], [])

    def test_no_fake_social_proof_in_public_pages(self):
        banned = ["testimonial", "customers love", "sold out", "bestseller", "best-seller",
                  "★★★★★", "5 stars", "trusted by", "happy customers", "copies sold"]
        for path in [ROOT / "landing-page" / "index.html", *sorted((ROOT / "marketing").glob("*.md"))]:
            text = path.read_text(encoding="utf-8").lower()
            for word in banned:
                with self.subTest(file=path.name, word=word):
                    self.assertNotIn(word.lower(), text)


if __name__ == "__main__":
    unittest.main()
