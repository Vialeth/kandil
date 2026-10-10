#!/usr/bin/env bash
# Kandil installer — https://github.com/Vialeth/kandil
# SPDX-License-Identifier: GPL-3.0-or-later
#
#   curl -fsSL https://raw.githubusercontent.com/Vialeth/kandil/main/install.sh | bash
#
# Running it again updates an existing installation.
# Options:
#   --yes              Do not ask questions, accept the defaults
#   --no-deps          Do not install missing packages
#   --shortcut KEYS    Global shortcut (default: Alt+Space, "none" to skip)
#   --keep-krunner     Do not take the shortcut away from KRunner
#   --deps-only        Only check and install the dependencies
set -euo pipefail

REPO="Vialeth/kandil"
BRANCH="main"
APP_ID="io.github.vialeth.Kandil"

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
APP_DIR="$DATA_HOME/kandil"
BIN_DIR="$HOME/.local/bin"
TOGGLE="$BIN_DIR/kandil-toggle"
UNIT_DIR="$CONFIG_HOME/systemd/user"
DBUS_DIR="$DATA_HOME/dbus-1/services"
DESKTOP_DIR="$DATA_HOME/applications"

ASSUME_YES=0
INSTALL_DEPS=1
SHORTCUT="Alt+Space"
TAKE_FROM_KRUNNER=1
DEPS_ONLY=0

# ── Messages ─────────────────────────────────────────────────────────
case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in tr*) TR=1 ;; *) TR=0 ;; esac
t() { if [ "$TR" = 1 ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }

if [ -t 1 ]; then
    B=$'\e[1m'; DIM=$'\e[2m'; RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; BLU=$'\e[34m'; R=$'\e[0m'
else
    B=""; DIM=""; RED=""; GRN=""; YEL=""; BLU=""; R=""
fi
step() { printf '%s==>%s %s%s%s\n' "$BLU" "$R" "$B" "$*" "$R"; }
ok()   { printf '  %s✓%s %s\n' "$GRN" "$R" "$*"; }
warn() { printf '  %s!%s %s\n' "$YEL" "$R" "$*"; }
die()  { printf '%s✗ %s%s\n' "$RED" "$*" "$R" >&2; exit 1; }

# Questions are read from the terminal, so they also work with "curl | bash".
ask() {
    local prompt="$1" default="$2" answer=""
    if [ "$ASSUME_YES" = 1 ] || ! { : </dev/tty; } 2>/dev/null; then
        [ "$default" = y ]; return
    fi
    local hint; hint=$([ "$default" = y ] && echo "[Y/n]" || echo "[y/N]")
    [ "$TR" = 1 ] && hint=$([ "$default" = y ] && echo "[E/h]" || echo "[e/H]")
    printf '  %s %s ' "$prompt" "$hint"
    read -r answer </dev/tty || answer=""
    case "${answer,,}" in
        "") [ "$default" = y ] ;;
        y|yes|e|evet) return 0 ;;
        *) return 1 ;;
    esac
}

usage() {
    cat <<'EOF'
Usage: install.sh [--yes] [--no-deps] [--shortcut KEYS] [--keep-krunner] [--deps-only]

  -y, --yes          Do not ask questions, accept the defaults
      --no-deps      Do not install missing packages
      --shortcut KEYS
                     Global shortcut (default: Alt+Space, "none" to skip)
      --keep-krunner Do not take the shortcut away from KRunner
      --deps-only    Only check and install the dependencies
  -h, --help         Show this help

Running the installer again updates an existing installation.
EOF
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes) ASSUME_YES=1 ;;
        --no-deps) INSTALL_DEPS=0 ;;
        --shortcut) SHORTCUT="${2:-}"; shift ;;
        --keep-krunner) TAKE_FROM_KRUNNER=0 ;;
        --deps-only) DEPS_ONLY=1 ;;
        -h|--help) usage ;;
        *) die "$(t "Unknown option: $1" "Bilinmeyen seçenek: $1")" ;;
    esac
    shift
done

printf '\n  %sKandil%s %s\n\n' "$B" "$R" "$(t "installer" "kurulumu")"

# ── 1. System checks ─────────────────────────────────────────────────
step "$(t "Checking the system" "Sistem denetleniyor")"
[ "$(id -u)" -ne 0 ] || die "$(t "Do not run as root; Kandil is installed for your user." \
                                "root olarak çalıştırmayın; Kandil kullanıcınız için kurulur.")"
command -v python3 >/dev/null || die "$(t "python3 is required." "python3 gerekli.")"
if [ "$DEPS_ONLY" = 0 ]; then
command -v systemctl >/dev/null && systemctl --user show-environment >/dev/null 2>&1 \
    || die "$(t "A systemd user session is required." "systemd kullanıcı oturumu gerekli.")"
