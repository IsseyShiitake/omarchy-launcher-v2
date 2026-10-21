#!/usr/bin/env bash
# Regenerate patches/omarchy-launcher-v2.patch, then prove it: the diff of the
# three files against the pinned base must apply cleanly and reproduce them.
set -euo pipefail
PACK="$(cd "$(dirname "$0")/../.." && pwd)"
OM="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"
BASE="${LAUNCHER_TEST_BASE:-821ae589059ffdadc970315f866c94b55d268af7}"
PATCH="$PACK/patches/omarchy-launcher-v2.patch"

git -C "$OM" cat-file -e "$BASE^{commit}" || { echo "no $BASE in $OM" >&2; exit 1; }

W="$(mktemp -d "${TMPDIR:-/tmp}/launcher-patchgen.XXXXXX")"
cleanup() { git -C "$OM" worktree remove --force "$W" >/dev/null 2>&1 || true; rm -rf "$W"; }
trap cleanup EXIT

git -C "$OM" worktree add --detach "$W" "$BASE" >/dev/null
cp "$PACK/files/Menu.qml"         "$W/shell/plugins/menu/Menu.qml"
cp "$PACK/files/MenuModel.js"     "$W/shell/plugins/menu/MenuModel.js"
cp "$PACK/files/OverlayWindow.qml" "$W/shell/Ui/OverlayWindow.qml"
git -C "$W" diff > "$PATCH"

# prove it
git -C "$W" checkout -- .
git -C "$W" apply "$PATCH"
for pair in "shell/plugins/menu/Menu.qml:Menu.qml" "shell/plugins/menu/MenuModel.js:MenuModel.js" "shell/Ui/OverlayWindow.qml:OverlayWindow.qml"; do
  cmp -s "$W/${pair%%:*}" "$PACK/files/${pair##*:}" || { echo "patch does not reproduce ${pair##*:}" >&2; exit 1; }
done
echo "wrote $PATCH ($(grep -c '' "$PATCH") lines) and verified it"
