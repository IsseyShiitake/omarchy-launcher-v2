#!/usr/bin/env bash
# Verification entry point for the pack: `make check`, or `bash tests/check.sh`.
# Anything that cannot run here is reported as "skip" with the reason.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

PASS=0 FAIL=0 SKIP=0
STRICT="${STRICT:-0}"   # 1 = a skip is a failure (CI)
FAILED=()
ok()   { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); FAILED+=("$1"); printf '  FAIL  %s\n' "$1"; }
skip() {
  if [[ "$STRICT" == "1" ]]; then
    bad "$1 (skipped, and STRICT=1)"
  else
    SKIP=$((SKIP + 1)); printf '  skip  %s\n' "$1"
  fi
}

run() {
  local name="$1"; shift
  local log rc; log=$(mktemp)
  "$@" >"$log" 2>&1; rc=$?
  if (( rc == 0 )); then
    local summary; summary=$(grep -oE 'passed: [0-9]+' "$log" | tail -1)
    ok "$name${summary:+ — $summary}"
  elif (( rc == 77 )); then
    skip "$name — $(head -1 "$log")"
  else
    bad "$name"
    tail -n 20 "$log" | sed 's/^/        /'
  fi
  rm -f "$log"
}

printf '==> static\n'
bash -n install.sh   && ok "install.sh parses"   || bad "install.sh parses"
bash -n uninstall.sh && ok "uninstall.sh parses" || bad "uninstall.sh parses"
node --check files/MenuModel.js && ok "MenuModel.js parses" || bad "MenuModel.js parses"

printf '\n==> packaging contracts\n'
[[ -f files/MenuModel.js ]] && ok "the pack vendors files/MenuModel.js" || bad "the pack vendors files/MenuModel.js"
grep -q 'install -Dm644 "$HERE/files/MenuModel.js"' install.sh && ok "install.sh installs it" || bad "install.sh installs it"
grep -q "menu-model-ranking.patch" install.sh && bad "install.sh no longer applies the ranking patch" || ok "install.sh no longer applies the ranking patch"
[[ ! -e patches/menu-model-ranking.patch ]] && ok "the superseded ranking patch is gone" || bad "the superseded ranking patch is gone"
grep -q 'checkout HEAD -- ' uninstall.sh && ok "uninstall.sh restores from HEAD" || bad "uninstall.sh restores from HEAD"
grep -q -- '-type d -printf' uninstall.sh && ok "uninstall.sh snapshots directories only" || bad "uninstall.sh snapshots directories only"
grep -q 'trap rollback ERR' install.sh && ok "install.sh rolls back on failure" || bad "install.sh rolls back on failure"

printf '\n==> installer, end to end\n'
run "install/uninstall" bash tests/test_installers.sh

printf '\n==> patch\n'
run "patch reproduces the files" bash tests/test_patch.sh

printf '\n==> editions\n'
if [[ -f ../omarchy-launcher-v2-plugin/files/Menu.qml ]]; then
  for f in Menu.qml MenuModel.js ravi-window-focus; do
    if cmp -s "files/$f" "../omarchy-launcher-v2-plugin/files/$f"; then ok "files/$f identical in both editions"; else bad "files/$f identical in both editions"; fi
  done
else
  skip "plugin checkout not beside this one — edition comparison needs both"
fi

printf '\n==> %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
for f in "${FAILED[@]:-}"; do [[ -n "$f" ]] && printf '  x %s\n' "$f"; done
exit $((FAIL > 0 ? 1 : 0))
