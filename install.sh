#!/usr/bin/env bash
# KRunner parity pack for the Omarchy launcher (Hyprland + Quickshell).
# Installs the enhanced menu files into an existing Omarchy shell checkout.
# Everything it overwrites is backed up first; run uninstall.sh to revert.
set -euo pipefail

OMARCHY="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"
MIRROR="$HOME/.config/quickshell/omarchy"
HERE="$(cd "$(dirname "$0")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
BACKUPS="$HOME/.local/share/omarchy-backups/launcher-krunner/$STAMP"

say()  { printf '%s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ -f "$OMARCHY/shell/plugins/menu/Menu.qml" ]] \
  || die "Omarchy shell not found at $OMARCHY — set OMARCHY_PATH if it lives elsewhere"
[[ -d "$HERE/files" ]] || die "run this script from the repository root"

say "==> Checking dependencies"
missing=()
for bin in fd hyprctl wl-copy; do
  command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  say "    WARNING: missing ${missing[*]} — the tiers they power will be silently empty:"
  say "             fd (file/folder search), hyprctl (window switcher), wl-copy (copy actions)"
fi
if ! command -v baloosearch6 >/dev/null 2>&1; then
  say "    NOTE: baloosearch6 not found — the file-CONTENT search tier will be empty."
  say "          (KDE users usually have it; enable Baloo indexing to use it.)"
fi

# A re-run on an already-installed (unmodified) tree would snapshot the pack
# itself, and "restore the newest backup" would then restore the pack instead
# of the pristine files. Only snapshot when something actually differs.
PACK_STATE=1
cmp -s "$OMARCHY/shell/plugins/menu/Menu.qml" "$HERE/files/Menu.qml" || PACK_STATE=0
cmp -s "$OMARCHY/shell/Ui/OverlayWindow.qml" "$HERE/files/OverlayWindow.qml" || PACK_STATE=0

if [[ $PACK_STATE -eq 1 ]]; then
  say "==> Already at the pack revision — no new backup taken"
  say "    (the existing pristine snapshot stays the one uninstall restores)"
else
  say "==> Backing up current files to $BACKUPS"
  mkdir -p "$BACKUPS/shell/plugins/menu" "$BACKUPS/shell/Ui"
  for f in shell/plugins/menu/Menu.qml shell/plugins/menu/MenuModel.js shell/Ui/OverlayWindow.qml; do
    [[ -f "$OMARCHY/$f" ]] && cp "$OMARCHY/$f" "$BACKUPS/$f"
  done
  [[ -f "$HOME/.local/bin/ravi-window-focus" ]] && cp "$HOME/.local/bin/ravi-window-focus" "$BACKUPS/"
  # The mirror gets overwritten below, so its current files land in the same
  # snapshot — uninstall can restore it byte-for-byte.
  if [[ -d "$MIRROR/plugins/menu" ]]; then
    mkdir -p "$BACKUPS/mirror/plugins/menu" "$BACKUPS/mirror/Ui"
    [[ -f "$MIRROR/plugins/menu/Menu.qml" ]] && cp "$MIRROR/plugins/menu/Menu.qml" "$BACKUPS/mirror/plugins/menu/"
    [[ -f "$MIRROR/plugins/menu/MenuModel.js" ]] && cp "$MIRROR/plugins/menu/MenuModel.js" "$BACKUPS/mirror/plugins/menu/"
    [[ -f "$MIRROR/Ui/OverlayWindow.qml" ]] && cp "$MIRROR/Ui/OverlayWindow.qml" "$BACKUPS/mirror/Ui/"
  fi
fi

say "==> Installing files"
install -Dm644 "$HERE/files/Menu.qml"         "$OMARCHY/shell/plugins/menu/Menu.qml"
install -Dm644 "$HERE/files/OverlayWindow.qml" "$OMARCHY/shell/Ui/OverlayWindow.qml"
install -Dm755 "$HERE/files/ravi-window-focus" "$HOME/.local/bin/ravi-window-focus"

say "==> Applying optional menu-ranking patch (MenuModel.js)"
PATCH="$HERE/patches/menu-model-ranking.patch"
if [[ ! -f "$PATCH" ]]; then
  say "    SKIPPED — patches/menu-model-ranking.patch is missing from this checkout."
  say "    Re-clone the repository to get it; only result ranking is affected."
elif git -C "$OMARCHY" apply --check "$PATCH" 2>/dev/null; then
  git -C "$OMARCHY" apply "$PATCH"
  say "    applied"
elif git -C "$OMARCHY" apply --check -R "$PATCH" 2>/dev/null; then
  say "    already applied (nothing to do)"
elif patch --forward -p1 -d "$OMARCHY" --dry-run -s -i "$PATCH" >/dev/null 2>&1; then
  patch --forward -p1 -d "$OMARCHY" -s -i "$PATCH"
  say "    applied"
elif patch -R -p1 -d "$OMARCHY" --dry-run -s -i "$PATCH" >/dev/null 2>&1; then
  say "    already applied (nothing to do)"
else
  say "    SKIPPED (your MenuModel.js differs from the expected base)."
  say "    This only affects result ranking (actions before submenus); everything else works."
fi

if [[ -d "$MIRROR/plugins/menu" ]]; then
  say "==> Syncing dormant quickshell mirror at $MIRROR"
  cp "$OMARCHY/shell/plugins/menu/Menu.qml" "$MIRROR/plugins/menu/Menu.qml"
  cp "$OMARCHY/shell/plugins/menu/MenuModel.js" "$MIRROR/plugins/menu/MenuModel.js" \
    || say "    NOTE: could not sync the mirror copy of MenuModel.js (continuing)"
  if [[ -d "$MIRROR/Ui" ]]; then
    cp "$OMARCHY/shell/Ui/OverlayWindow.qml" "$MIRROR/Ui/OverlayWindow.qml" \
      || say "    NOTE: could not sync the mirror copy of OverlayWindow.qml (continuing)"
  else
    say "    NOTE: $MIRROR/Ui is missing — OverlayWindow.qml not mirrored (harmless: the mirror is dormant)"
  fi
else
  say "==> No dormant quickshell mirror at $MIRROR/plugins/menu — skipping the mirror sync"
fi

say "==> Restarting the shell"
if [[ -x "$HOME/.local/bin/ravi-restart-shell" ]] && command -v hyprctl >/dev/null 2>&1; then
  # dispatch "ok" only means the command was spawned — confirm the restart
  # by watching the quickshell pid actually change.
  before_pid="$(pgrep -f 'quickshell -c omarchy' | head -n1 || true)"
  restart_out="$(hyprctl dispatch "hl.dsp.exec_cmd(\"$HOME/.local/bin/ravi-restart-shell\")" 2>&1 || true)"
  sleep 6
  after_pid="$(pgrep -f 'quickshell -c omarchy' | head -n1 || true)"
  if [[ -n "$after_pid" && "$after_pid" != "$before_pid" ]]; then
    say "    restarted — quickshell pid $before_pid → $after_pid"
  elif [[ -n "$after_pid" ]]; then
    say "    could not confirm a restart (pid still $after_pid)."
    say "    Restart quickshell yourself (log out/in) — QML does not hot-reload."
  else
    say "    restart dispatch answered: ${restart_out:-no answer}; quickshell is not running."
    say "    Start it (log out/in) — QML does not hot-reload."
  fi
else
  say "    Restart quickshell yourself now (log out/in, or however you usually restart it)."
  say "    Quickshell does not hot-reload QML — the new launcher only comes up after a restart."
fi

say "==> Done. Open the launcher (Super+Space) and type e.g. 2+2, 10 km in mi, date,"
say "    a file name, or a window title. Right-click a file/folder row copies its path."
