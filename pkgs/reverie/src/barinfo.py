"""barinfo: everything the bar knows, read from the bar's own configuration.

The HUD is meant to be able to replace the bar (zen), so it has to show what
the bar shows — and the way to keep the two from drifting is to have no second
definition at all. This reads ~/.config/waybar/config and style.css:

  - every `custom/*` module is run with the exact `exec` waybar uses, and its
    JSON (text, class, tooltip) is shown as is;
  - the built-in modules (bluetooth, network, pulseaudio, battery, mpris,
    tray, window title) are re-implemented, but with the bar's own format
    strings and icon tables, so a changed glyph changes in both places;
  - a module's colour comes from the same `#id.class { color: @role }` rule
    the bar is styled by.

One thing the bar cannot do and this can: there is room for the tooltip. On
the bar, "what does this icon mean right now" is a hover; here it is written
next to the icon.

A module that prints nothing (the bar hides those) is skipped here too.
"""

import glob
import json
import os
import re
import shlex
import shutil
import subprocess
import threading
from concurrent.futures import ThreadPoolExecutor

from gi.repository import Gio, GLib

from common import hypr

CONFIG = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "waybar")


def _run(cmd, timeout=3):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def _read(path, default=""):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


class BarInfo:
    def __init__(self):
        self.items = []          # [{"key", "text", "detail", "role"}], bar order
        self.title = ""          # the focused window's title, with the bar's rewrites
        self.config = {}
        self.colors = {}         # (css id, css class or None) -> palette role
        self.listeners = []      # called on the main loop when new data lands
        self._busy = False

    # -- the bar's own files ----------------------------------------------
    def load(self):
        try:
            with open(os.path.join(CONFIG, "config")) as f:
                data = json.load(f)
            self.config = data[0] if isinstance(data, list) else data
        except (OSError, ValueError, IndexError):
            self.config = {}
        self.colors = {}
        css = _read(os.path.join(CONFIG, "style.css"))
        css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
        for selectors, body in re.findall(r"([^{}]+)\{([^{}]*)\}", css):
            # the text colour, not background-color
            m = re.search(r"(?<![-\w])color:\s*@(\w+)", body)
            if not m:
                continue
            for sel in selectors.split(","):
                hit = re.fullmatch(r"#([\w-]+)(?:\.([\w-]+))?", sel.strip())
                if hit:
                    self.colors[(hit.group(1), hit.group(2))] = m.group(1)

    def role(self, css_id, css_class, default="subtle"):
        role = self.colors.get((css_id, css_class)) or self.colors.get((css_id, None)) or default
        # An inverted pill on the bar (dark text on a warm fill) has no
        # equivalent here; what it means is "this needs you".
        return "attention" if role == "bg" else role

    def persistent_workspaces(self):
        """The workspaces the bar always shows (its `persistent-workspaces`)."""
        if not self.config:
            self.load()
        spec = self.config.get("hyprland/workspaces", {}).get("persistent-workspaces", {})
        ids = set()
        for value in spec.values() if isinstance(spec, dict) else []:
            ids.update(v for v in (value if isinstance(value, list) else [value])
                       if isinstance(v, int))
        return sorted(ids)

    def modules(self):
        out = []
        for side in ("modules-left", "modules-center", "modules-right"):
            out += self.config.get(side, [])
        return out

    # -- refresh ----------------------------------------------------------
    def refresh(self):
        """Collect in a thread; the scripts fork and some take a moment."""
        if self._busy:
            return
        self._busy = True
        threading.Thread(target=self._work, daemon=True).start()

    def _work(self):
        try:
            items, title = self.collect()
            GLib.idle_add(self._land, items, title)
        finally:
            self._busy = False

    def collect(self):
        """Run every module once and return them in the bar's order.

        Blocking, so call it off the main loop. The modules run side by side:
        each is a fork or two, and the slowest one sets the total instead of
        the sum (measured: ~3.8 s in sequence, mostly one nmcli call).
        """
        self.load()
        names = self.modules()

        def one(name):
            try:
                if name.startswith("custom/"):
                    return self.custom(name)
                if name == "hyprland/window":
                    return {"title": self.window_title()}
                handler = getattr(self, "m_" + name.replace("/", "_"), None)
                return handler() if handler else None
            except Exception as exc:     # one broken module must not blank the rest
                print(f"barinfo: {name}: {exc!r}", flush=True)
                return None

        with ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(one, names))
        items, title = [], ""
        for name, item in zip(names, results):
            if not item:
                continue
            if "title" in item:
                title = item["title"]
            elif item.get("text", "").strip():
                item["key"] = name
                items.append(item)
        return items, title

    def _land(self, items, title):
        self.items, self.title = items, title
        for listener in self.listeners:
            listener()
        return False

    # -- modules ----------------------------------------------------------
    def custom(self, name):
        conf = self.config.get(name, {})
        if not conf.get("exec"):
            return None
        out = _run(shlex.split(conf["exec"]))
        if not out:
            return None
        if conf.get("return-type") == "json":
            data = json.loads(out.splitlines()[-1])
        else:
            lines = out.splitlines()
            data = {"text": lines[0], "tooltip": lines[1] if len(lines) > 1 else ""}
        tip = (data.get("tooltip") or "").split("\n")[0]
        return {"text": conf.get("format", "{}").replace("{}", data.get("text", "")),
                "detail": tip,
                "role": self.role(name.replace("/", "-"), data.get("class") or None)}

    def window_title(self):
        conf = self.config.get("hyprland/window", {})
        title = (hypr("j/activewindow") or {}).get("title", "")
        for pattern, repl in conf.get("rewrite", {}).items():
            try:
                if re.fullmatch(pattern, title):
                    title = re.sub(pattern, re.sub(r"\$(\d)", r"\\\1", repl), title)
                    break
            except re.error:
                pass
        limit = conf.get("max-length", 60)
        return title if len(title) <= limit else title[:limit - 1] + "…"

    def m_bluetooth(self):
        conf = self.config.get("bluetooth", {})
        if not shutil.which("bluetoothctl"):
            return None
        powered = "Powered: yes" in _run(["bluetoothctl", "show"])
        if not powered:
            return {"text": conf.get("format-off", "󰂲"), "detail": "bluetooth off",
                    "role": self.role("bluetooth", "off", "muted")}
        names = [ln.split(" ", 2)[2] for ln in _run(
            ["bluetoothctl", "devices", "Connected"]).splitlines() if ln.count(" ") >= 2]
        if names:
            text = conf.get("format-connected", "󰂱 {num_connections}").replace(
                "{num_connections}", str(len(names)))
            return {"text": text, "detail": ", ".join(names),
                    "role": self.role("bluetooth", "connected", "accent")}
        return {"text": conf.get("format", "󰂯"), "detail": "bluetooth on",
                "role": self.role("bluetooth", None)}

    def m_network(self):
        conf = self.config.get("network", {})
        if not shutil.which("nmcli"):
            return None
        # --rescan no: without it nmcli may start a scan and take seconds; the
        # cached list is all a status line needs.
        wifi = _run(["nmcli", "-t", "-f", "ACTIVE,SSID,SIGNAL", "dev", "wifi", "list",
                     "--rescan", "no"])
        for line in wifi.splitlines():
            if line.startswith("yes:"):
                _, ssid, signal = (line.split(":") + ["", ""])[:3]
                return {"text": conf.get("format-wifi", "󰖩  {essid}").replace("{essid}", ssid),
                        "detail": f"signal {signal}%", "role": self.role("network", None)}
        active = _run(["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active"])
        for line in active.splitlines():
            if line.endswith(":802-11-wireless"):
                return {"text": conf.get("format-wifi", "󰖩  {essid}").replace(
                            "{essid}", line.rsplit(":", 1)[0]),
                        "detail": "", "role": self.role("network", None)}
        if "ethernet" in active:
            return {"text": conf.get("format-ethernet", "󰈀  wired"), "detail": "",
                    "role": self.role("network", None)}
        return {"text": conf.get("format-disconnected", "󰖪  offline"), "detail": "",
                "role": self.role("network", "disconnected", "muted")}

    def m_pulseaudio(self):
        conf = self.config.get("pulseaudio", {})
        out = _run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]) if shutil.which("wpctl") else ""
        m = re.search(r"Volume:\s*([\d.]+)", out)
        if not m:
            return None
        if "MUTED" in out:
            return {"text": conf.get("format-muted", "󰖁  mute"), "detail": "",
                    "role": self.role("pulseaudio", "muted", "muted")}
        vol = round(float(m.group(1)) * 100)
        icons = conf.get("format-icons", {})
        icons = icons.get("default", ["󰕾"]) if isinstance(icons, dict) else icons
        icon = icons[min(len(icons) - 1, vol * len(icons) // 101)] if icons else ""
        text = conf.get("format", "{icon} {volume}%").replace("{icon}", icon).replace(
            "{volume}", str(vol))
        return {"text": text, "detail": "", "role": self.role("pulseaudio", None)}

    def m_battery(self):
        conf = self.config.get("battery", {})
        bats = glob.glob("/sys/class/power_supply/BAT*")
        if not bats:
            return None
        cap = _read(bats[0] + "/capacity")
        if not cap.isdigit():
            return None
        cap = int(cap)
        status = _read(bats[0] + "/status")
        watts = _read(bats[0] + "/power_now")
        detail = f"{int(watts) / 1e6:.1f} W" if watts.isdigit() and int(watts) else ""
        css_class = None
        if status == "Charging":
            fmt = conf.get("format-charging", conf.get("format", "{capacity}%"))
        elif status in ("Full", "Not charging"):
            fmt = conf.get("format-plugged", conf.get("format", "{capacity}%"))
        else:
            fmt = conf.get("format", "{icon} {capacity}%")
            states = conf.get("states", {})
            # the lowest threshold the level is under wins
            for name, limit in sorted(states.items(), key=lambda kv: kv[1]):
                if cap <= limit:
                    css_class = name
                    break
            if detail:
                detail = "discharging · " + detail
        icons = conf.get("format-icons", [])
        icon = icons[min(len(icons) - 1, cap * len(icons) // 101)] if icons else ""
        return {"text": fmt.replace("{icon}", icon).replace("{capacity}", str(cap)),
                "detail": detail, "role": self.role("battery", css_class)}

    def m_mpris(self):
        conf = self.config.get("mpris", {})
        if not shutil.which("playerctl"):
            return None
        status = _run(["playerctl", "status"]).lower()
        if status not in ("playing", "paused"):
            return None
        artist = _run(["playerctl", "metadata", "artist"])
        title = _run(["playerctl", "metadata", "title"])
        icon = conf.get("status-icons", {}).get(status, "")
        fmt = conf.get("format-" + status, conf.get("format", "{status_icon}  {artist} · {title}"))
        text = fmt.replace("{status_icon}", icon).replace("{artist}", artist).replace(
            "{title}", title).strip(" ·")
        limit = conf.get("max-length", 60)
        if len(text) > limit:
            text = text[:limit - 1] + "…"
        return {"text": text, "detail": "", "role": self.role("mpris", None, "muted")}

    def m_tray(self):
        """Names of the tray's applications (the icons themselves live in the bar)."""
        try:
            bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            reply = bus.call_sync(
                "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
                "org.freedesktop.DBus.Properties", "Get",
                GLib.Variant("(ss)", ("org.kde.StatusNotifierWatcher",
                                      "RegisteredStatusNotifierItems")),
                None, Gio.DBusCallFlags.NONE, 800, None)
            services = reply.unpack()[0]
        except GLib.Error:
            return None
        names = []
        for entry in services:
            service, _, path = entry.partition("/")
            try:
                got = bus.call_sync(
                    service, "/" + path if path else "/StatusNotifierItem",
                    "org.freedesktop.DBus.Properties", "Get",
                    GLib.Variant("(ss)", ("org.kde.StatusNotifierItem", "Title")),
                    None, Gio.DBusCallFlags.NONE, 500, None).unpack()[0]
            except GLib.Error:
                got = ""
            names.append(got or service.rsplit(".", 1)[-1])
        if not names:
            return None
        return {"text": "󰍜  " + " · ".join(names), "detail": "", "role": "subtle"}
