#!/usr/bin/env python3
"""Measures the solver and the preview, for comparing before and after a change.

    tools/solver_bench.py CASE [CASE ...] [--rooms 18,19] [--note TEXT]

Cases:
  preview     tools/render.sh --preview of every room (or --rooms), after import
  warm-world  whole-world validation reading the committed cache (--dump taken)
  synthetic   the small tests/fixtures/worlds/synth world solved with no cache
  rooms       cold preparation of --rooms (default 18,19): every jumps and climb
              piece the room needs, worked out one after another into a fresh
              cache folder (no other room's cache is touched). This can take
              hours; it is never run by default.

Each run writes build/solver-bench/<run-id>/report.json and the logs beside it;
an earlier run is never overwritten. Standard library only.

A report records the commit and a hash of uncommitted changes, Godot version, OS,
cores, cache mode, the solver and room fingerprints, wall time, CPU time and peak
memory of every Godot process it started (ru_maxrss of the direct child; a
process it cannot measure is "unavailable", never zero), and sha256 of the dumps.
Stage counters (plans, simulations, reuse) are the ones ReachGraph already keeps
and `validate.sh` prints; adding finer ones means touching the fingerprinted
solver, which is left to the change that needs them.
"""
import argparse
import hashlib
import json
import os
import platform
import re
import resource
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UNAVAILABLE = "unavailable"
GODOT = ["godot", "--headless", "--path", str(ROOT)]


def run_measured(name, argv, log_path, env=None):
    """Runs argv, logs its output, returns wall, CPU and peak memory."""
    started = time.monotonic()
    with open(log_path, "w") as log:
        child = subprocess.Popen(argv, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, env=env)
        _, status, usage = os.wait4(child.pid, 0)
    wall = time.monotonic() - started
    code = os.waitstatus_to_exitcode(status)
    peak = UNAVAILABLE
    if usage is not None and platform.system() == "Linux":
        peak = {"value": usage.ru_maxrss, "unit": "KiB", "source": "wait4 ru_maxrss of the process"}
    elif usage is not None and platform.system() == "Darwin":
        peak = {"value": usage.ru_maxrss // 1024, "unit": "KiB", "source": "wait4 ru_maxrss of the process"}
    cpu = {"user_s": round(usage.ru_utime, 3), "system_s": round(usage.ru_stime, 3)} if usage is not None else UNAVAILABLE
    return {"step": name, "argv": argv, "exit": code, "wall_s": round(wall, 3), "cpu": cpu, "peak_memory": peak, "log": str(log_path)}


def sha256(path):
    path = Path(path)
    if not path.is_file():
        return UNAVAILABLE
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True).stdout.strip()


def environment():
    dirty = git("diff", "HEAD")
    untracked = [p for p in git("ls-files", "--others", "--exclude-standard").splitlines() if not p.startswith("build/")]
    digest = hashlib.sha256(dirty.encode())
    for p in sorted(untracked):
        digest.update(p.encode())
        digest.update((ROOT / p).read_bytes())
    return {
        "commit": git("rev-parse", "HEAD"),
        "dirty_inputs_sha256": digest.hexdigest() if (dirty or untracked) else "clean",
        "os": platform.platform(),
        "cpu_cores": os.cpu_count(),
        "python": sys.version.split()[0],
        "godot": subprocess.run(["godot", "--version"], capture_output=True, text=True).stdout.strip(),
    }


def inputs(out):
    step = run_measured("inputs", GODOT + ["--script", "tests/lib/solver_bench.gd"], out / "inputs.log")
    for line in Path(step["log"]).read_text().splitlines():
        if line.startswith("BENCH_INPUTS "):
            return json.loads(line[len("BENCH_INPUTS "):])
    return UNAVAILABLE


def parse_validate(log):
    """The numbers validate.gd prints that a benchmark wants."""
    text = Path(log).read_text()
    found = {}
    m = re.search(r"cache: (\d+) rooms' ledges from it and (\d+) worked out", text)
    if m:
        found["edge_rooms_from_cache"], found["edge_rooms_solved"] = int(m.group(1)), int(m.group(2))
    rows = []
    for m in re.finditer(r"^  (\S.*?)\s+([\d.]+) s\s+(\d+) plans\s+(\d+) run once for every moment\s+(\d+) phases", text, re.M):
        rows.append({"key": m.group(1), "s": float(m.group(2)), "plans": int(m.group(3)), "reused": int(m.group(4)), "phases": int(m.group(5))})
    found["slowest_rooms"] = rows
    found["validate_pass"] = "validate pass" in text
    return found


