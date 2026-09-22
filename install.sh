#!/usr/bin/env bash
# copilot-key installer
#
# Installs the launcher for the whole machine (--user keeps it in your home),
# sets up keyd for the Copilot key and registers the desktop shortcut. Run as
# your normal user - it calls sudo where root is actually required.
#
# The programs are shared; the menu, its configuration and the shortcut belong
# to each user separately and appear on their first press.
#
# Messages follow your locale (see lib/i18n.sh); COPILOT_KEY_LANG overrides it.

set -euo pipefail

SRC="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=lib/i18n.sh
. "$SRC/lib/i18n.sh"

CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/copilot-key"
KEYD_CONF="/etc/keyd/copilot.conf"
SHORTCUT="<Control><Alt><Shift>F12"

info()  { printf '\033[1;36m==\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m  !\033[0m %s\n' "$*"; }
die()   { printf '\033[1;31m  x\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "$(t no_sudo)"

# --- 0. scope ---------------------------------------------------------------
# System-wide by default: one installation serves everyone on the machine.
SCOPE="system"
case "${1:-}" in
    ""|--system) ;;
    --user) SCOPE="user" ;;
    *) die "$(t usage_install)" ;;
esac

if [ "$SCOPE" = "system" ]; then
    BIN_DIR="/usr/local/bin"
    DATA_DIR="/usr/local/share/copilot-key"
    APPS_DIR="/usr/local/share/applications"
    AUTOSTART_DIR="/etc/xdg/autostart"
    SUDO="sudo"
    info "$(t scope_system)"
else
    BIN_DIR="$HOME/.local/bin"
    DATA_DIR="$HOME/.local/share/copilot-key"
    APPS_DIR="$HOME/.local/share/applications"
    AUTOSTART_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
    SUDO=""
    info "$(t scope_user "$USER")"
fi

# ~/.local/bin usually comes first in PATH, so an older per-user install would
# quietly keep winning after a system-wide one.
if [ "$SCOPE" = "system" ] && [ -e "$HOME/.local/bin/copilot-key" ]; then
    warn "$(t stale_user_install "$HOME/.local/bin")"
fi

# --- 1. dependencies --------------------------------------------------------
info "$(t deps_check)"
missing=()
need_pkg() { command -v "$1" >/dev/null 2>&1 || missing+=("$2"); }
need_pkg wmctrl wmctrl
need_pkg xdotool xdotool
python3 -c 'import gi' 2>/dev/null || missing+=(python3-gi)
python3 -c 'import gi, cairo; gi.require_foreign("cairo")' 2>/dev/null || missing+=(python3-gi-cairo)
command -v paplay >/dev/null 2>&1 || command -v pw-play >/dev/null 2>&1 || missing+=(pulseaudio-utils)

if [ ${#missing[@]} -gt 0 ]; then
    warn "$(t deps_missing "${missing[*]}")"
    read -rp "$(t deps_ask)" answer
    case "${answer:-Y}" in
        [nN]*) warn "$(t deps_skipped)" ;;
        *) sudo apt update && sudo apt install -y "${missing[@]}" ;;
    esac
else
    ok "$(t deps_ok)"
fi

# --- 2. keyd ----------------------------------------------------------------
if command -v keyd >/dev/null 2>&1; then
    ok "$(t keyd_installed "$(keyd --version 2>/dev/null | head -1)")"
else
    info "$(t keyd_install)"
    # Language-independent check: does any configured source ship keyd?
    if apt-cache show keyd >/dev/null 2>&1; then
        sudo apt install -y keyd
    else
        warn "$(t keyd_no_package)"
        read -rp "$(t keyd_build_ask)" answer
        case "${answer:-Y}" in
            [nN]*) die "$(t keyd_required)" ;;
        esac
        command -v git >/dev/null 2>&1 || sudo apt install -y git build-essential
        build_dir="$HOME/Downloads/keyd"
        if [ -d "$build_dir/.git" ]; then
            git -C "$build_dir" pull --ff-only
        else
            git clone https://github.com/rvaiya/keyd "$build_dir"
        fi
        make -C "$build_dir" -j"$(nproc)"
        sudo make -C "$build_dir" install
        sudo systemctl enable --now keyd
    fi
fi

