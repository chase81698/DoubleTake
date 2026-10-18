import DoubleTakeCore
import Foundation

enum Help {
    static let short = """
    doubletake — double-tap and key-combo shortcuts for macOS

    USAGE
      doubletake <command> [options]          add --json to any read command for JSON output

    SHORTCUTS
      list                                    list shortcuts (● on, ○ off)
      show <name|id>                          show one shortcut
      add <name> --trigger <t> <action>       add a shortcut (repeat --trigger for more triggers)
      edit <name|id> [--name n] [--trigger t] [--add-trigger t] [<action>] [--enable|--disable]
      remove <name|id>                        delete a shortcut
      enable <name|id> / disable <name|id>    turn one on or off
      run <name|id>                           run a shortcut's action right now
      presets / add-preset <number>           classic macOS shortcuts and popular ones

    TRIGGERS  (--trigger)
      double:fn  double:right-cmd  double:cmd (either ⌘)  triple:opt  double:esc
      ctrl+opt+t  cmd+shift+k  j+k (pressed together)  ctrl+opt (modifiers alone)

    ACTIONS  (pick one)
      --system <name>        built-in: dictation, siri, spotlight, missionControl… (see `actions`)
      --app <name|path>      open an app; add --toggle to hide it if it's already in front
      --url <url|path>       open a URL, file or folder
      --shell <script>       run a zsh script
      --applescript <src>    run AppleScript
      --shortcut <name>      run a Shortcuts-app shortcut
      --keystroke <keys>     send a keystroke, e.g. cmd+shift+t
      --menu <path>          click a menu item in the front app, e.g. "Edit > Start Dictation"

    OTHER
      actions | keys                          list built-in actions / key names
      settings [--interval s] [--chord-window s] [--on|--off]
      status                                  is the app running and allowed to listen?
      export [file] | import <file|-> [--replace]
      open | quit                             start or stop the menu bar app
      install-cli | uninstall-cli             add or remove /usr/local/bin/doubletake
      help --llm                              full reference for AI assistants

    EXAMPLES
      doubletake add "Dictation" --trigger double:fn --system dictation
      doubletake add "Terminal" --trigger ctrl+opt+t --app Terminal --toggle
      doubletake add "Notes" --trigger j+k --shell 'open -a Notes'
      doubletake edit Dictation --add-trigger double:right-cmd
    """

    static let actions = """
    Action options for `add` and `edit` (use exactly one):
      --system <name>       a built-in action (listed below)
      --app <name|path|bundle-id> [--toggle]
      --url <url|path>
      --shell <script>      run with /bin/zsh -l, so your PATH is set up
      --applescript <src>
      --shortcut <name>     a shortcut from the Shortcuts app
      --keystroke <keys>    e.g. cmd+shift+t, ctrl+cmd+q, f5
      --menu <path>         e.g. "Edit > Start Dictation" or just "Start Dictation"
    """