def case_preview(out, args):
    ids = args.rooms.split(",") if args.rooms else []
    step = run_measured("preview", [str(ROOT / "tools/render.sh"), "--preview", *ids], out / "preview.log", env={**os.environ, "SKIP_IMPORT": "1"})
    return {"case": "preview", "cache_mode": "none (no solver, no cache)", "steps": [step], "ok": step["exit"] == 0}


def case_warm_world(out, args):
    dump = out / "warm-world-dump.json"
    step = run_measured("validate", GODOT + ["--script", "tests/validate.gd", "--", f"--dump={dump}"], out / "warm-world.log")
    return {"case": "warm-world", "cache_mode": "committed data/solver-cache, read", "steps": [step], "parsed": parse_validate(step["log"]), "dump_sha256": sha256(dump), "ok": step["exit"] == 0}


def case_synthetic(out, args):
    dump = out / "synthetic-dump.json"
    step = run_measured("solve", GODOT + ["--script", "tests/lib/solver_dump_main.gd", "--", f"--dump={dump}", "--world=res://tests/fixtures/worlds/synth"], out / "synthetic.log")
    return {"case": "synthetic", "cache_mode": "none", "steps": [step], "dump_sha256": sha256(dump), "ok": step["exit"] == 0}


def case_rooms(out, args):
    rooms = (args.rooms or "18,19").split(",")
    cache = out / "cache"
    cache.mkdir()
    res_cache = f"--cache-dir=res://{os.path.relpath(cache, ROOT)}"
    plan = subprocess.run(GODOT + ["--script", "tests/validate.gd", "--", "--plan", res_cache], cwd=ROOT, capture_output=True, text=True).stdout
    pieces = [l[len("piece "):] for l in plan.splitlines() if l.startswith("piece ")]
    mine = [p for p in pieces if p.split(":")[0].split("~")[0] in rooms]
    # A room's climbs read its jumps from the cache, so jumps0 goes first.
    mine.sort(key=lambda p: (0 if p.endswith(":jumps0") else 1, p))
    steps = []
    for piece in mine:
        name = piece.replace(":", "_")
        steps.append(run_measured(piece, GODOT + ["--script", "tests/validate.gd", "--", f"--warm-piece={piece}", res_cache], out / f"piece-{name}.log"))
        if steps[-1]["exit"] != 0:
            break
    return {"case": "rooms", "rooms": rooms, "cache_mode": f"fresh cache folder {cache}", "pieces": mine, "steps": steps, "wall_s_total": round(sum(s["wall_s"] for s in steps), 3), "ok": bool(steps) and all(s["exit"] == 0 for s in steps)}


CASES = {"preview": case_preview, "warm-world": case_warm_world, "synthetic": case_synthetic, "rooms": case_rooms}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("cases", nargs="+", choices=sorted(CASES))
    parser.add_argument("--rooms", help="comma-separated room ids for preview and rooms")
    parser.add_argument("--note", default="", help="free text kept in the report")
    args = parser.parse_args()
    run_id = time.strftime("%Y%m%d-%H%M%S") + f"-{os.getpid()}"
    out = ROOT / "build" / "solver-bench" / run_id
    out.mkdir(parents=True)
    subprocess.run(GODOT + ["--import"], cwd=ROOT, capture_output=True)
    report = {"run_id": run_id, "note": args.note, "environment": environment(), "inputs": inputs(out), "workers": 1, "cases": []}
    for name in args.cases:
        print(f"== {name}", flush=True)
        result = CASES[name](out, args)
        report["cases"].append(result)
        wall = sum(s["wall_s"] for s in result["steps"])
        print(f"   {'ok' if result['ok'] else 'FAILED'}: {wall:.1f} s wall", flush=True)
        (out / "report.json").write_text(json.dumps(report, indent=2))
    (out / "report.json").write_text(json.dumps(report, indent=2))
    print(f"report: {out / 'report.json'}")
    return 0 if all(c["ok"] for c in report["cases"]) else 1


if __name__ == "__main__":
    sys.exit(main())
