#!/usr/bin/env python3
"""Kandil — KRunner motorunu kullanan, arka planda bekleyen başlatıcı arayüzü.

SPDX-License-Identifier: GPL-3.0-or-later
https://github.com/Vialeth/kandil

D-Bus: io.github.vialeth.Kandil  /  toggle() | show() | hide() | query(s) | settings()

Komut satırı (kurulum/kaldırma betikleri kullanır):
  kandil.py --set-shortcut "Alt+Space" [--take-from-krunner]
  kandil.py --release-shortcut
  kandil.py --version
"""
import copy
import ctypes
import gettext
import glob
import hashlib
import html
import json
import os
import re
import shlex
import struct
import subprocess
import sys
import threading
import time
import unicodedata
import zlib

import shiboken6
from PySide6.QtCore import (ClassInfo, QDir, QFileInfo, QFileSystemWatcher, QLibraryInfo, QLocale, QMargins,
                            QMimeDatabase, QObject, QPluginLoader, QProcess, QRect, QSettings, QStandardPaths,
                            Qt, QTimer, QUrl, Signal, Slot)
from PySide6.QtGui import QDesktopServices, QIcon, QImage, QImageReader, QKeySequence, QRegion
from PySide6.QtDBus import QDBusConnection, QDBusInterface
from PySide6.QtNetwork import QNetworkAccessManager, QNetworkReply, QNetworkRequest
from PySide6.QtQml import QQmlApplicationEngine, QQmlComponent, QQmlEngine
from PySide6.QtWidgets import QApplication

VERSION = "1.0"
SERVICE = "io.github.vialeth.Kandil"
HERE = os.path.dirname(os.path.abspath(__file__))
I18N_DIR = os.path.join(HERE, "i18n")
STATE_DIR = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "kandil")
HISTORY_FILE = os.path.join(STATE_DIR, "history.json")
EMOJI_RECENT_FILE = os.path.join(STATE_DIR, "emoji.json")
HISTORY_LIMIT = 200
HOME = os.path.expanduser("~")
CONFIG_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "kandil")
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.json")
CACHE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "kandil")
FAVICON_DIR = os.path.join(CACHE_DIR, "favicons")
SHORTCUTS_FILE = "kglobalshortcutsrc"
DESKTOP_ID = "kandil.desktop"
RTL_LANGUAGES = {"ar", "fa", "he"}

# Yerleşik modlar. Önek harfleri dilden bağımsızdır; adları çeviri dosyasından ("mode.<id>") gelir.
BUILTIN_MODES = [
    {"id": "files", "key": "f", "runner": "baloosearch", "icon": "folder-documents"},
    {"id": "browse", "key": "ff", "runner": ":browse", "icon": "folder-open"},
    {"id": "windows", "key": "w", "runner": "windows", "icon": "window"},
    {"id": "apps", "key": "a", "runner": "krunner_services", "icon": "applications-all"},
    {"id": "settings", "key": "ss", "runner": "krunner_systemsettings", "icon": "preferences-system"},
    {"id": "web", "key": "s", "runner": ":web", "icon": "internet-web-browser"},
    {"id": "calc", "key": "=", "runner": "calculator", "icon": "accessories-calculator"},
    {"id": "emoji", "key": "e", "runner": ":emoji", "icon": "preferences-desktop-emoticons"},
    {"id": "clipboard", "key": "c", "runner": ":clipboard", "icon": "klipper"},
    {"id": "command", "key": ">", "runner": ":command", "icon": "utilities-terminal"},
]

# Web araması (Brave Search). Sonuçlar sayfaya gömülü veri bloğundan okunur; bu blok
# Brave Search API'siyle aynı alan adlarını (title, url, description) kullanır.
WEB_SEARCH_URL = "https://search.brave.com/search"
WEB_USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"
WEB_RESULT_LIMIT = 10
_JS_STR = r'"((?:[^"\\]|\\.)*)"'
BRAVE_RESULT_RE = re.compile(r"\{title:" + _JS_STR + r",url:" + _JS_STR
                             + r",(?:full_title:[^,]*,)?description:(?:" + _JS_STR + r"|void 0)")
BRAVE_FAVICON_RE = re.compile(r'data-type="web".*?<a href="([^"]+)".*?<img[^>]*?'
                              r'src="(https://imgs\.search\.brave\.com/[^"]+)"', re.S)
TAG_RE = re.compile(r"<[^>]+>")

# Anahtar kelimeyle çalışan arama motorları ("gg ubuntu"). Adresteki %s arama terimiyle değiştirilir.
DEFAULT_SEARCH_ENGINES = [
    {"id": "google", "key": "gg", "name": "Google", "url": "https://www.google.com/search?q=%s"},
    {"id": "youtube", "key": "yt", "name": "YouTube", "url": "https://www.youtube.com/results?search_query=%s"},
    {"id": "wikipedia", "key": "wiki", "name": "Wikipedia", "url": "https://en.wikipedia.org/w/index.php?search=%s"},
    {"id": "maps", "key": "maps", "name": "Google Maps", "url": "https://www.google.com/maps/search/%s"},
    {"id": "amazon", "key": "ama", "name": "Amazon", "url": "https://www.amazon.com/s?k=%s"},
    {"id": "ebay", "key": "eb", "name": "eBay", "url": "https://www.ebay.com/sch/i.html?_nkw=%s"},
    {"id": "github", "key": "gh", "name": "GitHub", "url": "https://github.com/search?q=%s"},
    {"id": "duckduckgo", "key": "ddg", "name": "DuckDuckGo", "url": "https://duckduckgo.com/?q=%s"},
]

# Klasör gezgini ("ff"). Ad aramaları için ev dizini ve bağlı diskler bu derinliğe kadar taranır.
BROWSE_SKIP = {"node_modules", "__pycache__", "venv", ".venv", "site-packages", "dist-packages"}
BROWSE_DEPTH = 6
BROWSE_LIMIT = 300
BROWSE_SEARCH_LIMIT = 40
BROWSE_INDEX_TTL = 120          # saniye; daha eski dizin mod açılınca yenilenir

# Emoji seçici ("e"). Veriler Plasma'nın emoji seçicisinin (plasma-emojier) dil sözlüklerinden,
# kategori ve ten rengi adları onun çeviri kataloğundan okunur.
EMOJI_CATEGORIES = {1: "Smileys and Emotion", 2: "People and Body", 3: "Component", 4: "Animals and Nature",
                    5: "Food and Drink", 6: "Travel and Places", 7: "Activities", 8: "Objects", 9: "Symbols",
                    10: "Flags"}
EMOJI_LANG_FILES = {"zh_CN": "zh", "zh_TW": "zh_Hant", "pt_BR": "pt", "nb": "no"}
EMOJI_TONES = "\U0001F3FB\U0001F3FC\U0001F3FD\U0001F3FE\U0001F3FF"
EMOJI_TONE_RE = re.compile("[" + EMOJI_TONES + "]")
EMOJI_LIMIT = 80
EMOJI_RECENT_LIMIT = 24

