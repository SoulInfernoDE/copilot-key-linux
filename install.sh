#!/usr/bin/env bash
# copilot-key installer
#
# Installs the launcher into ~/.local, sets up keyd for the Copilot key and
# registers the desktop shortcut. Run as your normal user - it calls sudo where
# root is actually required.
#
# Messages follow your locale (see lib/i18n.sh); COPILOT_KEY_LANG overrides it.

set -euo pipefail

SRC="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=lib/i18n.sh
. "$SRC/lib/i18n.sh"

BIN_DIR="$HOME/.local/bin"
DATA_DIR="$HOME/.local/share/copilot-key"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/copilot-key"
KEYD_CONF="/etc/keyd/copilot.conf"
SHORTCUT="<Control><Alt><Shift>F12"
SHORTCUT_NAME="Copilot key"

info()  { printf '\033[1;36m==\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m  !\033[0m %s\n' "$*"; }
die()   { printf '\033[1;31m  x\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "$(t no_sudo)"

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
mkdir -p "$BIN_DIR" "$DATA_DIR/sounds" "$CONF_DIR"
install -m 755 "$SRC/bin/copilot-key"   "$BIN_DIR/copilot-key"
install -m 755 "$SRC/bin/copilot-sound" "$BIN_DIR/copilot-sound"
install -m 644 "$SRC"/sounds/*.ogg "$DATA_DIR/sounds/" 2>/dev/null \
    || install -m 644 "$SRC"/sounds/*.wav "$DATA_DIR/sounds/"
ok "$(t files_launcher "$BIN_DIR/copilot-key")"
ok "$(t files_sounds "$DATA_DIR/sounds")"

# The shipped config template follows the same language as the messages.
config_template="$SRC/config/config.toml"
[ "$COPILOT_LANG" = "de" ] && [ -f "$SRC/config/config.de.toml" ] && config_template="$SRC/config/config.de.toml"

if [ -f "$CONF_DIR/config.toml" ]; then
    ok "$(t files_config_kept "$CONF_DIR/config.toml")"
else
    install -m 644 "$config_template" "$CONF_DIR/config.toml"
    ok "$(t files_config_new "$CONF_DIR/config.toml")"
fi

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
info "$(t shortcut_register "$SHORTCUT")"
register_cinnamon() {
    local base="org.cinnamon.desktop.keybindings"
    local path_base="/org/cinnamon/desktop/keybindings/custom-keybindings"
    local list slot="" i=0 entry schema

    list="$(gsettings get "$base" custom-list 2>/dev/null || echo "@as []")"

    # Reuse our own entry if it already exists.
    while [ $i -lt 20 ]; do
        schema="$base.custom-keybinding:$path_base/custom$i/"
        if [ "$(gsettings get "$schema" name 2>/dev/null)" = "'$SHORTCUT_NAME'" ]; then
            slot="custom$i"
            break
        fi
        i=$((i + 1))
    done

    # Otherwise take the first free slot.
    if [ -z "$slot" ]; then
        i=0
        while [ $i -lt 20 ]; do
            case "$list" in
                *"'custom$i'"*) i=$((i + 1)); continue ;;
            esac
            slot="custom$i"
            break
        done
    fi
    [ -n "$slot" ] || return 1

    schema="$base.custom-keybinding:$path_base/$slot/"
    gsettings set "$schema" name "$SHORTCUT_NAME"
    gsettings set "$schema" command "$BIN_DIR/copilot-key"
    gsettings set "$schema" binding "['$SHORTCUT']"

    case "$list" in
        *"'$slot'"*) ;;
        *)
            if [ "$list" = "@as []" ] || [ "$list" = "[]" ]; then
                entry="['$slot']"
            else
                entry="${list%]}, '$slot']"
            fi
            gsettings set "$base" custom-list "$entry"
            ;;
    esac
    return 0
}

if command -v gsettings >/dev/null 2>&1 && gsettings list-schemas 2>/dev/null | grep -q '^org.cinnamon.desktop.keybindings$'; then
    if register_cinnamon; then
        ok "$(t shortcut_done)"
    else
        warn "$(t shortcut_no_slot)"
    fi
else
    warn "$(t shortcut_manual)"
    echo "$(t shortcut_combo "$SHORTCUT")"
    echo "$(t shortcut_command "$BIN_DIR/copilot-key")"
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