command -v busctl >/dev/null || die "$(t "busctl (systemd) is required." "busctl (systemd) gerekli.")"

plasma_version=$(plasmashell --version 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)
if [ "${plasma_version:-0}" -ge 6 ]; then
    ok "KDE Plasma $(plasmashell --version 2>/dev/null | awk '{print $2}')"
else
    warn "$(t "KDE Plasma 6 was not found. Kandil is made for Plasma 6." \
              "KDE Plasma 6 bulunamadı. Kandil, Plasma 6 için yapıldı.")"
    ask "$(t "Continue anyway?" "Yine de devam edilsin mi?")" n || exit 1
fi
if [ "${XDG_SESSION_TYPE:-}" = wayland ]; then
    ok "Wayland"
else
    warn "$(t "This is not a Wayland session. Kandil needs Wayland to appear in the right place." \
              "Bu bir Wayland oturumu değil. Kandil'in doğru yerde açılması için Wayland gerekir.")"
fi
fi

# ── 2. Source files ──────────────────────────────────────────────────
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/src/kandil.py" ]; then
    SRC="$SCRIPT_DIR/src"
else
    step "$(t "Downloading Kandil" "Kandil indiriliyor")"
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    url="https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH"
    if command -v curl >/dev/null; then curl -fsSL "$url" | tar -xz -C "$TMP"
    elif command -v wget >/dev/null; then wget -qO- "$url" | tar -xz -C "$TMP"
    else die "$(t "curl or wget is required to download." "İndirmek için curl ya da wget gerekli.")"; fi
    SRC="$(find "$TMP" -maxdepth 2 -type d -name src | head -1)"
    [ -f "$SRC/kandil.py" ] || die "$(t "Download failed." "İndirme başarısız oldu.")"
    ok "github.com/$REPO"
fi

# ── 3. Dependencies ──────────────────────────────────────────────────
# Prints the missing components as keywords. The PySide6 and QML modules are read from the
# source files, so the check always matches what Kandil actually imports:
#   pyside6            PySide6 itself          pyside6:QtNetwork   one PySide6 module
#   qml:QtQuick.Effects one QML module         kwindowsystem       libKF6WindowSystem
#   qt>=6.9            Qt is too old
check_deps() {
    QT_QPA_PLATFORM=offscreen python3 -I - "$SRC" 2>/dev/null <<'PY' || echo "pyside6"
import ctypes, os, re, sys
src = sys.argv[1]
with open(os.path.join(src, "kandil.py"), encoding="utf-8") as f:
    py_modules = sorted(set(re.findall(r"^from PySide6\.(\w+) import", f.read(), re.M)))
qml_modules = set()
for name in ("Main.qml", "Settings.qml"):
    with open(os.path.join(src, name), encoding="utf-8") as f:
        qml_modules |= set(re.findall(r"^import\s+([A-Za-z][\w.]*)", f.read(), re.M))
# The KDE Qt Quick Controls style is loaded at run time, not imported
qml_modules.add("org.kde.desktop")
try:
    import shiboken6  # noqa: F401
    from PySide6.QtCore import QUrl, qVersion
except ImportError:
    print("pyside6"); sys.exit(0)
missing = []
for module in py_modules:
    try:
        __import__("PySide6." + module)
    except ImportError:
        missing.append("pyside6:" + module)
if missing:
    print(" ".join(missing)); sys.exit(0)
try:
    ctypes.CDLL("libKF6WindowSystem.so.6")
except OSError:
    missing.append("kwindowsystem")
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
app = QGuiApplication(sys.argv[:1])
engine = QQmlEngine()
for module in sorted(qml_modules):
    c = QQmlComponent(engine)
    c.setData(f"import QtQuick\nimport {module}\nItem {{}}".encode(), QUrl())
    if c.isError():
        missing.append("qml:" + module)
major, minor = (int(x) for x in qVersion().split(".")[:2])
if (major, minor) < (6, 9):
    missing.append("qt>=6.9")
print(" ".join(missing))
PY
}

