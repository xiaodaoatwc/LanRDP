# LanRDP

A small RDP client for macOS, built on **FreeRDP 3.33.0** (`sdl-freerdp`).
It does not require a Microsoft account and has no internet health check.
It works on LAN or WAN; WAN access usually needs port forwarding, a VPN, or a tunnel.

## Features

- Add, edit, and organize PCs into groups
- Shared credentials or direct username/password login
- Passwords stored in the macOS Keychain (with a 0600 local fallback)
- Display modes: window, full screen, fixed resolution
- Common resolution presets and "use visible desktop" (excludes Dock/menu bar)
- Retina/high-DPI scaling: 100%, 125%, 150%, 175%, 180%, 200%
- Multiple monitors, clipboard, sound
- Local folder sharing (`\\tsclient\MacShare` on Windows)
- Admin session (`mstsc /admin`) for RDS servers without an available CAL
- Certificate policy: ignore (default), trust on first use, strict
- English and Simplified Chinese UI (System / 中文 / English)
- Concise connection errors with a "View log" button

## Install

Download `LanRDP-<version>-universal.dmg` from the Releases page, open it, and drag **LanRDP** to `Applications`.

The app is ad-hoc signed and not notarized by Apple. If macOS blocks it, right-click the app and choose **Open**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/LanRDP.app
```

## Requirements

- macOS 14 or later
- Apple Silicon or Intel (Universal build)
- TCP 3389 reachable on the target Windows PC

No Homebrew, XQuartz, FreeRDP, or Microsoft Remote Desktop installation is required. FreeRDP, SDL3, SDL3_ttf, FreeType, and OpenSSL are bundled or statically linked.

## Data

```text
~/Library/Application Support/LanRDP/config.json
~/Library/Application Support/LanRDP/Logs/
~/Library/Application Support/LanRDP/passwords-fallback.json
```

Passwords are stored in the macOS Keychain (`com.lanrdp.credentials`, `com.lanrdp.pcpasswords`) with a 0600 local fallback.

## License

LanRDP original code: MIT License, Copyright (c) 2026 xiaodaoatwc.

Third-party components retain their own licenses. See `THIRD_PARTY_NOTICES.md`, `MODIFICATIONS.md`, and `patches/`.
