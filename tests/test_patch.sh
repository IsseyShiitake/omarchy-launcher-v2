#!/usr/bin/env bash
# Prove patches/omarchy-launcher-v2.patch is what it claims: the complete diff
# of the three files against the pinned Omarchy base, applying cleanly and
# reproducing them byte-for-byte. Exit codes: 0 pass, 1 failure, 77 cannot run.
set -uo pipefail
PACK="$(cd "$(dirname "$0")/.." && pwd)"
OM="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"
BASE="${LAUNCHER_TEST_BASE:-821ae589059ffdadc970315f866c94b55d268af7}"
PATCH="$PACK/patches/omarchy-launcher-v2.patch"

if [[ ! -f "$PATCH" ]]; then echo "FAIL: $PATCH is missing"; exit 1; fi
if ! git -C "$OM" cat-file -e "$BASE^{commit}" 2>/dev/null; then
  echo "skip: no Omarchy checkout at $OM (set OMARCHY_PATH) with commit $BASE"
  exit 77
fi

FAIL=0
bad() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }
ok()  { echo "  ok    $1"; }

W="$(mktemp -d "${TMPDIR:-/tmp}/launcher-patch.XXXXXX")"
cleanup() { git -C "$OM" worktree remove --force "$W" >/dev/null 2>&1; rm -rf "$W"; }
trap cleanup EXIT

if ! git -C "$OM" worktree add --detach "$W" "$BASE" >/dev/null 2>&1; then
  echo "FAIL: could not create a worktree at $BASE"; exit 1
fi

files=$(grep -c '^diff --git ' "$PATCH")
if [[ "$files" == "3" ]]; then ok "the patch touches exactly 3 files"; else bad "the patch touches 3 files (found $files)"; fi

if git -C "$W" apply --check "$PATCH" 2>/dev/null; then ok "applies to pristine $BASE"; else bad "applies to pristine $BASE"; fi
if git -C "$W" apply "$PATCH" 2>/dev/null; then ok "applied"; else bad "applied"; fi

for pair in "shell/plugins/menu/Menu.qml:Menu.qml" "shell/plugins/menu/MenuModel.js:MenuModel.js" "shell/Ui/OverlayWindow.qml:OverlayWindow.qml"; do
  target="${pair%%:*}"; name="${pair##*:}"
  if cmp -s "$W/$target" "$PACK/files/$name"; then ok "reproduces files/$name byte-for-byte"; else bad "reproduces files/$name byte-for-byte"; fi
done

echo "  ($(grep -c '' "$PATCH") lines)"
exit $(( FAIL > 0 ? 1 : 0 ))
