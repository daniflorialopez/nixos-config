"""strata: a wallpaper that is a picture of your week.

Seven mountain ridges, one per day, the oldest furthest away and today in
front. A day's ridge is as tall and as jagged as the work done that day: a day
with no commits is a low smooth hill, a heavy day is a range. Every commit of
the last thirty days is a star, and each of today's commits is a light on
today's ridge — the same picture as the town lights under the mountains in the
wallpaper this desktop was built around.

The sky follows the clock (deep at night, warm at the two ends of the day), so
rendering it on a timer gives a wallpaper that is never the same twice and
never arbitrary. Pure pycairo, one PNG, no state.

    strata.py OUT.png [WIDTH HEIGHT]      repos from $REVERIE_REPOS (colon list)
"""

import datetime
import hashlib
import math
import os
import random
import subprocess
import sys

import cairo


DAYS = 7


def load_palette():
    import json
    with open(os.environ["REVERIE_PALETTE"]) as f:
        roles = json.load(f)["roles"]
    out = {}
    for name, role in roles.items():
        h = role["hex"].lstrip("#")
        out[name] = tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return out


PAL = load_palette()


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def commits(repos):
    """[(hash, unix_time)] over the last 30 days, all branches, all repos."""
    out = []
    for repo in repos:
        try:
            log = subprocess.run(
                ["git", "-C", repo, "log", "--all", "--since=30.days", "--format=%H %ct"],
                capture_output=True, text=True, timeout=10).stdout
        except (OSError, subprocess.TimeoutExpired):
            continue
        for line in log.splitlines():
            h, _, ts = line.partition(" ")
            if ts.isdigit():
                out.append((h, int(ts)))
    return sorted(set(out), key=lambda c: c[1])


def ridge(seed, width, base, amp, rough):
    """Midpoint displacement: a stable skyline for a given seed."""
    rng = random.Random(seed)
    # Five anchors rather than two: a range has several peaks, and two
    # anchors only ever give one slope.
    pts = [base - rng.random() * amp for _ in range(5)]
    spread = amp * 0.9
    while len(pts) < width / 6:
        nxt = []
        for a, b in zip(pts, pts[1:]):
            nxt += [a, (a + b) / 2 + (rng.random() - 0.5) * spread]
        nxt.append(pts[-1])
        pts = nxt
        spread *= rough
    return pts


