# Fork Notes (`thunder951413/vorssaint-utils`)

This repository is a personal enhanced fork of [vorssaint/vorssaint-utils](https://github.com/vorssaint/vorssaint-utils) under GPL-3.0-or-later. Fork-specific documentation lives here rather than in `README.md`, `docs/PRIVACY.md`, or `CONTRIBUTING.md` to keep periodic upstream syncs conflict-free.

## Fork-only enhancements

- **App Hotkeys:** Manico-style global per-app shortcuts to launch, summon, hide, or cycle windows for favorite apps, with one-click Dock import.
- **Trackpad Multi-Touch Gestures & Keyboard Automation:** 2–5 finger swipes and 4–5 finger pinches/spreads with palm and misfire rejection, plus clean global chord key remaps (per-app scope, keyDown/keyUp, repeat, Schema v2 rules).
- **Screen Color Filter & DDC Dimming:** Sun-scheduled tint wheel and color overlay in Displays, plus persistent software dimming for DDC monitors.
- **Custom Fan Control Curves:** Follow a selected temperature sensor with an adjustable acceleration factor while handing control back whenever firmware demands higher cooling.
- **Clipboard Cloud Sync (Jianguoyun WebDAV · E2EE):** Optional cross-device clipboard sync compatible with YTools for Windows (YTCE2 wire format).
- **Command Bar YTools Extensions:** Offline system dictionary (`define` / `dict`), English spelling suggestions (`spell`), interactive folder navigation (`/` and `~`) with atomic no-overwrite copy/move and a file buffer, Chinese Pinyin & initial matching, and `⌘L` Large Type.
- **Independent Fork Releases & Updates:** Signed builds are published from `thunder951413/vorssaint-utils` via `.github/workflows/fork-release.yml`.

## Additional Privacy Notes (Beyond `docs/PRIVACY.md`)

1. **Fork update checks:** Automatic update checks query `api.github.com` for releases of `thunder951413/vorssaint-utils` instead of upstream.
2. **Optional Clipboard Cloud Sync (Jianguoyun WebDAV · E2EE):** Off by default. When explicitly enabled and configured in Clipboard settings, clipboard events and optional deletion tombstones are end-to-end encrypted locally with PBKDF2-SHA256 (600,000 rounds) and AES-256-GCM before upload to your own Jianguoyun WebDAV folder at `https://dav.jianguoyun.com/dav/`. Credentials, sync passphrase, and sync state are encrypted locally with a device-bound macOS login Keychain key (`SecureVaultCodableStore`) and are never included in Settings backups.

## Build & Test Quick Reference

Always use `./build.sh` rather than `swift build` / `swift test` (`Package.swift` is for IDE indexing only):

```sh
./build.sh                            # release build + FanControlHelper + NowPlaying adapter + signing
./build/stage/Vorssaint.app/Contents/MacOS/Vorssaint --selftest
./build.sh --test                     # full unit test suite
./build.sh --test-suite=trackpad-gestures
./build.sh --install                  # install into /Applications
```
