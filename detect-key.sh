#!/usr/bin/env bash
# Find out what the Copilot key actually sends on this machine.
#
# Run it, press the Copilot key, then press Ctrl+C. The captured key names go
# straight into config/keyd-copilot.conf.

set -u

bold() { printf '\033[1m%s\033[0m\n' "$*"; }

bold "Copilot-Tasten-Detektor"
echo

if command -v keyd >/dev/null 2>&1; then
    echo "Methode: keyd monitor (genauester Weg – zeigt exakt die keyd-Namen)"
    echo "Jetzt die Copilot-Taste drücken. Beenden mit Ctrl+C."
    echo
    exec sudo keyd monitor
fi

if command -v evtest >/dev/null 2>&1; then
    echo "keyd ist nicht installiert - weiche auf evtest aus."
    echo "Gerät wählen (meist 'AT Translated Set 2 keyboard'), dann die Taste drücken."
    echo
    exec sudo evtest
fi

if command -v xev >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    echo "Weder keyd noch evtest gefunden - weiche auf xev aus."
    echo "Im erscheinenden Fenster die Copilot-Taste drücken."
    echo "Hinweis: xev zeigt nur, was X11 erreicht - der Modifier-Teil kann fehlen."
    echo
    exec xev -event keyboard
fi

echo "Kein Analyse-Werkzeug gefunden. Bitte installieren:" >&2
echo "  sudo apt install keyd     # empfohlen, oder" >&2
echo "  sudo apt install evtest x11-utils" >&2
exit 1