# Candidate package names per package manager; the first one that exists is installed.
# Debian and Ubuntu split PySide6 and every QML module into own packages, named after the module.
candidates() {
    local pm="$1" key="$2" lower="${2,,}"
    case "$pm:$key" in
        dnf:pyside6|dnf:pyside6:*)        echo "python3-pyside6" ;;
        pacman:pyside6|pacman:pyside6:*)  echo "pyside6" ;;
        # openSUSE names Python packages after the interpreter version (python313-pyside6)
        zypper:pyside6|zypper:pyside6:*)  echo "$(python3 -c 'import sys; print("python%d%d" % sys.version_info[:2])')-pyside6 python3-pyside6" ;;
        apt:pyside6)              echo "python3-pyside6.qtcore" ;;
        apt:pyside6:*)            echo "python3-pyside6.${lower#pyside6:}" ;;
        dnf:kwindowsystem)        echo "kf6-kwindowsystem" ;;
        pacman:kwindowsystem)     echo "kwindowsystem" ;;
        zypper:kwindowsystem)     echo "kf6-kwindowsystem libKF6WindowSystem6" ;;
        apt:kwindowsystem)        echo "libkf6windowsystem6" ;;
        dnf:qml:Qt*)              echo "qt6-qtdeclarative" ;;
        pacman:qml:Qt*)           echo "qt6-declarative" ;;
        zypper:qml:Qt*)           echo "qt6-declarative-imports qt6-declarative" ;;
        dnf:qml:org.kde.milou)    echo "plasma-milou" ;;
        pacman:qml:org.kde.milou) echo "milou" ;;
        zypper:qml:org.kde.milou) echo "milou6 milou" ;;
        dnf:qml:org.kde.layershell|pacman:qml:org.kde.layershell) echo "layer-shell-qt" ;;
        zypper:qml:org.kde.layershell) echo "layer-shell-qt6-imports layer-shell-qt6" ;;
        dnf:qml:org.kde.kirigami) echo "kf6-kirigami" ;;
        pacman:qml:org.kde.kirigami) echo "kirigami" ;;
        zypper:qml:org.kde.kirigami) echo "kf6-kirigami-imports kf6-kirigami" ;;
        dnf:qml:org.kde.kquickcontrols) echo "kf6-kdeclarative" ;;
        pacman:qml:org.kde.kquickcontrols) echo "kdeclarative" ;;
        zypper:qml:org.kde.kquickcontrols) echo "kf6-kdeclarative-imports kf6-kdeclarative" ;;
        dnf:qml:org.kde.desktop|zypper:qml:org.kde.desktop) echo "kf6-qqc2-desktop-style" ;;
        pacman:qml:org.kde.desktop) echo "qqc2-desktop-style" ;;
        apt:qml:org.kde.desktop)  echo "qml6-module-org-kde-desktop kf6-qqc2-desktop-style" ;;
        apt:qml:org.kde.milou)    echo "qml6-module-org-kde-milou milou" ;;
        apt:qml:*)                key="${lower#qml:}"; echo "qml6-module-${key//./-}" ;;
    esac
}

pkg_exists() {
    case "$1" in
        dnf)    dnf -q info "$2" >/dev/null 2>&1 ;;
        pacman) pacman -Si "$2" >/dev/null 2>&1 ;;
        zypper) zypper -q info "$2" 2>/dev/null | grep -q "^Name" ;;
        apt)    apt-cache show "$2" >/dev/null 2>&1 ;;
    esac
}

install_packages() {
    local pm="$1"; shift
    case "$pm" in
        dnf)    sudo dnf install -y "$@" ;;
        pacman) sudo pacman -S --needed --noconfirm "$@" ;;
        zypper) sudo zypper --non-interactive install "$@" ;;
        apt)    sudo apt-get install -y "$@" ;;
    esac
}

step "$(t "Checking dependencies" "Bağımlılıklar denetleniyor")"
# Without PySide6 the QML modules cannot be checked yet, so checking and installing is repeated
# until nothing is missing (at most three rounds).
missing="$(check_deps)"
if [ -z "$missing" ]; then
    ok "$(t "All dependencies are installed" "Tüm bağımlılıklar kurulu")"