# --- 3. files ---------------------------------------------------------------
info "$(t files_install)"
$SUDO mkdir -p "$BIN_DIR" "$DATA_DIR/sounds" "$DATA_DIR/skins" "$DATA_DIR/docs" "$APPS_DIR"
$SUDO install -m 755 "$SRC/bin/copilot-key"    "$BIN_DIR/copilot-key"
$SUDO install -m 755 "$SRC/bin/copilot-sound"  "$BIN_DIR/copilot-sound"
$SUDO install -m 755 "$SRC/bin/copilot-config" "$BIN_DIR/copilot-config"
$SUDO install -m 644 "$SRC"/sounds/*.ogg "$DATA_DIR/sounds/" 2>/dev/null \
    || $SUDO install -m 644 "$SRC"/sounds/*.wav "$DATA_DIR/sounds/"
[ -f "$SRC/sounds/theme.toml" ] && $SUDO install -m 644 "$SRC/sounds/theme.toml" "$DATA_DIR/sounds/"
# Every further sound theme is a directory of its own next to the glass bells.
themes=()
for theme in "$SRC"/sounds/*/; do
    [ -d "$theme" ] || continue
    name="$(basename "$theme")"
    $SUDO mkdir -p "$DATA_DIR/sounds/$name"
    $SUDO install -m 644 "$theme"* "$DATA_DIR/sounds/$name/"
    themes+=("$name")
done
[ -f "$SRC/docs/sound-themes.md" ] && $SUDO install -m 644 "$SRC/docs/sound-themes.md" "$DATA_DIR/docs/"
$SUDO install -m 644 "$SRC"/skins/*.toml "$DATA_DIR/skins/"
[ -f "$SRC/docs/skins.md" ] && $SUDO install -m 644 "$SRC/docs/skins.md" "$DATA_DIR/docs/"
ok "$(t files_launcher "$BIN_DIR/copilot-key")"
ok "$(t files_editor "$BIN_DIR/copilot-config")"
ok "$(t files_sounds "$DATA_DIR/sounds")"
[ ${#themes[@]} -gt 0 ] && ok "$(t files_sound_themes "${themes[*]}")"
ok "$(t files_skins "$DATA_DIR/skins")"

# The editor is an ordinary application too, so it belongs in the start menu.
sed "s|^Exec=.*|Exec=$BIN_DIR/copilot-config|" "$SRC/config/copilot-key-config.desktop" \
    | $SUDO tee "$APPS_DIR/copilot-key-config.desktop" >/dev/null
$SUDO chmod 644 "$APPS_DIR/copilot-key-config.desktop"
command -v update-desktop-database >/dev/null 2>&1 \
    && $SUDO update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
ok "$(t files_menu_entry "$APPS_DIR/copilot-key-config.desktop")"

# One login hook per machine: it gives each user their shortcut and, with it,
# their own copy of the defaults - nobody has to run an installer twice.
$SUDO mkdir -p "$AUTOSTART_DIR"
sed "s|^Exec=.*|Exec=$BIN_DIR/copilot-key ensure-shortcut|" \
    "$SRC/config/copilot-key-autostart.desktop" \
    | $SUDO tee "$AUTOSTART_DIR/copilot-key-setup.desktop" >/dev/null
$SUDO chmod 644 "$AUTOSTART_DIR/copilot-key-setup.desktop"
ok "$(t files_autostart "$AUTOSTART_DIR/copilot-key-setup.desktop")"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$(t path_warning "$BIN_DIR")" ;;
esac

# --- 4. keyd configuration --------------------------------------------------
info "$(t keyd_configure)"
sudo mkdir -p /etc/keyd
sudo install -m 644 "$SRC/config/keyd-copilot.conf" "$KEYD_CONF"
sudo systemctl enable keyd >/dev/null 2>&1 || true
sudo systemctl restart keyd
if systemctl is-active --quiet keyd; then
    ok "$(t keyd_running "$KEYD_CONF")"
else
    warn "$(t keyd_not_running)"
fi

# --- 5. desktop shortcut ----------------------------------------------------
# The launcher knows how to do this; doing it here as well would mean two
# implementations of the same gsettings dance.
info "$(t shortcut_register "$SHORTCUT")"
had_config=0
[ -f "$CONF_DIR/config.toml" ] && had_config=1
if "$BIN_DIR/copilot-key" ensure-shortcut; then
    ok "$(t shortcut_done)"
else
    warn "$(t shortcut_manual)"
    echo "$(t shortcut_combo "$SHORTCUT")"
    echo "$(t shortcut_command "$BIN_DIR/copilot-key")"
fi
if [ "$had_config" -eq 1 ]; then
    ok "$(t files_config_kept "$CONF_DIR/config.toml")"
elif [ -f "$CONF_DIR/config.toml" ]; then
    ok "$(t files_config_new "$CONF_DIR/config.toml")"
fi

# --- 6. done ----------------------------------------------------------------
echo
info "$(t done)"
echo "$(t usage_short)"
echo "$(t usage_double)"
echo
echo "$(t test_sounds "$BIN_DIR/copilot-key")"
echo "$(t test_menu "$BIN_DIR/copilot-key")"
echo "$(t test_key "$SRC/detect-key.sh")"
echo "$(t usage_configure "$BIN_DIR/copilot-key")"
[ "$SCOPE" = "system" ] && echo "$(t other_users)"
exit 0
