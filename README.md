<div align="center">

# 🪔 Kandil

**A fast, good-looking launcher for KDE Plasma 6, built on KRunner.**

Kandil replaces KRunner's window with a modern search panel, while keeping
everything that makes KRunner great: all of its plugins, results and settings.

[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
![KDE Plasma 6](https://img.shields.io/badge/KDE%20Plasma-6-1d99f3?logo=kde&logoColor=white)
![Wayland](https://img.shields.io/badge/Wayland-ready-ffbc00?logo=wayland&logoColor=white)
![Languages](https://img.shields.io/badge/languages-31-success)

<!-- Main screenshot: the panel open with a few results -->
<img src="docs/screenshots/hero.png" alt="Kandil showing search results" width="820">

</div>

---

## Why Kandil?

KRunner is one of the best things about KDE Plasma: it finds applications,
files, settings and windows, does math and converts units. But its window
cannot be themed — in Plasma 6 its interface is compiled into the program.

Kandil keeps KRunner's search engine and gives it a new face:

- **Same results as KRunner.** Kandil talks directly to KRunner's engine, so every
  plugin you have enabled works, with the settings you already chose.
- **Smooth and modern.** A floating, blurred card with soft shadows that grows and
  shrinks with fluid animations instead of jumping.
- **Always ready.** Kandil waits in the background and opens instantly.
- **Nothing to configure to get started.** One command installs it and moves
  <kbd>Alt</kbd>+<kbd>Space</kbd> from KRunner to Kandil.

## Features

| | |
|---|---|
| 🕘 **Recent & frequent** | With an empty search, your most recently and most often opened items are one <kbd>Enter</kbd> away. |
| 🔢 **Quick select** | Hold <kbd>Ctrl</kbd> to see numbers next to results, then press <kbd>Ctrl</kbd>+<kbd>1</kbd>…<kbd>9</kbd> to open one directly. |
| 🧮 **Big answers** | Calculations and unit conversions are shown in a large card. <kbd>Enter</kbd> copies the result. |
| 🖼️ **Preview panel** | Images, the first lines of text files and the contents of folders, without opening them. |
| 🎯 **Prefixes** | Search only one source: `f` files, `w` windows, `a` apps, `s` settings, `=` calculator, `c` clipboard, `>` command. |
| 📋 **Clipboard history** | Search everything you copied (from Klipper) and copy it again. |
| ⌨️ **Shell commands** | `> df -h` runs a command and shows its output right inside the panel. |
| ⚙️ **Lots of settings** | Size, position, transparency, blur, colors, animations, prefixes, shortcut and more. |
| 🌍 **31 languages** | The interface follows your system language, or the one you pick. |

<!-- Two screenshots side by side: the calculator card and the file preview -->
<p align="center">
  <img src="docs/screenshots/calculator.png" alt="Calculation shown in a large card" width="49%">
  <img src="docs/screenshots/preview.png" alt="File preview panel" width="49%">
</p>

## Installation

Open a terminal and run:

```bash
curl -fsSL https://raw.githubusercontent.com/Vialeth/kandil/main/install.sh | bash
```

That's it. Press <kbd>Alt</kbd>+<kbd>Space</kbd> and start typing.

The installer:

1. checks that you are on KDE Plasma 6,
2. finds any missing dependencies and, after asking you, installs them with your
   package manager (Fedora, Arch, openSUSE, Debian and Ubuntu are supported),
3. installs Kandil for your user only — **no root access is needed for Kandil itself**,
4. starts it, and makes it start automatically when you log in,
5. asks whether <kbd>Alt</kbd>+<kbd>Space</kbd> should open Kandil instead of KRunner.
   <kbd>Alt</kbd>+<kbd>F2</kbd> keeps opening KRunner.

**Updating** is the same command: running the installer again updates Kandil and
keeps your settings.

<details>
<summary><b>Install from a clone instead</b></summary>

```bash
git clone https://github.com/Vialeth/kandil.git
cd kandil
./install.sh
```

Installer options:

| Option | Effect |
|---|---|
| `--yes` | Do not ask questions, accept the defaults |
| `--no-deps` | Do not install missing packages |
| `--shortcut KEYS` | Use another shortcut, e.g. `--shortcut "Meta+Space"`; `none` to skip |
| `--keep-krunner` | Leave KRunner's shortcuts untouched |

</details>

### Requirements

- KDE Plasma 6 on **Wayland**
- Qt 6.9 or newer
- systemd (used by Plasma on most distributions)
- Python 3 with PySide6, and the KDE QML modules Kirigami, Milou, LayerShellQt,
  KQuickControls and the Breeze Qt Quick style

The installer takes care of all of these.

## Usage

Press <kbd>Alt</kbd>+<kbd>Space</kbd>, type, press <kbd>Enter</kbd>.
Type **`?`** at any time to see every prefix and shortcut.

<!-- Screenshot: the help list opened with "?" -->
<p align="center">
  <img src="docs/screenshots/help.png" alt="Help list with prefixes and shortcuts" width="720">
</p>

### Prefixes

Type a prefix followed by a space to search in only one place. A label appears
in the search field; <kbd>Backspace</kbd> on an empty field removes it.

| Prefix | Searches | Example |
|:---:|---|---|
| `f` | Files and folders | `f invoice` |
| `w` | Open windows | `w firefox` |
| `a` | Applications | `a calc` |
| `s` | System Settings pages | `s bluetooth` |
| `=` | Calculator | `= 2^10`, `= sqrt(2)` |
| `c` | Clipboard history | `c address` |
| `>` | Runs a shell command | `> uptime` |

Unit conversions such as `10 km > mi` or `100 usd` work in the normal search,
without a prefix.

Prefixes are the same in every language. You can change any of them, turn them
off, or add your own prefix for **any installed KRunner plugin** (for example
`b` for bookmarks) in the settings.

### Keyboard

| Keys | Action |
|---|---|
| <kbd>↑</kbd> <kbd>↓</kbd> | Move between results |
| <kbd>Ctrl</kbd>+<kbd>↑</kbd> <kbd>↓</kbd> | Jump between categories |
| <kbd>Enter</kbd> | Open the selected result |
| <kbd>Shift</kbd>+<kbd>Enter</kbd> | Run the first action of the result |
| <kbd>Tab</kbd> | Cycle through the result's actions |
| <kbd>Ctrl</kbd>+<kbd>1</kbd>…<kbd>9</kbd> | Open the result with that number |
| <kbd>Shift</kbd>+<kbd>Del</kbd> | Remove an item from recent history |
| <kbd>Esc</kbd> | Clear the text, leave the mode, or close |

In command mode (`>`): <kbd>Enter</kbd> runs the command,
<kbd>Ctrl</kbd>+<kbd>Enter</kbd> runs it in a terminal,
<kbd>Alt</kbd>+<kbd>C</kbd> copies the output.

<!-- Two screenshots side by side: clipboard mode and command mode -->
<p align="center">
  <img src="docs/screenshots/clipboard.png" alt="Clipboard history" width="49%">
  <img src="docs/screenshots/command.png" alt="Shell command output" width="49%">
</p>

## Settings

Open the settings by typing `?` and choosing **Kandil settings** at the bottom
of the list.

<!-- Screenshot: the settings window -->
<p align="center">
  <img src="docs/screenshots/settings.png" alt="Kandil settings window" width="720">
</p>

| Page | What you can change |
|---|---|
| **General** | Language, global shortcut, start on login, KRunner plugin settings |
| **Appearance** | Width, visible rows, row height, icon and text size, position, corner radius, opacity, blur, shadow, accent color, preview panel, large calculation card, category headers, hint bar |
| **Animation** | Animation speed, opening effect |
| **Behavior** | Close on focus loss, select on hover, remember the last search, recent history and its size, result limit |
| **Prefixes** | Change, disable or add prefixes; the help key |
| **Commands** | Timeout, shell, terminal |
| **Data** | Clear history, open the settings file, reset everything |

Every change is applied immediately. Settings are stored in
`~/.config/kandil/config.json`; you can also edit this file by hand and Kandil
picks up the changes as soon as you save it.

Which plugins appear, and in which order, is still controlled by KRunner:
**System Settings → Search → Plasma Search**.

## Languages

Kandil is available in 31 languages and follows your system language by default:

Arabic · Azerbaijani · Bulgarian · Chinese (Simplified) · Chinese (Traditional) ·
Czech · Danish · Dutch · English · Finnish · French · German · Greek · Hebrew ·
Hindi · Hungarian · Indonesian · Italian · Japanese · Korean · Norwegian Bokmål ·
Persian · Polish · Portuguese (Brazil) · Romanian · Russian · Spanish · Swedish ·
Turkish · Ukrainian · Vietnamese

Right-to-left languages (Arabic, Persian, Hebrew) get a mirrored layout.

*Kandil* is Turkish for an oil lamp — a light you carry to find things in the
dark. The word travelled from Latin *candela* through Greek and Arabic, so in
languages that share it, Kandil uses the local name: **Candil** in Spanish,
**Candeia** in Portuguese, **Καντήλι** in Greek, **Кандило** in Bulgarian,
**قنديل** in Arabic, and so on.

Translations live in [`src/i18n`](src/i18n), one JSON file per language. Fixes
and new languages are very welcome — copy `en.json`, translate the values and
open a pull request.

## Uninstalling

```bash
~/.local/share/kandil/uninstall.sh
```

or, if that file is gone:

```bash
curl -fsSL https://raw.githubusercontent.com/Vialeth/kandil/main/uninstall.sh | bash
```

This removes everything Kandil installed — the program, its service, its
shortcut, cache, settings and history — and gives <kbd>Alt</kbd>+<kbd>Space</kbd> back
to KRunner. Use `--keep-data` to keep your settings and history. System packages
such as PySide6 are not removed, because other applications may use them.

## How it works

```
 Alt+Space ──► kglobalaccel ──► kandil-toggle ──► D-Bus ──► Kandil (always running)
                                                              │
                         ┌────────────────────────────────────┤
                         ▼                                    ▼
              Milou ResultsModel                     Qt Quick interface
           (KRunner's own engine)            (layer-shell window, KWin blur)
```

- Kandil is a small Python program (PySide6) with a Qt Quick interface. It runs
  as a systemd user service and listens on D-Bus as `io.github.vialeth.Kandil`.
- Results come from **Milou**, the same model KRunner itself uses, so every
  KRunner plugin works without changes.
- The panel is a Wayland **layer-shell** surface, like KRunner's. Its window
  never resizes; only the card inside it animates. This is what keeps the
  animations free of flicker.
- Background blur uses KWin's blur effect, and is updated every frame to match
  the card's shape.

| Path | Contents |
|---|---|
| `~/.local/share/kandil/` | Program |
| `~/.config/kandil/config.json` | Settings |
| `~/.local/state/kandil/history.json` | Recent and frequent items |
| `~/.config/systemd/user/kandil.service` | Background service |

## Troubleshooting

<details>
<summary><b>Nothing happens when I press the shortcut</b></summary>

Check that Kandil is running:

```bash
systemctl --user status kandil
```

If another application uses the same keys, choose another shortcut in
**Settings → General**, or reinstall with `--shortcut "Meta+Space"`.
</details>

<details>
<summary><b>The panel does not appear in the middle of the screen</b></summary>

Kandil needs a **Wayland** session. On X11 the panel cannot be placed correctly.
</details>

<details>
<summary><b>KRunner results are in a different language than Kandil</b></summary>

Kandil's own interface changes language immediately. Texts that come from
KRunner plugins (such as category names) follow the new language after Kandil
restarts — use the **Restart Kandil** button that appears in the settings.
</details>

<details>
<summary><b>Something else went wrong</b></summary>

Kandil's log usually explains it:

```bash
journalctl --user -u kandil -b
```

Please [open an issue](https://github.com/Vialeth/kandil/issues) and include
this log.
</details>

## Credits

- Built on [KRunner](https://invent.kde.org/frameworks/krunner),
  [Milou](https://invent.kde.org/plasma/milou),
  [Kirigami](https://invent.kde.org/frameworks/kirigami) and
  [LayerShellQt](https://invent.kde.org/plasma/layer-shell-qt) by the KDE community.
- Coded using **Claude Opus 5.5**.

## License

Kandil is free software, released under the
[GNU General Public License v3.0 or later](LICENSE).
