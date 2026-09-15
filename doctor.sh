#!/usr/bin/env bash
# copilot-key doctor - checks the installation and, above all, the audio path.
#
# Run it as your normal user in a graphical session:  ./doctor.sh

set -u

SRC="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=lib/i18n.sh
. "$SRC/lib/i18n.sh"

BIN_DIR="$HOME/.local/bin"
DATA_DIR="$HOME/.local/share/copilot-key"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/copilot-key/config.toml"

pass()  { printf '\033[1;32m  ok \033[0m%s\n' "$*"; }
fail()  { printf '\033[1;31m  x  \033[0m%s\n' "$*"; }
note()  { printf '\033[1;33m  !  \033[0m%s\n' "$*"; }
head_() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }

head_ "$(t doc_install)"
for f in "$BIN_DIR/copilot-key" "$BIN_DIR/copilot-sound"; do
    if [ -x "$f" ]; then pass "$f"; else fail "$(t doc_missing "$f")"; fi
done
if [ -f "$CONF" ]; then pass "$(t doc_config "$CONF")"; else fail "$(t doc_config_missing "$CONF")"; fi

head_ "$(t doc_sounds)"
if [ -d "$DATA_DIR/sounds" ]; then
    count=$(find "$DATA_DIR/sounds" -maxdepth 1 -type f \( -name '*.ogg' -o -name '*.wav' \) | wc -l)
    if [ "$count" -gt 0 ]; then
        pass "$(t doc_sounds_found "$count" "$DATA_DIR/sounds")"
        ls -1 "$DATA_DIR/sounds" | sed 's/^/       /'
    else
        fail "$(t doc_sounds_empty "$DATA_DIR/sounds")"
    fi
else
    fail "$(t doc_sounds_nodir "$DATA_DIR/sounds")"
fi

head_ "$(t doc_audio)"
if command -v pactl >/dev/null 2>&1; then
    server=$(pactl info 2>/dev/null | grep -i 'Server Name\|Server-Name' | head -1)
    sink=$(pactl info 2>/dev/null | grep -i 'Default Sink\|Standard-Ziel' | head -1)
    if [ -n "$server" ]; then pass "${server#*: }"; else fail "$(t doc_audio_none)"; fi
    [ -n "$sink" ] && pass "${sink#*: }"
else
    note "$(t doc_pactl_missing)"
fi

head_ "$(t doc_players)"
for p in paplay pw-play canberra-gtk-play ffplay mpv gst-play-1.0 aplay; do
    if command -v "$p" >/dev/null 2>&1; then pass "$p"; else printf '       -   %s\n' "$p"; fi
done

head_ "$(t doc_playback)"
sound_dir="$DATA_DIR/sounds"
[ -d "$sound_dir" ] || sound_dir="$SRC/sounds"
test_file="$sound_dir/menu-open.ogg"
if [ -f "$test_file" ]; then
    echo "$(t doc_playback_file "$test_file")"
    echo "$(t doc_playback_hint)"
    COPILOT_KEY_DEBUG=1 COPILOT_KEY_SOUND_DIR="$sound_dir" "$BIN_DIR/copilot-sound" menu-open 0.9
    rc=$?
    if [ $rc -eq 0 ]; then
        pass "$(t doc_playback_ok)"
        note "$(t doc_playback_volume)"
    else
        fail "$(t doc_playback_fail)"
        echo "$(t doc_playback_fix)"
    fi
else
    fail "$(t doc_testfile_missing "$test_file")"
fi

head_ "$(t doc_keychain)"
if command -v keyd >/dev/null 2>&1; then
    pass "$(t doc_keyd_installed)"
    if systemctl is-active --quiet keyd; then pass "$(t doc_keyd_running)"; else fail "$(t doc_keyd_stopped)"; fi
    if [ -f /etc/keyd/copilot.conf ]; then
        pass "$(t doc_keyd_conf /etc/keyd/copilot.conf)"
    else
        fail "$(t doc_keyd_conf_missing /etc/keyd/copilot.conf)"
    fi
else
    fail "$(t doc_keyd_missing)"
fi

if command -v gsettings >/dev/null 2>&1; then
    found=0
    i=0
    while [ $i -lt 20 ]; do
        schema="org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/custom$i/"
        name=$(gsettings get "$schema" name 2>/dev/null)
        if [ "$name" = "'Copilot key'" ]; then
            pass "$(t doc_shortcut "$(gsettings get "$schema" binding 2>/dev/null)" "$(gsettings get "$schema" command 2>/dev/null)")"
            found=1
            break
        fi
        i=$((i + 1))
    done
    [ $found -eq 1 ] || note "$(t doc_shortcut_missing)"
fi

head_ "$(t doc_graphics)"
if python3 -c 'import gi' 2>/dev/null; then pass "$(t doc_gi_ok)"; else fail "$(t doc_gi_missing)"; fi
if python3 -c 'import gi, cairo; gi.require_foreign("cairo")' 2>/dev/null; then
    pass "$(t doc_cairo_ok)"
else
    fail "$(t doc_cairo_missing)"
fi

head_ "$(t doc_windowtools)"
for p in wmctrl xdotool; do
    if command -v "$p" >/dev/null 2>&1; then pass "$p"; else fail "$(t doc_tool_missing "$p" "$p")"; fi
done

echo
