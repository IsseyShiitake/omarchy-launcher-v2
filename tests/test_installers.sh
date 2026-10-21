#!/usr/bin/env bash
# End-to-end test of install.sh / uninstall.sh against a sandboxed omarchy tree.
# Every scenario asserts on the RESULT, not on the output. Exit codes: 0 pass,
# 1 failure, 77 cannot run here (no pristine checkout to build sandboxes from).
set -uo pipefail
PACK="$(cd "$(dirname "$0")/.." && pwd)"
LIVE="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"
BASE="${LAUNCHER_TEST_BASE:-821ae589059ffdadc970315f866c94b55d268af7}"
PASS=0; FAIL=0; FAILURES=(); SKIP=0
ok()  { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); FAILURES+=("$1"); printf '  FAIL  %s\n     %s\n' "$1" "${2:-}"; }
skip(){ SKIP=$((SKIP+1)); printf '  skip  %s\n' "$1"; }
check() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "expected [$3] got [$2]"; fi; }

if ! git -C "$LIVE" cat-file -e "$BASE^{commit}" 2>/dev/null; then
  echo "skip: no Omarchy checkout at $LIVE (set OMARCHY_PATH) with commit $BASE"
  exit 77
fi

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/launcher-installers.XXXXXX")"
cleanup() { chmod -R u+rwX "$TMPROOT" 2>/dev/null; rm -rf "$TMPROOT"; }
trap cleanup EXIT

new_sandbox() {
  local R="$1"
  rm -rf "$R"; mkdir -p "$R/home" "$R/omarchy/shell/plugins/menu" "$R/omarchy/shell/Ui"
  mkdir -p "$R/home/.config/quickshell/omarchy/plugins/menu" "$R/home/.config/quickshell/omarchy/Ui"
  git -C "$LIVE" show "$BASE:shell/plugins/menu/Menu.qml"     > "$R/omarchy/shell/plugins/menu/Menu.qml"
  git -C "$LIVE" show "$BASE:shell/plugins/menu/MenuModel.js" > "$R/omarchy/shell/plugins/menu/MenuModel.js"
  git -C "$LIVE" show "$BASE:shell/Ui/OverlayWindow.qml"      > "$R/omarchy/shell/Ui/OverlayWindow.qml"
  cp "$R/omarchy/shell/plugins/menu/Menu.qml"      "$R/home/.config/quickshell/omarchy/plugins/menu/"
  cp "$R/omarchy/shell/plugins/menu/MenuModel.js"  "$R/home/.config/quickshell/omarchy/plugins/menu/"
  cp "$R/omarchy/shell/Ui/OverlayWindow.qml"       "$R/home/.config/quickshell/omarchy/Ui/"
  ( cd "$R/omarchy" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm base )
  ( cd "$R/omarchy" && sha256sum shell/plugins/menu/Menu.qml shell/plugins/menu/MenuModel.js shell/Ui/OverlayWindow.qml > "$R/pristine.sha" )
}

run_install()   { HOME="$1/home" OMARCHY_PATH="$1/omarchy" bash "$PACK/install.sh"   >"$1/install.out" 2>&1; echo $?; }
run_uninstall() { HOME="$1/home" OMARCHY_PATH="$1/omarchy" bash "$PACK/uninstall.sh" >"$1/uninstall.out" 2>&1; echo $?; }

echo "=== 1. fresh install -> uninstall restores byte-for-byte ==="
R="$TMPROOT/it1"; new_sandbox "$R"
rc=$(run_install "$R"); check "install exits 0" "$rc" "0"
cmp -s "$R/omarchy/shell/plugins/menu/Menu.qml" "$PACK/files/Menu.qml" && ok "Menu.qml installed" || bad "Menu.qml installed" ""
cmp -s "$R/omarchy/shell/plugins/menu/MenuModel.js" "$PACK/files/MenuModel.js" && ok "MenuModel.js installed (vendored, not patched)" || bad "MenuModel.js installed" ""
cmp -s "$R/omarchy/shell/Ui/OverlayWindow.qml" "$PACK/files/OverlayWindow.qml" && ok "OverlayWindow.qml installed" || bad "OverlayWindow.qml installed" ""
[[ -x "$R/home/.local/bin/ravi-window-focus" ]] && ok "focus helper installed" || bad "focus helper installed" ""
cmp -s "$R/home/.config/quickshell/omarchy/plugins/menu/MenuModel.js" "$PACK/files/MenuModel.js" && ok "mirror MenuModel.js synced" || bad "mirror MenuModel.js synced" ""
rc=$(run_uninstall "$R"); check "uninstall exits 0" "$rc" "0"
( cd "$R/omarchy" && sha256sum -c "$R/pristine.sha" >/dev/null 2>&1 ) && ok "all three files restored byte-for-byte" || bad "all three files restored byte-for-byte" "$( cd "$R/omarchy" && sha256sum -c "$R/pristine.sha" 2>&1 )"
[[ -z "$( cd "$R/omarchy" && git status --short )" ]] && ok "checkout is clean after uninstall" || bad "checkout is clean after uninstall" "$( cd "$R/omarchy" && git status --short )"

