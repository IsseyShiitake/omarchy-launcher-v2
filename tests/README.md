# Tests

`make check` (or `bash tests/check.sh`) verifies the pack the way a user meets
it: the installer, the revert, and the patch.

`STRICT=1 make check` turns every skip into a failure; CI runs that way, with
both editions checked out side by side and Omarchy at the pinned base, so a
missing prerequisite fails the job instead of quietly shrinking the suite.

| Check | What it pins down | Needs |
|---|---|---|
| packaging contracts | the pack vendors `MenuModel.js`; `install.sh` installs it; no ranking patch; `uninstall.sh` restores `HEAD` and snapshots directories only; the install has a rollback trap | — |
| `test_installers.sh` | seven end-to-end scenarios in sandboxed trees: fresh install → uninstall restores byte-for-byte; a file missing from the snapshot; HEAD vs index; failure rollback; idempotent re-run; hand-edit backup; a stray file in the backup root | a git checkout of Omarchy at the test base |
| `test_patch.sh` | `patches/omarchy-launcher-v2.patch` touches three files, applies to the pinned base and reproduces them byte-for-byte | the same checkout |
| editions | `Menu.qml`, `MenuModel.js` and `ravi-window-focus` are byte-identical to the plugin edition's | both checkouts side by side |

The installer and patch tests build a temporary `git init` tree seeded from
`$OMARCHY_PATH` at the pinned base (`821ae58`), with `HOME` pointed inside the
sandbox, so they never touch the live install. If no such checkout exists they
exit 77 and the runner reports a skip, naming the reason.

`make patch` regenerates the patch from `files/`, then proves it the same way
the test does. Run it after changing any of the three shared files — a stale
patch is otherwise only discovered when someone applies it.

## What is deliberately not here

The model and QML suites live in the plugin repository: the pack ships the
same shared files, and duplicating ~1,500 lines of tests across two repos would
drift exactly like the code once did. `make check` there covers the code; this
one covers the packaging.
