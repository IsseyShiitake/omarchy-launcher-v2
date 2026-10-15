#!/usr/bin/env bash
# Reverts Launcher v2: restores the newest install.sh backup,
# or falls back to the pristine files from the Omarchy git checkout.
set -euo pipefail

OMARCHY="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"
MIRROR="$HOME/.config/quickshell/omarchy"
BACKUP_ROOT="$HOME/.local/share/omarchy-backups/launcher-v2"

say()  { printf '%s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ -f "$OMARCHY/shell/plugins/menu/Menu.qml" ]] || die "Omarchy shell not found at $OMARCHY"

# Newest by the timestamp IN THE NAME (snapshots are YYYYMMDD-HHMMSS-PID), not
# by directory mtime — touching an old snapshot must not make it win.
LATEST=""
if [[ -d "$BACKUP_ROOT" ]]; then
  newest_name="$(ls -1 "$BACKUP_ROOT" 2>/dev/null | sort -r | head -n1 || true)"
  if [[ -n "$newest_name" && -d "$BACKUP_ROOT/$newest_name" ]]; then
    LATEST="$BACKUP_ROOT/$newest_name/"
  fi
fi
# Snapshots written by install.sh say what they hold: "pristine" (the Omarchy
# originals — the state this script exists to return to) or "modified" (an
# older pack revision, or a local edit). An older pack also differs from the
# current pack, so without the marker "restore the newest backup" would quietly
# leave an outdated pack installed. Snapshots from older install.sh runs carry
# no marker and are treated as pristine, which is what they were.
BACKUP_KIND=""
# Guarded: an empty LATEST would otherwise cat a relative BACKUP_KIND from
# the current directory.
[[ -n "$LATEST" ]] && BACKUP_KIND="$(cat "${LATEST}BACKUP_KIND" 2>/dev/null || true)"
[[ -n "$BACKUP_KIND" ]] || BACKUP_KIND=pristine

restore_from_snapshot() {
  say "==> Restoring files from $LATEST"
  # Per-file, never set -e fatal: one missing or unreadable snapshot entry
  # must not abort a revert halfway — a half-restored tree is worse than a
  # file left as-is. Summary at the end.
  local restored=0 skipped=0 f
  for f in shell/plugins/menu/Menu.qml shell/plugins/menu/MenuModel.js shell/Ui/OverlayWindow.qml; do
    if [[ -f "$LATEST/$f" ]]; then
      if cp "$LATEST/$f" "$OMARCHY/$f"; then
        restored=$((restored + 1))
      else
        say "    WARNING: could not restore $f"
        skipped=$((skipped + 1))
      fi
    else
      say "    WARNING: $f missing from the snapshot — left as-is"
      skipped=$((skipped + 1))
    fi
  done
  say "    $restored file(s) restored, $skipped skipped"
}

# SNAPSHOT is the backup the mirror can be restored from — only set when the
# snapshot is what we actually restored, so a pack-era snapshot never lands in
# the mirror while the checkout holds pristine files.
SNAPSHOT=""
if [[ -n "$LATEST" && "$BACKUP_KIND" == pristine && -f "$LATEST/shell/plugins/menu/Menu.qml" ]]; then
  restore_from_snapshot
  SNAPSHOT="$LATEST"
elif git -C "$OMARCHY" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [[ -n "$LATEST" ]]; then
    say "==> The newest snapshot holds a previous pack revision (or a local edit),"
    say "    not your pre-pack files — restoring the Omarchy checkout instead."
    say "    Snapshot kept as a safety net: $LATEST"
  else
    say "==> No backup found; restoring pristine files from the Omarchy git checkout"
  fi
  git -C "$OMARCHY" checkout -- shell/plugins/menu/Menu.qml shell/plugins/menu/MenuModel.js shell/Ui/OverlayWindow.qml
elif [[ -n "$LATEST" && -f "$LATEST/shell/plugins/menu/Menu.qml" ]]; then
  say "==> $OMARCHY is not a git checkout — falling back to the newest snapshot"
  say "    ($LATEST, marked $BACKUP_KIND)"
  restore_from_snapshot
  SNAPSHOT="$LATEST"
else
  die "no usable backups under $BACKUP_ROOT and $OMARCHY is not a git checkout — restore Menu.qml by hand"
fi

# The focus wrapper only ever comes from this pack — remove it, UNLESS it has
# been edited away from the pack's copy: then it is the user's file and gets
# renamed aside instead of deleted (install.sh keeps such a file in its
# snapshot too).
HERE="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$HOME/.local/bin/ravi-window-focus" ]]; then
  if [[ -f "$HERE/files/ravi-window-focus" ]] \
     && ! cmp -s "$HOME/.local/bin/ravi-window-focus" "$HERE/files/ravi-window-focus"; then
    say "==> ~/.local/bin/ravi-window-focus differs from the pack — kept as ravi-window-focus.user"
    mv "$HOME/.local/bin/ravi-window-focus" "$HOME/.local/bin/ravi-window-focus.user"
  else
    rm -f "$HOME/.local/bin/ravi-window-focus"
  fi
fi

# Per-file mirror copies that never abort the revert: a missing source is
# skipped with a warning, a failing cp ditto.
mirror_copy() {
  if [[ -f "$1" ]]; then
    cp "$1" "$2" || say "    WARNING: could not restore $(basename "$1") into the mirror"
  fi
}

# Install synced the live quickshell config (qs -c omarchy loads it); leaving the pack's files
# there after a revert would be an inconsistency waiting to confuse a
# future debugging session. Restore its backup if there is one, else copy
# the just-restored checkout files over.
if [[ -d "$MIRROR/plugins/menu" ]]; then
  say "==> Re-syncing the live quickshell config at $MIRROR"
  if [[ -n "$SNAPSHOT" && -f "$SNAPSHOT/mirror/plugins/menu/Menu.qml" ]]; then
    mirror_copy "$SNAPSHOT/mirror/plugins/menu/Menu.qml" "$MIRROR/plugins/menu/Menu.qml"
    mirror_copy "$SNAPSHOT/mirror/plugins/menu/MenuModel.js" "$MIRROR/plugins/menu/MenuModel.js"
    mirror_copy "$SNAPSHOT/mirror/Ui/OverlayWindow.qml" "$MIRROR/Ui/OverlayWindow.qml"
  else
    mirror_copy "$OMARCHY/shell/plugins/menu/Menu.qml" "$MIRROR/plugins/menu/Menu.qml"
    mirror_copy "$OMARCHY/shell/plugins/menu/MenuModel.js" "$MIRROR/plugins/menu/MenuModel.js"
    mirror_copy "$OMARCHY/shell/Ui/OverlayWindow.qml" "$MIRROR/Ui/OverlayWindow.qml"
  fi
fi
say "==> Frecency state (if any) left in place at"
say "    ~/.local/state/omarchy/launcher-frecency.json — delete it freely."

say "==> Restart the shell (log out/in) to complete the revert."
