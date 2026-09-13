#!/usr/bin/env bash
# copilot-key doctor - checks the installation and, above all, the audio path.
#
# Run it as your normal user in a graphical session:  ./doctor.sh

set -u

BIN_DIR="$HOME/.local/bin"
DATA_DIR="$HOME/.local/share/copilot-key"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/copilot-key/config.toml"

pass() { printf '\033[1;32m  ok \033[0m%s\n' "$*"; }
fail() { printf '\033[1;31m  x  \033[0m%s\n' "$*"; }
note() { printf '\033[1;33m  !  \033[0m%s\n' "$*"; }
head_() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }

head_ "Installation"
for f in "$BIN_DIR/copilot-key" "$BIN_DIR/copilot-sound"; do
    if [ -x "$f" ]; then pass "$f"; else fail "$f fehlt oder ist nicht ausführbar"; fi
done
[ -f "$CONF" ] && pass "Konfiguration: $CONF" || fail "Konfiguration fehlt: $CONF"

head_ "Sound-Dateien"
if [ -d "$DATA_DIR/sounds" ]; then
    count=$(find "$DATA_DIR/sounds" -maxdepth 1 -type f \( -name '*.ogg' -o -name '*.wav' \) | wc -l)
    if [ "$count" -gt 0 ]; then
        pass "$count Dateien in $DATA_DIR/sounds"
        ls -1 "$DATA_DIR/sounds" | sed 's/^/       /'
    else
        fail "$DATA_DIR/sounds ist leer - install.sh erneut ausführen"
    fi
else
    fail "$DATA_DIR/sounds existiert nicht - install.sh erneut ausführen"
fi

head_ "Audio-System"
if command -v pactl >/dev/null 2>&1; then
    server=$(pactl info 2>/dev/null | grep -i 'Server Name\|Server-Name' | head -1)
    sink=$(pactl info 2>/dev/null | grep -i 'Default Sink\|Standard-Ziel' | head -1)
    if [ -n "$server" ]; then pass "${server#*: }"; else fail "pactl erreicht keinen Sound-Server"; fi
    [ -n "$sink" ] && pass "${sink#*: }"
else
    note "pactl nicht installiert (Paket pulseaudio-utils)"
fi

head_ "Verfügbare Player"
for p in paplay pw-play canberra-gtk-play ffplay mpv gst-play-1.0 aplay; do
    if command -v "$p" >/dev/null 2>&1; then pass "$p"; else printf '       -   %s\n' "$p"; fi
done

head_ "Wiedergabe-Test"
sound_dir="$DATA_DIR/sounds"
[ -d "$sound_dir" ] || sound_dir="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/sounds"
test_file="$sound_dir/menu-open.ogg"
if [ -f "$test_file" ]; then
    echo "   Datei: $test_file"
    echo "   Es sollte jetzt ein kurzer, leiser Zweiklang zu hören sein."
    COPILOT_KEY_DEBUG=1 COPILOT_KEY_SOUND_DIR="$sound_dir" "$BIN_DIR/copilot-sound" menu-open 0.9
    rc=$?
    if [ $rc -eq 0 ]; then
        pass "mindestens ein Player hat die Datei angenommen"
        note "Falls trotzdem nichts zu hören war: Lautstärke des Ausgabegeräts prüfen"
    else
        fail "kein Player konnte die Datei abspielen"
        echo "       Abhilfe:  sudo apt install pulseaudio-utils   (oder ffmpeg / mpv)"
    fi
else
    fail "Testdatei nicht gefunden: $test_file"
fi

head_ "Tastenkette"
if command -v keyd >/dev/null 2>&1; then
    pass "keyd installiert"
    if systemctl is-active --quiet keyd; then pass "keyd läuft"; else fail "keyd läuft nicht (systemctl status keyd)"; fi
    [ -f /etc/keyd/copilot.conf ] && pass "/etc/keyd/copilot.conf vorhanden" || fail "/etc/keyd/copilot.conf fehlt"
else
    fail "keyd ist nicht installiert"
fi

if command -v gsettings >/dev/null 2>&1; then
    found=0
    i=0
    while [ $i -lt 20 ]; do
        schema="org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/custom$i/"
        name=$(gsettings get "$schema" name 2>/dev/null)
        if [ "$name" = "'Copilot key'" ]; then
            pass "Tastenkürzel: $(gsettings get "$schema" binding 2>/dev/null) -> $(gsettings get "$schema" command 2>/dev/null)"
            found=1
            break
        fi
        i=$((i + 1))
    done
    [ $found -eq 1 ] || note "Kein Cinnamon-Kürzel 'Copilot key' gefunden"
fi

head_ "Grafik-Bibliotheken"
if python3 -c 'import gi' 2>/dev/null; then pass "python3-gi"; else fail "python3-gi fehlt (sudo apt install python3-gi)"; fi
if python3 -c 'import gi, cairo; gi.require_foreign("cairo")' 2>/dev/null; then
    pass "python3-gi-cairo (radiales Menü verfügbar)"
else
    fail "python3-gi-cairo fehlt - es erscheint nur das Listenmenü (sudo apt install python3-gi-cairo)"
fi

head_ "Fensterwerkzeuge (für das Toggeln)"
for p in wmctrl xdotool; do
    command -v "$p" >/dev/null 2>&1 && pass "$p" || fail "$p fehlt (sudo apt install $p)"
done

echo
