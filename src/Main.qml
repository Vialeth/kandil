import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Effects

import org.kde.kirigami as Kirigami
import org.kde.layershell as LayerShell
import org.kde.milou as Milou

Window {
    id: root

    property QtObject controller
    property var config: ({})                      // ~/.config/kandil/config.json
    property var strings: ({})                     // i18n/<dil>.json
    property bool rtl: false
    property var uiLocale: Qt.locale()

    // Çeviri: tr("results.count", 5) → "5 sonuç"
    function tr(key, ...args) {
        let s = strings[key] ?? key
        for (let i = 0; i < args.length; i++)
            s = s.split("%" + (i + 1)).join(String(args[i]))
        return s
    }

    function applyLanguage() {
        rtl = controller.isRtl()
        uiLocale = Qt.locale(controller.activeLanguage())
    }
    Component.onCompleted: applyLanguage()

    // Görünüm ayarları (ayar dosyasından)
    readonly property int panelWidth: config.panelWidth ?? 720
    readonly property int previewWidth: config.previewEnabled === false ? 0 : (config.previewWidth ?? 320)
    readonly property int rowHeight: config.rowHeight ?? 52
    readonly property int heroHeight: 84
    readonly property int iconSize: config.iconSize ?? 32
    readonly property int maxVisibleRows: config.maxVisibleRows ?? 8
    readonly property real topRatio: config.topRatio ?? 0.22    // ekranın üstünden oran
    readonly property int cardRadius: config.cardRadius ?? 14
    readonly property int animDuration: config.animationDuration ?? 260
    // Önek modları; yardım modu ("?") her zaman listenin sonundadır
    readonly property var modes: (config.modes ?? []).concat([{ id: "help", key: config.helpKey ?? "?",
                                                                runner: ":help", icon: "help-about", enabled: true }])
    readonly property int shadowMargin: 28         // gölge için kartın çevresindeki saydam pay
    readonly property int maxCardHeight: 640
    readonly property color accent: config.accentColor ? config.accentColor : Kirigami.Theme.highlightColor
    readonly property color textColor: Kirigami.Theme.textColor
    readonly property color dimColor: Qt.alpha(Kirigami.Theme.textColor, 0.55)
    readonly property color faintColor: Qt.alpha(Kirigami.Theme.textColor, 0.10)

    property int activeAction: -1
    property bool runWhenReady: false
    property bool ctrlHeld: false

    // Önek modu: "f rapor" yazılınca etiket "Dosyalar" olur ve arama yalnızca o kaynakta yapılır.
    // mode, modun kimliğini (files, clipboard, help, özel…) tutar.
    property string mode: ""
    readonly property var modeInfo: mode === "" ? null
                                  : mode.startsWith("engine:") ? engineMode(engines.find(e => "engine:" + e.id === mode))
                                  : mode.startsWith("ai:") ? aiMode(aiProviders.find(p => "ai:" + p.id === mode))
                                  : (modes.find(m => m.id === mode) ?? null)
    readonly property string modeRunner: modeInfo ? modeInfo.runner : ""

    function modeLabel(m) {
        return m.custom ? (m.label || m.runner) : tr("mode." + m.id)
    }

    // Arama motorları ("gg ubuntu"): anahtar kelimesi yazılınca mod gibi etiket olur
    readonly property var engines: (config.searchEngines ?? []).filter(e => e.enabled && e.key)
    property int faviconTick: 0                // site simgesi indirildikçe artar, simgeler yeniden sorulur

    function engineIcon(e) {
        faviconTick
        return controller.favicon(e.url) || "internet-web-browser"
    }

    function engineMode(e) {
        return e ? { id: "engine:" + e.id, key: e.key, runner: ":engine", icon: engineIcon(e), label: e.name,
                     custom: true, enabled: true, engine: e } : null
    }

    // Yapay zekâ sağlayıcıları ("ai soru"): her sağlayıcının anahtar kelimesi bir mod açar
    readonly property var aiProviders: (config.aiProviders ?? []).filter(p => p.enabled && p.key)

    function aiMode(p) {
        return p ? { id: "ai:" + p.id, key: p.key, runner: ":ai", icon: "dialog-messages", label: p.name,
                     custom: true, enabled: true, provider: p } : null
    }

    function siteOf(url) {
        const m = /^https?:\/\/[^\/?#]+/.exec(url)
        return m ? m[0] : url
    }

    // Boş sorguda son/sık kullanılanlar gösterilir
    readonly property bool historyMode: field.text.length === 0 && mode === ""
    // Listenin o an neyi gösterdiği: history | clip | web | command | results
    readonly property string listKind: historyMode ? "history"
                                     : modeRunner === ":help" ? "help"
                                     : modeRunner === ":clipboard" ? "clip"
                                     : modeRunner === ":web" ? "web"
                                     : modeRunner === ":engine" ? "engine"
                                     : modeRunner === ":browse" ? "browse"
                                     : modeRunner === ":emoji" ? "emoji"
                                     : modeRunner === ":ai" ? "ai"
                                     : modeRunner === ":command" ? "command" : "results"

    // Komut modu durumu
    property string cmdState: "idle"           // idle | running | done
    property string cmdOutput: ""
    property int cmdExit: 0
    property bool cmdTimedOut: false
    property string cmdText: ""
    property real cmdElapsed: 0

    // Açılış efekti: kart üst kenarından hafifçe büyüyerek belirir
    property real openScale: 1
    onOpenScaleChanged: updateCardRegion()

    function detectPrefix() {
        if (mode !== "") return false
        const t = field.text
        if (t === (config.helpKey ?? "?")) {
            mode = "help"
            field.text = ""
            return true
        }
        for (const m of modes) {
            if (m.enabled && m.runner !== ":help" && m.key && t.startsWith(m.key + " ")) {
                mode = m.id
                field.text = t.slice(m.key.length + 1)
                return true
            }
        }
        for (const e of engines) {
            if (t.startsWith(e.key + " ")) {
                mode = "engine:" + e.id
                field.text = t.slice(e.key.length + 1)
                return true
            }
        }
        for (const p of aiProviders) {
            if (t.startsWith(p.key + " ")) {
                mode = "ai:" + p.id
                field.text = t.slice(p.key.length + 1)
                return true
            }
        }
        return false
    }

    onModeChanged: {
        list.currentIndex = 0
        activeAction = -1
        if (listKind === "clip") loadClipboard()
        if (listKind === "help") loadHelp()
        if (listKind === "web") queueWebSearch()
        else if (webState !== "idle") resetWeb()
        loadEngine()
        if (listKind === "browse") {
            controller.prepareBrowse()
            loadBrowse()
        }
        if (listKind === "emoji") loadEmoji()
        else if (emojiModel.count > 0) emojiModel.clear()
        if (listKind === "ai") loadAiChat()
    }

    // ── Yapay zekâ sohbeti ───────────────────────────────────────────
    // Enter soruyu gönderir; yanıt akış hâlinde gelir. Sohbet aynı sağlayıcıyla sürer,
    // Ctrl+N yeni sohbet başlatır, Esc yanıtı durdurur, Alt+C son yanıtı kopyalar.
    ListModel { id: aiModel }
    property string aiState: "idle"            // idle | waiting | streaming | done | error
    property string aiError: ""
    property string aiNote: ""
    property bool aiThinking: false
    property real aiStarted: 0

    function loadAiChat() {
        aiModel.clear()
        aiError = ""
        aiNote = ""
        const p = modeInfo?.provider
        if (p && controller.aiChatProvider() === p.id)
            for (const m of controller.aiHistory())
                aiModel.append(m)
        aiState = aiModel.count > 0 ? "done" : "idle"
    }

    function sendAi() {
        const q = field.text.trim()
        const p = modeInfo?.provider
        if (!q || !p || aiState === "waiting" || aiState === "streaming") return
        if (controller.aiChatProvider() !== p.id) aiModel.clear()
        aiModel.append({ role: "user", text: q })
        aiModel.append({ role: "assistant", text: "" })
        aiState = "waiting"
        aiError = ""
        aiNote = ""
        aiThinking = false
        aiStarted = Date.now()
        field.text = ""
        controller.aiAsk(p.id, q)
    }

    function stopAi() {
        controller.aiCancel()
        const last = aiModel.count - 1
        if (last >= 0 && aiModel.get(last).role === "assistant" && !aiModel.get(last).text) {
            aiModel.remove(last)
            if (aiModel.count > 0 && aiModel.get(aiModel.count - 1).role === "user") {
                field.text = aiModel.get(aiModel.count - 1).text
                aiModel.remove(aiModel.count - 1)
            }
        }
        aiState = aiModel.count > 0 ? "done" : "idle"
    }

    function lastAiAnswer() {
        for (let i = aiModel.count - 1; i >= 0; i--)
            if (aiModel.get(i).role === "assistant" && aiModel.get(i).text) return aiModel.get(i).text
        return ""
    }

    // ── Emoji ("e") ──────────────────────────────────────────────────
    // Enter emojiyi, Shift+Enter adını panoya kopyalar. Boş sorguda son kullanılanlar ve
    // kategoriler listelenir; Ctrl+↑/↓ kategoriler arasında atlar.
    ListModel { id: emojiModel }

    function loadEmoji() {
        emojiModel.clear()
        for (const e of controller.emojiList(field.text))
            emojiModel.append(e)
        list.currentIndex = 0
        Qt.callLater(refreshPreview)
    }

    // ── Klasör gezgini ("ff") ────────────────────────────────────────
    // Boşken yerler, "~/" ya da "/" ile başlayınca o klasörün içeriği, diğer metinlerde adı
    // eşleşen klasörler listelenir. Klasöre Enter/Tab ile girilir, dosya varsayılan uygulamayla açılır.
    ListModel { id: browseModel }
    property var browseInfo: ({})
    readonly property var browseSel: listKind === "browse" && list.currentIndex >= 0
                                     && list.currentIndex < browseModel.count ? browseModel.get(list.currentIndex) : null

    function loadBrowse() {
        const r = controller.browseList(field.text)
        browseInfo = r
        browseModel.clear()
        for (const e of r.entries)
            browseModel.append(e)
        list.currentIndex = 0
        Qt.callLater(refreshPreview)
    }

    function enterFolder(e) {
        field.text = e.tildePath === "/" ? "/" : e.tildePath + "/"
        field.cursorPosition = field.text.length
    }

    // ── Arama motorları ──────────────────────────────────────────────
    ListModel { id: engineModel }

    function loadEngine() {
        engineModel.clear()
        const e = listKind === "engine" ? modeInfo.engine : null
        if (!e) return
        const q = field.text.trim()
        // Adreste %s yoksa terim sona eklenir; terim yoksa sitenin ana sayfası açılır
        const url = !q ? siteOf(e.url)
                  : e.url.includes("%s") ? e.url.split("%s").join(encodeURIComponent(q))
                  : e.url + encodeURIComponent(q)
        engineModel.append({ matchId: "engine:" + e.id, url: url, display: e.name,
                             subtext: q ? tr("engine.searchFor", e.name, q) : tr("engine.openSite", siteOf(e.url)),
                             decoration: engineIcon(e), category: tr("help.engines"), multiLine: false, keyLabel: "" })
        list.currentIndex = 0
    }

    // ── Yardım ("?") ─────────────────────────────────────────────────
    ListModel { id: helpModel }

    function loadHelp() {
        helpModel.clear()
        const needle = field.text.toLocaleLowerCase()
        const add = e => {
            if (!needle || (e.display + " " + e.subtext).toLocaleLowerCase().includes(needle))
                helpModel.append(Object.assign({ matchId: "help:" + helpModel.count, multiLine: false }, e))
        }
        const prefixes = tr("help.prefixes")
        for (const m of modes) {
            if (!m.enabled || m.runner === ":help") continue
            add({ display: modeLabel(m), subtext: m.custom ? tr("help.mode.custom", m.label || m.runner) : tr("help.mode." + m.id),
                  decoration: m.icon, category: prefixes, keyLabel: m.key + " ␣", action: "mode:" + m.id })
        }
        const engs = tr("help.engines")
        for (const e of engines)
            add({ display: e.name, subtext: siteOf(e.url).replace(/^https?:\/\/(www\.)?/, ""), decoration: engineIcon(e),
                  category: engs, keyLabel: e.key + " ␣", action: "mode:engine:" + e.id })
        const ais = tr("help.ai")
        for (const p of aiProviders)
            add({ display: p.name, subtext: p.model || siteOf(p.url).replace(/^https?:\/\//, ""), decoration: "dialog-messages",
                  category: ais, keyLabel: p.key + " ␣", action: "mode:ai:" + p.id })
        add({ display: tr("help.settings"), subtext: tr("help.settingsDesc"), decoration: "configure",
              category: tr("app.name"), keyLabel: "", action: "settings" })
        const keys = tr("help.keys")
        const shortcuts = [
            ["↑ ↓", "help.key.navigate"], ["Ctrl ↑ ↓", "help.key.category"], ["↵", "help.key.open"],
            ["⇧ ↵", "help.key.firstAction"], ["Tab", "help.key.actions"], ["Ctrl 1–9", "help.key.quick"],
            ["⇧ Del", "help.key.removeHistory"], ["⌫", "help.key.backspace"], ["Esc", "help.key.escape"],
            ["Tab", "help.key.enterFolder"], ["Alt ↑", "help.key.parentFolder"], ["Ctrl ↵", "help.key.fileManager"],
            ["Alt C", "help.key.copyPath"], ["Ctrl T", "help.key.terminalHere"], ["⇧ ↵", "help.key.copyName"],
            ["Ctrl N", "help.key.newChat"]
        ]
        for (const [k, key] of shortcuts)
            add({ display: tr(key), subtext: "", decoration: "input-keyboard", category: keys, keyLabel: k, action: "" })
        list.currentIndex = 0
    }

    function activateHelp(i) {
        const e = helpModel.get(i)
        if (!e) return
        if (e.action === "settings") {
            close()
            controller.openSettings()
        } else if (e.action.startsWith("mode:")) {
            field.text = ""
            mode = e.action.slice(5)
        }
    }

    // Sonuç varsa kart sağa doğru genişler ve seçili sonucun önizleme paneli açılır
    property bool hasResults: false
    readonly property bool previewMode: previewWidth > 0
        && ((listKind === "results" && hasResults)
            || (["clip", "web", "browse", "emoji"].includes(listKind) && list.count > 0))
    property var previewInfo: ({})
    onPreviewModeChanged: refreshPreview()

    // Boyut animasyonu: pencere sabit boyutta ve saydamdır; yalnızca içindeki kart uzar/kısalır.
    // (Wayland penceresini her karede yeniden boyutlandırmak titremeye yol açıyordu.)
    // Sorgu sürerken sonuçlar bir anlığına boşalırsa kart zıplamasın diye küçülme kısa süre bekletilir.
    readonly property real naturalHeight: content.implicitHeight
    property real shownHeight: 60
    property real shownWidth: previewMode ? panelWidth + previewWidth : panelWidth
    property bool animateSize: false

    function syncHeight() {
        if (naturalHeight < shownHeight && results.querying && listKind === "results") {
            shrinkDelay.restart()
            return
        }
        shrinkDelay.stop()
        shownHeight = naturalHeight
    }
    onNaturalHeightChanged: syncHeight()

    Timer {
        id: shrinkDelay
        interval: 150
        onTriggered: root.shownHeight = root.naturalHeight
    }

    Behavior on shownHeight {
        enabled: root.animateSize
        NumberAnimation { duration: root.animDuration; easing.type: Easing.OutQuint }
    }
    Behavior on shownWidth {
        enabled: root.animateSize
        NumberAnimation { duration: root.animDuration; easing.type: Easing.OutQuint }
    }

    visible: false
    color: "transparent"
    flags: Qt.FramelessWindowHint
    width: panelWidth + previewWidth + 2 * shadowMargin
    height: maxCardHeight + 2 * shadowMargin

    LayerShell.Window.scope: "kandil"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityOnDemand
    LayerShell.Window.activateOnShow: true
    LayerShell.Window.wantsToBeOnActiveScreen: true
    LayerShell.Window.exclusionZone: -1

    function open() {
        if (leaving) finishLeaving()
        const scr = root.screen ?? Qt.application.screens[0]
        controller.setTopMargin(root.LayerShell.Window, Math.round(scr.height * topRatio) - shadowMargin)
        loadHistory()
        animateSize = false
        shownHeight = naturalHeight
        animateSize = true
        appear.restart()
        if (config.openAnimation !== false) openEffect.restart()
        root.visible = true
        root.updateCardRegion()
        root.requestActivate()
        field.forceActiveFocus()
        field.selectAll()
    }

    function close() {
        root.visible = false
        if (leaving) finishLeaving()
        runWhenReady = false
        activeAction = -1
        ctrlHeld = false
        // "Son aramayı hatırla" açıksa metin, mod ve sonuçlar bir sonraki açılışa kalır
        if (config.rememberQuery !== true || listKind === "help") {
            field.text = ""
            results.clear()
            hasResults = false
            mode = ""
        }
        controller.cancelCommand()
        cmdState = "idle"
        cmdOutput = ""
        if (aiState === "waiting" || aiState === "streaming") stopAi()
        if (listKind !== "web") resetWeb()
        else controller.cancelWebSearch()
    }

    NumberAnimation {
        id: openEffect
        target: root
        property: "openScale"
        from: 0.96
        to: 1
        duration: 200
        easing.type: Easing.OutCubic
    }

    // Wayland'de Qt, xdg-open'ı pencere için istediği etkinleştirme jetonu gelince çalıştırır.
    // Layer-shell penceresi aynı anda gizlenirse istek yanıtsız kalır ve adres hiç açılmaz.
    // Bu yüzden kart hemen görünmez olur, tıklamalar alttaki pencereye geçer; pencere kısa
    // bir süre sonra kapanır.
    property bool leaving: false

    function openExternal(url) {
        controller.openUrl(url)
        leaving = true
        root.contentItem.opacity = 0
        // Boş maske Qt'de "maske yok" demektir; bu yüzden 1×1'lik bir alan bırakılır
        controller.updateCardRegion(root, 0, 0, 1, 1, 0)
        leaveTimer.start()
    }

    function finishLeaving() {
        leaveTimer.stop()
        leaving = false
        root.contentItem.opacity = 1
    }

    Timer {
        id: leaveTimer
        interval: 250
        onTriggered: root.close()
    }

    // Bulanıklık ve tıklama alanı kartın o anki şekliyle sınırlı tutulur.
    function updateCardRegion() {
        if (!visible || leaving) return
        const w = card.width * openScale
        const h = card.height * openScale
        controller.updateCardRegion(root, card.x + (card.width - w) / 2, card.y, w, h, cardRadius * openScale)
    }

    function toggle() {
        root.visible ? close() : open()
    }

    onActiveChanged: if (!active && visible && config.closeOnFocusLoss !== false) close()

    Connections {
        target: root.controller
        function onToggleRequested() { root.toggle() }
        function onShowRequested() { root.open() }
        function onHideRequested() { root.close() }
        function onQueryRequested(text) {
            if (!root.visible) root.open()
            field.text = text
            field.cursorPosition = text.length
        }
        function onConfigChanged(cfg) { root.config = cfg }
        function onStringsChanged(s) {
            root.strings = s
            root.applyLanguage()
            if (root.listKind === "help") root.loadHelp()
        }
        function onCommandFinished(output, code, timedOut, elapsed) {
            root.cmdOutput = output
            root.cmdExit = code
            root.cmdTimedOut = timedOut
            root.cmdElapsed = elapsed
            root.cmdState = "done"
        }
        function onAiUpdate(text, thinking) {
            if (aiModel.count === 0) return
            aiModel.setProperty(aiModel.count - 1, "text", text)
            root.aiThinking = thinking
            if (text) root.aiState = "streaming"
        }
        function onAiFinished(error, stop) {
            if (error) {
                // Soru alana geri konur; düzeltip yeniden gönderilebilir
                if (aiModel.count >= 2) {
                    aiModel.remove(aiModel.count - 1)
                    field.text = aiModel.get(aiModel.count - 1).text
                    field.cursorPosition = field.text.length
                    aiModel.remove(aiModel.count - 1)
                }
                root.aiError = error
                root.aiState = "error"
            } else {
                root.aiState = "done"
                root.aiNote = stop === "refusal" ? root.tr("ai.refused")
                            : (stop === "length" || stop === "max_tokens") ? root.tr("ai.truncated") : ""
            }
            root.aiThinking = false
        }
        function onBrowseIndexReady() {
            if (root.listKind === "browse" && root.browseInfo.kind === "search") root.loadBrowse()
        }
        function onFaviconReady(host) {
            root.faviconTick++
            if (root.listKind === "engine") root.loadEngine()
            if (root.listKind === "help") root.loadHelp()
        }
        function onWebResults(query, items, error) {
            if (root.listKind !== "web" || query !== field.text.trim()) return
            root.webError = error
            root.webState = error ? "error" : "done"
            root.fillWeb(query, items)
        }
    }

    // ── Web araması ──────────────────────────────────────────────────
    // Sonuçlar Brave Search'ten gelir; listenin sonunda sorguyu tarayıcıda açan bir satır
    // her zaman bulunur, böylece sonuçlar gelmeden Enter'a basılırsa arama tarayıcıda açılır.
    ListModel { id: webModel }
    property string webState: "idle"           // idle | searching | done | error
    property string webError: ""
    property int webCount: 0

    Timer {
        id: webDelay
        interval: 450
        onTriggered: controller.webSearch(field.text.trim())
    }

    function queueWebSearch() {
        const q = field.text.trim()
        webDelay.stop()
        controller.cancelWebSearch()
        if (!q) {
            resetWeb()
            return
        }
        webState = "searching"
        webError = ""
        // Yeni sonuçlar gelene kadar eskiler kalır; yalnızca tarayıcı satırı güncellenir
        if (webModel.count > 0) {
            webModel.set(webModel.count - 1, { url: controller.webSearchPage(q), display: tr("web.inBrowser", q) })
            if (webModel.count === 1) Qt.callLater(refreshPreview)
        } else {
            fillWeb(q, [])
        }
        webDelay.start()
    }

    function fillWeb(query, items) {
        webModel.clear()
        for (const r of items)
            webModel.append({ matchId: "web:" + r.url, url: r.url, display: r.title,
                              subtext: r.url.replace(/^https?:\/\/(www\.)?/, ""), description: r.description,
                              decoration: r.favicon || "internet-web-browser",
                              category: tr("web.section"), multiLine: false, keyLabel: "" })
        webCount = items.length
        webModel.append({ matchId: "web:search", url: controller.webSearchPage(query),
                          display: tr("web.inBrowser", query), subtext: tr("web.inBrowserSub"), description: "",
                          decoration: "internet-web-browser", category: tr("web.section"),
                          multiLine: false, keyLabel: "" })
        list.currentIndex = 0
        Qt.callLater(refreshPreview)
    }

    function resetWeb() {
        webDelay.stop()
        controller.cancelWebSearch()
        webModel.clear()
        webState = "idle"
        webError = ""
        webCount = 0
    }

    // ── Pano ─────────────────────────────────────────────────────────
    ListModel { id: clipModel }

    function loadClipboard() {
        clipModel.clear()
        for (const e of controller.clipboardItems(field.text))
            clipModel.append(e)
        list.currentIndex = 0
        Qt.callLater(refreshPreview)
    }

    // ── Komut ────────────────────────────────────────────────────────
    function runCommand() {
        const cmd = field.text.trim()
        if (!cmd) return
        cmdText = cmd
        cmdOutput = ""
        cmdState = "running"
        controller.runCommand(cmd)
    }

    // ── Geçmiş ───────────────────────────────────────────────────────
    ListModel { id: historyModel }

    function loadHistory() {
        historyModel.clear()
        for (const e of controller.historyList())
            historyModel.append(e)
    }

    function removeHistoryAt(i) {
        if (i < 0 || i >= historyModel.count) return
        controller.removeHistory(historyModel.get(i).matchId)
        historyModel.remove(i)
    }

    function recordRow(i) {
        const idx = results.index(i, 0)
        controller.recordRun(field.text,
                             String(results.data(idx, Milou.ResultsModel.IdRole) ?? ""),
                             String(results.data(idx, Qt.DisplayRole) ?? ""),
                             String(results.data(idx, Milou.ResultsModel.SubtextRole) ?? ""),
                             results.data(idx, Qt.DecorationRole),
                             String(results.data(idx, Milou.ResultsModel.CategoryRole) ?? ""))
    }

    // Geçmişteki bir öğe, kaydedilen sorgu arka planda yeniden çalıştırılıp
    // aynı kimlikli sonuç bulunarak açılır.
    property var pendingReplay: null

    function replay(i) {
        const e = historyModel.get(i)
        pendingReplay = { id: e.matchId, display: e.display }
        controller.recordRun(e.query, e.matchId, e.display, e.subtext, e.decoration, e.origCategory)
        close()
        replayModel.queryString = ""
        replayModel.queryString = e.query
        replayTimeout.restart()
    }

    function tryReplay(final) {
        if (!pendingReplay) return
        let fallback = -1
        for (let r = 0; r < replayModel.rowCount(); r++) {
            const idx = replayModel.index(r, 0)
            if (replayModel.data(idx, Milou.ResultsModel.IdRole) === pendingReplay.id) {
                finishReplay(idx)
                return
            }
            if (fallback < 0 && replayModel.data(idx, Qt.DisplayRole) === pendingReplay.display)
                fallback = r
        }
        if (final) {
            if (fallback >= 0) finishReplay(replayModel.index(fallback, 0))
            else pendingReplay = null
        }
    }

    function finishReplay(idx) {
        pendingReplay = null
        replayTimeout.stop()
        replayModel.run(idx)
        Qt.callLater(replayModel.clear)
    }

    Milou.ResultsModel {
        id: replayModel
        limit: 50
        onRowsInserted: root.tryReplay(false)
        onQueryingChanged: if (!querying) root.tryReplay(true)
    }

    Timer {
        id: replayTimeout
        interval: 3000
        onTriggered: root.tryReplay(true)
    }

    // ── Sonuçlar ─────────────────────────────────────────────────────
    function localModel() {
        return listKind === "history" ? historyModel : listKind === "clip" ? clipModel
             : listKind === "help" ? helpModel : listKind === "web" ? webModel
             : listKind === "engine" ? engineModel : listKind === "browse" ? browseModel
             : listKind === "emoji" ? emojiModel : null
    }

    function idAt(i) {
        const m = localModel()
        if (m) return i >= 0 && i < m.count ? m.get(i).matchId : ""
        if (listKind === "command") return ""
        return String(results.data(results.index(i, 0), Milou.ResultsModel.IdRole) ?? "")
    }

    function categoryAt(i) {
        const m = localModel()
        if (m) return m.get(i).category
        return results.data(results.index(i, 0), Milou.ResultsModel.CategoryRole)
    }

    function currentActions() {
        return list.currentItem ? (list.currentItem.matchActions || []) : []
    }

    function runIndex(i, shift) {
        if (listKind === "help") {
            activateHelp(i)
            return
        }
        if (listKind === "history") {
            if (i >= 0 && i < historyModel.count) replay(i)
            return
        }
        if (listKind === "clip") {
            if (i >= 0 && i < clipModel.count) {
                controller.restoreClipboard(clipModel.get(i).clipIndex)
                close()
            }
            return
        }
        if (listKind === "emoji") {
            const em = i >= 0 && i < emojiModel.count ? emojiModel.get(i) : null
            if (em) {
                controller.useEmoji(em.base, shift ? em.display : em.glyph)
                close()
            }
            return
        }
        if (listKind === "browse") {
            const e = i >= 0 && i < browseModel.count ? browseModel.get(i) : null
            if (e) e.isDir ? enterFolder(e) : openExternal(e.url)
            return
        }
        if (listKind === "web" || listKind === "engine") {
            const m = localModel()
            if (i >= 0 && i < m.count) openExternal(m.get(i).url)
            return
        }
        if (listKind === "command") return
        const idx = results.index(i, 0)
        recordRow(i)
        let ok
        if (shift && currentActions().length > 0) {
            ok = results.runAction(idx, 0)
        } else if (activeAction >= 0) {
            ok = results.runAction(idx, activeAction)
        } else {
            ok = results.run(idx)
        }
        if (ok) close()
    }

    function runCurrent(shift) {
        if (listKind === "ai") {
            sendAi()
            return
        }
        if (listKind === "command") {
            runCommand()
            return
        }
        if (list.count === 0) {
            if (listKind === "results" && (results.querying || field.text.length > 0)) runWhenReady = true
            return
        }
        runIndex(list.currentIndex, shift)
    }

    function moveCategory(step) {
        const n = list.count
        if (n === 0) return
        const start = categoryAt(list.currentIndex)
        let i = list.currentIndex
        for (let k = 0; k < n; k++) {
            i = (i + step + n) % n
            if (categoryAt(i) !== start && (step > 0 || i === 0 || categoryAt(i - 1) !== categoryAt(i))) {
                list.currentIndex = i
                return
            }
        }
    }

    function scanResults() {
        if (list.currentIndex < 0 && list.count > 0) list.currentIndex = 0
        if (results.rowCount() > 0) {
            narrowDelay.stop()
            hasResults = true
        } else if (hasResults) {
            narrowDelay.restart()
        }
        refreshPreview()
    }

    // Yazarken sonuçlar bir anlığına boşalınca kart daralıp yeniden genişlemesin
    Timer {
        id: narrowDelay
        interval: 220
        onTriggered: if (results.rowCount() === 0) root.hasResults = false
    }

    function refreshPreview() {
        if (!previewMode || !list.currentItem) return
        const item = list.currentItem
        if (listKind === "clip") {
            const e = clipModel.get(list.currentIndex)
            if (!e) return
            previewInfo = { exists: true, kind: "text", noMeta: true, name: root.tr("clip.item"),
                            location: e.subtext, icon: "edit-paste", text: e.fullText }
        } else if (listKind === "emoji") {
            const em = emojiModel.get(list.currentIndex)
            if (!em) return
            previewInfo = { exists: true, kind: "text", noMeta: true, name: em.display, location: em.codepoints,
                            glyph: em.glyph, text: [em.categoryName, em.keywords, em.variants].filter(x => x).join("\n\n") }
        } else if (listKind === "browse") {
            const b = browseModel.get(list.currentIndex)
            if (!b) return
            previewInfo = controller.fileInfo(b.url)
        } else if (listKind === "web") {
            const w = webModel.get(list.currentIndex)
            if (!w) return
            previewInfo = { exists: true, kind: "text", noMeta: true, name: w.display,
                            location: w.url, icon: w.decoration, text: w.description }
        } else if (item.matchId.startsWith("file://")) {
            previewInfo = controller.fileInfo(item.matchId)
        } else {
            previewInfo = { exists: true, kind: "match", name: item.model.display ?? "",
                            location: String(item.model.subtext || ""), icon: item.model.decoration,
                            mime: item.model.category ?? "" }
        }
        previewFade.restart()
    }

    Milou.ResultsModel {
        id: results
        limit: root.config.resultLimit ?? 25
        queryString: root.listKind === "results" ? field.text : ""
        singleRunner: root.modeRunner !== "" && !root.modeRunner.startsWith(":") ? root.modeRunner : ""
        onQueryStringChangeRequested: (text, pos) => {
            field.text = text
            field.cursorPosition = pos
        }
        onModelReset: {
            list.currentIndex = 0
            Qt.callLater(root.scanResults)
        }
        onRowsInserted: {
            if (list.currentIndex < 0) list.currentIndex = 0
            Qt.callLater(root.scanResults)
            if (root.runWhenReady) Qt.callLater(root.flushPendingRun)
        }
        onRowsRemoved: Qt.callLater(root.scanResults)
        onQueryingChanged: {
            root.syncHeight()
            if (!querying && root.runWhenReady) Qt.callLater(root.flushPendingRun)
        }
    }

    function flushPendingRun() {
        if (!runWhenReady || list.count === 0) return
        runWhenReady = false
        list.currentIndex = 0
        runCurrent(false)
    }

    // ── Görünüm ──────────────────────────────────────────────────────
    RectangularShadow {
        anchors.fill: card
        visible: root.config.shadow !== false
        transformOrigin: Item.Top
        scale: root.openScale
        radius: card.radius
        blur: 26
        spread: 0
        offset.y: 6
        color: Qt.rgba(0, 0, 0, 0.45)
    }

    Rectangle {
        id: card
        LayoutMirroring.enabled: root.rtl
        LayoutMirroring.childrenInherit: true
        x: Math.round((root.width - width) / 2)
        y: root.shadowMargin
        width: Math.round(root.shownWidth)
        height: Math.ceil(root.shownHeight)
        radius: root.cardRadius
        color: Qt.alpha(Kirigami.Theme.backgroundColor, root.config.cardOpacity ?? 0.80)
        transformOrigin: Item.Top
        scale: root.openScale
        border.width: 1
        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
        clip: true
        onHeightChanged: root.updateCardRegion()
        onWidthChanged: root.updateCardRegion()

        ColumnLayout {
            id: content
            anchors.top: parent.top
            width: parent.width
            spacing: 0

            NumberAnimation on opacity { id: appear; from: 0; to: 1; duration: 140; easing.type: Easing.OutCubic }

            // ── Arama satırı ─────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 60
                Layout.leftMargin: 18
                Layout.rightMargin: 14
                spacing: 14

                Kirigami.Icon {
                    source: "search"
                    implicitWidth: 22
                    implicitHeight: 22
                    color: root.dimColor
                    isMask: true
                }

                Rectangle {
                    visible: root.modeInfo !== null
                    implicitWidth: chipRow.implicitWidth + 18
                    implicitHeight: 28
                    radius: 8
                    color: Qt.alpha(root.accent, 0.22)
                    border.width: 1
                    border.color: Qt.alpha(root.accent, 0.55)
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6
                        Kirigami.Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: 16
                            implicitHeight: 16
                            source: root.modeInfo?.icon ?? ""
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.modeInfo ? root.modeLabel(root.modeInfo) : ""
                            color: root.textColor
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                    }
                }

                QQC2.TextField {
                    id: field
                    Layout.fillWidth: true
                    background: null
                    leftPadding: 0
                    rightPadding: 0
                    font.pixelSize: root.config.searchFontSize ?? 21
                    font.weight: Font.Normal
                    color: root.textColor
                    placeholderText: root.modeRunner === ":command" ? root.tr("search.placeholderCommand")
                                   : root.modeRunner === ":ai" ? (aiModel.count > 0 ? root.tr("ai.followUp")
                                                                  : root.tr("ai.placeholder", root.modeLabel(root.modeInfo)))
                                   : root.modeInfo ? root.tr("search.placeholderMode", root.modeLabel(root.modeInfo))
                                   : root.tr("search.placeholder", root.config.helpKey ?? "?")
                    placeholderTextColor: Qt.alpha(root.textColor, 0.38)
                    selectionColor: Qt.alpha(root.accent, 0.5)
                    selectByMouse: true
                    onTextChanged: {
                        if (root.detectPrefix()) return
                        root.activeAction = -1
                        list.currentIndex = 0
                        if (root.listKind === "clip") root.loadClipboard()
                        if (root.listKind === "help") root.loadHelp()
                        if (root.listKind === "web") root.queueWebSearch()
                        if (root.listKind === "engine") root.loadEngine()
                        if (root.listKind === "browse") root.loadBrowse()
                        if (root.listKind === "emoji") root.loadEmoji()
                    }

                    Keys.onReleased: event => {
                        if (event.key === Qt.Key_Control) root.ctrlHeld = false
                    }

                    Keys.onPressed: event => {
                        const ctrl = event.modifiers & Qt.ControlModifier
                        const shift = event.modifiers & Qt.ShiftModifier
                        if (event.key === Qt.Key_Control) {
                            root.ctrlHeld = true
                            event.accepted = false
                            return
                        }
                        // Ctrl+1…9: ilgili sonucu doğrudan aç
                        if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                            const n = event.key - Qt.Key_1
                            if (n < list.count) {
                                list.currentIndex = n
                                root.activeAction = -1
                                root.runIndex(n, false)
                            }
                            event.accepted = true
                            return
                        }
                        // Komut modu: Ctrl+↵ Konsole'da çalıştırır, Alt+C çıktıyı kopyalar
                        if (root.listKind === "command") {
                            if (ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                                if (field.text.trim()) {
                                    controller.runInTerminal(field.text.trim())
                                    root.close()
                                }
                                event.accepted = true
                                return
                            }
                            if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_C) {
                                if (root.cmdOutput) controller.copyText(root.cmdOutput)
                                event.accepted = true
                                return
                            }
                        }
                        // Klasör gezgini: Tab klasöre girer, Alt+↑ üst klasöre çıkar, Ctrl+↵ dosya
                        // yöneticisinde gösterir, Alt+C yolu kopyalar, Ctrl+T orada terminal açar
                        if (root.listKind === "ai") {
                            const busy = root.aiState === "waiting" || root.aiState === "streaming"
                            if (event.key === Qt.Key_Escape && busy) {
                                root.stopAi()
                                event.accepted = true
                                return
                            }
                            if (ctrl && event.key === Qt.Key_N) {
                                controller.aiReset()
                                aiModel.clear()
                                root.aiState = "idle"
                                root.aiError = ""
                                root.aiNote = ""
                                event.accepted = true
                                return
                            }
                            if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_C) {
                                const a = root.lastAiAnswer()
                                if (a) controller.copyText(a)
                                event.accepted = true
                                return
                            }
                        }
                        if (root.listKind === "browse") {
                            const alt = event.modifiers & Qt.AltModifier
                            const sel = root.browseSel
                            let handled = true
                            if (event.key === Qt.Key_Tab && !ctrl && !alt) {
                                if (sel && sel.isDir) root.enterFolder(sel)
                            } else if (alt && event.key === Qt.Key_Up) {
                                field.text = controller.browseParent(field.text)
                                field.cursorPosition = field.text.length
                            } else if (ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                                if (sel) {
                                    if (sel.isDir) {
                                        root.openExternal(sel.url)
                                    } else {
                                        controller.showInFileManager(sel.url)
                                        root.close()
                                    }
                                }
                            } else if (alt && event.key === Qt.Key_C) {
                                if (sel) controller.copyText(sel.path)
                            } else if (ctrl && event.key === Qt.Key_T) {
                                if (sel) {
                                    controller.openTerminalAt(sel.isDir ? sel.path : sel.path.replace(/\/[^\/]*$/, "") || "/")
                                    root.close()
                                }
                            } else {
                                handled = false
                            }
                            if (handled) {
                                event.accepted = true
                                return
                            }
                        }
                        switch (event.key) {
                        case Qt.Key_Escape:
                            if (field.text.length > 0) field.clear()
                            else if (root.mode !== "") root.mode = ""
                            else root.close()
                            break
                        case Qt.Key_Backspace:
                            // Boş alanda Backspace mod etiketini kaldırır
                            if (root.mode !== "" && field.cursorPosition === 0 && field.selectedText === "") {
                                root.mode = ""
                                break
                            }
                            event.accepted = false
                            return
                        case Qt.Key_Down:
                            ctrl ? root.moveCategory(1) : list.incrementCurrentIndex()
                            break
                        case Qt.Key_Up:
                            ctrl ? root.moveCategory(-1) : list.decrementCurrentIndex()
                            break
                        case Qt.Key_PageDown:
                            root.moveCategory(1)
                            break
                        case Qt.Key_PageUp:
                            root.moveCategory(-1)
                            break
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            root.runCurrent(shift)
                            break
                        case Qt.Key_Delete:
                            if (shift && root.historyMode) {
                                root.removeHistoryAt(list.currentIndex)
                                break
                            }
                            event.accepted = false
                            return
                        case Qt.Key_Tab: {
                            const n = root.currentActions().length
                            root.activeAction = root.activeAction + 1 < n ? root.activeAction + 1 : -1
                            break
                        }
                        case Qt.Key_Backtab: {
                            const n = root.currentActions().length
                            root.activeAction = root.activeAction < 0 ? n - 1 : root.activeAction - 1
                            break
                        }
                        default:
                            if (ctrl && (event.key === Qt.Key_J || event.key === Qt.Key_K)) {
                                event.key === Qt.Key_J ? list.incrementCurrentIndex() : list.decrementCurrentIndex()
                                break
                            }
                            event.accepted = false
                            return
                        }
                        event.accepted = true
                    }
                }

                QQC2.BusyIndicator {
                    implicitWidth: 22
                    implicitHeight: 22
                    running: (results.querying && root.listKind === "results") || root.cmdState === "running"
                             || (root.listKind === "ai" && (root.aiState === "waiting" || root.aiState === "streaming"))
                    opacity: running ? 0.7 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }
            }

            // ── Ayraç ────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: root.faintColor
                visible: list.count > 0 || noResults.visible || commandPanel.visible || aiPanel.visible
            }

            // ── Sonuçlar + önizleme ──────────────────────────────────
            RowLayout {
                id: body
                readonly property real listHeight: Math.min(list.contentHeight, root.rowHeight * root.maxVisibleRows + 60)
                Layout.fillWidth: true
                Layout.preferredHeight: root.previewMode ? Math.max(listHeight, 340) : listHeight
                Layout.topMargin: list.count > 0 ? 6 : 0
                Layout.bottomMargin: list.count > 0 ? 6 : 0
                visible: list.count > 0
                spacing: 0

                ListView {
                    id: list
                    Layout.preferredWidth: root.panelWidth - 16
                    Layout.fillHeight: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    opacity: count > 0 ? 1 : 0
                    transform: Translate { y: (1 - list.opacity) * -10 }
                    Behavior on opacity {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                    clip: true
                    model: root.listKind === "history" ? historyModel
                         : root.listKind === "clip" ? clipModel
                         : root.listKind === "help" ? helpModel
                         : root.listKind === "web" ? webModel
                         : root.listKind === "engine" ? engineModel
                         : root.listKind === "browse" ? browseModel
                         : root.listKind === "emoji" ? emojiModel
                         : root.listKind === "command" ? null : results
                    keyNavigationWraps: true
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 110
                    highlightResizeDuration: 0
                    onCurrentIndexChanged: {
                        root.activeAction = -1
                        Qt.callLater(root.refreshPreview)
                    }

                    // Kaydırma çubuğu gerektiğinde satırlar daralır; çubuk kendi şeridinde durur
                    // Liste yüksekliği içerikten türediği için üst sınırla karşılaştırılır (bağlama döngüsü olmasın)
                    readonly property bool scrollNeeded: contentHeight > root.rowHeight * root.maxVisibleRows + 60 + 1
                    readonly property real rowWidth: width - (scrollNeeded ? 14 : 0)

                    QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                        policy: list.scrollNeeded ? QQC2.ScrollBar.AsNeeded : QQC2.ScrollBar.AlwaysOff
                        background: Item {}
                    }

                    section.property: root.config.showSectionHeaders === false ? "" : "category"
                    section.criteria: ViewSection.FullString
                    section.delegate: Item {
                        required property string section
                        width: list.rowWidth
                        height: 28
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 5
                            text: parent.section.toLocaleUpperCase(root.uiLocale.name)
                            color: root.dimColor
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.8
                        }
                    }

                    highlight: Rectangle {
                        radius: 10
                        color: Qt.alpha(root.accent, 0.20)
                        border.width: 1
                        border.color: Qt.alpha(root.accent, 0.45)
                    }

                    delegate: Item {
                        id: row
                        required property int index
                        required property var model
                        readonly property var matchActions: root.listKind === "results" ? (model.actions ?? []) : []
                        readonly property bool isCurrent: ListView.isCurrentItem
                        readonly property string matchId: root.idAt(index)
                        // Hesap makinesi ve birim çeviricinin ilk sonucu büyük kart olarak gösterilir
                        readonly property bool isHero: root.listKind === "results" && root.config.heroCard !== false
                            && (matchId.startsWith("calculator_")
                                || (matchId === "unitconverter" && (index === 0 || root.idAt(index - 1) !== "unitconverter")))

                        width: list.rowWidth
                        height: isHero ? root.heroHeight : Math.max(root.rowHeight, textCol.implicitHeight + 16)

                        HoverHandler {
                            enabled: root.config.hoverSelect !== false
                            onHoveredChanged: if (hovered) list.currentIndex = row.index
                        }
                        TapHandler {
                            onTapped: {
                                list.currentIndex = row.index
                                root.runCurrent(false)
                            }
                        }

                        // Normal satır
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 10
                            spacing: 12
                            visible: !row.isHero

                            Text {
                                visible: !!row.model.glyph
                                text: row.model.glyph ?? ""
                                Layout.preferredWidth: root.iconSize
                                Layout.alignment: Qt.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: Math.round(root.iconSize * 0.8)
                            }
                            Kirigami.Icon {
                                visible: !row.model.glyph
                                source: row.model.decoration
                                // Web sonuçlarında site simgesi yüklenemezse
                                fallback: ["web", "engine", "help"].includes(root.listKind) ? "internet-web-browser" : "unknown"
                                implicitWidth: root.iconSize
                                implicitHeight: root.iconSize
                                Layout.alignment: Qt.AlignVCenter
                            }

                            ColumnLayout {
                                id: textCol
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: row.model.display ?? ""
                                    color: root.textColor
                                    font.pixelSize: 15
                                    elide: Text.ElideRight
                                    wrapMode: row.model.multiLine ? Text.WordWrap : Text.NoWrap
                                    maximumLineCount: row.model.multiLine ? 6 : 1
                                    textFormat: row.model.multiLine ? Text.StyledText : Text.PlainText
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: String(row.model.subtext || "")
                                    visible: text.length > 0
                                    color: root.dimColor
                                    font.pixelSize: 12
                                    elide: Text.ElideMiddle
                                    textFormat: Text.PlainText
                                }
                            }

                            // Eylemler (yalnızca seçili satırda)
                            Row {
                                spacing: 4
                                visible: row.isCurrent && row.matchActions.length > 0 && !root.ctrlHeld
                                Layout.alignment: Qt.AlignVCenter
                                Repeater {
                                    model: row.matchActions
                                    delegate: Rectangle {
                                        required property var modelData
                                        required property int index
                                        readonly property bool selected: root.activeAction === index
                                        width: 30
                                        height: 30
                                        radius: 8
                                        color: selected ? root.accent : (actHover.hovered ? root.faintColor : "transparent")
                                        border.width: selected ? 0 : 1
                                        border.color: root.faintColor
                                        Kirigami.Icon {
                                            anchors.centerIn: parent
                                            implicitWidth: 18
                                            implicitHeight: 18
                                            source: parent.modelData.iconSource || ""
                                            selected: parent.selected
                                        }
                                        HoverHandler { id: actHover }
                                        TapHandler {
                                            onTapped: {
                                                root.recordRow(row.index)
                                                const ok = results.runAction(results.index(row.index, 0), parent.index)
                                                if (ok) root.close()
                                            }
                                        }
                                        QQC2.ToolTip.visible: actHover.hovered
                                        QQC2.ToolTip.delay: 400
                                        QQC2.ToolTip.text: modelData.text || ""
                                    }
                                }
                            }

                            // Yardım satırlarında önek / tuş rozeti
                            Keycap {
                                visible: (row.model.keyLabel ?? "") !== "" && !root.ctrlHeld
                                label: row.model.keyLabel ?? ""
                                highlighted: row.isCurrent
                            }
                            Keycap {
                                visible: row.isCurrent && root.activeAction < 0 && !root.ctrlHeld
                                         && (root.listKind !== "help" || (row.model.action ?? "") !== "")
                                label: "↵"
                            }
                            Keycap {
                                visible: root.ctrlHeld && row.index < 9
                                label: "Ctrl " + (row.index + 1)
                                highlighted: true
                            }
                        }

                        // Büyük sonuç kartı (hesap / birim çevirisi)
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 12
                            spacing: 14
                            visible: row.isHero

                            Rectangle {
                                implicitWidth: 44
                                implicitHeight: 44
                                radius: 12
                                color: Qt.alpha(root.accent, 0.18)
                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    implicitWidth: 26
                                    implicitHeight: 26
                                    source: row.model.decoration
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        const sub = String(row.model.subtext || "")
                                        return field.text + "  =" + (sub ? "   ·   " + sub : "")
                                    }
                                    color: root.dimColor
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: row.model.display ?? ""
                                    color: root.textColor
                                    font.pixelSize: 30
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                }
                            }

                            Row {
                                spacing: 6
                                Layout.alignment: Qt.AlignVCenter
                                visible: row.isCurrent && !root.ctrlHeld
                                Keycap { label: "↵"; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.tr("hint.copy")
                                    color: root.dimColor
                                    font.pixelSize: 12
                                }
                            }
                            Keycap {
                                visible: root.ctrlHeld && row.index < 9
                                label: "Ctrl " + (row.index + 1)
                                highlighted: true
                            }
                        }
                    }
                }

                // ── Önizleme paneli ──────────────────────────────────
                Item {
                    id: previewArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: card.width > root.panelWidth + 1
                    clip: true

                    Rectangle {
                        width: 1
                        height: parent.height
                        color: root.faintColor
                    }

                    Item {
                        id: preview
                        x: 1
                        width: root.previewWidth - 1
                        height: parent.height

                        NumberAnimation on opacity { id: previewFade; from: 0.25; to: 1; duration: 160; easing.type: Easing.OutCubic }

                        readonly property var info: root.previewInfo
                        readonly property bool ok: info.exists === true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 10
                            visible: preview.ok

                            // Görsel ya da büyük simge
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: preview.info.kind === "image" ? 170 : 76

                                Image {
                                    id: thumb
                                    anchors.fill: parent
                                    visible: preview.info.kind === "image"
                                    source: visible ? preview.info.url : ""
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectFit
                                    sourceSize.width: 576
                                    sourceSize.height: 340
                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        maskEnabled: true
                                        maskSource: thumbMask
                                    }
                                }
                                Rectangle {
                                    id: thumbMask
                                    anchors.fill: parent
                                    radius: 8
                                    visible: false
                                    layer.enabled: true
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: !!preview.info.glyph
                                    text: preview.info.glyph ?? ""
                                    font.pixelSize: 56
                                }
                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    visible: !preview.info.glyph && (preview.info.kind !== "image" || thumb.status === Image.Error)
                                    implicitWidth: 64
                                    implicitHeight: 64
                                    source: preview.info.icon ?? ""
                                    fallback: ["web", "engine", "help"].includes(root.listKind) ? "internet-web-browser" : "unknown"
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: preview.info.name ?? ""
                                color: root.textColor
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                                wrapMode: Text.WrapAnywhere
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                textFormat: Text.PlainText
                            }
                            Text {
                                Layout.fillWidth: true
                                Layout.topMargin: -6
                                text: preview.info.location ?? ""
                                visible: text.length > 0
                                color: root.dimColor
                                font.pixelSize: 12
                                elide: Text.ElideMiddle
                                horizontalAlignment: Text.AlignHCenter
                                textFormat: Text.PlainText
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                color: root.faintColor
                            }

                            // Bilgi satırları
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 12
                                rowSpacing: 4
                                visible: preview.info.kind !== "match" && !preview.info.noMeta

                                InfoKey { text: root.tr("preview.type") }
                                InfoValue { text: preview.info.mime ?? "" }
                                InfoKey { text: root.tr("preview.dimensions"); visible: !!preview.info.dimensions }
                                InfoValue { text: preview.info.dimensions ?? ""; visible: !!preview.info.dimensions }
                                InfoKey { text: root.tr("preview.size"); visible: !preview.info.isDir }
                                InfoValue { text: preview.info.size ?? ""; visible: !preview.info.isDir }
                                InfoKey { text: root.tr("preview.contents"); visible: preview.info.isDir === true }
                                InfoValue { text: root.tr("preview.items", preview.info.entryCount ?? 0); visible: preview.info.isDir === true }
                                InfoKey { text: root.tr("preview.modified") }
                                InfoValue { text: preview.info.modified ?? "" }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: preview.info.kind === "match"
                                text: preview.info.mime ?? ""
                                color: root.dimColor
                                font.pixelSize: 12
                                horizontalAlignment: Text.AlignHCenter
                            }

                            // Metin dosyası: ilk satırlar
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: preview.info.kind === "text"
                                radius: 8
                                color: Qt.alpha(root.textColor, 0.05)
                                border.width: 1
                                border.color: root.faintColor
                                clip: true
                                Text {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    text: preview.info.text ?? ""
                                    color: Qt.alpha(root.textColor, 0.75)
                                    font.family: "monospace"
                                    font.pixelSize: 11
                                    textFormat: Text.PlainText
                                    wrapMode: Text.NoWrap
                                    elide: Text.ElideRight
                                }
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 1
                                    height: 28
                                    radius: 8
                                    gradient: Gradient {
                                        GradientStop { position: 0; color: "transparent" }
                                        GradientStop { position: 1; color: Qt.alpha(Kirigami.Theme.backgroundColor, 0.9) }
                                    }
                                }
                            }

                            // Klasör: içindekiler
                            Column {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: preview.info.kind === "dir"
                                spacing: 3
                                clip: true
                                Repeater {
                                    model: preview.info.kind === "dir" ? preview.info.entries : []
                                    delegate: Row {
                                        required property var modelData
                                        spacing: 8
                                        Kirigami.Icon {
                                            implicitWidth: 16
                                            implicitHeight: 16
                                            source: parent.modelData.icon
                                        }
                                        Text {
                                            width: preview.width - 32 - 24
                                            text: parent.modelData.name
                                            color: Qt.alpha(root.textColor, 0.8)
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                            textFormat: Text.PlainText
                                        }
                                    }
                                }
                            }

                            Item { Layout.fillHeight: true; visible: preview.info.kind === "image" || preview.info.kind === "match" || preview.info.kind === "other" }
                        }
                    }
                }
            }

            // ── Yapay zekâ paneli ────────────────────────────────────
            ColumnLayout {
                id: aiPanel
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.topMargin: 12
                Layout.bottomMargin: 14
                visible: root.listKind === "ai"
                spacing: 10

                readonly property bool busy: root.aiState === "waiting" || root.aiState === "streaming"
                readonly property var provider: root.modeInfo?.provider ?? null

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Kirigami.Icon {
                        implicitWidth: 18
                        implicitHeight: 18
                        source: "dialog-messages"
                    }
                    Text {
                        Layout.fillWidth: true
                        text: aiPanel.provider ? aiPanel.provider.name + (aiPanel.provider.model ? "  ·  " + aiPanel.provider.model : "") : ""
                        color: root.dimColor
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: aiPanel.busy
                        color: root.dimColor
                        font.pixelSize: 12
                        // Yerel modelin ilk yanıtı modelin belleğe yüklenmesini bekler
                        text: root.aiState === "streaming" ? root.tr("ai.writing")
                            : root.aiThinking ? root.tr("ai.thinking")
                            : aiClock.slow ? root.tr("ai.loading") : root.tr("ai.waiting")
                        Timer {
                            id: aiClock
                            property bool slow: false
                            interval: 500
                            repeat: true
                            running: root.aiState === "waiting"
                            onRunningChanged: if (running) slow = false
                            onTriggered: slow = Date.now() - root.aiStarted > 4000
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: aiModel.count === 0 && root.aiState !== "error"
                    text: root.tr("ai.empty", aiPanel.provider ? aiPanel.provider.name : "")
                    color: root.dimColor
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.aiState === "error"
                    text: root.tr("ai.error", root.aiError)
                    color: Kirigami.Theme.negativeTextColor
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }

                Flickable {
                    id: aiFlick
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(aiColumn.implicitHeight, 430)
                    visible: aiModel.count > 0
                    clip: true
                    contentWidth: width
                    contentHeight: aiColumn.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                        background: Item {}
                    }
                    // Yanıt gelirken en alta kaydırılır
                    onContentHeightChanged: if (aiPanel.busy) contentY = Math.max(0, contentHeight - height)

                    Column {
                        id: aiColumn
                        width: aiFlick.width - 12
                        spacing: 12

                        Repeater {
                            model: aiModel
                            delegate: Item {
                                id: aiMsg
                                required property string role
                                required property string text
                                readonly property bool user: role === "user"
                                width: aiColumn.width
                                height: user ? userBubble.height : answer.implicitHeight

                                Rectangle {
                                    id: userBubble
                                    visible: aiMsg.user
                                    anchors.right: parent.right
                                    width: Math.min(question.implicitWidth, aiColumn.width * 0.8 - 24) + 24
                                    height: question.implicitHeight + 16
                                    radius: 10
                                    color: Qt.alpha(root.accent, 0.18)
                                    Text {
                                        id: question
                                        x: 12
                                        y: 8
                                        width: Math.min(implicitWidth, aiColumn.width * 0.8 - 24)
                                        text: aiMsg.user ? aiMsg.text : ""
                                        color: root.textColor
                                        font.pixelSize: 14
                                        wrapMode: Text.Wrap
                                        textFormat: Text.PlainText
                                    }
                                }

                                TextEdit {
                                    id: answer
                                    visible: !aiMsg.user
                                    width: parent.width
                                    readOnly: true
                                    selectByMouse: true
                                    text: aiMsg.user ? "" : (aiMsg.text || "…")
                                    color: aiMsg.text ? root.textColor : root.dimColor
                                    selectionColor: Qt.alpha(root.accent, 0.5)
                                    font.pixelSize: 14
                                    wrapMode: TextEdit.Wrap
                                    textFormat: TextEdit.MarkdownText
                                    onLinkActivated: link => root.openExternal(link)
                                }
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.aiNote !== ""
                    text: root.aiNote
                    color: Kirigami.Theme.neutralTextColor
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }

            // ── Komut paneli ─────────────────────────────────────────
            ColumnLayout {
                id: commandPanel
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.topMargin: 12
                Layout.bottomMargin: 14
                visible: root.listKind === "command" && (field.text.trim().length > 0 || root.cmdState !== "idle")
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Kirigami.Icon {
                        implicitWidth: 20
                        implicitHeight: 20
                        source: "utilities-terminal"
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.cmdState === "idle" || root.cmdText !== field.text.trim()
                              ? field.text.trim() : root.cmdText
                        color: root.textColor
                        font.family: "monospace"
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }
                    Text {
                        text: {
                            if (root.cmdState === "running") return root.tr("cmd.running")
                            if (root.cmdState === "done") {
                                const t = root.tr("cmd.seconds", root.cmdElapsed.toLocaleString(root.uiLocale, "f", 1))
                                if (root.cmdTimedOut) return root.tr("cmd.timeout") + " · " + t
                                return root.tr("cmd.exit", root.cmdExit) + " · " + t
                            }
                            return ""
                        }
                        visible: text.length > 0
                        color: root.cmdState === "done" && (root.cmdExit !== 0 || root.cmdTimedOut)
                               ? Kirigami.Theme.negativeTextColor : root.dimColor
                        font.pixelSize: 12
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(outputText.implicitHeight + 20, 380)
                    visible: root.cmdState === "done"
                    radius: 8
                    color: Qt.alpha(root.textColor, 0.05)
                    border.width: 1
                    border.color: root.faintColor
                    clip: true

                    Flickable {
                        id: outputFlick
                        anchors.fill: parent
                        anchors.margins: 10
                        contentWidth: width
                        contentHeight: outputText.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                            background: Item {}
                        }
                        TextEdit {
                            id: outputText
                            width: outputFlick.width - 12
                            readOnly: true
                            selectByMouse: true
                            text: root.cmdOutput.length > 0 ? root.cmdOutput : root.tr("cmd.noOutput")
                            color: root.cmdOutput.length > 0 ? Qt.alpha(root.textColor, 0.85) : root.dimColor
                            selectionColor: Qt.alpha(root.accent, 0.5)
                            font.family: "monospace"
                            font.pixelSize: 12
                            wrapMode: TextEdit.WrapAnywhere
                            textFormat: TextEdit.PlainText
                        }
                    }
                }
            }

            // ── Sonuç yok ────────────────────────────────────────────
            Text {
                id: noResults
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                visible: list.count === 0 && ((root.listKind === "results" && !results.querying)
                                              || root.listKind === "clip" || root.listKind === "help"
                                              || root.listKind === "web" || root.listKind === "browse"
                                              || root.listKind === "emoji")
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: root.listKind === "clip" ? (field.text ? root.tr("clip.noMatch") : root.tr("clip.empty"))
                    : root.listKind === "web" ? root.tr("web.empty")
                    : root.listKind === "browse" ? (root.browseInfo.error ? root.tr("browse." + root.browseInfo.error)
                                                    : root.browseInfo.indexing ? root.tr("browse.indexing")
                                                    : root.tr("results.none"))
                    : root.tr("results.none")
                color: root.dimColor
                font.pixelSize: 13
            }

            // ── Alt bilgi çubuğu ─────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: root.faintColor
                visible: footer.visible
                opacity: footer.opacity
            }
            RowLayout {
                id: footer
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                Layout.leftMargin: 16
                Layout.rightMargin: 14
                // Sonuçlar boşalınca düzenden hemen çıkar (kart tek seferde küçülsün);
                // görünürken solarak belirir.
                visible: root.config.showFooter !== false && (list.count > 0 || commandPanel.visible || aiPanel.visible)
                opacity: visible ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }
                spacing: 14

                Text {
                    Layout.fillWidth: true
                    text: {
                        const a = root.currentActions()
                        if (root.activeAction >= 0 && a[root.activeAction])
                            return a[root.activeAction].text
                        if (root.listKind === "command") return root.tr("cmd.shell", root.config.commandShell ?? "/bin/bash")
                        if (root.listKind === "history") return root.tr("history.title")
                        if (root.listKind === "help") return root.tr("mode.help")
                        if (root.listKind === "engine") return root.modeLabel(root.modeInfo)
                        if (root.listKind === "emoji") return root.tr("emoji.count", list.count)
                        if (root.listKind === "ai") return root.modeLabel(root.modeInfo)
                        if (root.listKind === "browse") {
                            const b = root.browseInfo
                            if (b.kind === "dir") return b.dir + "  ·  " + root.tr("preview.items", b.total)
                            if (b.kind === "search") return b.indexing ? root.tr("browse.indexing") : root.tr("browse.found", b.total)
                            return root.tr("browse.places")
                        }
                        if (root.listKind === "clip") return root.tr("clip.count", list.count)
                        if (root.listKind === "web") {
                            if (root.webState === "searching") return root.tr("web.searching")
                            if (root.webState === "error") return root.tr("web.failed", root.webError)
                            return root.webCount > 0 ? root.tr("web.count", root.webCount) : root.tr("results.none")
                        }
                        return root.tr("results.count", list.count)
                    }
                    color: root.dimColor
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
                readonly property bool cmd: root.listKind === "command"
                readonly property bool browse: root.listKind === "browse"
                readonly property bool ai: root.listKind === "ai"
                Hint { keys: "↵"; label: root.tr("hint.send"); visible: footer.ai && !aiPanel.busy }
                Hint { keys: "Esc"; label: root.tr("hint.stop"); visible: footer.ai && aiPanel.busy }
                Hint { keys: "Alt C"; label: root.tr("hint.copyAnswer"); visible: footer.ai && aiModel.count > 0 && !aiPanel.busy }
                Hint { keys: "Ctrl N"; label: root.tr("hint.newChat"); visible: footer.ai && aiModel.count > 0 }
                Hint { keys: "↑↓"; label: root.tr("hint.navigate"); visible: !footer.cmd && !footer.browse && !footer.ai }
                Hint { keys: "↵"; label: footer.cmd ? root.tr("hint.run") : ["clip", "emoji"].includes(root.listKind) ? root.tr("hint.toClipboard")
                                       : root.browseSel?.isDir ? root.tr("hint.enterFolder") : root.tr("hint.open"); visible: !footer.ai }
                Hint { keys: "⇧ ↵"; label: root.tr("hint.copyName"); visible: root.listKind === "emoji" && list.count > 0 }
                Hint { keys: "Ctrl ↑↓"; label: root.tr("hint.category"); visible: root.listKind === "emoji" && field.text === "" }
                Hint { keys: "Alt ↑"; label: root.tr("hint.parentFolder"); visible: footer.browse && root.browseInfo.kind === "dir" }
                Hint { keys: "Ctrl ↵"; label: root.tr("hint.fileManager"); visible: footer.browse && root.browseSel !== null }
                Hint { keys: "Alt C"; label: root.tr("hint.copyPath"); visible: footer.browse && root.browseSel !== null }
                Hint { keys: "Ctrl ↵"; label: root.tr("hint.terminal"); visible: footer.cmd }
                Hint { keys: "Alt C"; label: root.tr("hint.copyOutput"); visible: footer.cmd && root.cmdState === "done" }
                Hint { keys: "Ctrl 1–9"; label: root.tr("hint.quickSelect"); visible: !footer.cmd && !footer.browse && root.listKind !== "emoji" && !footer.ai }
                Hint { keys: "Tab"; label: root.tr("hint.actions"); visible: root.currentActions().length > 0 }
                Hint { keys: "⇧ Del"; label: root.tr("hint.removeHistory"); visible: root.historyMode }
                Hint { keys: root.config.helpKey ?? "?"; label: root.tr("hint.help"); visible: root.historyMode }
                Hint { keys: "Esc"; label: root.mode !== "" && field.text.length === 0 ? root.tr("hint.exitMode") : root.tr("hint.close"); visible: !(footer.ai && aiPanel.busy) }
            }
        }
    }

    component Keycap: Rectangle {
        property alias label: capText.text
        property bool highlighted: false
        implicitWidth: Math.max(22, capText.implicitWidth + 12)
        implicitHeight: 20
        radius: 5
        color: highlighted ? Qt.alpha(root.accent, 0.35) : Qt.alpha(root.textColor, 0.08)
        border.width: 1
        border.color: highlighted ? Qt.alpha(root.accent, 0.7) : Qt.alpha(root.textColor, 0.14)
        Text {
            id: capText
            anchors.centerIn: parent
            color: parent.highlighted ? root.textColor : root.dimColor
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
    }

    component Hint: Row {
        property string keys
        property string label
        spacing: 6
        Keycap { label: parent.keys; anchors.verticalCenter: parent.verticalCenter }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: root.dimColor
            font.pixelSize: 12
        }
    }

    component InfoKey: Text {
        color: root.dimColor
        font.pixelSize: 12
    }

    component InfoValue: Text {
        Layout.fillWidth: true
        color: Qt.alpha(root.textColor, 0.85)
        font.pixelSize: 12
        elide: Text.ElideRight
        textFormat: Text.PlainText
    }
}
