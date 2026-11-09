#!/usr/bin/env bash
# Turn the dock off. Super+Space stays the Omarchy menu. Super+Alt+Space
# opens apps without the dock. Safe to run again: an already-off dock and
# bindings that already avoid the dock are left alone.
#
#   ./install.sh

set -euo pipefail

fail() {
  echo "install: $*" >&2
  exit 1
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  echo "Usage: install.sh"
  echo "Disables the dock and keeps Super+Space and Super+Alt+Space off it."
  exit 0
fi
[[ $# -eq 0 ]] || fail "unknown argument: $1"

plugin_json() {
  local json
  json="$(omarchy plugin list --json)"
  [[ $json == \[* ]] || fail "omarchy plugin list --json did not return a list"
  printf '%s\n' "$json"
}

disable_docks() {
  local json id
  json="$(plugin_json)"

  # Disabling a clone restores the built-in dock when the clone was what
  # replaced it. Disable clones first, then the built-in.
  while read -r id; do
    [[ -n $id ]] || continue
    omarchy plugin disable "$id"
  done < <(jq -r '.[] | select(.clonedFrom == "omarchy.dock" and .enabled == true) | .id' <<<"$json")

  json="$(plugin_json)"
  if jq -e '.[] | select(.id == "omarchy.dock" and .enabled == true)' <<<"$json" >/dev/null; then
    omarchy plugin disable omarchy.dock
  fi

  json="$(plugin_json)"
  if jq -e '.[] | select((.id == "omarchy.dock" or .clonedFrom == "omarchy.dock") and .enabled == true)' <<<"$json" >/dev/null; then
    fail "a dock plugin is still enabled"
  fi
  echo "Dock is off"
  PLUGINS_JSON="$json"
}

echo "==> dock"
PLUGINS_JSON=""
disable_docks
plugins="$PLUGINS_JSON"

applist_on=0
if jq -e '.[] | select(.id == "dtpietrzak.applist" and .enabled == true)' <<<"$plugins" >/dev/null; then
  applist_on=1
fi

status="$(python3 - "$applist_on" <<'PY'
import json
import re
import sys
from pathlib import Path

applist_on = sys.argv[1] == "1"
home = Path.home()

def fail(message):
    raise SystemExit(f"install: {message}")

def read_text(path):
    if not path.is_file():
        fail(f"{path} must already exist")
    return path.read_text()

def write_if_changed(path, text, label):
    old = path.read_text()
    if old == text:
        print(f"{label} is already set")
        return False
    path.write_text(text)
    print(f"Updated {label}")
    return True

def normalize_chord(value):
    return re.sub(r"\s+", " ", value.strip())

def line_chords(line):
    return [normalize_chord(match) for match in re.findall(r'"([^"]+)"', line)]

def lines_for_chord(lines, chord):
    want = normalize_chord(chord)
    hits = []
    for index, line in enumerate(lines):
        if line.lstrip().startswith("--"):
            continue
        if want in line_chords(line):
            hits.append(index)
    return hits

def ensure_binding(path, chord, pattern, addition, label):
    text = read_text(path)
    lines = text.splitlines()
    hits = lines_for_chord(lines, chord)
    if len(hits) > 1:
        fail(f"{label} is bound more than once in {path}")
    if len(hits) == 1 and re.search(pattern, lines[hits[0]]):
        print(f"{label} is already set")
        return False
    if len(hits) == 1:
        previous = lines[hits[0]].strip()
        lines[hits[0]] = addition.strip()
        new_text = "\n".join(lines)
        if text.endswith("\n"):
            new_text += "\n"
        changed = write_if_changed(path, new_text, label)
        if changed:
            print(f"{label} replaced: {previous}")
        return changed
    if text and not text.endswith("\n"):
        text += "\n"
    text += "\n" + addition
    if not text.endswith("\n"):
        text += "\n"
    return write_if_changed(path, text, label)

def calls_dock(action):
    return "omarchy.dock" in action or "omarchy-dock" in action

def upsert_apps(path, desired):
    if not path.exists():
        template = Path("/usr/share/omarchy/config/omarchy/extensions/omarchy-menu.jsonc")
        omarchy = __import__("os").environ.get("OMARCHY_PATH", "")
        if omarchy:
            candidate = Path(omarchy) / "config/omarchy/extensions/omarchy-menu.jsonc"
            if candidate.is_file():
                template = candidate
        if not template.is_file():
            fail("omarchy-menu.jsonc is missing and no template was found")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(template.read_text())
    lines = path.read_text().splitlines()
    hits = []
    for index, line in enumerate(lines):
        stripped = line.lstrip()
        if stripped.startswith("//"):
            continue
        if re.search(r'"apps"\s*:', line):
            hits.append(index)
    if len(hits) > 1:
        fail("omarchy-menu.jsonc has more than one apps key")
    if len(hits) == 1:
        line = lines[hits[0]]
        start = line.index("{")
        end = line.rindex("}")
        current = json.loads(line[start:end + 1])
        action = str(current.get("action") or "")
        stale_list = action.startswith("omarchy-shell shell summon dtpietrzak.applist") and not applist_on
        if not calls_dock(action) and not stale_list:
            print("Menu Apps row already avoids the dock")
            return False
    body = json.dumps(desired, ensure_ascii=False, separators=(",", ":"))
    rendered = f'  "apps": {body}'
    if len(hits) == 1:
        comma = "," if lines[hits[0]].rstrip().endswith(",") else ""
        lines[hits[0]] = rendered + comma
    else:
        close = None
        for index in range(len(lines) - 1, -1, -1):
            if lines[index].strip() == "}":
                close = index
                break
        if close is None:
            fail("omarchy-menu.jsonc has no closing brace")
        previous = close - 1
        while previous >= 0 and (lines[previous].strip() == "" or lines[previous].lstrip().startswith("//")):
            previous -= 1
        if previous >= 0 and lines[previous].strip() not in ("{",) and not lines[previous].rstrip().endswith(","):
            lines[previous] = lines[previous].rstrip() + ","
        lines.insert(close, rendered)
    text = "\n".join(lines)
    if path.read_text().endswith("\n") or not text.endswith("\n"):
        text += "\n"
    return write_if_changed(path, text, "Menu Apps row")

bindings = home / ".config/hypr/bindings.lua"
hypr_changed = False
if applist_on:
    bind = 'o.rebind("SUPER + ALT + SPACE", "Apps", { panel = "dtpietrzak.applist" })\n'
    bind_pattern = r'o\.rebind\(\s*"SUPER \+ ALT \+ SPACE"\s*,\s*"Apps"\s*,\s*\{\s*panel\s*=\s*"dtpietrzak\.applist"\s*\}\s*\)'
    comment = "-- App launcher. The dock is off, so this opens the list.\n"
else:
    bind = 'o.rebind("SUPER + ALT + SPACE", "Apps", { menu = "apps" })\n'
    bind_pattern = r'o\.rebind\(\s*"SUPER \+ ALT \+ SPACE"\s*,\s*"Apps"\s*,\s*\{\s*menu\s*=\s*"apps"\s*\}\s*\)'
    comment = "-- App launcher. The dock is off, so this opens the Apps menu.\n"
if ensure_binding(bindings, "SUPER + ALT + SPACE", bind_pattern, comment + bind, "Super+Alt+Space"):
    hypr_changed = True

space_pattern = r'o\.rebind\(\s*"SUPER \+ SPACE"\s*,\s*"Omarchy menu"\s*,\s*\{\s*menu\s*=\s*"root"\s*\}\s*\)'
space_bind = 'o.rebind("SUPER + SPACE", "Omarchy menu", { menu = "root" })\n'
space_lines = lines_for_chord(read_text(bindings).splitlines(), "SUPER + SPACE")
if space_lines:
    if ensure_binding(
        bindings,
        "SUPER + SPACE",
        space_pattern,
        "-- System menu. Super+Space opens the Omarchy menu.\n" + space_bind,
        "Super+Space",
    ):
        hypr_changed = True
else:
    print("Super+Space already opens the Omarchy menu")

if applist_on:
    apps = {
        "icon": "\uf03a",
        "label": "Apps",
        "aliases": ["app", "applications"],
        "provider": "apps",
        "action": "omarchy-shell shell summon dtpietrzak.applist",
    }
else:
    apps = {
        "icon": "\uf003b",
        "label": "Apps",
        "aliases": ["app", "applications"],
        "provider": "apps",
    }
upsert_apps(home / ".config/omarchy/extensions/omarchy-menu.jsonc", apps)
print(f"STATUS hypr_changed={1 if hypr_changed else 0}")
PY
)"
printf '%s\n' "$status"

hypr_changed=0
if grep -q '^STATUS hypr_changed=1$' <<<"$status"; then
  hypr_changed=1
fi

if [[ $hypr_changed -eq 1 ]]; then
  hyprctl reload >/dev/null
fi
errors="$(hyprctl configerrors 2>&1 || true)"
if [[ -n ${errors//[[:space:]]/} ]]; then
  printf '%s\n' "$errors" >&2
  fail "Hyprland reported config errors"
fi
if [[ $hypr_changed -eq 1 ]]; then
  echo "Hyprland config reloaded with no errors"
else
  echo "Hyprland config has no errors"
fi

keys="$(omarchy menu keybindings --print)"
printf '%s\n' "$keys" | grep -E -q 'SUPER \+ SPACE[[:space:]]+→ Omarchy menu$' || fail "Super+Space does not open the Omarchy menu"
printf '%s\n' "$keys" | grep -E -q 'SUPER ALT \+ SPACE[[:space:]]+→ Apps$' || fail "Super+Alt+Space does not open Apps"

layer_namespaces() {
  hyprctl layers -j | jq -r '.[] | .levels | to_entries[] | .value[]? | .namespace'
}

if layer_namespaces | grep -qx 'omarchy-dock'; then
  echo "Dock layer is still up. Restarting the shell."
  omarchy restart shell
  sleep 1
fi
if layer_namespaces | grep -qx 'omarchy-dock'; then
  fail "the omarchy-dock layer is still mapped"
fi
echo "Dock layer is gone"