else
    pm=""
    for c in dnf pacman zypper apt-get; do command -v "$c" >/dev/null && { pm="${c%-get}"; break; }; done
    for round in 1 2 3; do
        warn "$(t "Missing:" "Eksik:") $missing"
        [[ " $missing " == *" qt>=6.9 "* ]] && die "$(t "Qt 6.9 or newer is required; please update your system." \
                                                        "Qt 6.9 ya da daha yeni bir sürüm gerekli; lütfen sisteminizi güncelleyin.")"
        [ "$INSTALL_DEPS" = 1 ] && [ -n "$pm" ] || die "$(t "Please install the missing components and run the installer again." \
                                                           "Lütfen eksik bileşenleri kurup kurulumu yeniden çalıştırın.")"
        packages=()
        for key in $missing; do
            found=""
            for cand in $(candidates "$pm" "$key"); do
                if pkg_exists "$pm" "${cand%%+*}"; then found="${cand//+/ }"; break; fi
            done
            [ -n "$found" ] || die "$(t "No package found for '$key'. Please install it manually." \
                                        "'$key' için paket bulunamadı. Lütfen elle kurun.")"
            # shellcheck disable=SC2206
            packages+=($found)
        done
        declare -A seen=(); unique=()
        for pkg in "${packages[@]}"; do [ -n "${seen[$pkg]:-}" ] || { seen[$pkg]=1; unique+=("$pkg"); }; done
        packages=("${unique[@]}"); unset seen
        printf '  %s%s%s\n' "$DIM" "${packages[*]}" "$R"
        ask "$(t "Install these packages with sudo?" "Bu paketler sudo ile kurulsun mu?")" y \
            || die "$(t "Cannot continue without the dependencies." "Bağımlılıklar olmadan devam edilemez.")"
        install_packages "$pm" "${packages[@]}"
        missing="$(check_deps)"
        [ -n "$missing" ] || break
    done
    [ -z "$missing" ] || die "$(t "Still missing:" "Hâlâ eksik:") $missing"
    ok "$(t "Dependencies installed" "Bağımlılıklar kuruldu")"
fi
[ "$DEPS_ONLY" = 0 ] || exit 0

# ── 4. Files ─────────────────────────────────────────────────────────
step "$(t "Installing Kandil" "Kandil kuruluyor")"
systemctl --user stop kandil.service >/dev/null 2>&1 || true
mkdir -p "$APP_DIR" "$BIN_DIR" "$UNIT_DIR" "$DBUS_DIR" "$DESKTOP_DIR"
rm -rf "$APP_DIR/i18n" "$APP_DIR/__pycache__"
cp "$SRC/kandil.py" "$SRC/Main.qml" "$SRC/Settings.qml" "$APP_DIR/"
cp -r "$SRC/i18n" "$APP_DIR/"
[ -f "$SRC/../uninstall.sh" ] && install -m 755 "$SRC/../uninstall.sh" "$APP_DIR/uninstall.sh"
ok "$APP_DIR"

cat > "$TOGGLE" <<EOF
#!/bin/sh
# Opens or closes Kandil. With --settings, opens the settings window;
# with other arguments, opens Kandil with that text.
dest=$APP_ID
case "\$1" in
    --settings) method=settings ;;
    "") method=toggle ;;
    *) method=query ;;
esac
if command -v busctl >/dev/null; then
    if [ \$method = query ]; then exec busctl --user call \$dest / \$dest query s "\$*"; fi
    exec busctl --user call \$dest / \$dest \$method
elif command -v gdbus >/dev/null; then
    if [ \$method = query ]; then exec gdbus call --session -d \$dest -o / -m \$dest.query "\$*" >/dev/null; fi
    exec gdbus call --session -d \$dest -o / -m \$dest.\$method >/dev/null
else
    if [ \$method = query ]; then exec qdbus6 \$dest / \$dest.query "\$*"; fi
    exec qdbus6 \$dest / \$dest.\$method
fi
EOF
chmod +x "$TOGGLE"
ok "$TOGGLE"

cat > "$UNIT_DIR/kandil.service" <<EOF
[Unit]
Description=Kandil launcher
Documentation=https://github.com/$REPO
PartOf=graphical-session.target
After=graphical-session.target plasma-plasmashell.service

[Service]
Type=dbus
BusName=$APP_ID
ExecStart=/usr/bin/env python3 -I $APP_DIR/kandil.py
Restart=on-failure
RestartSec=2

[Install]
WantedBy=graphical-session.target
EOF

cat > "$DBUS_DIR/$APP_ID.service" <<EOF
[D-BUS Service]
Name=$APP_ID
Exec=/usr/bin/env python3 -I $APP_DIR/kandil.py
SystemdService=kandil.service
EOF

cat > "$DESKTOP_DIR/kandil.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Kandil
GenericName=Launcher
GenericName[tr]=Başlatıcı
Comment=Open or close Kandil
Comment[tr]=Kandil'i aç/kapat
Icon=search
Exec=$TOGGLE
NoDisplay=true
StartupNotify=false
X-KDE-Shortcuts=$SHORTCUT
EOF
# The settings window as an application, so that it can be found in Kandil, KRunner and the
# application menu. The names come from the translation files.
{
    echo "[Desktop Entry]"
    echo "Type=Application"
    python3 -I - "$APP_DIR/i18n" <<'PY'
import json, os, sys
d = sys.argv[1]
names = {}
for f in sorted(os.listdir(d)):
    if f.endswith(".json"):
        with open(os.path.join(d, f), encoding="utf-8") as fh:
            names[f[:-5]] = json.load(fh).get("settings.title", "")
print("Name=" + names.get("en", "Kandil Settings"))
for code, name in names.items():
    if code != "en" and name and name != names.get("en"):
        print(f"Name[{code}]={name}")
PY
    echo "Comment=Configure the Kandil launcher"
    echo "Comment[tr]=Kandil başlatıcısını yapılandır"
    echo "Keywords=kandil;launcher;settings;preferences;configure;options;"
    echo "Keywords[tr]=kandil;başlatıcı;ayarlar;tercihler;yapılandır;seçenekler;"
    echo "Icon=configure"
    echo "Exec=$TOGGLE --settings"
    echo "Categories=Settings;"
    echo "StartupNotify=false"
} > "$DESKTOP_DIR/kandil-settings.desktop"