# Ayar dosyasında olmayan anahtarlar bu değerlerle tamamlanır.
DEFAULT_CONFIG = {
    "language": "system",
    # Görünüm
    "panelWidth": 720,
    "previewEnabled": True,
    "previewWidth": 320,
    "rowHeight": 52,
    "iconSize": 32,
    "searchFontSize": 21,
    "maxVisibleRows": 8,
    "topRatio": 0.22,
    "cardRadius": 14,
    "cardOpacity": 0.80,
    "blur": True,
    "shadow": True,
    "accentColor": "",
    "showFooter": True,
    "showSectionHeaders": True,
    "heroCard": True,
    # Animasyon
    "animationDuration": 260,
    "openAnimation": True,
    # Davranış
    "closeOnFocusLoss": True,
    "hoverSelect": True,
    "rememberQuery": False,
    "historyEnabled": True,
    "historyCount": 6,
    "emojiSkinTone": 0,          # 0 nötr, 1–5 açıktan koyuya
    "resultLimit": 25,
    # Komutlar
    "commandTimeout": 10,
    "commandShell": "/bin/bash",
    "terminalCommand": "konsole --hold -e",
    # Önekler
    "helpKey": "?",
    "modes": [dict(m, enabled=True) for m in BUILTIN_MODES],
    # Arama motorları
    "searchEngines": [dict(e, enabled=True) for e in DEFAULT_SEARCH_ENGINES],
}

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
COMMAND_OUTPUT_LIMIT = 200_000


# ── Ayarlar ──────────────────────────────────────────────────────────
def merge_modes(user_modes):
    """Kullanıcının mod listesini yerleşik modlarla birleştirir: yerleşiklerde yalnızca
    önek ve etkinlik kullanıcıdan alınır, özel modlar olduğu gibi korunur."""
    by_id = {m.get("id"): m for m in user_modes if isinstance(m, dict) and m.get("id")}
    # Web modu "s" önekini aldığında Sistem Ayarları eski varsayılanı "s"'den "ss"'ye geçer
    if by_id and "web" not in by_id and by_id.get("settings", {}).get("key") == "s":
        by_id["settings"] = dict(by_id["settings"], key="ss")
    merged = []
    for b in BUILTIN_MODES:
        u = by_id.pop(b["id"], {})
        merged.append(dict(b, key=str(u.get("key", b["key"])), enabled=bool(u.get("enabled", True))))
    for m in by_id.values():
        if m.get("runner") and m.get("key"):
            merged.append({"id": m["id"], "key": str(m["key"]), "runner": m["runner"],
                           "icon": m.get("icon", "search"), "label": m.get("label", m["runner"]),
                           "enabled": bool(m.get("enabled", True)), "custom": True})
    return merged


def clean_engines(engines):
    """Ayar dosyasındaki arama motorlarından eksik ya da bozuk olanları ayıklar."""
    out = []
    for i, e in enumerate(engines):
        if not isinstance(e, dict):
            continue
        key, url = str(e.get("key", "")).strip(), str(e.get("url", "")).strip()
        if not key or not url.startswith(("http://", "https://")):
            continue
        out.append({"id": str(e.get("id") or f"engine-{i}"), "key": key, "name": str(e.get("name") or key),
                    "url": url, "enabled": bool(e.get("enabled", True))})
    return out


def migrate_prefixes(old):
    """Eski "prefixes" biçimini (önek → eklenti) yeni "modes" listesine çevirir."""
    modes = [dict(m, enabled=False) for m in BUILTIN_MODES]
    for key, entry in old.items():
        for m in modes:
            if isinstance(entry, dict) and entry.get("runner") == m["runner"]:
                m.update(key=key, enabled=True)
    return modes


def write_config(config):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    tmp = CONFIG_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(config, f, ensure_ascii=False, indent=2)
    os.replace(tmp, CONFIG_FILE)


def load_config():
    config = copy.deepcopy(DEFAULT_CONFIG)
    if not os.path.exists(CONFIG_FILE):
        write_config(config)
        return config
    try:
        with open(CONFIG_FILE, encoding="utf-8") as f:
            user = json.load(f)
    except (OSError, ValueError) as e:
        print(f"Ayar dosyası okunamadı, varsayılanlar kullanılıyor: {e}", file=sys.stderr)
        return config
    if "prefixes" in user and "modes" not in user:
        user["modes"] = migrate_prefixes(user.pop("prefixes"))
        write_config({**config, **{k: v for k, v in user.items() if k in config}})
    for key, value in user.items():
        if key not in config:
            continue
        if type(value) is not type(config[key]) and not (
                isinstance(value, (int, float)) and isinstance(config[key], (int, float))):
            print(f"Ayar yok sayıldı (tür uyumsuz): {key}", file=sys.stderr)
            continue
        config[key] = value
    config["modes"] = merge_modes(config["modes"])
    config["searchEngines"] = clean_engines(config["searchEngines"])
    return config


# ── Web araması ──────────────────────────────────────────────────────
def _js_string(s):
    try:
        return json.loads('"' + s + '"')
    except ValueError:
        return s


def _plain(s):
    return " ".join(html.unescape(TAG_RE.sub("", s)).split())


def parse_brave(page, limit=WEB_RESULT_LIMIT):
    start = page.find('web:{type:"search"')
    if start < 0:
        return []
    favicons = {html.unescape(u): f for u, f in BRAVE_FAVICON_RE.findall(page)}
    out, seen = [], set()
    for m in BRAVE_RESULT_RE.finditer(page, start):
        # Haber, video gibi diğer bloklar da aynı alanlara sahip; yalnızca web sonuçları alınır
        nxt = page.find("{title:", m.end())
        if 'type:"search_result"' not in page[m.end():nxt if nxt > 0 else None]:
            continue
        url = _js_string(m.group(2))
        if url in seen or not url.startswith(("http://", "https://")):
            continue
        seen.add(url)
        out.append({"title": _plain(_js_string(m.group(1))), "url": url,
                    "description": _plain(_js_string(m.group(3) or "")), "favicon": favicons.get(url, "")})
        if len(out) >= limit:
            break
    return out


def web_search_url(query):
    url = QUrl(WEB_SEARCH_URL)
    url.setQuery("q=" + QUrl.toPercentEncoding(query).data().decode() + "&source=web")
    return url


# ── Emoji ────────────────────────────────────────────────────────────
def read_emoji_dict(path):
    """plasma-emojier sözlüğü: qCompress + küçük endian (adet; emoji, ad, kategori, [anahtar kelimeler])."""
    with open(path, "rb") as f:
        raw = zlib.decompress(f.read()[4:])
    pos = 0

    def u32():
        nonlocal pos
        pos += 4
        return struct.unpack_from("<I", raw, pos - 4)[0]

    def text():
        nonlocal pos
        n = u32()
        pos += n
        return raw[pos - n:pos].decode("utf-8", errors="replace")

    out = []
    for _ in range(u32()):
        glyph, name, category = text(), text(), u32()
        out.append((glyph, name, category, [text() for _ in range(u32())]))
    return out


def emoji_dict_path(lang):
    base = QStandardPaths.locate(QStandardPaths.GenericDataLocation, "plasma/emoji", QStandardPaths.LocateDirectory)
    if not base:
        return ""
    for name in (lang, EMOJI_LANG_FILES.get(lang), lang.split("_")[0], "en"):
        if name and os.path.exists(os.path.join(base, name + ".dict")):
            return os.path.join(base, name + ".dict")
    return ""


