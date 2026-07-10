#!/bin/bash
# Build the Dev channel and install it to /Applications/Quill Dev.app, running side
# by side with a Stable Quill.app (distinct bundle id, no updater). Mirrors
# Crisp/Porter dev.sh.
set -euo pipefail
cd "$(dirname "$0")"

# Dev builds are signed AD-HOC on purpose: no certificate, no keychain access, no
# password/authorization prompts. Only Stable/main (build.sh + CI) uses the stable
# `Quill Local Signing` identity.
#
# Tradeoff, accepted deliberately: an ad-hoc signature changes on every build, so macOS
# keys the Accessibility (TCC) grant to a signature that no longer exists after a rebuild
# — you may need to re-grant Accessibility to Quill Dev after a rebuild if you use the
# dictation hotkey. That's fine for a throwaway dev build and avoids the keychain prompt.
#
# Force ad-hoc EXPLICITLY (empty value) rather than just leaving it unset: the shell may
# already `export QUILL_SIGN_IDENTITY="Quill Local Signing"` (e.g. from ~/.zshrc), and an
# empty value makes build.sh's `${QUILL_SIGN_IDENTITY:--}` fall back to "-" (ad-hoc).
export QUILL_SIGN_IDENTITY=""
echo "Signing dev build ad-hoc (no keychain, no prompts). Stable/main signing is unaffected."

QUILL_CHANNEL=dev ./build.sh

APP="Quill Dev.app"
osascript -e 'quit app "Quill Dev"' 2>/dev/null || true
sleep 1
rm -rf "/Applications/$APP"
ditto "build/$APP" "/Applications/$APP"
open "/Applications/$APP"
echo "Installed and launched /Applications/$APP"
