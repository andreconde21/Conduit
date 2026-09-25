# Conductore privacy policy

Effective 25 September 2026. Applies to the Conductore app for Android and
iOS, published by Outsmartis, including builds from Google Play, the App
Store, TestFlight and GitHub releases.

## The short version

Conductore is a terminal for your own computers. It has no account, no
analytics, no advertising, no crash reporting and no telemetry. Outsmartis
runs no server that the app talks to. What you enter stays on your phone
and goes only to the machines you connect to.

## What the app stores, and where

On your device only:

- **Saved machines and settings.** Host names, ports, user names, tags,
  snippets, themes and other preferences.
- **Credentials.** Passwords and SSH private keys you add are kept in the
  platform's secure storage (Android Keystore, iOS Keychain). They are sent
  only to the machine you are logging in to, as part of SSH authentication.
- **Temporary files.** Files you open, upload or attach are cached on the
  device while you work with them.

Outsmartis never receives any of this. Uninstalling the app deletes it.
If you export a backup, the app writes the file to a location you choose,
encrypted with the password you set. What happens to that file after
that is up to you.

If you turn on device sync, the app stores one file encrypted on your
device with your sync passphrase (Argon2id, XChaCha20-Poly1305) in
`~/.conductore/sync` on a machine of yours that you pick, over SSH, plus a
small unencrypted list of your device names and sync times. Passwords and
SSH keys are included only if you turn that on. Adding a device adds an
SSH key marked `conductore-device` to that machine's
`~/.ssh/authorized_keys`, after you confirm.

## Network connections

Conductore connects only to:

- **Your machines**, over SSH, Mosh and SFTP, using the addresses you enter.
  Agent status, the Conductore host companion (`conductore-hostd`) and theme
  sync all run over those same connections, on machines you control.
- **Web pages you open.** Links open in your browser. Live Preview shows a
  web page served by your own machine over a forwarded port.
- **GitHub, for the Android local shell only.** When you set up the local
  Linux shell, the app downloads its root filesystem from GitHub. GitHub
  sees an ordinary download request.

## Permissions and why they are used

| Permission | Why |
|---|---|
| Network access | To connect to the machines you add. |
| Local network (iOS) | To reach machines on your home or office network. |
| Microphone (Android) | For dictation into the terminal. The app asks Android for its on-device recognizer. If that is not available, Android's speech service handles the audio under its own policy. The app itself never sends audio anywhere. |
| Camera and photos | To take or pick a picture that you upload to your machine or attach to a coding agent prompt. On Android the system photo picker and camera app are used, so the app gets only the picture you choose. |
| Notifications (Android) | To show that sessions are kept alive in the background and to tell you when a coding agent on your machine needs you. |
| Foreground service (Android) | To keep your terminal sessions connected while the app is in the background. |
| Biometrics (Face ID, fingerprint) | To unlock the app and your saved credentials, if you turn the lock on. Biometric data never leaves the operating system. |
| NFC | To use a hardware security key (FIDO2) for SSH login. |
| All files access (Android, GitHub builds only) | To let the file browser and local shell reach your phone's shared storage. The Play Store build does not ask for it. |

## Children

Conductore is a developer tool and is not directed at children.

## Changes

Changes to this policy are published in this file, and its history is
public in the repository.

## Contact

Questions or requests: open an issue at
https://github.com/andreconde21/conductore-mobile/issues
