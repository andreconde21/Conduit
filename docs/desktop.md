# Desktop builds (Linux, Windows, macOS)

Conductore runs on Linux, Windows and macOS from the same Flutter code as
the phone apps. The desktop builds are **test builds**: unsigned, not in any
store, meant for trying the app with a real keyboard and a big screen. The
goal is one experience across phone and desktop. For now the desktops get
the phone UI with a keyboard-first terminal and a centred home screen.

## Getting a build

CI builds all three on every push to `main` and every PR (`ci.yml`, jobs
*Linux / Windows / macOS desktop build*). Open the run and download the
artifact. Tagged releases attach the same bundles to the GitHub prerelease
(`release.yml`, job *Desktop*):

| Platform | Release asset | CI artifact |
|---|---|---|
| Linux x64 | `conductore-v<version>-linux-x64.tar.gz` | `conductore-linux-x64` |
| Windows x64 | `conductore-v<version>-windows-x64.zip` | `conductore-windows-x64` |
| macOS (Apple silicon + Intel) | `conductore-v<version>-macos.zip` | `conductore-macos` |

`SHA256SUMS-desktop-v<version>.txt` sits next to them.

### Linux

```sh
tar -xzf conductore-v<version>-linux-x64.tar.gz
./conductore/conductore
```

Runtime needs: GTK 3 and **libsecret** with a running Secret Service
(GNOME Keyring or KWallet). Saved hosts, keys and settings live in
libsecret. Without a keyring daemon, saving fails. On a minimal system,
install `libgtk-3-0` and `libsecret-1-0` (Debian/Ubuntu) or `gtk3` and
`libsecret` (Arch/Omarchy), plus `gnome-keyring`.

To get a launcher entry, move the folder to `/opt/conductore` and copy
`data/conductore.desktop` to `~/.local/share/applications/`. Edit its two
paths if you put the folder elsewhere.

### Windows

