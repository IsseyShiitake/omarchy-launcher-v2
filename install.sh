#!/usr/bin/env bash
# Launcher v2: enhanced menu for the Omarchy shell (Hyprland + Quickshell).
# Installs the enhanced menu files into an existing Omarchy shell checkout.
# Everything it overwrites is backed up first; run uninstall.sh to revert.
set -euo pipefail

OMARCHY="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"
MIRROR="$HOME/.config/quickshell/omarchy"
HERE="$(cd "$(dirname "$0")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
BACKUPS="$HOME/.local/share/omarchy-backups/launcher-v2/$STAMP"

say()  { printf '%s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ -f "$OMARCHY/shell/plugins/menu/Menu.qml" ]] \
  || die "Omarchy shell not found at $OMARCHY — set OMARCHY_PATH if it lives elsewhere"
[[ -d "$HERE/files" ]] || die "run this script from the repository root"

# The pack is a drop-in for one known base. A drifted checkout may have changed
# the surrounding contract (APIs the QML binds to); warn so it is a conscious
# choice, not a silent overwrite. The backup below still covers recovery.
EXPECTED_BASE="821ae589059ffdadc970315f866c94b55d268af7"
if current_base="$(git -C "$OMARCHY" rev-parse HEAD 2>/dev/null)" \
   && [[ "$current_base" != "$EXPECTED_BASE" ]]; then
  say "    NOTE: this pack is tested against Omarchy shell commit 821ae58, but the"
  say "          checkout is at ${current_base:0:7} — upstream has drifted. Files are"
  say "          copied over as-is; keep this run's backup and re-check the launcher."
fi

say "==> Checking dependencies"
missing=()
for bin in fd hyprctl wl-copy wl-paste; do
  command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  say "    WARNING: missing ${missing[*]} — the tiers they power will be silently empty:"
  say "             fd (file/folder search), hyprctl (window switcher), wl-copy (copy"
  say "             actions), wl-paste (paste into the field)"
fi
if ! command -v baloosearch6 >/dev/null 2>&1; then
  say "    NOTE: baloosearch6 not found — the file-CONTENT search tier will be empty."
  say "          (KDE users usually have it; enable Baloo indexing to use it.)"
fi

# A re-run on an already-installed (unmodified) tree would snapshot the pack
# itself, and "restore the newest backup" would then restore the pack instead
# of the pristine files. Only snapshot when something actually differs — in
# the checkout OR in the live mirror, which is overwritten below: a hand edit
# made directly in the live tree must not be discarded unbacked.
PACK_STATE=1
cmp -s "$OMARCHY/shell/plugins/menu/Menu.qml" "$HERE/files/Menu.qml" || PACK_STATE=0
cmp -s "$OMARCHY/shell/Ui/OverlayWindow.qml" "$HERE/files/OverlayWindow.qml" || PACK_STATE=0
if [[ -d "$MIRROR/plugins/menu" ]]; then
  cmp -s "$MIRROR/plugins/menu/Menu.qml" "$HERE/files/Menu.qml" || PACK_STATE=0
  cmp -s "$MIRROR/Ui/OverlayWindow.qml" "$HERE/files/OverlayWindow.qml" 2>/dev/null || PACK_STATE=0
  # MenuModel.js has no pristine copy in this repo (it ships as a patch), so
  # "fresh" means mirror == checkout: install keeps them synced, so an
  # inequality is a hand edit one step ahead of being overwritten unbacked.
  cmp -s "$MIRROR/plugins/menu/MenuModel.js" "$OMARCHY/shell/plugins/menu/MenuModel.js" || PACK_STATE=0
fi
# Same for the focus helper: differing from the pack means somebody's own
# file sits at that path, and the reinstall below would flatten it unbacked.
if [[ -f "$HOME/.local/bin/ravi-window-focus" ]] \
   && ! cmp -s "$HOME/.local/bin/ravi-window-focus" "$HERE/files/ravi-window-focus"; then
  PACK_STATE=0
fi

# What is being snapshotted? "Pristine" means the files still match the Omarchy
# checkout's HEAD — the state uninstall is supposed to return to. An older pack
# revision ALSO differs from the current pack, and snapshotting it silently
# would make uninstall "revert" to that older pack. The marker lets uninstall
# tell the two apart and fall back to the checkout when needed.
BACKUP_KIND=pristine
if git -C "$OMARCHY" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  for f in shell/plugins/menu/Menu.qml shell/plugins/menu/MenuModel.js shell/Ui/OverlayWindow.qml; do
    [[ -f "$OMARCHY/$f" ]] || continue
    if ! cmp -s "$OMARCHY/$f" <(git -C "$OMARCHY" show "HEAD:$f" 2>/dev/null); then
      BACKUP_KIND=modified
      break
    fi
  done
else
  # No history to compare against — assume the files are not pristine, so
  # uninstall does not silently treat them as such.
  BACKUP_KIND=modified
fi

if [[ $PACK_STATE -eq 1 ]]; then
  say "==> Already at the pack revision — no new backup taken"
  say "    (the existing pristine snapshot stays the one uninstall restores)"
else
  say "==> Backing up current files to $BACKUPS ($BACKUP_KIND)"
  mkdir -p "$BACKUPS/shell/plugins/menu" "$BACKUPS/shell/Ui"
  printf '%s\n' "$BACKUP_KIND" > "$BACKUPS/BACKUP_KIND"
  for f in shell/plugins/menu/Menu.qml shell/plugins/menu/MenuModel.js shell/Ui/OverlayWindow.qml; do
    [[ -f "$OMARCHY/$f" ]] && cp "$OMARCHY/$f" "$BACKUPS/$f"
  done
  # The pack's own helper is not snapshotted (uninstall can rebuild the
  # situation), but a helper that DIFFERS from the pack is somebody's file —
  # it was already snapshotted above. The mirror gets overwritten below, so
  # its current files land in the same snapshot — uninstall can restore it
  # byte-for-byte.
  if [[ -d "$MIRROR/plugins/menu" ]]; then
    mkdir -p "$BACKUPS/mirror/plugins/menu" "$BACKUPS/mirror/Ui"
    [[ -f "$MIRROR/plugins/menu/Menu.qml" ]] && cp "$MIRROR/plugins/menu/Menu.qml" "$BACKUPS/mirror/plugins/menu/"
    [[ -f "$MIRROR/plugins/menu/MenuModel.js" ]] && cp "$MIRROR/plugins/menu/MenuModel.js" "$BACKUPS/mirror/plugins/menu/"
    [[ -f "$MIRROR/Ui/OverlayWindow.qml" ]] && cp "$MIRROR/Ui/OverlayWindow.qml" "$BACKUPS/mirror/Ui/"
  fi
  # A helper differing from the pack is somebody's file — keep it beside the
  # snapshot instead of letting the reinstall flatten it (uninstall does the
  # same: it renames instead of deleting).
  if [[ -f "$HOME/.local/bin/ravi-window-focus" ]] \
     && ! cmp -s "$HOME/.local/bin/ravi-window-focus" "$HERE/files/ravi-window-focus"; then
    mkdir -p "$BACKUPS/helper"
    cp "$HOME/.local/bin/ravi-window-focus" "$BACKUPS/helper/ravi-window-focus.user"
  fi
  if [[ $BACKUP_KIND != pristine ]]; then
    say "    NOTE: those files are not the Omarchy originals (an older pack or a"
    say "          local edit). uninstall.sh will restore the checkout instead,"
    say "          and keep this snapshot only as a safety net."
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
  say "==> Syncing the live quickshell config at $MIRROR (qs -c omarchy loads this one)"
  cp "$OMARCHY/shell/plugins/menu/Menu.qml" "$MIRROR/plugins/menu/Menu.qml" \
    || say "    NOTE: could not sync the live copy of Menu.qml (the running shell keeps its current one)"
  cp "$OMARCHY/shell/plugins/menu/MenuModel.js" "$MIRROR/plugins/menu/MenuModel.js" \
    || say "    NOTE: could not sync the mirror copy of MenuModel.js (continuing)"
  if [[ -d "$MIRROR/Ui" ]]; then
    cp "$OMARCHY/shell/Ui/OverlayWindow.qml" "$MIRROR/Ui/OverlayWindow.qml" \
      || say "    NOTE: could not sync the mirror copy of OverlayWindow.qml (continuing)"
  else
    say "    NOTE: $MIRROR/Ui is missing — OverlayWindow.qml not mirrored there"
  fi
else
  say "==> No quickshell config at $MIRROR/plugins/menu — skipping that sync"
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
