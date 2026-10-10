#!/usr/bin/env bash
# Kandil uninstaller — https://github.com/Vialeth/kandil
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Removes everything Kandil installed: the program, its service, D-Bus and
# shortcut entries, cache, settings and history. The global shortcut is given back
# to KRunner. System packages (PySide6, Qt, KDE libraries) are left alone,
# because other applications may use them.
#
#   ~/.local/share/kandil/uninstall.sh
#   curl -fsSL https://raw.githubusercontent.com/Vialeth/kandil/main/uninstall.sh | bash
set -euo pipefail

APP_ID="io.github.vialeth.Kandil"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
APP_DIR="$DATA_HOME/kandil"

ASSUME_YES=0
KEEP_DATA=0

case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in tr*) TR=1 ;; *) TR=0 ;; esac
t() { if [ "$TR" = 1 ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }

if [ -t 1 ]; then
    B=$'\e[1m'; DIM=$'\e[2m'; RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; BLU=$'\e[34m'; R=$'\e[0m'
else
    B=""; DIM=""; RED=""; GRN=""; YEL=""; BLU=""; R=""
fi
step() { printf '%s==>%s %s%s%s\n' "$BLU" "$R" "$B" "$*" "$R"; }
ok()   { printf '  %s✓%s %s\n' "$GRN" "$R" "$*"; }
skip() { printf '  %s·%s %s%s%s\n' "$DIM" "$R" "$DIM" "$*" "$R"; }
die()  { printf '%s✗ %s%s\n' "$RED" "$*" "$R" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: uninstall.sh [--yes] [--keep-data]

  -y, --yes        Do not ask for confirmation
      --keep-data  Keep settings (~/.config/kandil) and history (~/.local/state/kandil)
  -h, --help       Show this help
EOF
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes) ASSUME_YES=1 ;;
        --keep-data) KEEP_DATA=1 ;;
        -h|--help) usage ;;
        *) die "$(t "Unknown option: $1" "Bilinmeyen seçenek: $1")" ;;
    esac
    shift
done

[ "$(id -u)" -ne 0 ] || die "$(t "Do not run as root." "root olarak çalıştırmayın.")"

# Removes a file or folder and reports it; reports nothing to do if it is absent.
remove() {
    if [ -e "$1" ] || [ -L "$1" ]; then
        rm -rf -- "$1"
        ok "$1"
    else
        skip "$1"
    fi
}

printf '\n  %sKandil%s %s\n\n' "$B" "$R" "$(t "uninstaller" "kaldırma")"

if [ "$KEEP_DATA" = 1 ]; then
    summary="$(t "Kandil will be removed. Your settings and history will be kept." \
                 "Kandil kaldırılacak. Ayarlarınız ve geçmişiniz korunacak.")"
else
    summary="$(t "Kandil will be removed together with its settings and history." \
                 "Kandil, ayarları ve geçmişiyle birlikte kaldırılacak.")"
fi
printf '  %s\n' "$summary"
if [ "$ASSUME_YES" != 1 ] && { : </dev/tty; } 2>/dev/null; then
    printf '  %s ' "$(t "Continue? [y/N]" "Devam edilsin mi? [e/H]")"
    read -r answer </dev/tty || answer=""
    case "${answer,,}" in y|yes|e|evet) ;; *) printf '  %s\n\n' "$(t "Cancelled." "İptal edildi.")"; exit 0 ;; esac
fi
echo

# ── 1. Service ───────────────────────────────────────────────────────
step "$(t "Stopping the service" "Servis durduruluyor")"
if systemctl --user cat kandil.service >/dev/null 2>&1; then
    systemctl --user disable --now kandil.service >/dev/null 2>&1 || true
    ok "kandil.service"
else
    skip "kandil.service"
fi
pkill -f "$APP_DIR/kandil.py" 2>/dev/null || true

# ── 2. Global shortcut (given back to KRunner) ───────────────────────
step "$(t "Removing the shortcut" "Kısayol kaldırılıyor")"
if [ -f "$APP_DIR/kandil.py" ] && command -v python3 >/dev/null; then
    given_back="$(python3 -I "$APP_DIR/kandil.py" --release-shortcut 2>/dev/null || true)"
    if [ -n "$given_back" ]; then
        ok "$(t "Given back to KRunner:" "KRunner'a geri verildi:") ${given_back//$'\t'/, }"
    else
        ok "$(t "Kandil's shortcut removed" "Kandil'in kısayolu kaldırıldı")"
    fi
else
    # The program is already gone: clean up the shortcut entry directly.
    busctl --user call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel \
        unregister ss kandil.desktop _launch >/dev/null 2>&1 || true
    kwriteconfig6 --file kglobalshortcutsrc --group services --group kandil.desktop \
        --key _launch --delete 2>/dev/null || true
    ok "$(t "Shortcut entry removed" "Kısayol girdisi kaldırıldı")"
fi

# ── 3. Files ─────────────────────────────────────────────────────────
step "$(t "Removing files" "Dosyalar siliniyor")"
remove "$CONFIG_HOME/systemd/user/kandil.service"
remove "$CONFIG_HOME/systemd/user/graphical-session.target.wants/kandil.service"
remove "$DATA_HOME/dbus-1/services/$APP_ID.service"
remove "$DATA_HOME/applications/kandil.desktop"
remove "$DATA_HOME/applications/kandil-settings.desktop"
remove "$HOME/.local/bin/kandil-toggle"
remove "$APP_DIR"
remove "$CACHE_HOME/kandil"          # Qt's QML and graphics pipeline cache
systemctl --user daemon-reload 2>/dev/null || true
command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 >/dev/null 2>&1 || true

# ── 4. User data ─────────────────────────────────────────────────────
if [ "$KEEP_DATA" = 1 ]; then
    step "$(t "Keeping your data" "Verileriniz korunuyor")"
    skip "$CONFIG_HOME/kandil"
    skip "$STATE_HOME/kandil"
else
    step "$(t "Removing settings and history" "Ayarlar ve geçmiş siliniyor")"
    remove "$CONFIG_HOME/kandil"
    remove "$STATE_HOME/kandil"
fi

printf '\n  %s%s%s%s\n' "$GRN" "$B" "$(t "Kandil has been removed." "Kandil kaldırıldı.")" "$R"
printf '  %s%s%s\n\n' "$DIM" "$(t "KRunner works as before. System packages were not touched." \
                                  "KRunner eskisi gibi çalışıyor. Sistem paketlerine dokunulmadı.")" "$R"