Unzip `conductore-v<version>-windows-x64.zip` and run
`conductore\conductore.exe`. Keep the folder together: the exe loads the
DLLs and `data\` next to it. SmartScreen warns about an unsigned app the
first time: **More info → Run anyway**. Windows 10 or 11, x64.

### macOS

Unzip and move `Conductore.app` to Applications. The app is ad-hoc signed,
not notarised, so Gatekeeper blocks a double-click the first time:
**right-click (or Control-click) → Open → Open**. On macOS 15 and later, if
there is no Open button, go to **System Settings → Privacy & Security** and
click **Open Anyway**. Alternatively run:

```sh
xattr -dr com.apple.quarantine /Applications/Conductore.app
```

macOS 10.15 or later.

### Building locally

The desktop toolchains are the usual Flutter ones; see
`.github/workflows/ci.yml` for the exact setup.

```sh
flutter build linux --release     # Ubuntu: clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libsecret-1-dev libstdc++-12-dev
flutter build windows --release   # Visual Studio 2022 with "Desktop development with C++"
flutter build macos --release     # Xcode
```

Outputs: `build/linux/x64/release/bundle/`,
`build/windows/x64/runner/Release/`,
`build/macos/Build/Products/Release/Conductore.app`.

Desktop icons come from `tools/render_launcher_icon.py --desktop` (the
Windows `.ico`, the macOS AppIcon set and the Linux window icon).

## Using it on a desktop

- **Keyboard.** Keys go straight to the remote shell. Ctrl+C, Ctrl+A,
  Ctrl+V, Ctrl+[ ] \ / reach the shell. Alt is Meta on Linux and Windows,
  so Alt+b and Alt+f move by word. On macOS, Option composes characters,
  like Terminal.app. Arrows, Home/End, PgUp/PgDn and F1 to F12 send xterm
  sequences, including modifiers.
- **Copy and paste.** Ctrl+Shift+C and Ctrl+Shift+V (or Shift+Insert) on
  Linux and Windows. Cmd+C, Cmd+V and Cmd+A on macOS.
- **Quick switcher.** Ctrl+Shift+K (Cmd+K on macOS) opens it from the home
  screen and the terminal. The key never reaches the shell; plain Ctrl+K
  does.
- **Mouse.** Drag to select, and use the wheel to scroll back. The phone
  swipe gestures only react to touch, so a mouse drag never switches tmux
  windows.
- **Zoom.** Ctrl + mouse wheel (Cmd + wheel on macOS) or a trackpad pinch
  changes the terminal font size, like the phone's pinch, and it is saved
  the same way. A plain wheel still scrolls.
- **Shortcuts.** Ctrl+Shift+/ (Cmd+/ on macOS) or *Keyboard shortcuts* in
  the terminal menu lists them all:

  | Action | Linux / Windows | macOS |
  |---|---|---|
  | Zoom in / out / reset | Ctrl+= (or Ctrl++) / Ctrl+- / Ctrl+0 | Cmd+= / Cmd+- / Cmd+0 |
  | New session on this machine (connect picker) | Ctrl+Shift+T | Cmd+T |
  | Close session | Ctrl+Shift+W | Cmd+W |
  | Next / previous session | Ctrl+Tab / Ctrl+Shift+Tab | Ctrl+Tab / Ctrl+Shift+Tab, Cmd+Shift+] / Cmd+Shift+[ |
  | Go to session 1 to 9 | Alt+1 to Alt+9 | Cmd+1 to Cmd+9 |
  | Fullscreen terminal | F11 | Ctrl+Cmd+F or F11 |
  | Keyboard shortcuts | Ctrl+Shift+/ | Cmd+/ |

  None of these reach the shell. Two choices avoid clashes with shells and
  TUIs. Go to session uses Alt+digit, because Ctrl+2 to Ctrl+8 are control
  characters (Ctrl+6 is vim's alternate file). The price is readline's
  rarely used Alt+digit argument. Help is Ctrl+Shift+/ because Ctrl+/ sends
  ^_ (undo) and F1 belongs to htop and mc. Ctrl+Shift+- (Ctrl+_, undo)
  still reaches the shell. Close asks first when the session is a plain
  shell, because closing it ends what runs there. tmux and Herdr sessions
  just detach. Fullscreen hides the app's chrome, not the OS window
  decorations. There is no scrollback search yet (conduit_vt has none).
- **Menus and sheets.** Nothing slides up from the bottom on desktop.
  Action menus open as popovers at the click. Pickers and forms, such as
  the connect picker, open as centred dialogs. The agent inbox and the
  Herdr and tmux navigators slide in from the right. The quick switcher
  and snippets open as a command palette at the top. Esc closes any of
  them, and the first field has the focus. Phones keep the bottom sheets.
  All of these go through `lib/core/presentation/adaptive_modal.dart`.
- **On-screen keys.** The pill and key rows are hidden by default. The
  *On-screen keys* button above the bottom edge brings them back for the
  multiplexer shortcuts, snippets and the chat button. It resets for each
  terminal screen.
- **Window.** It opens at 1280x800, shrinks to 900x600 at the smallest, and
  the terminal reflows on resize. The home screen is centred at 960 px.

## What each platform supports

| Feature | Linux | Windows | macOS | Why |
|---|---|---|---|---|
| SSH, Mosh, SFTP, tmux / Herdr | yes | yes | yes | Pure Dart (dartssh2, dart_mosh over UDP) |
| Chat View, agent inbox, themes | yes | yes | yes | Flutter UI |
| Live preview (port forward) | browser | browser | embedded | webview_flutter has no official Linux/Windows implementation. The forward runs and *Open in browser* opens it |
| HTML files in the SFTP viewer | source | source | rendered | Same web view gap |
| PDF viewer | yes | yes | yes | pdfrx (PDFium, fetched at build time) |
| App lock | no | Windows Hello | Touch ID / password | local_auth has no Linux implementation. On Linux the app starts unlocked |
| Secret storage | libsecret | Credential Manager | login keychain | flutter_secure_storage |
| Attach image to a prompt | file picker | file picker | file picker | image_picker's desktop implementations pick files. No camera |
| Hardware security keys (`sk-` SSH keys) | no | no | no | FIDO runs over NFC (flutter_nfc_kit) or Android USB. Use a regular OpenSSH key on desktop. Connecting with an `sk-` key says so |
| Local shell | no | no | no | The local shell section is Android's proot Linux (arm64 binaries). flutter_pty works on all three desktops, so a native local terminal running the user's shell is the natural follow-up |
| Dictation, read-aloud (Talk) | no | no | no | Android `conduit/speech` and `conduit/tts` channels |
| Live preview screenshot to Claude | no | no | yes | Needs the embedded page. Android uses PixelCopy |
| Paste a clipboard image as a file | no | no | no | Android `conduit/clipboard_image` bridge. Paste falls back to text |
| Sync setup | paste code | paste code | paste code | The QR scanner (mobile_scanner) is phone-only. Desktops paste the setup code |
| Share target, home widget, Quick Settings tile, notification Allow/Deny, clipboard images, background keep-alive | no | no | no | Android platform channels (MainActivity). `PlatformFeatures` hides them |
| Keep screen on, network change reconnect | yes | yes | yes | wakelock_plus, connectivity_plus (NetworkManager on Linux) |

Gating lives in `lib/core/platform_features.dart`. Every flag reads
`defaultTargetPlatform`, so a widget test can check the desktop UI with
`TargetPlatformVariant`.

## macOS sandbox and keychain

- **The App Sandbox is off** (`macos/Runner/*.entitlements`). A terminal
  needs the user's shell, files, `~/.ssh` and Homebrew. Inside the sandbox
  a future local terminal would get a container home instead. Apps
  distributed outside the Mac App Store may be unsandboxed. The
  entitlements still list `network.client`, `files.user-selected.read-write`
  and `files.downloads.read-write`, so switching `app-sandbox` to `true` for
  a store build keeps SSH, Mosh, the file pickers and SFTP downloads
  working.
- **Keychain.** flutter_secure_storage defaults to the data-protection
  keychain, which needs the restricted `keychain-access-groups`
  entitlement. An ad-hoc signed app carrying it is killed at launch.
  `lib/core/secure_storage.dart` uses the login keychain on macOS instead,
  which needs no entitlement. macOS may ask once to allow Conductore into
  the login keychain. A Developer ID signed build could move to the
  data-protection keychain, but existing items would not follow.
- **Signing and notarisation** need an Apple Developer ID certificate. They
  are not set up. Until then, see the Gatekeeper steps above.

## Known limitations

- Unsigned builds on all three platforms (Gatekeeper, SmartScreen).
- No auto-update. Download the next release by hand.
- Linux and Windows builds are x64 only. There is no ARM64 Linux or Windows
  build yet.
- The on-screen keys toggle is per screen and not remembered.
- The UI is the phone UI with a centred home screen. Settings and sheets are
  full width. A real desktop layout, such as a side-by-side host list and
  terminal, comes later.
- No scrollback search (Ctrl+Shift+F) yet, and the shortcuts are not
  configurable.
