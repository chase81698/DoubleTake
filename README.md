# DoubleTake

Double-tap shortcuts for macOS, back again. DoubleTake is a small menu bar app that runs
something when you **double- or triple-tap a key** (fn, ⌘, ⌥, ⌃, ⇧, Esc…) or **press keys
together** (⌃⌥T, or two ordinary keys like J + K at the same moment).

- **The old macOS shortcuts are back:** press fn twice for Dictation, press Right ⌘ twice for Siri, and the rest.
- **Make your own:** double-tap, triple-tap, modifier combos, simultaneous keys, or modifiers alone (⌃ + ⌥ pressed together).
- **Choose what each one does:** open or toggle an app, open a URL or file, run a shell script or AppleScript,
  run a Shortcuts shortcut, send a keystroke, click a menu item, or use a built-in action
  (Dictation, Siri, Spotlight, Mission Control, Show Desktop, Lock Screen, media keys, Dark Mode…).
- **Give one action several triggers**, e.g. double-tap fn *or* ⌃⌥D.
- **GUI for people, CLI for scripts and AI assistants.** Both edit the same config, and changes take effect immediately.
- **Lightweight:** native Swift, no dependencies, no network access, nothing running in the background except one event listener.

Requires macOS 15 or later (built for macOS 27).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/chase81698/DoubleTake/main/install.sh | bash
```

This puts **DoubleTake.app in /Applications** and the **`doubletake` command in /usr/local/bin**
(your password may be requested for that folder), then starts the app. It downloads the latest
release, or builds from source if there isn't one.

**From source** (needs Xcode or `xcode-select --install`):

```bash
git clone https://github.com/chase81698/DoubleTake.git
cd DoubleTake
./install.sh
```

**Uninstall:** `./install.sh --uninstall` (or `curl … | bash -s -- --uninstall`). Your shortcuts stay in
`~/Library/Application Support/DoubleTake/` until you delete that folder.

If you run the app from somewhere else (for example, Downloads), it offers to move itself to Applications.

### The one manual step: Accessibility access

To see key presses, macOS requires you to approve DoubleTake once in **System Settings › Privacy & Security ›
Accessibility**. The app opens that page for you, and starts working as soon as you switch it on.
No app can grant itself this permission, which is the point of it.

## Using the app

Click the tapping-hand icon in the menu bar, then **Open DoubleTake…**.

- **+** adds a blank shortcut or one of the presets (Classic Dictation, Classic Siri, Popular).
- In each shortcut, choose **Tap** or **Key Combo**, click **Record**, and press the keys.
- Choose an action and click **Test Action** to try it.
- **General** has the double-tap speed, the simultaneous-key window, launch at login, and the CLI installer.

How triggers behave:

| Trigger | Example | Notes |
|---|---|---|
| Double / triple tap of a modifier | `fn fn`, `Right ⌘ Right ⌘` | The key has to be tapped on its own. Using ⌘C or ⌘V never counts as tapping ⌘. Choose one side or "either side". |
| Double tap of a normal key | `Esc Esc` | The first press types as usual and DoubleTake consumes the second. |
| Modifiers + key | `⌃⌥T` | DoubleTake consumes the key press, so the front app never sees it. |
| Keys together | `J + K` | Those keys wait a split second (80 ms by default) before typing, in case they're part of a combo. |
| Modifiers alone | `⌃ + ⌥` | Press them together and release them, with no other key in between. |

## Command line (and LLMs)

```bash
doubletake list
doubletake add "Dictation" --trigger double:fn --system dictation
doubletake add "Terminal"  --trigger ctrl+opt+t --app Terminal --toggle
doubletake add "Notes"     --trigger j+k --shell 'open -a Notes'
doubletake add "New tab"   --trigger triple:opt --keystroke cmd+t
doubletake edit Terminal --add-trigger double:right-opt
doubletake disable Notes
doubletake run Terminal
doubletake status
```

Every read command accepts `--json`. `doubletake help` shows a summary, and **`doubletake help --llm` prints a
complete reference written for AI assistants**: trigger syntax, every action, the config schema, and the
rules. Give that output to your assistant, or just tell it "run `doubletake help --llm` and set up …".

**Triggers:** `double:<key>`, `triple:<key>`, or keys joined with `+`. A bare modifier name (`cmd`, `opt`, `ctrl`, `shift`)
matches either side, while `left-cmd`, `right-opt` and the like match one side only. Run `doubletake keys` for every key name.

**Actions:** `--system <name>`, `--app <name|path|bundle id> [--toggle]`, `--url`, `--shell`, `--applescript`,
`--shortcut <Shortcuts name>`, `--keystroke <keys>`, `--menu "Edit > Start Dictation"`. Run `doubletake actions` for the
built-in list.

**Config file:** `~/Library/Application Support/DoubleTake/config.json` is plain JSON, and the app reloads it when it changes.
`doubletake export` and `doubletake import <file|->` back it up and share it.

## Building

```bash
swift test                 # engine tests
scripts/build-app.sh       # → build/DoubleTake.app (ad-hoc signed; set SIGN_IDENTITY to use your certificate)
scripts/package-release.sh # → dist/DoubleTake.zip (universal), for a GitHub release
```

Layout:

- `Sources/DoubleTakeCore`: the pure parts. Models, the key-matching engine, the recorder, and the CLI text formats. Fully unit-tested.
- `Sources/DoubleTake`: the app. Event tap, actions, SwiftUI interface, CLI, and installer. The app and the `doubletake` command are the same binary.

Ad-hoc-signed builds have no stable identity, so macOS forgets the Accessibility approval when the app is
rebuilt or updated. `install.sh` clears the stale entry so you can switch it on again.

## License

None. DoubleTake is released into the **public domain** under [The Unlicense](UNLICENSE).
Copy it, change it, sell it, ship it, and you don't need to ask or give credit.
