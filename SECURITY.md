# Security

DoubleTake sees every key you press and can run scripts as root, so security reports are very welcome.

## Reporting a vulnerability

Please report it privately: on GitHub, open the **Security** tab of this repository and click
**Report a vulnerability**. Don't open a public issue for anything exploitable. You'll get a reply as soon
as possible, and a fix will ship as a signed release that installed copies can update to from inside the app.

Only the latest release is supported.

## How DoubleTake is built to be safe

- **Key presses stay on your Mac.** DoubleTake watches the keyboard through an Accessibility event tap, matches
  presses against your shortcuts in memory, and forgets them. It doesn't log or store what you type, and
  doesn't send it anywhere.
- **The only network use is checking for updates**, and only when you click Check for Updates or turn on the
  automatic check (off by default). It asks GitHub for the latest release and downloads it.
- **Updates are signed.** Each release's `DoubleTake.zip` is signed with an Ed25519 key that never leaves the
  maintainer's Mac; the app carries the public key and installs nothing whose signature (`DoubleTake.zip.sig`)
  doesn't verify. Downloads must come over HTTPS from this repository's GitHub releases, must be DoubleTake, must
  be newer than the installed copy, and must pass `codesign --verify`.
- **Administrator scripts are approved one by one.** Approving installs a root-owned copy of exactly the script you
  were shown into `/Library/Application Support/DoubleTake/AdminScripts`, plus a rule in `/etc/sudoers.d` that lets
  your account run only those files as root. The text goes straight from the approval dialog into the
  password-protected root step, never through a folder your account can write to, and the sudoers rule is checked
  with `visudo` before it's installed. Editing a script makes it unapproved again.
- **Uninstalling removes everything it added**: the login item, administrator approvals, the `doubletake`
  command and the Accessibility entry (General › Uninstall DoubleTake…, or `doubletake uninstall --yes`).

The app isn't signed with an Apple Developer ID, so macOS asks you to confirm it the first time you open it.