def load_emoji(lang):
    """Ana emojiler (ten rengi varyantları ana emojiye bağlanır), arama için katlanmış anahtar kelimelerle."""
    local = read_emoji_dict(emoji_dict_path(lang)) if emoji_dict_path(lang) else []
    english = {} if lang.startswith("en") else {
        g: [n] + a for g, n, _, a in read_emoji_dict(emoji_dict_path("en"))} if emoji_dict_path("en") else {}
    entries, by_key = [], {}
    for glyph, name, category, annotations in local:
        if EMOJI_TONE_RE.search(glyph):
            continue
        words = [name] + annotations + english.get(glyph, [])
        e = {"glyph": glyph, "name": name, "category": category, "annotations": annotations,
             "keys": [fold(w) for w in words], "tones": {}}
        entries.append(e)
        by_key[glyph.replace("\uFE0F", "")] = e
    for glyph, *_ in local:
        tones = set(EMOJI_TONE_RE.findall(glyph))
        if len(tones) == 1:
            base = by_key.get(EMOJI_TONE_RE.sub("", glyph).replace("\uFE0F", ""))
            if base is not None:
                base["tones"][EMOJI_TONES.index(tones.pop()) + 1] = glyph
    return entries


def emoji_score(e, words):
    """Her kelime adda ya da anahtar kelimelerde geçmeli; küçük puan daha iyi."""
    total = 0
    for w in words:
        best = None
        for i, k in enumerate(e["keys"]):
            if k == w:
                score = 0 if i == 0 else 3
            elif k.startswith(w):
                score = 1 if i == 0 else 4
            elif (" " + w) in (" " + k):
                score = 2 if i == 0 else 5
            elif len(w) >= 4 and w in k:          # kısa sorgularda kelime içi eşleşme gürültü üretir
                score = 6
            else:
                continue
            best = score if best is None else min(best, score)
        if best is None:
            return None
        total += best
    return total


# ── Çeviriler ────────────────────────────────────────────────────────
def available_languages():
    langs = []
    for path in sorted(glob.glob(os.path.join(I18N_DIR, "*.json"))):
        code = os.path.basename(path)[:-5]
        try:
            with open(path, encoding="utf-8") as f:
                langs.append({"code": code, "name": json.load(f).get("_name", code)})
        except (OSError, ValueError):
            pass
    return langs


# Sistem dili, LANGUAGE değişkeni Kandil tarafından değiştirilmeden önce saklanır.
SYSTEM_UI_LANGUAGES = []


def env_ui_languages():
    # QLocale.system() burada kullanılmaz: Qt sistem yerel ayarını ilk okumada önbelleğe alır,
    # sonradan LANGUAGE değiştirilse bile KRunner eklentileri ve ksycoca eski dilde kalır.
    names = [n for n in os.environ.get("LANGUAGE", "").split(":") if n]
    for var in ("LC_ALL", "LC_MESSAGES", "LANG"):
        value = os.environ.get(var, "")
        if value:
            names.append(value)
            break
    return [n.split(".")[0].split("@")[0] for n in names if n not in ("C", "POSIX")]


def resolve_language(setting):
    codes = {l["code"] for l in available_languages()}
    candidates = [setting] if setting and setting != "system" else []
    for name in SYSTEM_UI_LANGUAGES or QLocale.system().uiLanguages():
        name = name.replace("-", "_")
        candidates += [name, name.split("_")[0]]
    for c in candidates:
        if c in codes:
            return c
    return "en"


def load_strings(lang):
    strings = {}
    for code in ("en", lang):
        try:
            with open(os.path.join(I18N_DIR, code + ".json"), encoding="utf-8") as f:
                strings.update(json.load(f))
        except (OSError, ValueError):
            pass
    return strings


# ── Pencere bölgesi ──────────────────────────────────────────────────
# KWindowEffects::enableBlurBehind(QWindow*, bool, const QRegion&) — KF6'nın Python bağlaması yok.
_kwin = ctypes.CDLL("libKF6WindowSystem.so.6")
_enable_blur = _kwin._ZN14KWindowEffects16enableBlurBehindEP7QWindowbRK7QRegion
_enable_blur.argtypes = [ctypes.c_void_p, ctypes.c_bool, ctypes.c_void_p]
_enable_blur.restype = None