def render(path, w, h, repos, now=None):
    now = now or datetime.datetime.now()
    hour = now.hour + now.minute / 60
    today = now.date()
    log = commits(repos)
    per_day = {}
    for sha, ts in log:
        d = datetime.date.fromtimestamp(ts)
        per_day.setdefault(d, []).append(sha)

    surf = cairo.ImageSurface(cairo.FORMAT_RGB24, w, h)
    cr = cairo.Context(surf)
    u = h / 1440

    # --- sky. `glow` peaks at the two ends of the day, `light` at noon.
    def bump(x, centre, width):
        return math.exp(-((x - centre) / width) ** 2)

    glow = max(bump(hour, 7.5, 1.4), bump(hour, 17.2, 1.6))
    light = max(0.0, math.sin((hour - 6.5) / 11.5 * math.pi)) if 6.5 < hour < 18 else 0.0
    top = lerp(PAL["bgDeep"], PAL["searchMatch"], 0.55 * light)
    mid = lerp(PAL["bg"], PAL["accent"], 0.38 * light)
    mid = lerp(mid, PAL["critical"], 0.30 * glow)
    low = lerp(PAL["selection"], PAL["fg"], 0.35 * light)
    low = lerp(low, PAL["attention"], 0.75 * glow)
    sky = cairo.LinearGradient(0, 0, 0, h * 0.78)
    sky.add_color_stop_rgb(0.0, *top)
    sky.add_color_stop_rgb(0.55, *mid)
    sky.add_color_stop_rgb(0.85, *lerp(mid, low, 0.7))
    sky.add_color_stop_rgb(1.0, *low)
    cr.set_source(sky)
    cr.paint()

    # --- stars: one per commit, placed by its hash, so a commit is always
    # the same star. Recent ones are brighter; daylight washes them out.
    night = 1.0 - 0.85 * light
    for sha, ts in log:
        digest = hashlib.sha256(sha.encode()).digest()
        x = int.from_bytes(digest[0:2], "big") / 65535 * w
        y = (int.from_bytes(digest[2:4], "big") / 65535) ** 1.6 * h * 0.52
        age = (now.timestamp() - ts) / (30 * 86400)
        size = (0.8 + 1.7 * (1 - age)) * u
        cr.set_source_rgba(*PAL["fg"], (0.25 + 0.75 * (1 - age)) * night)
        cr.arc(x, y, size, 0, math.tau)
        cr.fill()
        if age < 0.04:                       # the last day or so: a soft halo
            cr.set_source_rgba(*PAL["fg"], 0.10 * night)
            cr.arc(x, y, size * 4, 0, math.tau)
            cr.fill()

    # --- sun or moon, riding an arc across the sky.
    if 6.5 < hour < 18:
        t = (hour - 6.5) / 11.5
        body, alpha = PAL["warning"], 0.95
    else:
        t = ((hour - 18) % 24) / 12.5
        body, alpha = PAL["fg"], 0.85
    bx = w * (0.08 + 0.84 * t)
    by = h * (0.60 - 0.44 * math.sin(t * math.pi))
    halo = cairo.RadialGradient(bx, by, 0, bx, by, 190 * u)
    halo.add_color_stop_rgba(0.0, *body, 0.30)
    halo.add_color_stop_rgba(0.35, *body, 0.10)
    halo.add_color_stop_rgba(1.0, *body, 0.0)
    cr.set_source(halo)
    cr.arc(bx, by, 190 * u, 0, math.tau)
    cr.fill()
    cr.set_source_rgba(*body, alpha)
    cr.arc(bx, by, 30 * u, 0, math.tau)
    cr.fill()

    # --- the ridges, far to near.
    busiest = max([len(v) for v in per_day.values()] + [1])
    for i in range(DAYS):
        day = today - datetime.timedelta(days=DAYS - 1 - i)
        n = len(per_day.get(day, []))
        depth = i / (DAYS - 1)                       # 0 far .. 1 near
        effort = math.sqrt(n / busiest) if n else 0.0
        base = h * (0.56 + 0.36 * depth)
        amp = h * (0.07 + 0.24 * effort) * (0.7 + 0.5 * depth)
        pts = ridge(day.toordinal(), w, base, amp, 0.52 + 0.12 * effort)
        haze = lerp(mid, low, 0.5)
        near = lerp(PAL["bgDeep"], PAL["gutter"], 0.25)
        col = lerp(lerp(haze, PAL["slate"], 0.45), near, depth ** 0.8)
        # Each ridge fades into mist toward its foot, which is what separates
        # it from the one in front.
        body_grad = cairo.LinearGradient(0, base - amp, 0, base + 0.20 * h)
        body_grad.add_color_stop_rgb(0.0, *col)
        body_grad.add_color_stop_rgb(1.0, *lerp(col, haze, 0.55 * (1 - depth)))
        cr.set_source(body_grad)
        cr.move_to(0, h)
        step = w / (len(pts) - 1)
        for k, y in enumerate(pts):
            cr.line_to(k * step, y)
        cr.line_to(w, h)
        cr.close_path()
        cr.fill()

        # Lights: each commit of the two nearest days is a lit window on its
        # own ridge. Today's are the brightest.
        if i >= DAYS - 2:
            for sha in per_day.get(day, []):
                digest = hashlib.sha256(sha.encode()).digest()
                fx = int.from_bytes(digest[4:6], "big") / 65535
                k = fx * (len(pts) - 1)
                y0 = pts[int(k)] + (0.02 + 0.10 * digest[6] / 255) * h
                strength = 1.0 if i == DAYS - 1 else 0.45
                cr.set_source_rgba(*PAL["attention"], 0.12 * strength)
                cr.arc(fx * w, y0, 9 * u, 0, math.tau)
                cr.fill()
                cr.set_source_rgba(*PAL["warning"], 0.95 * strength)
                cr.arc(fx * w, y0, 2.2 * u, 0, math.tau)
                cr.fill()

    # --- a legend small enough to ignore.
    total = sum(len(per_day.get(today - datetime.timedelta(days=d), [])) for d in range(DAYS))
    cr.select_font_face("Inter Variable", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    cr.set_font_size(15 * u)
    cr.set_source_rgba(*PAL["hint"], 0.9)
    cr.move_to(40 * u, h - 34 * u)
    cr.show_text(f"{DAYS} days  ·  {total} commits  ·  {len(per_day.get(today, []))} today")
    surf.write_to_png(path)


if __name__ == "__main__":
    out = sys.argv[1]
    width = int(sys.argv[2]) if len(sys.argv) > 3 else 2560
    height = int(sys.argv[3]) if len(sys.argv) > 3 else 1440
    repo_list = [r for r in os.environ.get(
        "REVERIE_REPOS", os.path.expanduser("~/nixos-config")).split(":") if r]
    render(out, width, height, repo_list)
    print(out)
