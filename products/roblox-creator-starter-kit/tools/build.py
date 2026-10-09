#!/usr/bin/env python3
"""Check and package the Roblox Creator Starter Kit.

    python3 tools/build.py            # run all checks, build place file + zip
    python3 tools/build.py --check    # checks only, no packaging

Tools are looked up in ../../.tools (run tools/setup_dev_tools.sh at the repo root)
or via env vars LUAU_BIN, LUAU_ANALYZE_BIN, ROJO_BIN, LUAU_LSP_BIN, ROBLOX_DEFS.
A missing tool is reported as SKIPPED, never as passed.
None of these checks is a substitute for testing in Roblox Studio.
"""
import os
import subprocess
import sys
import zipfile
from pathlib import Path

KIT = Path(__file__).resolve().parent.parent
TOOLS = KIT.parent.parent / ".tools"
VERSION = (KIT / "VERSION").read_text().strip()
DIST = KIT / "dist"
NAME = f"RobloxCreatorStarterKit-v{VERSION}"
TIMEOUT = 120  # seconds, every subprocess


def tool(env, rel):
    path = os.environ.get(env) or str(TOOLS / rel)
    return path if Path(path).exists() else None


def run(cmd, cwd=KIT):
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return False, f"timed out after {TIMEOUT}s"
    out = (p.stdout + p.stderr).strip()
    return p.returncode == 0, out


def main():
    check_only = "--check" in sys.argv
    luau = tool("LUAU_BIN", "luau/luau")
    analyze = tool("LUAU_ANALYZE_BIN", "luau/luau-analyze")
    rojo = tool("ROJO_BIN", "rojo/rojo")
    lsp = tool("LUAU_LSP_BIN", "lsp/luau-lsp")
    defs = tool("ROBLOX_DEFS", "globalTypes.d.luau")
    results = []

    def record(name, ok, detail=""):
        status = "SKIPPED" if ok is None else ("PASS" if ok else "FAIL")
        results.append((name, status, detail))
        print(f"[{status}] {name}" + (f"\n{detail}" if detail and status != "PASS" else ""))

    if luau:
        ok, out = run([luau, "tests/run.luau"])
        record("Luau unit tests (tests/run.luau)", ok, out)
    else:
        record("Luau unit tests", None, "luau binary not found")

    if analyze:
        shared = sorted(str(p.relative_to(KIT)) for p in (KIT / "src/Shared").glob("*.luau"))
        ok, out = run([analyze, "--mode=strict", *shared])
        record("Strict type check of src/Shared", ok, out)
    else:
        record("Strict type check", None, "luau-analyze not found")

    sourcemap = DIST / "sourcemap.json"
    if rojo and lsp and defs:
        DIST.mkdir(exist_ok=True)
        ok, out = run([rojo, "sourcemap", "default.project.json", "-o", str(sourcemap)])
        if ok:
            ok, out = run([lsp, "analyze", f"--definitions={defs}", f"--sourcemap={sourcemap}", "src", "examples"])
            out = "\n".join(l for l in out.splitlines() if not l.startswith(("[INFO]", "[WARN]")))
        record("Roblox API strict type check (luau-lsp, src + examples)", ok, out)
        sourcemap.unlink(missing_ok=True)
    else:
        record("Roblox API type check", None, "rojo / luau-lsp / definitions not found")

    failed = any(s == "FAIL" for _, s, _ in results)
    if check_only or failed:
        return 1 if failed else 0

    DIST.mkdir(exist_ok=True)
    place = DIST / f"{NAME}.rbxlx"
    if rojo:
        ok, out = run([rojo, "build", "default.project.json", "-o", str(place)])
        record("Rojo build of demo place (.rbxlx)", ok, out)
        if not ok:
            return 1
    else:
        record("Rojo build", None, "rojo not found - zip will not contain the .rbxlx")

    zip_path = DIST / f"{NAME}.zip"
    include = ["README.md", "LICENSE.txt", "CHANGELOG.md", "VERSION", "default.project.json", ".luaurc"]
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for rel in include:
            z.write(KIT / rel, f"{NAME}/{rel}")
        for folder in ["src", "docs", "examples", "tests"]:
            for p in sorted((KIT / folder).rglob("*")):
                if p.is_file():
                    z.write(p, f"{NAME}/{p.relative_to(KIT)}")
        if place.exists():
            z.write(place, f"{NAME}/{place.name}")
        report = "\n".join(f"{s:8} {n}" for n, s, _ in results)
        z.writestr(f"{NAME}/BUILD_CHECKS.txt",
                   "Automated checks run when this package was built.\n"
                   "These are NOT a Roblox Studio play-test.\n\n" + report + "\n")
    print(f"Packaged {zip_path.relative_to(KIT)} ({zip_path.stat().st_size // 1024} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
