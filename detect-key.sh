#!/usr/bin/env bash
# Find out what the Copilot key actually sends on this machine.
#
# Run it, press the Copilot key, then press Ctrl+C. The captured key names go
# straight into config/keyd-copilot.conf.

set -u

SRC="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=lib/i18n.sh
. "$SRC/lib/i18n.sh"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }

bold "$(t detect_title)"
echo

if command -v keyd >/dev/null 2>&1; then
    echo "$(t detect_keyd)"
    echo "$(t detect_keyd_hint)"
    echo
    exec sudo keyd monitor
fi

if command -v evtest >/dev/null 2>&1; then
    echo "$(t detect_evtest)"
    echo "$(t detect_evtest_hint)"
    echo
    exec sudo evtest
fi

if command -v xev >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    echo "$(t detect_xev)"
    echo "$(t detect_xev_hint)"
    echo "$(t detect_xev_note)"
    echo
    exec xev -event keyboard
fi

echo "$(t detect_none)" >&2
echo "  sudo apt install keyd     # recommended, or" >&2
echo "  sudo apt install evtest x11-utils" >&2
exit 1
