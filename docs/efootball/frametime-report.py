#!/usr/bin/env python3
"""Summarise a MangoHud frametime log.

Usage:  python3 frametime-report.py <mangohud_log.csv> [more.csv ...]

MangoHud writes two header lines of system info before the real column
header, so we scan for the row that actually contains 'frametime'.
Frametimes are logged in microseconds.
"""
import csv
import statistics as st
import sys


def load(path):
    with open(path, newline="", errors="replace") as fh:
        rows = list(csv.reader(fh))
    start = next((i for i, r in enumerate(rows) if r and "frametime" in r), None)
    if start is None:
        raise SystemExit(f"{path}: no frametime column found — is this a MangoHud log?")
    header = [c.strip() for c in rows[start]]
    idx = header.index("frametime")
    out = []
    for r in rows[start + 1:]:
        if len(r) <= idx:
            continue
        try:
            v = float(r[idx])
        except ValueError:
            continue
        if v > 0:
            out.append(v)
    if not out:
        raise SystemExit(f"{path}: frametime column is empty")
    # microseconds -> milliseconds if needed
    return [v / 1000.0 for v in out] if st.median(out) > 1000 else out


def pct(sorted_vals, p):
    if not sorted_vals:
        return 0.0
    k = min(len(sorted_vals) - 1, int(round(p / 100.0 * (len(sorted_vals) - 1))))
    return sorted_vals[k]


def report(path):
    ft = load(path)
    s = sorted(ft)
    med = st.median(ft)
    p99 = pct(s, 99)
    p999 = pct(s, 99.9)
    hitches = sum(1 for v in ft if v > 2 * med)
    stutters = sum(1 for v in ft if v > 50.0)
    dur = sum(ft) / 1000.0

    print(f"\n=== {path} ===")
    print(f"  samples            {len(ft)}   ({dur:.0f}s captured)")
    print(f"  average fps        {1000.0 / (sum(ft) / len(ft)):.1f}")
    print(f"  median frametime   {med:.2f} ms")
    print(f"  1% low  (p99 ft)   {p99:.2f} ms  -> {1000.0 / p99:.1f} fps")
    print(f"  0.1% low (p99.9)   {p999:.2f} ms  -> {1000.0 / p999:.1f} fps")
    print(f"  consistency        stdev {st.pstdev(ft):.2f} ms")
    print(f"  hitches (>2x med)  {hitches}  ({100.0 * hitches / len(ft):.2f}% of frames)")
    print(f"  stutters (>50ms)   {stutters}")

    print("  verdict:")
    if st.pstdev(ft) > 0.35 * med:
        print("    - frame pacing is UNEVEN. Suspect compositor path (try gamescope),")
        print("      an uncapped framerate, or thermal throttling. Check gpu_temp in the log.")
    else:
        print("    - frame pacing is even; the render path is not your problem.")
    if stutters:
        print(f"    - {stutters} frames over 50ms. Early in a session this is shader")
        print("      compilation; spread evenly it is more likely CPU contention or I/O.")
    if p99 > 3 * med:
        print("    - the tail is far worse than the median: the average fps number is")
        print("      lying to you, and this is what 'sluggish' actually feels like.")
    if not stutters and p99 <= 2 * med and st.pstdev(ft) <= 0.35 * med:
        print("    - nothing wrong locally. If it still feels late, it is the network.")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    for p in sys.argv[1:]:
        report(p)
