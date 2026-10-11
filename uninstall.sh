#!/usr/bin/env bash
# Reverts the KRunner parity pack: restores the newest install.sh backup,
# or falls back to the pristine files from the Omarchy git checkout.
set -euo pipefail

OMARCHY="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"
MIRROR="$HOME/.config/quickshell/omarchy"
BACKUP_ROOT="$HOME/.local/share/omarchy-backups/launcher-krunner"

say()  { printf '%s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ -f "$OMARCHY/shell/plugins/menu/Menu.qml" ]] || die "Omarchy shell not found at $OMARCHY"

LATEST="$(ls -1dt "$BACKUP_ROOT"/*/ 2>/dev/null | head -n1 || true)"
if [[ -n "$LATEST" && -f "$LATEST/shell/plugins/menu/Menu.qml" ]]; then
  say "==> Restoring files from $LATEST"
  cp "$LATEST/shell/plugins/menu/Menu.qml" "$OMARCHY/shell/plugins/menu/Menu.qml"
  [[ -f "$LATEST/shell/plugins/menu/MenuModel.js" ]] \
    && cp "$LATEST/shell/plugins/menu/MenuModel.js" "$OMARCHY/shell/plugins/menu/MenuModel.js"
  [[ -f "$LATEST/shell/Ui/OverlayWindow.qml" ]] \
    && cp "$LATEST/shell/Ui/OverlayWindow.qml" "$OMARCHY/shell/Ui/OverlayWindow.qml"
elif git -C "$OMARCHY" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  say "==> No backup found; restoring pristine files from the Omarchy git checkout"
  git -C "$OMARCHY" checkout -- shell/plugins/menu/Menu.qml shell/plugins/menu/MenuModel.js shell/Ui/OverlayWindow.qml
else
  die "no backups under $BACKUP_ROOT and $OMARCHY is not a git checkout — restore Menu.qml by hand"
fi

# The focus wrapper only ever comes from this pack — always remove it.
rm -f "$HOME/.local/bin/ravi-window-focus"

# Install synced the dormant quickshell mirror; leaving the pack's files
# there after a revert would be an inconsistency waiting to confuse a
# future debugging session. Restore its backup if there is one, else copy
# the just-restored checkout files over.
if [[ -d "$MIRROR/plugins/menu" ]]; then
  say "==> Re-syncing dormant quickshell mirror at $MIRROR"
  if [[ -n "$LATEST" && -f "$LATEST/mirror/plugins/menu/Menu.qml" ]]; then
    cp "$LATEST/mirror/plugins/menu/Menu.qml" "$MIRROR/plugins/menu/Menu.qml"
    [[ -f "$LATEST/mirror/plugins/menu/MenuModel.js" ]] \
      && cp "$LATEST/mirror/plugins/menu/MenuModel.js" "$MIRROR/plugins/menu/MenuModel.js"
    [[ -f "$LATEST/mirror/Ui/OverlayWindow.qml" ]] \
      && cp "$LATEST/mirror/Ui/OverlayWindow.qml" "$MIRROR/Ui/OverlayWindow.qml"
  else
    cp "$OMARCHY/shell/plugins/menu/Menu.qml" "$MIRROR/plugins/menu/Menu.qml"
    [[ -f "$OMARCHY/shell/plugins/menu/MenuModel.js" ]] \
      && cp "$OMARCHY/shell/plugins/menu/MenuModel.js" "$MIRROR/plugins/menu/MenuModel.js"
    if [[ -d "$MIRROR/Ui" && -f "$OMARCHY/shell/Ui/OverlayWindow.qml" ]]; then
      cp "$OMARCHY/shell/Ui/OverlayWindow.qml" "$MIRROR/Ui/OverlayWindow.qml"
    fi
  fi
fi
say "==> Frecency state (if any) left in place at"
say "    ~/.local/state/omarchy/launcher-frecency.json — delete it freely."

say "==> Restart the shell (log out/in) to complete the revert."