echo
echo "=== 2. uninstall restores a file the snapshot does NOT hold ==="
R="$TMPROOT/it2"; new_sandbox "$R"
run_install "$R" >/dev/null
SNAP=$(find "$R/home/.local/share/omarchy-backups/launcher-v2" -mindepth 1 -maxdepth 1 -type d | head -1)
rm -f "$SNAP/shell/plugins/menu/MenuModel.js"
rc=$(run_uninstall "$R"); check "uninstall exits 0" "$rc" "0"
( cd "$R/omarchy" && sha256sum -c "$R/pristine.sha" >/dev/null 2>&1 ) && ok "the missing file was taken from the checkout (not left as-is)" || bad "the missing file was taken from the checkout" "$( cd "$R/omarchy" && sha256sum -c "$R/pristine.sha" 2>&1 )"

echo
echo "=== 3. uninstall restores from HEAD, not from the INDEX ==="
R="$TMPROOT/it3"; new_sandbox "$R"
printf '\n// staged local edit\n' >> "$R/omarchy/shell/plugins/menu/Menu.qml"
( cd "$R/omarchy" && git add -A )
run_install "$R" >/dev/null
rc=$(run_uninstall "$R"); check "uninstall exits 0" "$rc" "0"
if grep -q "staged local edit" "$R/omarchy/shell/plugins/menu/Menu.qml"; then
  bad "the staged edit is gone (HEAD was restored)" "the staged edit survived"
else
  ok "the staged edit is gone (HEAD was restored)"
fi

echo
echo "=== 4. install rolls back when it fails part way ==="
if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  skip "rollback scenario (root bypasses the permission denial it uses)"
else
  R="$TMPROOT/it4"; new_sandbox "$R"
  chmod 555 "$R/omarchy/shell/Ui"
  rc=$(run_install "$R")
  chmod 755 "$R/omarchy/shell/Ui"
  if [[ "$rc" != "0" ]]; then ok "a failing install exits non-zero ($rc)"; else bad "a failing install exits non-zero" "got 0"; fi
  grep -qi "restor\|rollback" "$R/install.out" && ok "the failure is reported" || bad "the failure is reported" "$(tail -3 "$R/install.out")"
  ( cd "$R/omarchy" && sha256sum -c "$R/pristine.sha" >/dev/null 2>&1 ) && ok "the tree was rolled back (no half-installed state)" || bad "the tree was rolled back" "$( cd "$R/omarchy" && sha256sum -c "$R/pristine.sha" 2>&1 )"
fi

echo
echo "=== 5. re-running install is idempotent (no second backup) ==="
R="$TMPROOT/it5"; new_sandbox "$R"
run_install "$R" >/dev/null
N1=$(find "$R/home/.local/share/omarchy-backups/launcher-v2" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
run_install "$R" >/dev/null
N2=$(find "$R/home/.local/share/omarchy-backups/launcher-v2" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
check "no second snapshot is taken" "$N2" "$N1"
grep -q "Already at the pack revision" "$R/install.out" && ok "the re-run says so" || bad "the re-run says so" "$(tail -3 "$R/install.out")"

echo
echo "=== 6. a hand-edited MenuModel.js forces a backup (the PACK_STATE fix) ==="
R="$TMPROOT/it6"; new_sandbox "$R"
run_install "$R" >/dev/null
printf '\n// hand edit\n' >> "$R/omarchy/shell/plugins/menu/MenuModel.js"
rm -rf "$R/home/.local/share/omarchy-backups/launcher-v2"
run_install "$R" >/dev/null
if [[ -d "$R/home/.local/share/omarchy-backups/launcher-v2" ]]; then ok "a backup WAS taken for the hand-edited file"; else bad "a backup WAS taken for the hand-edited file" "no backup directory"; fi
SNAP=$(find "$R/home/.local/share/omarchy-backups/launcher-v2" -mindepth 1 -maxdepth 1 -type d | head -1)
grep -q "hand edit" "$SNAP/shell/plugins/menu/MenuModel.js" 2>/dev/null && ok "the hand edit is IN the backup" || bad "the hand edit is IN the backup" ""

echo
echo "=== 7. a stray FILE in the backup root does not break the revert ==="
R="$TMPROOT/it7"; new_sandbox "$R"
run_install "$R" >/dev/null
mkdir -p "$R/home/.local/share/omarchy-backups/launcher-v2"
printf 'stray\n' > "$R/home/.local/share/omarchy-backups/launcher-v2/README"
rc=$(run_uninstall "$R"); check "uninstall exits 0" "$rc" "0"
( cd "$R/omarchy" && sha256sum -c "$R/pristine.sha" >/dev/null 2>&1 ) && ok "the revert still restored everything" || bad "the revert still restored everything" "$( cd "$R/omarchy" && sha256sum -c "$R/pristine.sha" 2>&1 )"

echo
echo "passed: $PASS  failed: $FAIL  skipped: $SKIP"
for f in "${FAILURES[@]:-}"; do [[ -n "$f" ]] && echo "  x $f"; done
exit $(( FAIL > 0 ? 1 : 0 ))