    static let llm = """
    # DoubleTake CLI reference (for AI assistants)

    DoubleTake is a macOS menu bar app that runs actions when the user double-taps or
    triple-taps a key, or presses a key combination. The `doubletake` command edits its
    config; the running app reloads changes automatically, with no restart needed.

    ## Rules
    - Prefer the CLI over editing the config file. Every command that reads takes --json.
    - Address shortcuts by exact name (case-insensitive) or by the 8-character id from `list`.
    - Names must be unique unless --allow-duplicate is given.
    - Exit status is 0 on success and 1 on error; errors go to stderr prefixed "doubletake:".
    - Shortcuts only fire while the app runs and has Accessibility access: check `doubletake status`.
      If accessibilityGranted is "no", the user must enable DoubleTake in System Settings >
      Privacy & Security > Accessibility; you can't do that for them.
    - After adding, warn the user about any "warning: shares a trigger" line in the output.

    ## Commands
    doubletake list [--json]
    doubletake show <name|id> [--json]
    doubletake add <name> --trigger <trigger> [--trigger <trigger>...] <action> [--disabled]
    doubletake edit <name|id> [--name <new>] [--trigger <t>...] [--add-trigger <t>...] [<action>] [--enable|--disable]
        --trigger replaces all triggers; --add-trigger appends.
    doubletake remove <name|id>
    doubletake enable <name|id>
    doubletake disable <name|id>
    doubletake run <name|id>              performs the action now; non-zero exit with the error if it fails
    doubletake presets [--json]
    doubletake add-preset <number> [--disabled]
    doubletake actions [--json]           built-in action names for --system
    doubletake keys [--json]              key names usable in triggers and keystrokes
    doubletake settings [--json] [--interval <seconds 0.1-1.0>] [--chord-window <seconds 0.01-0.5>] [--on|--off]
    doubletake status [--json]
    doubletake export [<file>]            prints JSON when no file is given
    doubletake import <file|-> [--replace]   merges by default; accepts a config object or an array of shortcuts
    doubletake open | quit

    ## Trigger syntax
    Tap triggers (the key must be pressed and released on its own, quickly):
      double:<key>    triple:<key>
      Modifier keys: fn, cmd, opt, ctrl, shift mean either side; left-cmd, right-cmd,
      left-opt, right-opt, left-ctrl, right-ctrl, left-shift, right-shift mean one side.
      Ordinary keys also work (double:esc); the second press is consumed, the first types normally.
    Combo triggers (keys held together, joined with +):
      ctrl+opt+t      modifiers plus one key; the key press is consumed
      j+k             two or more ordinary keys pressed at the same moment (within the chord window)
      cmd+shift       two or more modifiers alone, pressed and released with no other key
    Key names: a-z, 0-9, f1-f20, esc, space, return, tab, delete, forward-delete, enter, left, right,
      up, down, home, end, page-up, page-down, punctuation (- = [ ] ; ' , . / \\ `), keypad-0..9,
      or key<code> for any macOS virtual key code.

    ## Actions (exactly one per add; optional on edit)
      --system <name>       \(SystemActionNames.list)
      --app <name|path|bundle id> [--toggle]   open an app; --toggle hides it if it's already in front
      --url <url|path>      https://…, mailto:…, ~/file, /folder
      --shell <script>      zsh login shell
      --applescript <source>
      --shortcut <name>     a Shortcuts-app shortcut
      --keystroke <keys>    one key plus modifiers, e.g. cmd+shift+t
      --menu <path>         "Edit > Start Dictation" (full path) or "Start Dictation" (item name)

    ## Examples
      doubletake add "Dictation" --trigger double:fn --system dictation
      doubletake add "Siri" --trigger double:right-cmd --system siri
      doubletake add "Terminal" --trigger ctrl+opt+t --app Terminal --toggle
      doubletake add "Standup notes" --trigger j+k --shell 'open ~/Notes/standup.md'
      doubletake add "New tab" --trigger triple:opt --keystroke cmd+t
      doubletake edit "Terminal" --add-trigger double:right-opt
      doubletake disable "Siri"
      doubletake list --json

    ## Config file
    \(DoubleTakeCoreInfo.configPath)
    JSON: {"settings": {"isEnabled", "doubleTapInterval", "chordWindow"},
           "shortcuts": [{"id", "name", "enabled", "triggers": [...], "action": {...}}]}
    Missing fields take defaults. Trigger fields: kind ("tap"|"combo"), keyCode, eitherSide, tapCount,
    modifiers (bitmask: fn=1 ctrl=2 opt=4 shift=8 cmd=16), keys (key codes).
    Action fields: type (system|openApp|openURL|shellScript|appleScript|runShortcut|keystroke|menuItem),
    system, target, script, keystroke {modifiers, keyCode}, toggleApp.
    """
}


private enum SystemActionNames {
    static var list: String { SystemAction.allCases.map(\.rawValue).joined(separator: ", ") }
}

private enum DoubleTakeCoreInfo {
    static var configPath: String { ConfigFile.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
}

