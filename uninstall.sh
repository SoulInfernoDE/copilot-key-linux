#!/usr/bin/env bash
# copilot-key uninstaller - removes everything install.sh created.
# keyd itself is left installed; only our config file is removed.

set -euo pipefail

SRC="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=lib/i18n.sh
. "$SRC/lib/i18n.sh"

USER_BIN="$HOME/.local/bin"
USER_DATA="$HOME/.local/share/copilot-key"
USER_APPS="$HOME/.local/share/applications"
USER_AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/copilot-key-setup.desktop"
SYS_BIN="/usr/local/bin"
SYS_DATA="/usr/local/share/copilot-key"
SYS_APPS="/usr/local/share/applications"
SYS_AUTOSTART="/etc/xdg/autostart/copilot-key-setup.desktop"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/copilot-key"
KEYD_CONF="/etc/keyd/copilot.conf"
SHORTCUT_NAME="Copilot key"

info() { printf '\033[1;36m==\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ok\033[0m %s\n' "$*"; }

# Whatever is there goes - a machine may carry both a per-user install from
# before and a system-wide one from later.
info "$(t uninstall_launcher)"
rm -f "$USER_BIN/copilot-key" "$USER_BIN/copilot-sound" "$USER_BIN/copilot-config"
rm -f "$USER_APPS/copilot-key-config.desktop" "$USER_AUTOSTART"
rm -rf "$USER_DATA"
if [ -e "$SYS_BIN/copilot-key" ] || [ -d "$SYS_DATA" ] || [ -e "$SYS_AUTOSTART" ]; then
    sudo rm -f "$SYS_BIN/copilot-key" "$SYS_BIN/copilot-sound" "$SYS_BIN/copilot-config"
    sudo rm -f "$SYS_APPS/copilot-key-config.desktop" "$SYS_AUTOSTART"
    sudo rm -rf "$SYS_DATA"
    command -v update-desktop-database >/dev/null 2>&1 \
        && sudo update-desktop-database "$SYS_APPS" >/dev/null 2>&1 || true
fi
command -v update-desktop-database >/dev/null 2>&1 \
    && update-desktop-database "$USER_APPS" >/dev/null 2>&1 || true
ok "$(t uninstall_files_gone)"

read -rp "$(t uninstall_config_ask "$CONF_DIR")" answer
case "${answer:-N}" in
    [jJyY]*) rm -rf "$CONF_DIR"; ok "$(t uninstall_config_gone)" ;;
    *) ok "$(t uninstall_config_kept)" ;;
esac

info "$(t uninstall_keyd)"
if [ -f "$KEYD_CONF" ]; then
    sudo rm -f "$KEYD_CONF"
    sudo systemctl restart keyd || true
    ok "$(t uninstall_keyd_gone "$KEYD_CONF")"
fi

info "$(t uninstall_shortcut)"
base="org.cinnamon.desktop.keybindings"
path_base="/org/cinnamon/desktop/keybindings/custom-keybindings"
if command -v gsettings >/dev/null 2>&1 && gsettings list-schemas 2>/dev/null | grep -q "^$base\$"; then
    list="$(gsettings get "$base" custom-list 2>/dev/null || echo "[]")"
    i=0
    while [ $i -lt 20 ]; do
        schema="$base.custom-keybinding:$path_base/custom$i/"
        if [ "$(gsettings get "$schema" name 2>/dev/null)" = "'$SHORTCUT_NAME'" ]; then
            # Drop the slot from the list and reset the entry itself.
            new="$(python3 - "$list" "custom$i" <<'PY'
import ast, sys
raw, slot = sys.argv[1], sys.argv[2]
raw = raw.replace("@as ", "", 1).strip()
try:
    items = ast.literal_eval(raw)
except Exception:
    items = []
items = [x for x in items if x != slot]
print("[" + ", ".join(f"'{x}'" for x in items) + "]")
PY
)"
            gsettings set "$base" custom-list "$new"
            for key in name command binding; do
                gsettings reset "$schema" "$key" 2>/dev/null || true
            done
            ok "$(t uninstall_slot_freed "custom$i")"
            break
        fi
        i=$((i + 1))
    done
fi

echo
info "$(t uninstall_done)"
echo "$(t uninstall_other_users)"
