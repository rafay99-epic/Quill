<div align="center">
  <img src="VoiceInk/Assets.xcassets/AppIcon.appiconset/256-mac.png" width="180" height="180" />
  <h1>Quill</h1>
  <p>A personal, for-fun fork of <a href="https://github.com/Beingpax/VoiceInk">VoiceInk</a> — local speech-to-text dictation for macOS, powered by whisper.cpp.</p>

  [![License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
  ![Platform](https://img.shields.io/badge/platform-macOS%2014.4%2B%20(Apple%20Silicon)-brightgreen)
</div>

---

## ⚠️ Read this first

**Quill is not the official app.** It is a personal hobby fork I built for my own use,
for fun and to learn. It is **not affiliated with, endorsed by, or supported by** the
original developer.

- **Want the real thing, with real support, updates, and a developer who stands
  behind it?** Use the **official VoiceInk app** → **[tryvoiceink.com](https://tryvoiceink.com)**.
  If you rely on it, please **buy a license** and support the developer's work.
- **Do not** take Quill's bugs, questions, or support requests to the official
  VoiceInk project or its developer. This fork is my responsibility, not theirs.
- **No warranty. Use at your own risk.** I take **no responsibility** for anything
  that breaks, misbehaves, eats your data, or otherwise goes wrong. It's a fun
  project — treat it like one.

## 🙏 Credit where it's due

**All of the real work here is [Beingpax](https://github.com/Beingpax)'s.** VoiceInk —
the app, the design, the engineering, the polish — is their creation. Quill is just a
thin personal fork on top of it. Huge thanks to them for building VoiceInk and for
open-sourcing it under the GPL.

- Original project: **[Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk)**
- Official app & support: **[tryvoiceink.com](https://tryvoiceink.com)**

## What Quill actually is

VoiceInk is GPL-3.0 source, and the GPL grants the right to modify and run your own
build. Quill is exactly that — my own build, with a few personal changes:

- Rebranded to its own identity (name, bundle id, icon) so it doesn't pretend to be
  the official app.
- Builds locally with no Apple Developer account (ad-hoc signed).
- A custom GitHub-Releases updater (instead of the official update feed) and its own
  `stable` / `nightly` / `dev` channels.

Everything that makes it useful — local Whisper / Parakeet transcription, the paste
engine, the dashboard — is upstream VoiceInk's work.

## Install

Apple Silicon, macOS 14.4+.

```sh
brew tap rafay99-epic/homebrew-apps
brew install --cask quill            # stable
brew install --cask quill-nightly    # nightly channel (pre-release)
```

First launch (the build is ad-hoc signed, not notarized): right-click the app →
**Open** → **Open**. Then grant **Microphone** and **Accessibility** in System
Settings → Privacy & Security, and download a model in-app.

### Build from source

```sh
git clone https://github.com/rafay99-epic/Quill.git
cd Quill
./build.sh        # → build/Quill.app   (needs Xcode; builds whisper.cpp on first run)
./make-dmg.sh     # → build/Quill.dmg
```

## Channels

| Channel | App | Updates |
|---|---|---|
| **Stable** | `Quill.app` | latest GitHub release |
| **Nightly** | `Quill Nightly.app` | rolling pre-release |
| **Dev** | `Quill Dev.app` | none (local builds) |

All three install side by side with separate icons and data.

## License

GPL-3.0, inherited from [VoiceInk](https://github.com/Beingpax/VoiceInk). See
[`LICENSE`](LICENSE). This fork is provided **as-is, with no warranty of any kind**.
