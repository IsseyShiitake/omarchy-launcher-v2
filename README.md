# Omarchy Launcher, improved

More functions, more practicality, more power. Implemented the following:
- websearching
- finds files & folders — **folders and files in two blocks**, five each, with a
  "more" row that hands the query to your file manager, Baloo content hits in a
  block of their own, folders that open in your file manager, files that open
  with your desktop's real default app (not whatever `xdg-open` happens to pick),
  and every row saying what it is before it says where it is
- right click **or Ctrl+C** to copy a path to the clipboard
- calculations
- unit conversion
- **colour answers** (`#ff0000` → rgb/hsl)
- full-text search
- window switching
- recent documents with learning rankings

All in the same minimal menu, with zero new daemons.

<p align="center">
  <img src="screenshots/calculate.png" alt="calculator answer coexisting with file results" width="49%">
  <img src="screenshots/files-folders.png" alt="file and folder search" width="49%">
</p>

<p align="center">
  <img src="screenshots/distance.png" alt="unit conversion" width="49%">
  <img src="screenshots/time.png" alt="date answer" width="49%">
</p>

## What you get

Type in the launcher (≥ 2 characters, or any `=`-expression):

| You type | You get |
|---|---|
| `2+2`, `sqrt(2)*10`, `2^10`, `(1+2)*3`, `max(3,7)` | A math answer row — **Enter copies the result** and confirms with a `Copied!` pill (the answer stays; Esc dismisses) |
| `=2+2` | Forced calculator mode: *only* the answer, nothing else |
| `10 km in mi`, `1 gb in mib`, `100 f in c`, `-10 c in f`, `1e9 b in gb`, `5 kg in pounds` | Unit conversion (SI + IEC bytes, length, mass, time, speed, temperature; signs and exponents included; tonnes are metric) — Enter copies the **numeric value** (the row shows the unit) |
| `#ff0000`, `#0f0`, `#ff000080` | A colour answer row with a swatch painted from the colour itself: `rgb(255,0,0) · hsl(0,100%,50%)`, or `rgba(255,0,0,0.5) · hsl(…)` when the query carried an alpha channel — Enter copies the hex and shows a "Color copied!" pill |
| `date`, `time`, `now`, `today` (+ `heure`) | Current date/time, kept ticking second-by-second while it is shown — Enter copies what is on screen |
| any file/folder name | Matching **folders and files from `$HOME` in two blocks** (fd-powered, ~50 ms; hidden and gitignored paths skipped) — Enter opens (a folder in your file manager, a file in that type's default app), **Right/Tab on a folder browses into it**, **Ctrl+Enter reveals the containing folder**, **right-click or Ctrl+C copies the path** |
| words that appear inside files | A second tier of Baloo hits (name *or* contents), in their own block after the files, each marked `content · …` |
| a word from an open window's title or app id | Open-window switcher rows — Enter focuses that window |
| anything | A "Search the web for …" fallback row (DuckDuckGo) |

### The order of results

Every file-tier row's second line says **what** the match is before it says
where it is — `folder · ~/Documents`, `file · ~/Documents`,
`content · ~/Documents` — because the folder/file split can be switched off
(one merged block) and the recents/places tier always mixes the two. The word
sits at the front so the detail line's right-side elision can never eat it.

Every search reads top to bottom as one story, with a hairline wherever the
*kind* of result changes:

1. **The answer**, if what you typed is one — maths, conversion, `#rrggbb`, date.
2. **Matches** — apps and menu rows together, best match first. An app you can
   launch outranks a menu row of equal match; there is deliberately no second
   "deeper in the menu" group.
3. **Open windows** — title, then `class · workspace N`; Enter focuses it.
4. **Folders** — up to five, then `More folders…` when there were more.
5. **Files** — up to five, then `More files…` when there were more.
6. **File contents** — Baloo hits, in a block of their own behind a
   hairline, each marked `content · ~/where/it/lives`. They are a different kind
   of match, so they are never mixed into the file block: three rows that look exactly like files
   and appear after `More files…` read as "the list is broken", not as "another
   tier" — which is what they used to do.
7. **Notices** — a dimmed row when a tool is missing, a binary is not installed,
   or a block was capped with nowhere to hand the rest.
8. **Web search** — always last, and the only row that leaves the machine.

Recent documents and places are **off by default** (`showRecentRows`): they used
to lead the file tier, where they read as unexplained extra folders above the
real results. Frecency does that job from your own behaviour instead — and it is
not lost: the paths you open or reveal keep climbing the folders and files
blocks. Turned on, the places come from Dolphin's `user-places.xbel` *and* the
GTK bookmarks file (`~/.config/gtk-3.0/bookmarks`, which Nautilus and Thunar
use), so the tier is populated on a non-KDE desktop too.

### Folder and file blocks

Folders and files list as two blocks, separated by the same hairline that splits
menu matches from the file tier, and each block shows **at most five** entries.
When a block has more matches than that, its sixth row is `More folders…` /
`More files…`: Enter hands the query to your file manager's own search and closes
the launcher. Recents and `content` rows are separate tiers with their own small
budgets.

**The cap and the "more" row are one decision.** The cap exists to make room for
the row, so it only applies when there is something that can actually take the
rest of the query. On a machine whose file manager has no command-line search
(see [File managers and openers](#file-managers-and-openers)) the blocks are not
cut at all: folders show six, files show twelve — the pre-pack numbers — and the
block ends with a plain notice (`More files matched` / `Showing 12 of 40 — no
file manager search available`) instead of a row that would open nothing. A
configured command whose binary is missing says so by name in that notice.

### Browsing a folder

Highlight a folder and press **Right** (or **Tab**): the list becomes that
folder's contents, immediately — no click, no second step. Type to filter inside
the folder, press Right again to go deeper. **Backspace/Left** (with an empty
filter) or the `..` row go back up one level; going up from `$HOME` ends the
browse and search resumes. Enter still opens a folder in your file manager, so
"look inside here" and "hand this to Dolphin" stay separate actions.

A browse listing ignores the five-entry search cap — it is a listing, not a
search — and only stops at a guard of 120 folders / 240 files per level, saying
"Showing up to N …" when a level came back full. Gitignored entries and symlinks
*are* listed while browsing (you asked to see inside: `node_modules/`, `dist/`
and links are real contents), while hidden dotfiles stay hidden — the same
default a file manager shows. A symlinked folder appears as a file and opens on
Enter rather than browsing, because fd reports it as its own type. Set
`browseShowsIgnored` to `false` to go back to search-like filtering.

### Copying a path, and pasting anything in

Right-click a file or folder row, or highlight it and press **Ctrl+C** (Super+C
works too where the compositor forwards it — note Omarchy binds `SUPER, C` to
`sendshortcut , CTRL, C`). Either way the path lands in the clipboard and an
**opaque** "Path copied!" pill appears just above the row. Ctrl+C on any other
row does nothing.

**Every answer row confirms its copy the same way and stays open** — maths
and conversions show `Copied!`, a colour shows `Color copied!` — because the
pill lives inside the card, and closing in the same breath would hide it
before it is seen. Enter again re-copies; the pill fades out on its own after
about a second and a half, and a click outside closes the card (and the pill
with it). **Esc does not dismiss it** — Esc clears the query first, and only
closes the launcher when the query is already empty. The pill used to be the
theme's 8 %-alpha highlight, which read straight through a busy background — it
is now that tone composited to full opacity, with the accent as its border
(the theme's selected-border alpha defaults to 0, which would leave nothing to
separate it from the card).

**Ctrl+V** (or **Shift+Insert**) reads the clipboard and appends it to the query —
the launcher has no text field, so this is how a copied hex, path or phrase gets
in. It works in `dmenu` prompts too (those are the same filter, rebuilt against
the caller's list — the pack replaces the stock menu, so `omarchy-menu-select`
and `omarchy-menu-input` reach it). Only the first line is used, control
characters are dropped and the paste is
capped at 200 characters, so dropping a document in cannot fill the query with
something unreadable. Pasting `#ff000080` answers with the colour row; a
clipboard holding an image pastes nothing (silently, as a text field would).

The 200-character cap counts **characters, not bytes**: a paste that would cut
an emoji in half is trimmed one character earlier instead. Half a character is
not a character, and the rest of the launcher (the web-search row builds a URL
out of the query) cannot encode one.

**Typing is not restricted to Shift**: any key that produces a printable
character types it, including the AltGr/Option level-3 characters an
international layout keeps there (`#`, `@`, `~`, brackets …) and emoji, which
count as one character. Ctrl and Meta combinations stay reserved for shortcuts,
so nothing is hijacked.

### How answers coexist

Auto-detected math, conversions, and dates **share the list** with menu items,
files, windows and content hits — so `2+2` shows `4` *and* your matching files.
A **leading `=` is exclusive for the search tiers**: it suppresses the file,
content and window tiers and the web row. It does not suppress the menu's own
rows, which are still listed and still searchable, so `=hello` is the answer
plus any menu row that matches `hello` — and a `Missing:` notice still appears
if a tool is absent.

A date is not arithmetic. `2026-10-21` used to be read as `2026 - 10 - 21` and
answered with **1995**; a date-shaped query is now left to the file and window
tiers, and only an explicit `=2026-10-21` asks for the arithmetic.

### Your own menu rows (`~/.config/omarchy/extensions/omarchy-menu.jsonc`)

The launcher reads Omarchy's own menu file **and** your extension file, and
merges the two. The merge is **per key**: only the fields your entry actually
writes change; every other field of the default row is left alone.

```jsonc
{
  // A default row, changed in two places. Its icon, action, description and
  // guards are the defaults' — you did not restate them, so they stay.
  "system.lock": { "label": "Lock Screen", "action": "hyprlock" },

  // A row nobody can see. The label and icon it would have had do not matter.
  "install.docker": { "when": "false" }
}
```

Two rules worth knowing:

- **Aliases replace, they do not add up.** A row with `"aliases": ["x"]` ends
  up with exactly `["x"]` — the default's other aliases are gone. Write them
  all out if you want to keep them.
- **`kind` follows the action.** A row whose `action` you clear becomes a
  submenu rather than a leaf, and a submenu with no children is not shown.

Rows you add outright (an id Omarchy does not know) work the same way: give it
a `label`, and an `action` if it should do something.

### Frecency (it learns, then forgets)

Opening or revealing a file/folder, or focusing a window, records a hit
(`~/.local/state/omarchy/launcher-frecency.json`, capped at 300 keys, no
analysis leaves the machine). Frequently used items quietly climb the file and
window rankings; the boost is capped so a favorite can outrank, never dominate.
Hits **decay with a 30-day half-life**, so what you binged last month stops
outranking what you actually use every day.

### File managers and openers

Two desktop decisions are resolved by *your* desktop, not by the pack, and both
used to be hardcoded to KDE:

**`More folders…` / `More files…`** hands the query to your file manager's own
search. The file manager is **detected** (`dolphin`, `nautilus`, `thunar`,
`nemo`, `pcmanfm`, `files` — first one installed wins), and only Dolphin has a
real command-line search to hand a query to (KDE's `baloosearch` kioslave).
GNOME Files is not an option however tempting: `nautilus --search` does not
exist (its whole CLI is `--version/--new-window/--quit/--select`) and its
internal search URI is refused from the command line (*"is an internal
protocol"*), and Thunar, Nemo and PCManFM have no search switch either. On those
machines the blocks simply show more rows and say so — see
[Folder and file blocks](#folder-and-file-blocks). Set
`fileManagerSearchCommand` if you have your own wrapper.

**Enter on a file row** (and Ctrl+Enter's reveal) opens the way your file manager
does, because two resolvers on the same machine do not always agree.
`xdg-open` goes through GLib/GIO: on a Hyprland box with KDE apps it classified a
`.md` as `text/plain` and launched LibreOffice Writer, while Dolphin (KService)
knew the same file as `text/markdown` and opened Obsidian. So the opener follows
the detected file manager — `kde-open` for Dolphin (the exact resolver Dolphin
uses), `gio open` for Nautilus/Thunar/Nemo/PCManFM, `xdg-open` as the fallback —
and `fileOpenCommand` overrides it in one line — argv style, one word per
argument, so a command that needs quoted arguments belongs in a wrapper script
(`fileOpenCommand: "my-opener"`). The path is always passed as an *argument*,
never spliced into a command string. The web row is a URL, not a
file, and stays on `xdg-open`.

**A folder always goes to the file manager itself** (`dolphin <path>`,
`nautilus <path>`, …), not through a resolver. Measured on the machine this was
written for: `xdg-open` and `gio open` send a directory to Dolphin, but
`kde-open` — which is right for *files* — sends it to **Gwenview**, because
Gwenview also claims `inode/directory`. "Open this folder" means the file
manager, so the file manager is what gets called. An explicit
`fileOpenCommand` wins for folders too, so one setting still means one
behaviour.

### Missing tools are reported, not silent

One probe runs at shell start. It checks `fd`, `hyprctl`, `baloosearch6`,
`wl-copy`, `wl-paste`, the opener binaries (`kde-open`, `gio`, `xdg-open`)
**and the window-focus helper** (`~/.local/bin/ravi-window-focus`, installed
by `install.sh` — window rows are Enter-able only when it is there).
If a tier's tool is absent, that tier is switched off (no dead subprocess per
keystroke)
and a dimmed `Missing: …` row says so under the results — for the openers,
only when *all three* are gone, since any one of them still serves as the
fallback chain's end. A file manager is
deliberately *not* in that list: without one the file tier still works, it just
shows its rows instead of redirecting. The probe re-runs on the next open
whenever something was missing, so installing the tool picks it up without
restarting the shell.

### Tuning (one line each, all ON by default)

Every switch lives at the top of `Menu.qml`, in the "Result presentation
switches" block — flip one and restart the shell:

| Property | Default | Effect |
|---|---|---|
| `separateFolderRows` | `true` | Hairline between the folder block and the file block |
| `showRecentRows` | `false` | Show your recent documents and Dolphin places above the file tier |
| `capFileTier` | `true` | Five folders + five files, each block ending in a "more" row when it ran out of room; `false` restores the pre-pack caps (6 folders / 12 files, no redirect rows) |
| `fileTierLimit` | `5` | How many folders and how many files a capped block shows |
| `uncappedFolderLimit` / `uncappedFileLimit` | `6` / `12` | What a block shows when there is no "more" row to earn the tighter cap: `capFileTier` off, or a file manager with no command-line search |
| `contentTierLimit` | `3` | How many `content · …` rows survive their cap (only while `capFileTier` is on) |
| `fileManagerCandidates` | `["dolphin","nautilus","thunar","nemo","pcmanfm","files"]` | File managers the probe looks for, most capable first; the first installed one decides the "more" row and the opener |
| `browseDirLimit` / `browseFileLimit` | `120` / `240` | Per-level guard while browsing a folder |
| `browseShowsIgnored` | `true` | While browsing, list gitignored entries and symlinks too |
| `colorAnswers` | `true` | `#rrggbb` answer rows |
| `fileManagerSearchCommand` | `""` (auto) | What the "more" rows run; every `%1` becomes the query as a shell-inert percent-encoded token (safe inside or outside quotes), and a command with no `%1` gets the query appended as a trailing argument. Empty means "use the detected file manager": Dolphin gets `dolphin 'baloosearch:?query=%1'`, everything else gets nothing (no CLI search exists). Its first word is also the first thing the capability probe checks. KDE's worker reads the term from `?query=`, not from the path — `baloosearch:/foo` would search for a *folder* named foo |
| `fileOpenCommand` | `""` (auto) | How Enter opens a file row (argv, the path is appended): `kde-open` for Dolphin, `gio open` for the GTK file managers, `xdg-open` otherwise. Set e.g. `"gio open"` or `"kde-open"` to force one |
| `clipboardCommand` | `/usr/bin/wl-copy --type 'text/plain;charset=utf-8'` | Clipboard sink for every copy action (`--type` pinned so numerics can't sniff as octet-stream) |
| `winClientsTtlMs` | `1000` | How long an `hyprctl clients` answer is reused instead of re-fetched |
| `winClientsMaxAgeMs` | `10000` | How long window rows may still be derived from that cache (fail-closed ceiling) |
| `frecencyHalfLifeMs` | 30 days | How fast a recorded hit loses half its weight |

## Requirements

- An Omarchy-style shell checkout with the `omarchy.menu` plugin
  (`~/.local/share/omarchy/shell/plugins/menu/`) running under Hyprland +
  Quickshell (tested: Quickshell 0.2.1, Hyprland 0.56.2 with the lua dispatch)
- `fd` — file/folder search (as are `hyprctl`, `wl-copy`, `wl-paste` and
  `baloosearch6` below: the tiers spawn each tool from `/usr/bin`, and the
  probe checks exactly that path — a PATH-only or non-FHS install is reported
  as missing rather than failing silently)
- `hyprctl` plus the `ravi-window-focus` helper (`install.sh` puts it in
  `~/.local/bin`) — window switcher
- `wl-copy` and `wl-paste` (wl-clipboard) — copy actions and Ctrl+V paste
- a file manager — `dolphin`, `nautilus`, `thunar`, `nemo`, `pcmanfm` or `files`
  (detected, not required): its own opener is used for Enter, and Dolphin's
  Baloo search powers the "more" rows. Without one, files still open and the
  blocks show their pre-pack limits
- optional: `kde-open` / `gio` / `xdg-open` — the opener, in that order of
  preference according to the detected file manager (`xdg-open` is the fallback)
- optional: `baloosearch6` + a running Baloo index — content search tier
  (without it the tier is simply empty; nothing breaks)
- optional: `git` — only if you want to apply `patches/omarchy-launcher-v2.patch`
  instead of copying the files; `install.sh` itself needs neither `git` nor
  `patch` (it copies, and only reads `git` to identify your base revision)

## Install

```sh
git clone https://github.com/IsseyShiitake/omarchy-launcher-v2.git
cd omarchy-launcher-v2
bash install.sh
```

The installer:

1. checks dependencies and tells you which tiers any missing one degrades,
2. backs up every file it touches to `~/.local/share/omarchy-backups/launcher-v2/<timestamp>/`,
3. copies in the enhanced files — `Menu.qml`, `MenuModel.js`, `OverlayWindow.qml`
   and `~/.local/bin/ravi-window-focus`; if any copy fails it puts the backed-up
   files back and says so rather than leaving the tree half-upgraded,
4. restarts the shell if it can (Quickshell has no QML hot-reload — log out/in otherwise).

Re-running `bash install.sh` is a safe update: it overwrites, and takes a fresh
backup whenever the installed files — or the live quickshell mirror — differ
from the pack. An identical re-run takes no new backup (the existing pristine
snapshot stays the one uninstall restores).

## Uninstall / rollback

```sh
bash uninstall.sh
```

Restores the newest backup **if it holds the pre-pack files**, otherwise the
pristine files from the Omarchy git checkout. Snapshots record which they are
(`BACKUP_KIND`), because an older pack revision is not the same thing as the
originals — installing over a previous version of this pack marks its snapshot
`modified`, and uninstall then restores the checkout and keeps the snapshot as a
safety net. The frecency state file is inert without the
pack — keep or delete it.

## What it modifies

| File | Change |
|---|---|
| `shell/plugins/menu/Menu.qml` | All new tiers, answer rows, frecency, right-click copy (drop-in replacement) |
| `shell/Ui/OverlayWindow.qml` | Holds overlay geometry ~280 ms on close **for the menu only**, so its fade-out can play (drop-in replacement) |
| `shell/plugins/menu/MenuModel.js` | Leaf actions rank above submenu containers, the guard batch runs in parallel, the extension merge is per key, and the JSONC parser tolerates comments (drop-in replacement) |
| `~/.local/bin/ravi-window-focus` | New helper: focuses a window by address via Hyprland's lua dispatch |

The installer **copies** all three shell files in rather than patching them:
the pack and the plugin edition ship byte-identical copies, so the two editions
cannot drift apart. `patches/omarchy-launcher-v2.patch` is the complete,
reviewable diff of
all three files against upstream Omarchy shell commit `821ae58` — if you run
that base you may `git apply` it instead of copying files. The patch covers
those three files only: also install the window-focus helper with
`install -Dm755 files/ravi-window-focus ~/.local/bin/ravi-window-focus`
(without it the window tier switches itself off and the `Missing:` row says
so — window rows are never shown as Enter-able dead ends).

The overlay's close-hold is **opt-in and off by default**, because the hold
keeps the surface fullscreen and visible: a consumer that draws a scrim
without binding it to `shown` (the emoji picker, the clipboard history, the
reminder flow, the wifi-QR panel) would otherwise leave that scrim on screen
for a quarter of a second after it was dismissed. Only the menu asks for the
hold, and only the menu fades.

An install that fails part way through is **rolled back** from the backup it
took, so the tree is never left half-upgraded (the menu replaced but not its
overlay is a launcher whose fade never plays). `uninstall.sh` restores a file
the snapshot does not hold from the Omarchy checkout rather than leaving it
alone, and restores it from `HEAD` rather than from the git index — so a
staged local edit does not survive a revert that claims to have reverted.

## Compatibility

Tested against Omarchy shell `821ae58` (2026-10-02), Quickshell 0.2.1,
Hyprland 0.56.2 on Fedora 44. The QML is defensive: missing binaries, empty or
malformed recents/places files, and unreadable JSON all degrade to empty
tiers rather than errors. Newer upstream `Menu.qml` versions may drift —
prefer the patch route if your base matches, and re-check after Omarchy
updates (`install.sh` warns when the checkout is not at the tested commit).
An `omarchy update` that pulls newer upstream files can conflict
with these; if the launcher misbehaves after an update, re-run
`bash install.sh` (it re-applies; a backup is taken if anything differs).

## Privacy notes

File search covers `$HOME` only, using fd's defaults (hidden and gitignored
paths skipped). Symlinks are neither followed nor matched while searching —
fd's file type does not include them — but they *are* listed while browsing a
folder. Filenames containing newlines cannot be represented in the line
protocol the tiers use and would surface as junk rows.
Window rows read `hyprctl clients`.
Nothing is sent anywhere; the only fallback row is an explicit web search you
choose to press Enter on.


## Development

[![check](https://github.com/IsseyShiitake/omarchy-launcher-v2/actions/workflows/check.yml/badge.svg)](https://github.com/IsseyShiitake/omarchy-launcher-v2/actions/workflows/check.yml)

`make check` runs the installer scenarios end to end against sandboxed trees,
verifies the patch reproduces the three files byte-for-byte, and — when the
plugin checkout sits beside this one — that the shared files are identical. It
needs a git checkout of Omarchy at the pinned base; without one those checks
are reported as skips, with the reason. `make patch` regenerates the patch from
`files/`. See `tests/README.md`.

## Credits & license

Built on top of [Omarchy](https://omarchy.org) by DHH and contributors — the
three modified files derive from the Omarchy shell (MIT). This pack is released
under the MIT License too; see [LICENSE](LICENSE).