def rounded_region(x, y, w, h, r):
    r = max(0, min(r, w // 2, h // 2))
    region = QRegion(x + r, y, w - 2 * r, h) + QRegion(x, y + r, w, h - 2 * r)
    for cx, cy in ((x, y), (x + w - 2 * r, y), (x, y + h - 2 * r), (x + w - 2 * r, y + h - 2 * r)):
        region += QRegion(QRect(cx, cy, 2 * r, 2 * r), QRegion.Ellipse)
    return region


# ── Geçmiş ───────────────────────────────────────────────────────────
class History:
    """Çalıştırılan sonuçlar: son kullanılanlar ve sık kullanılanlar için."""

    # Sorgunun kendisinden üretilen ve tekrar çalıştırmanın anlamsız olduğu sonuçlar
    SKIP_PREFIXES = ("calculator_", "unitconverter")

    def __init__(self):
        self.entries = {}
        try:
            with open(HISTORY_FILE, encoding="utf-8") as f:
                self.entries = {e["id"]: e for e in json.load(f)}
        except (OSError, ValueError, KeyError):
            pass

    def save(self):
        os.makedirs(STATE_DIR, exist_ok=True)
        tmp = HISTORY_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(list(self.entries.values()), f, ensure_ascii=False, indent=1)
        os.replace(tmp, HISTORY_FILE)

    def record(self, query, match_id, display, subtext, icon, category):
        if not match_id or match_id.startswith(self.SKIP_PREFIXES):
            return
        e = self.entries.get(match_id, {"id": match_id, "count": 0})
        e.update(query=query, display=display, subtext=subtext, category=category,
                 icon=icon or e.get("icon", ""), last=time.time())
        e["count"] += 1
        self.entries[match_id] = e
        if len(self.entries) > HISTORY_LIMIT:
            oldest = sorted(self.entries.values(), key=lambda x: (x["count"], x["last"]))
            for old in oldest[: len(self.entries) - HISTORY_LIMIT]:
                del self.entries[old["id"]]
        self.save()

    def remove(self, match_id):
        if self.entries.pop(match_id, None):
            self.save()

    def clear(self):
        self.entries = {}
        self.save()

    def listing(self, total, recent_title, frequent_title):
        recent_max = (total + 1) // 2
        by_recent = sorted(self.entries.values(), key=lambda e: e["last"], reverse=True)
        recent_ids = {e["id"] for e in by_recent[:recent_max]}
        frequent = [e for e in sorted(self.entries.values(), key=lambda e: (e["count"], e["last"]), reverse=True)
                    if e["id"] not in recent_ids and e["count"] >= 2][: total - recent_max]
        freq_ids = {e["id"] for e in frequent}
        recent = [e for e in by_recent if e["id"] not in freq_ids][: total - len(frequent)]

        def row(e, section):
            return {"matchId": e["id"], "query": e["query"], "display": e["display"],
                    "subtext": e.get("subtext", ""), "decoration": e.get("icon", ""),
                    "origCategory": e.get("category", ""), "category": section}
        return [row(e, recent_title) for e in recent] + [row(e, frequent_title) for e in frequent]


def tilde(path):
    return "~" + path[len(HOME):] if path == HOME or path.startswith(HOME + "/") else path


def file_info(url, locale):
    """Önizleme paneli için dosya/klasör bilgisi."""
    path = QUrl(url).toLocalFile()
    fi = QFileInfo(path)
    if not path or not fi.exists():
        return {"exists": False}
    mime = QMimeDatabase().mimeTypeForFile(fi)
    info = {
        "exists": True,
        "url": QUrl.fromLocalFile(path).toString(),
        "name": fi.fileName() or path,
        "location": tilde(fi.absolutePath()),
        "isDir": fi.isDir(),
        "mime": mime.comment(),
        "icon": mime.iconName() or mime.genericIconName() or "unknown",
        "modified": locale.toString(fi.lastModified(), QLocale.LongFormat),
        "kind": "other",
        "size": "",
        "text": "",
        "entries": [],
        "entryCount": 0,
    }
    if fi.isDir():
        info["kind"] = "dir"
        d = QDir(path)
        names = d.entryInfoList(QDir.AllEntries | QDir.NoDotAndDotDot, QDir.DirsFirst | QDir.Name | QDir.IgnoreCase)
        info["entryCount"] = len(names)
        info["entries"] = [{"name": n.fileName(), "icon": "folder" if n.isDir() else
                            (QMimeDatabase().mimeTypeForFile(n, QMimeDatabase.MatchExtension).iconName() or "unknown")}
                           for n in names[:12]]
        return info
    info["size"] = locale.formattedDataSize(fi.size())
    # PDF'nin ilk sayfası da Qt'nin görüntü eklentisiyle görüntü olarak okunur
    if mime.name().startswith("image/") or mime.inherits("application/pdf"):
        info["kind"] = "image"
        size = QImageReader(path).size()
        if size.isValid():
            info["dimensions"] = f"{size.width()} × {size.height()}"
    elif mime.inherits("text/plain") and fi.size() < 5 * 1024 * 1024:
        try:
            with open(path, "rb") as f:
                raw = f.read(4096)
            if b"\0" not in raw:
                lines = raw.decode("utf-8", errors="replace").splitlines()[:40]
                info["kind"] = "text"
                info["text"] = "\n".join(l[:200] for l in lines)
        except OSError:
            pass
    return info


# ── Klasör gezgini ───────────────────────────────────────────────────
def fold(s):
    """Büyük/küçük harf ve aksan duyarsız karşılaştırma: "masaustu" "Masaüstü"yü bulur."""
    s = unicodedata.normalize("NFKD", s.casefold().replace("ı", "i"))
    return "".join(c for c in s if not unicodedata.combining(c))


def place_icons():
    icons = {HOME: "user-home"}
    for loc, icon in ((QStandardPaths.DesktopLocation, "user-desktop"),
                      (QStandardPaths.DocumentsLocation, "folder-documents"),
                      (QStandardPaths.DownloadLocation, "folder-download"),
                      (QStandardPaths.MusicLocation, "folder-music"),
                      (QStandardPaths.PicturesLocation, "folder-pictures"),
                      (QStandardPaths.MoviesLocation, "folder-videos")):
        path = QStandardPaths.writableLocation(loc)
        if path and path != HOME and os.path.isdir(path):
            icons[path] = icon
    return icons


def mount_dirs():
    user = os.environ.get("USER", "")
    paths = glob.glob("/mnt/*") + glob.glob("/media/*") + glob.glob(f"/run/media/{user}/*")
    return sorted(p for p in paths if os.path.isdir(p) and not p.startswith(HOME + "/"))


def build_folder_index():
    """Klasör adlarının listesi: (katlanmış ad, yol, derinlik). Gizli ve büyük geliştirme klasörleri atlanır."""
    index = []
    stack = [(root, 0) for root in [HOME] + mount_dirs()]
    while stack:
        path, depth = stack.pop()
        try:
            with os.scandir(path) as it:
                for e in it:
                    if e.name.startswith(".") or e.name in BROWSE_SKIP:
                        continue
                    if e.is_dir(follow_symlinks=False):
                        index.append((fold(e.name), e.path, depth))
                        if depth < BROWSE_DEPTH:
                            stack.append((e.path, depth + 1))
        except OSError:
            pass
    return index


def match_score(name, needle):
    """Küçük puan daha iyi; eşleşme yoksa None."""
    if name == needle:
        return 0
    if name.startswith(needle):
        return 1
    pos = name.find(needle)
    if pos < 0:
        return None
    return 2 if not name[pos - 1].isalnum() else 3


def runner_list(lang):
    """Kurulu KRunner eklentileri (özel önek eklerken seçmek için)."""
    def localized(get, key):
        return get(f"{key}[{lang}]") or get(f"{key}[{lang.split('_')[0]}]") or get(key) or ""

    runners = []
    plugin_dir = os.path.join(QLibraryInfo.path(QLibraryInfo.LibraryPath.PluginsPath), "kf6", "krunner")
    dbus_dirs = QStandardPaths.locateAll(QStandardPaths.GenericDataLocation, "krunner/dbusplugins",
                                         QStandardPaths.LocateDirectory)
    for path in glob.glob(os.path.join(plugin_dir, "*.so")):
        meta = QPluginLoader(path).metaData().get("MetaData", {}).get("KPlugin", {})
        rid = meta.get("Id") or os.path.basename(path)[:-3]
        runners.append({"id": rid, "name": localized(meta.get, "Name") or rid, "icon": meta.get("Icon", "")})
    for path in [p for d in dbus_dirs for p in glob.glob(os.path.join(d, "*.desktop"))]:
        s = QSettings(path, QSettings.IniFormat)
        s.beginGroup("Desktop Entry")
        rid = s.value("X-KDE-PluginInfo-Name") or os.path.basename(path)[:-8]
        runners.append({"id": rid, "name": localized(s.value, "Name") or rid, "icon": s.value("Icon") or ""})
    return sorted(runners, key=lambda r: r["name"].casefold())


# ── Genel kısayol (kglobalaccel) ─────────────────────────────────────
def busctl(*args):
    return subprocess.run(["busctl", "--user", "call", "org.kde.kglobalaccel", "/kglobalaccel",
                           "org.kde.KGlobalAccel", *args], capture_output=True, text=True, timeout=5)


KANDIL_ACTION = [DESKTOP_ID, "_launch", "Kandil", "Kandil"]
KRUNNER_ACTION = ["org.kde.krunner.desktop", "_launch", "KRunner", "Launch KRunner"]
KRUNNER_DEFAULT_KEYS = ["Alt+Space", "Alt+F2", "Search"]


def live_keys(action):
    """Çalışan kglobalaccel'deki kısayollar (PortableText listesi); yanıt yoksa None."""
    r = busctl("shortcutKeys", "as", "4", *action)
    parts = r.stdout.split()
    if r.returncode != 0 or len(parts) < 2:
        return None
    count, keys = int(parts[1]), []
    for i in range(count):
        code = int(parts[3 + 5 * i])
        if code:
            keys.append(QKeySequence(code).toString(QKeySequence.PortableText))
    return keys


def current_keys(action, default=()):
    """Önce çalışan sistemdeki, yoksa ayar dosyasındaki kısayollar."""
    live = live_keys(action)
    return live if live is not None else read_keys(action[0], default)


def read_keys(desktop_id, default=()):
    """kglobalshortcutsrc'deki kısayollar (PortableText listesi)."""
    out = subprocess.run(["kreadconfig6", "--file", SHORTCUTS_FILE, "--group", "services",
                          "--group", desktop_id, "--key", "_launch"], capture_output=True, text=True).stdout.strip()
    if not out:
        return list(default)
    return [] if out == "none" else [k for k in out.split("\t") if k and k != "none"]


def write_keys(action, seqs):
    """Kısayolları hem çalışan kglobalaccel'e hem de kglobalshortcutsrc'ye yazar."""
    codes = [QKeySequence(s)[0].toCombined() for s in seqs if not QKeySequence(s).isEmpty()]
    keys = [str(len(codes))] + [x for c in codes for x in ("4", str(c), "0", "0", "0")]
    # Yeni kurulan .desktop dosyası KDE'nin uygulama veritabanını arka planda yeniler ve
    # bu, hemen ardından yapılan atamayı geri alabilir; bu yüzden atama doğrulanıp yinelenir.
    ok = False
    for attempt in range(8):
        if attempt:
            time.sleep(0.5)
        busctl("doRegister", "as", "4", *action)
        busctl("setForeignShortcutKeys", "asa(ai)", "4", *action, *keys)
        applied = busctl("shortcutKeys", "as", "4", *action).stdout.split()
        ok = all(str(c) in applied for c in codes) and len(applied) - 2 == 5 * len(codes)
        if ok:
            time.sleep(0.3)
            applied = busctl("shortcutKeys", "as", "4", *action).stdout.split()
            ok = all(str(c) in applied for c in codes)
            if ok:
                break
    if ok:
        subprocess.run(["kwriteconfig6", "--file", SHORTCUTS_FILE, "--group", "services", "--group", action[0],
                        "--key", "_launch", "\t".join(seqs) or "none"])
    return ok


def get_shortcut():
    keys = read_keys(DESKTOP_ID)
    return keys[0] if keys else ""


def set_shortcut(seq, take_from_krunner=False):
    text = seq.toString(QKeySequence.PortableText)
    if take_from_krunner and text:
        krunner = current_keys(KRUNNER_ACTION, KRUNNER_DEFAULT_KEYS)
        if text in krunner:
            write_keys(KRUNNER_ACTION, [k for k in krunner if k != text])
    return write_keys(KANDIL_ACTION, [text] if text else [])


def release_shortcut():
    """Kandil'in kısayolunu kaldırır; KRunner'da yoksa ona geri verir."""
    mine = current_keys(KANDIL_ACTION) or read_keys(DESKTOP_ID)
    write_keys(KANDIL_ACTION, [])
    busctl("unregister", "ss", DESKTOP_ID, "_launch")
    subprocess.run(["kwriteconfig6", "--file", SHORTCUTS_FILE, "--group", "services", "--group", DESKTOP_ID,
                    "--key", "_launch", "--delete"])
    krunner = current_keys(KRUNNER_ACTION, KRUNNER_DEFAULT_KEYS)
    missing = [k for k in mine if k not in krunner]
    if missing:
        write_keys(KRUNNER_ACTION, missing + krunner)
    return missing


# ── Denetleyici ──────────────────────────────────────────────────────
class Controller(QObject):
    toggleRequested = Signal()
    showRequested = Signal()
    hideRequested = Signal()
    queryRequested = Signal(str)
    configChanged = Signal("QVariantMap")
    stringsChanged = Signal("QVariantMap")
    commandFinished = Signal(str, int, bool, float)     # çıktı, çıkış kodu, zaman aşımı, süre (sn)
    webResults = Signal(str, "QVariantList", str)        # sorgu, sonuçlar, hata
    faviconReady = Signal(str)                          # site adı (host)
    browseIndexReady = Signal()

    def __init__(self):
        super().__init__()
        self.history = History()
        self.config = load_config()
        self.process = None
        self.engine = None
        self.settings_window = None
        self.language = resolve_language(self.config["language"])
        self.started_language = self.language
        self.strings = load_strings(self.language)

        # Ayar dosyası kaydedildiğinde anında uygulanır. Düzenleyiciler dosyayı
        # yeniden adlandırarak kaydedebildiği için izleme her değişimde tazelenir.
        self.watcher = QFileSystemWatcher([CONFIG_DIR, CONFIG_FILE])
        self.reload_timer = QTimer(self)
        self.reload_timer.setSingleShot(True)
        self.reload_timer.setInterval(150)
        self.reload_timer.timeout.connect(self.reloadConfig)
        self.watcher.fileChanged.connect(lambda _: self.reload_timer.start())
        self.watcher.directoryChanged.connect(lambda _: self.reload_timer.start())

        self.klipper = QDBusInterface("org.kde.klipper", "/klipper", "org.kde.klipper.klipper")

        self.network = QNetworkAccessManager(self)
        self.web_reply = None
        self.web_cache = {}
        self.favicon_pending = set()
        self.folder_index = None
        self.emoji = None
        self.emoji_lang = ""
        self.emoji_catalog = None
        self.folder_index_time = 0
        self.folder_index_building = False
        self.browseIndexReady.connect(lambda: setattr(self, "folder_index_building", False))

    def t(self, key, *args):
        s = self.strings.get(key, key)
        for i, a in enumerate(args, 1):
            s = s.replace(f"%{i}", str(a))
        return s

    def locale(self):
        return QLocale(self.language)

    # ── D-Bus'tan gelen istekler ─────────────────────────────────────
    @Slot()
    def toggle(self):
        self.toggleRequested.emit()

    @Slot()
    def show(self):
        self.showRequested.emit()

    @Slot()
    def hide(self):
        self.hideRequested.emit()

    @Slot(str)
    def query(self, text):
        self.queryRequested.emit(text)

    # ── Ayarlar ──────────────────────────────────────────────────────
    def apply_config(self, config):
        self.config = config
        lang = resolve_language(config["language"])
        if lang != self.language:
            self.language = lang
            self.strings = load_strings(lang)
            QApplication.instance().setApplicationDisplayName(self.t("app.name"))
            self.stringsChanged.emit(self.strings)
        self.configChanged.emit(config)

    @Slot()
    def reloadConfig(self):
        if os.path.exists(CONFIG_FILE) and CONFIG_FILE not in self.watcher.files():
            self.watcher.addPath(CONFIG_FILE)
        config = load_config()
        if config != self.config:
            self.apply_config(config)

    @Slot("QVariantMap")
    def saveConfig(self, config):
        merged = copy.deepcopy(self.config)
        merged.update(config)
        write_config(merged)
        self.apply_config(load_config())

    @Slot()
    def resetConfig(self):
        write_config(copy.deepcopy(DEFAULT_CONFIG))
        self.apply_config(load_config())

    @Slot(result="QVariantList")
    def defaultModes(self):
        return copy.deepcopy(DEFAULT_CONFIG["modes"])

    @Slot(result="QVariantMap")
    def currentConfig(self):
        return self.config

    @Slot(result="QVariantMap")
    def currentStrings(self):
        return self.strings

    @Slot(result=bool)
    def isRtl(self):
        return self.language.split("_")[0] in RTL_LANGUAGES

    @Slot(result="QVariantList")
    def languages(self):
        return available_languages()

    @Slot(result=str)
    def activeLanguage(self):
        return self.language

    @Slot(result=bool)
    def needsRestart(self):
        return self.language != self.started_language

    @Slot()
    def restart(self):
        if os.environ.get("INVOCATION_ID"):
            QProcess.startDetached("systemctl", ["--user", "restart", "kandil.service"])
        else:
            os.execv(sys.executable, [sys.executable, "-I", os.path.abspath(__file__)])

    @Slot(result="QVariantList")
    def runners(self):
        return runner_list(self.language)

    @Slot(result="QVariant")
    def shortcut(self):
        return QKeySequence(get_shortcut())

    @Slot("QVariant", result=bool)
    def setShortcut(self, value):
        seq = value if isinstance(value, QKeySequence) else QKeySequence(str(value or ""))
        return set_shortcut(seq)

    @Slot(result=bool)
    def autostart(self):
        r = subprocess.run(["systemctl", "--user", "is-enabled", "kandil.service"], capture_output=True, text=True)
        return r.stdout.strip() == "enabled"

    @Slot(bool)
    def setAutostart(self, enabled):
        subprocess.run(["systemctl", "--user", "enable" if enabled else "disable", "kandil.service"],
                       capture_output=True)

    @Slot()
    def openConfigFile(self):
        QDesktopServices.openUrl(QUrl.fromLocalFile(CONFIG_FILE))

    @Slot()
    def openSearchPlugins(self):
        QProcess.startDetached("systemsettings", ["kcm_plasmasearch"])

    @Slot(result=str)
    def version(self):
        return VERSION

    @Slot(result="QVariantMap")
    def paths(self):
        return {"config": tilde(CONFIG_FILE), "history": tilde(HISTORY_FILE), "program": tilde(HERE)}

    @Slot()
    def openSettings(self):
        if self.settings_window is None:
            # Bileşen ve pencere saklanır; sahiplik açıkça C++ tarafına verilir ki
            # QML'in çöp toplayıcısı pencereyi silmesin.
            self.settings_component = QQmlComponent(self.engine, QUrl.fromLocalFile(os.path.join(HERE, "Settings.qml")))
            window = self.settings_component.createWithInitialProperties({"controller": self})
            if window is None:
                for e in self.settings_component.errors():
                    print(e.toString(), file=sys.stderr)
                return
            QQmlEngine.setObjectOwnership(window, QQmlEngine.CppOwnership)
            self.settings_window = window
        self.settings_window.show()
        self.settings_window.raise_()
        self.settings_window.requestActivate()

    # ── Geçmiş ───────────────────────────────────────────────────────
    @Slot(str, str, str, str, "QVariant", str)
    def recordRun(self, query, match_id, display, subtext, decoration, category):
        if isinstance(decoration, QIcon):
            icon = decoration.name()
        else:
            icon = decoration if isinstance(decoration, str) else ""
        if not icon and match_id.startswith("file://"):
            icon = QMimeDatabase().mimeTypeForUrl(QUrl(match_id)).iconName()
        self.history.record(query, match_id, display, subtext, icon, category)

    @Slot(result="QVariantList")
    def historyList(self):
        if not self.config["historyEnabled"]:
            return []
        return self.history.listing(int(self.config["historyCount"]),
                                    self.t("history.recent"), self.t("history.frequent"))

    @Slot(str)
    def removeHistory(self, match_id):
        self.history.remove(match_id)

    @Slot()
    def clearHistory(self):
        self.history.clear()

    @Slot(result=int)
    def historySize(self):
        return len(self.history.entries)

    @Slot(str, result="QVariantMap")
    def fileInfo(self, url):
        return file_info(url, self.locale())

    # ── Pano geçmişi (Klipper) ───────────────────────────────────────
    @Slot(str, result="QVariantList")
    def clipboardItems(self, needle):
        reply = self.klipper.call("getClipboardHistoryMenu")
        items = reply.arguments()[0] if reply.arguments() else []
        needle = needle.casefold()
        out = []
        for i, text in enumerate(items):
            # Görsel girdileri Klipper "▨ G × Y" biçiminde verir; metin olarak geri yüklenemez
            if text.startswith("▨ "):
                continue
            if needle and needle not in text.casefold():
                continue
            first = next((l.strip() for l in text.splitlines() if l.strip()), text.strip())
            lines = text.count("\n") + 1
            subtext = self.t("clip.chars", len(text))
            if lines > 1:
                subtext = self.t("clip.lines", lines) + " · " + subtext
            out.append({
                "matchId": f"clip:{i}",
                "clipIndex": i,
                "display": first[:300],
                "subtext": subtext,
                "decoration": "edit-paste",
                "category": self.t("clip.section"),
                "fullText": text[:4000],
            })
        return out

    @Slot(int)
    def restoreClipboard(self, index):
        reply = self.klipper.call("getClipboardHistoryItem", index)
        if reply.arguments():
            self.klipper.call("setClipboardContents", reply.arguments()[0])

    @Slot(str)
    def copyText(self, text):
        self.klipper.call("setClipboardContents", text)

    # ── Web araması ──────────────────────────────────────────────────
    @Slot(str)
    def webSearch(self, query):
        query = query.strip()
        self.cancelWebSearch()
        if not query:
            return
        if query in self.web_cache:
            self.webResults.emit(query, self.web_cache[query], "")
            return
        request = QNetworkRequest(web_search_url(query))
        request.setHeader(QNetworkRequest.UserAgentHeader, WEB_USER_AGENT)
        request.setRawHeader(b"Accept-Language", f"{self.language.replace('_', '-')},en;q=0.8".encode())
        request.setTransferTimeout(10000)
        reply = self.network.get(request)
        self.web_reply = reply

        def on_finished():
            reply.deleteLater()
            if self.web_reply is not reply:
                return
            self.web_reply = None
            if reply.error() != QNetworkReply.NoError:
                self.webResults.emit(query, [], reply.errorString())
                return
            results = parse_brave(bytes(reply.readAll().data()).decode("utf-8", errors="replace"))
            if results:
                if len(self.web_cache) >= 50:
                    self.web_cache.pop(next(iter(self.web_cache)))
                self.web_cache[query] = results
            self.webResults.emit(query, results, "")

        reply.finished.connect(on_finished)

    @Slot()
    def cancelWebSearch(self):
        if self.web_reply is not None:
            reply, self.web_reply = self.web_reply, None
            reply.abort()

    @Slot(str, result=str)
    def webSearchPage(self, query):
        return web_search_url(query.strip()).toString(QUrl.FullyEncoded)

    @Slot(result="QVariantList")
    def defaultSearchEngines(self):
        return copy.deepcopy(DEFAULT_CONFIG["searchEngines"])

    # Site simgeleri bir kez indirilip önbellekte PNG olarak saklanır. Simge henüz yoksa boş
    # döner ve indirme başlar; bitince faviconReady ile arayüz yeniden sorar.
    @Slot(str, result=str)
    def favicon(self, url):
        host = QUrl(url).host()
        if not host:
            return ""
        path = os.path.join(FAVICON_DIR, hashlib.sha1(host.encode()).hexdigest() + ".png")
        if os.path.exists(path):
            return QUrl.fromLocalFile(path).toString()
        if host not in self.favicon_pending:
            self.favicon_pending.add(host)
            request = QNetworkRequest(QUrl(f"https://{host}/favicon.ico"))
            request.setHeader(QNetworkRequest.UserAgentHeader, WEB_USER_AGENT)
            request.setTransferTimeout(10000)
            reply = self.network.get(request)

            def on_finished():
                reply.deleteLater()
                image = QImage()
                if reply.error() == QNetworkReply.NoError and image.loadFromData(reply.readAll()):
                    os.makedirs(FAVICON_DIR, exist_ok=True)
                    if image.width() > 64:
                        image = image.scaledToWidth(64, Qt.SmoothTransformation)
                    if image.save(path, "PNG"):
                        self.faviconReady.emit(host)
                # Başarısız olursa bu oturumda yeniden denenmez (host kümede kalır)

            reply.finished.connect(on_finished)
        return ""

    # ── Klasör gezgini ───────────────────────────────────────────────
    @Slot()
    def prepareBrowse(self):
        if self.folder_index_building or time.monotonic() - self.folder_index_time < BROWSE_INDEX_TTL:
            return
        self.folder_index_building = True

        def work():
            index = build_folder_index()
            self.folder_index, self.folder_index_time = index, time.monotonic()
            self.browseIndexReady.emit()      # ana iş parçacığına sıraya alınarak iletilir

        threading.Thread(target=work, daemon=True).start()

    def browse_entry(self, path, is_dir, category, subtext=None, icons=None):
        name = os.path.basename(path.rstrip("/")) or path
        if is_dir:
            icon = (icons or {}).get(path, "folder")
            sub = subtext if subtext is not None else self.t("browse.folder")
        else:
            db = QMimeDatabase()
            mime = db.mimeTypeForFile(path, QMimeDatabase.MatchExtension)
            if mime.isDefault():          # uzantı yetmiyorsa içerikten tanınır
                mime = db.mimeTypeForFile(path)
            icon = mime.iconName() or mime.genericIconName() or "unknown"
            try:
                size = self.locale().formattedDataSize(os.path.getsize(path))
            except OSError:
                size = ""
            sub = subtext if subtext is not None else " · ".join(x for x in (mime.comment(), size) if x)
        return {"matchId": QUrl.fromLocalFile(path).toString(), "url": QUrl.fromLocalFile(path).toString(),
                "path": path, "tildePath": tilde(path), "display": name, "subtext": sub, "decoration": icon, "isDir": is_dir,
                "category": category, "multiLine": False, "keyLabel": ""}

    @Slot(str, result="QVariantMap")
    def browseList(self, text):
        """Boş metin: yerler; "/" ya da "~" ile başlayan: o klasörün içeriği (son parça süzgeç);
        diğerleri: adı eşleşen klasörler."""
        icons = place_icons()
        if not text.strip():
            entries = [self.browse_entry(p, True, self.t("browse.places"), tilde(p), icons) for p in icons]
            entries[0]["display"] = self.t("browse.home")
            entries += [self.browse_entry(p, True, self.t("browse.drives"), p, {p: "drive-harddisk"})
                        for p in mount_dirs()]
            entries.append(dict(self.browse_entry("/", True, self.t("browse.drives"), "/", {"/": "drive-harddisk-root"}),
                                display=self.t("browse.root")))
            return {"kind": "places", "dir": "", "entries": entries, "total": len(entries)}

        if text.startswith(("/", "~")):
            expanded = os.path.expanduser(text)
            folder, needle = os.path.split(expanded)
            folder = folder or "/"
            if not os.path.isdir(folder):
                return {"kind": "dir", "dir": tilde(folder), "entries": [], "total": 0, "error": "notFound"}
            needle = fold(needle)
            show_hidden = needle.startswith(".")
            found = []
            try:
                with os.scandir(folder) as it:
                    for e in it:
                        if e.name.startswith(".") and not show_hidden:
                            continue
                        score = match_score(fold(e.name), needle) if needle else 0
                        if score is None:
                            continue
                        try:
                            is_dir = e.is_dir()
                        except OSError:
                            is_dir = False
                        found.append((not is_dir, min(score, 1), fold(e.name), e.path, is_dir))
            except OSError:
                return {"kind": "dir", "dir": tilde(folder), "entries": [], "total": 0, "error": "unreadable"}
            found.sort()
            folders, files = self.t("browse.folders"), self.t("browse.files")
            entries = [self.browse_entry(f[3], f[4], folders if f[4] else files, icons=icons)
                       for f in found[:BROWSE_LIMIT]]
            return {"kind": "dir", "dir": tilde(folder), "entries": entries, "total": len(found),
                    "error": "" if found or needle else "empty"}

        needle = fold(text.strip())
        self.prepareBrowse()
        ranked = []
        for path, icon in icons.items():
            score = match_score(fold(os.path.basename(path)), needle)
            if score is not None:
                ranked.append((score - 1, 0, path))
        seen = {r[2] for r in ranked}
        for name, path, depth in self.folder_index or []:
            score = match_score(name, needle)
            if score is not None and path not in seen:
                ranked.append((score, depth, path))
        ranked.sort(key=lambda r: (r[0], r[1], len(r[2])))
        category = self.t("browse.folders")
        entries = [self.browse_entry(r[2], True, category, tilde(os.path.dirname(r[2])), icons)
                   for r in ranked[:BROWSE_SEARCH_LIMIT]]
        return {"kind": "search", "dir": "", "entries": entries, "total": len(ranked),
                "indexing": self.folder_index is None}

    @Slot(str, result=str)
    def browseParent(self, text):
        """Alt+↑: yazılı yoldaki klasörün bir üstü."""
        folder = os.path.dirname(os.path.expanduser(text)) if text.startswith(("/", "~")) else HOME
        parent = os.path.dirname(folder.rstrip("/")) or "/"
        return "/" if parent == "/" else tilde(parent) + "/"

    # ── Emoji ────────────────────────────────────────────────────────
    def emoji_data(self):
        if self.emoji is None or self.emoji_lang != self.language:
            self.emoji, self.emoji_lang = load_emoji(self.language), self.language
            self.emoji_catalog = gettext.translation("org.kde.plasma.emojier", "/usr/share/locale",
                                                     [self.language, self.language.split("_")[0]], fallback=True)
        return self.emoji

    def emoji_category(self, number):
        return self.emoji_catalog.pgettext("Emoji Category", EMOJI_CATEGORIES.get(number, ""))

    def emoji_entry(self, e, category):
        tone = int(self.config["emojiSkinTone"])
        glyph = e["tones"].get(tone, e["glyph"])
        return {"matchId": "emoji:" + e["glyph"], "base": e["glyph"], "glyph": glyph, "display": e["name"],
                "subtext": ", ".join(a for a in e["annotations"] if a != e["name"])[:120],
                "decoration": "", "category": category, "multiLine": False, "keyLabel": "",
                "codepoints": " ".join(f"U+{ord(c):04X}" for c in glyph if ord(c) != 0xFE0F),
                "variants": " ".join(e["tones"][t] for t in sorted(e["tones"])),
                "keywords": ", ".join(e["annotations"]), "categoryName": self.emoji_category(e["category"])}

    def emoji_recent(self):
        try:
            with open(EMOJI_RECENT_FILE, encoding="utf-8") as f:
                recent = json.load(f)
            return [g for g in recent if isinstance(g, str)]
        except (OSError, ValueError):
            return []

    @Slot(str, result="QVariantList")
    def emojiList(self, query):
        """Boş sorguda son kullanılanlar ve kategorilere göre bütün emojiler, aksi hâlde eşleşenler."""
        data = self.emoji_data()
        words = [fold(w) for w in query.split()]
        if words:
            ranked = sorted(((score, i, e) for i, e in enumerate(data)
                             if (score := emoji_score(e, words)) is not None), key=lambda r: r[:2])
            return [self.emoji_entry(e, self.emoji_category(e["category"])) for _, _, e in ranked[:EMOJI_LIMIT]]
        by_glyph = {e["glyph"]: e for e in data}
        out = [self.emoji_entry(by_glyph[g], self.t("emoji.recent")) for g in self.emoji_recent() if g in by_glyph]
        return out + [self.emoji_entry(e, self.emoji_category(e["category"])) for e in data]

    @Slot(str, str)
    def useEmoji(self, base, text):
        """Seçilen metni (emoji ya da adı) panoya kopyalar ve emojiyi son kullanılanların başına alır."""
        self.copyText(text)
        recent = [base] + [g for g in self.emoji_recent() if g != base]
        os.makedirs(STATE_DIR, exist_ok=True)
        with open(EMOJI_RECENT_FILE, "w", encoding="utf-8") as f:
            json.dump(recent[:EMOJI_RECENT_LIMIT], f, ensure_ascii=False)

    @Slot()
    def clearEmojiRecent(self):
        try:
            os.remove(EMOJI_RECENT_FILE)
        except OSError:
            pass

    @Slot(str)
    def showInFileManager(self, url):
        # Dosya yöneticisi (Dolphin) dosyayı seçili olarak bulunduğu klasörde açar
        QProcess.startDetached("busctl", ["--user", "call", "org.freedesktop.FileManager1",
                                          "/org/freedesktop/FileManager1", "org.freedesktop.FileManager1",
                                          "ShowItems", "ass", "1", url, ""])

    @Slot(str)
    def openTerminalAt(self, path):
        term = shlex.split(self.config["terminalCommand"])[:1] or ["konsole"]
        QProcess.startDetached(term[0], [], path)

    @Slot(str)
    def openUrl(self, url):
        QDesktopServices.openUrl(QUrl(url))

    # ── Komut çalıştırma ─────────────────────────────────────────────
    @Slot(str)
    def runCommand(self, command):
        self.cancelCommand()
        proc = QProcess(self)
        proc.setProcessChannelMode(QProcess.MergedChannels)
        proc.setWorkingDirectory(HOME)
        env = proc.processEnvironment()
        env.insert("TERM", "dumb")
        proc.setProcessEnvironment(env)
        timed_out = {"value": False}
        started = time.monotonic()
        timer = QTimer(proc)
        timer.setSingleShot(True)
        timer.setInterval(int(self.config["commandTimeout"] * 1000))

        def on_timeout():
            timed_out["value"] = True
            proc.kill()

        def on_finished(code, _status):
            timer.stop()
            raw = bytes(proc.readAll().data())[:COMMAND_OUTPUT_LIMIT]
            text = ANSI_RE.sub("", raw.decode("utf-8", errors="replace"))
            if self.process is proc:
                self.process = None
                self.commandFinished.emit(text, code, timed_out["value"], time.monotonic() - started)
            proc.deleteLater()

        timer.timeout.connect(on_timeout)
        proc.finished.connect(on_finished)
        self.process = proc
        proc.start(self.config["commandShell"], ["-c", command])
        proc.closeWriteChannel()
        timer.start()

    @Slot()
    def cancelCommand(self):
        if self.process is not None:
            proc, self.process = self.process, None
            proc.kill()

    @Slot(str)
    def runInTerminal(self, command):
        term = shlex.split(self.config["terminalCommand"]) or ["konsole", "--hold", "-e"]
        QProcess.startDetached(term[0], term[1:] + [self.config["commandShell"], "-c", command], HOME)

    # ── Pencere ──────────────────────────────────────────────────────
    # QMargins QML'de yazılamadığı için layer-shell kenar boşluğu buradan ayarlanır.
    @Slot(QObject, int)
    def setTopMargin(self, layer_window, top):
        layer_window.setProperty("margins", QMargins(0, top, 0, 0))

    # Kart canlanırken bulanıklık ve tıklama alanı kartın şekline göre güncellenir;
    # kart dışındaki saydam alana yapılan tıklamalar alttaki pencereye geçer.
    @Slot(QObject, float, float, float, float, float)
    def updateCardRegion(self, window, x, y, w, h, radius):
        region = rounded_region(round(x), round(y), round(w), round(h), round(radius))
        window.setMask(region)
        _enable_blur(shiboken6.getCppPointer(window)[0], bool(self.config["blur"]),
                     shiboken6.getCppPointer(region)[0])


@ClassInfo({"D-Bus Interface": SERVICE})
class DBusApi(QObject):
    """D-Bus'a yalnızca açma/kapama yöntemleri açılır. Controller'daki komut çalıştırma
    gibi yöntemler dışarıya kapalı kalır (örn. oturum veriyoluna erişen Flatpak uygulamaları)."""

    def __init__(self, controller):
        super().__init__()
        self.controller = controller

    @Slot()
    def toggle(self):
        self.controller.toggle()

    @Slot()
    def show(self):
        self.controller.show()

    @Slot()
    def hide(self):
        self.controller.hide()

    @Slot(str)
    def query(self, text):
        self.controller.query(text)

    @Slot()
    def settings(self):
        self.controller.openSettings()


def cli(argv):
    """Kurulum/kaldırma betiklerinin kullandığı komutlar. İşlendiyse çıkış kodunu döndürür."""
    if "--version" in argv:
        print(VERSION)
        return 0
    if "--set-shortcut" in argv:
        i = argv.index("--set-shortcut")
        seq = QKeySequence(argv[i + 1] if i + 1 < len(argv) else "")
        ok = set_shortcut(seq, take_from_krunner="--take-from-krunner" in argv)
        print(seq.toString(QKeySequence.PortableText) if ok else "")
        return 0 if ok else 1
    if "--release-shortcut" in argv:
        given_back = release_shortcut()
        print("\t".join(given_back))
        return 0
    return None


def main():
    code = cli(sys.argv[1:])
    if code is not None:
        return code

    # KRunner eklentilerinin (uygulamalar, hesap makinesi vb.) dili de Kandil'in diline uyar.
    SYSTEM_UI_LANGUAGES.extend(env_ui_languages())
    language = load_config()["language"]
    if language != "system":
        os.environ["LANGUAGE"] = resolve_language(language)

    app = QApplication(sys.argv)
    app.setApplicationName("kandil")
    app.setApplicationDisplayName("Kandil")
    app.setDesktopFileName("kandil")
    app.setWindowIcon(QIcon.fromTheme("search"))
    app.setQuitOnLastWindowClosed(False)
    # Pencere gizliyken KJob vb. işlerin bitişi uygulamayı kapatmasın
    app.setQuitLockEnabled(False)

    bus = QDBusConnection.sessionBus()
    if not bus.registerService(SERVICE):
        print("Kandil zaten çalışıyor.", file=sys.stderr)
        return 1

    controller = Controller()
    app.setApplicationDisplayName(controller.t("app.name"))
    api = DBusApi(controller)
    bus.registerObject("/", api, QDBusConnection.ExportAllSlots)

    engine = QQmlApplicationEngine()
    controller.engine = engine
    engine.setInitialProperties({"controller": controller, "config": controller.config,
                                 "strings": controller.strings})
    engine.load(QUrl.fromLocalFile(os.path.join(HERE, "Main.qml")))
    if not engine.rootObjects():
        return 1
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