# Let KDE index the new .desktop file now, so that it does not reset the shortcut later
command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 >/dev/null 2>&1 || true
ok "$(t "Service, D-Bus activation and shortcut entry" "Servis, D-Bus etkinleştirme ve kısayol girdisi")"

systemctl --user daemon-reload
# restart, not just start: an update must replace the running version
systemctl --user enable kandil.service >/dev/null 2>&1
systemctl --user restart kandil.service >/dev/null 2>&1 \
    || die "$(t "The service could not be started. See: journalctl --user -u kandil" \
                "Servis başlatılamadı. Bakınız: journalctl --user -u kandil")"
for _ in 1 2 3 4 5 6 7 8 9 10; do
    busctl --user status "$APP_ID" >/dev/null 2>&1 && break
    sleep 0.5
done
busctl --user status "$APP_ID" >/dev/null 2>&1 \
    || die "$(t "Kandil did not start. See: journalctl --user -u kandil" \
                "Kandil başlamadı. Bakınız: journalctl --user -u kandil")"
ok "$(t "Kandil is running" "Kandil çalışıyor")"

# ── 5. Global shortcut ───────────────────────────────────────────────
step "$(t "Setting up the shortcut" "Kısayol ayarlanıyor")"
if [ -z "$SHORTCUT" ] || [ "$SHORTCUT" = none ]; then
    warn "$(t "No shortcut set. You can assign one later in Kandil's settings." \
              "Kısayol atanmadı. Daha sonra Kandil ayarlarından atayabilirsiniz.")"
else
    take=()
    if [ "$TAKE_FROM_KRUNNER" = 1 ]; then
        krunner_keys="$(kreadconfig6 --file kglobalshortcutsrc --group services \
                         --group org.kde.krunner.desktop --key _launch 2>/dev/null || true)"
        # Never changed: KRunner's defaults apply
        [ -n "$krunner_keys" ] || krunner_keys=$'Alt+Space\tAlt+F2\tSearch'
        if [[ $'\t'"$krunner_keys"$'\t' == *$'\t'"$SHORTCUT"$'\t'* ]]; then
            if ask "$(t "$SHORTCUT currently opens KRunner. Give it to Kandil? (Alt+F2 keeps opening KRunner)" \
                        "$SHORTCUT şu an KRunner'ı açıyor. Kandil'e verilsin mi? (Alt+F2 KRunner'ı açmaya devam eder)")" y; then
                take=(--take-from-krunner)
            fi
        fi
    fi
    if python3 -I "$APP_DIR/kandil.py" --set-shortcut "$SHORTCUT" "${take[@]}" >/dev/null; then
        ok "$SHORTCUT"
    else
        warn "$(t "$SHORTCUT could not be assigned; it is probably used by another application. Choose one in Kandil's settings." \
                  "$SHORTCUT atanamadı; büyük olasılıkla başka bir uygulama kullanıyor. Kandil ayarlarından başka bir kısayol seçin.")"
    fi
fi

# ── Done ─────────────────────────────────────────────────────────────
version="$(python3 -I "$APP_DIR/kandil.py" --version)"
printf '\n  %s%sKandil %s %s%s\n\n' "$GRN" "$B" "$version" "$(t "is ready." "hazır.")" "$R"
if [ -n "$SHORTCUT" ] && [ "$SHORTCUT" != none ]; then
    printf '  %s\n' "$(t "Press $SHORTCUT to open it." "Açmak için $SHORTCUT tuşlarına basın.")"
fi
printf '  %s\n' "$(t "Type ? in the search field for prefixes, shortcuts and settings." \
                     "Önekler, kısayollar ve ayarlar için arama alanına ? yazın.")"
printf '  %s%s %s%s\n\n' "$DIM" "$(t "To uninstall:" "Kaldırmak için:")" "$APP_DIR/uninstall.sh" "$R"
