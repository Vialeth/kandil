import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls

QQC2.ApplicationWindow {
    id: win

    property QtObject controller
    property var cfg: controller.currentConfig()
    property var strings: controller.currentStrings()
    property bool rtl: controller.isRtl()
    property bool needsRestart: controller.needsRestart()
    property bool dirty: false

    // Pencere açıldığında tazelenen, ayar dosyasında olmayan durumlar
    property var shortcutSeq: controller.shortcut()
    property bool shortcutFailed: false
    property bool autostartOn: false
    property int historySize: 0
    property var runnerModel: []

    title: tr("settings.title")
    width: 940
    height: 680
    minimumWidth: 780
    minimumHeight: 520
    visible: false

    function tr(key, ...args) {
        let s = strings[key] ?? key
        for (let i = 0; i < args.length; i++)
            s = s.split("%" + (i + 1)).join(String(args[i]))
        return s
    }

    // Her değişiklik kısa bir gecikmeyle ayar dosyasına yazılır; Kandil dosyayı anında uygular.
    function setv(key, value) {
        if (cfg[key] === value) return
        const c = Object.assign({}, cfg)
        c[key] = value
        cfg = c
        dirty = true
        saveTimer.restart()
    }

    function flush() {
        if (!dirty) return
        saveTimer.stop()
        dirty = false
        controller.saveConfig(cfg)
    }

    // Kullanım rehberlerindeki önekler ayarlardaki güncel değerlerden gelir
    function modeKey(id) {
        const m = (cfg.modes ?? []).find(m => m.id === id)
        return m ? m.key : ""
    }

    function aiKey() {
        const p = (cfg.aiProviders ?? []).find(p => p.enabled && p.key)
        return p ? p.key : "ai"
    }

    function updateMode(i, patch) {
        const ms = cfg.modes.map(m => Object.assign({}, m))
        Object.assign(ms[i], patch)
        setv("modes", ms)
    }

    function modeLabel(m) {
        return m.custom ? (m.label || m.runner) : tr("mode." + m.id)
    }

    // Önek ve arama motoru anahtarları aynı alanı paylaşır; çakışmada önek önce gelir
    function keyConflict(i) {
        const m = cfg.modes[i]
        if (!m.enabled || !m.key) return false
        if (m.key === cfg.helpKey) return true
        return cfg.modes.some((o, j) => j !== i && o.enabled && o.key === m.key)
            || cfg.searchEngines.some(e => e.enabled && e.key === m.key)
    }

    function engineConflict(i) {
        const e = cfg.searchEngines[i]
        if (!e.enabled || !e.key) return false
        if (e.key === cfg.helpKey) return true
        return cfg.modes.some(m => m.enabled && m.key === e.key)
            || cfg.searchEngines.some((o, j) => j !== i && o.enabled && o.key === e.key)
    }

    function updateEngine(i, patch) {
        const es = cfg.searchEngines.map(e => Object.assign({}, e))
        Object.assign(es[i], patch)
        setv("searchEngines", es)
    }

    // Yapay zekâ sağlayıcıları; API anahtarları ayar dosyasına değil ayrı, korumalı bir dosyaya yazılır
    property var aiModelLists: ({})
    property var aiModelErrors: ({})
    property int aiKeyTick: 0

    function updateProvider(i, patch) {
        const ps = cfg.aiProviders.map(p => Object.assign({}, p))
        Object.assign(ps[i], patch)
        setv("aiProviders", ps)
    }

    function addProvider(presetId) {
        const preset = controller.aiPresets()[presetId]
        const used = cfg.aiProviders.map(p => p.key).concat(cfg.modes.map(m => m.key), cfg.searchEngines.map(e => e.key))
        let key = presetId === "anthropic" ? "claude" : presetId === "openai" ? "gpt" : "ai"
        let n = 2
        const base = key
        while (used.includes(key)) key = base + n++
        setv("aiProviders", cfg.aiProviders.concat([Object.assign({ effort: "" }, preset,
                                                                    { id: presetId + "-" + Date.now(), key: key, enabled: true })]))
    }

    function providerConflict(i) {
        const p = cfg.aiProviders[i]
        if (!p.enabled || !p.key) return false
        if (p.key === cfg.helpKey) return true
        return cfg.modes.some(m => m.enabled && m.key === p.key)
            || cfg.searchEngines.some(e => e.enabled && e.key === p.key)
            || cfg.aiProviders.some((o, j) => j !== i && o.enabled && o.key === p.key)
    }

    // Site simgeleri indirildikçe yeniden sorulur
    property int faviconTick: 0
    function engineIcon(url) {
        faviconTick
        return controller.favicon(url) || "internet-web-browser"
    }

    function refreshState() {
        cfg = controller.currentConfig()
        shortcutSeq = controller.shortcut()
        shortcutFailed = false
        autostartOn = controller.autostart()
        historySize = controller.historySize()
        needsRestart = controller.needsRestart()
        if (runnerModel.length === 0) runnerModel = controller.runners()
    }

    onVisibleChanged: if (visible) refreshState()
    onClosing: flush()

    Timer {
        id: saveTimer
        interval: 300
        onTriggered: win.flush()
    }

    Connections {
        target: win.controller
        function onConfigChanged(c) {
            if (!win.dirty) win.cfg = c
            win.needsRestart = win.controller.needsRestart()
        }
        function onFaviconReady(host) { win.faviconTick++ }
        function onAiModelsReady(pid, models, error) {
            const lists = Object.assign({}, win.aiModelLists)
            lists[pid] = models
            win.aiModelLists = lists
            const errors = Object.assign({}, win.aiModelErrors)
            errors[pid] = error
            win.aiModelErrors = errors
        }
        function onStringsChanged(s) {
            win.strings = s
            win.rtl = win.controller.isRtl()
            win.runnerModel = win.controller.runners()
        }
    }

    readonly property var pages: [
        { id: "general", icon: "preferences-system" },
        { id: "appearance", icon: "preferences-desktop-theme-global" },
        { id: "animation", icon: "preferences-desktop-effects" },
        { id: "behavior", icon: "preferences-system-windows-behavior" },
        { id: "prefixes", icon: "input-keyboard" },
        { id: "engines", icon: "internet-web-browser" },
        { id: "ai", icon: "dialog-messages" },
        { id: "command", icon: "utilities-terminal" },
        { id: "data", icon: "document-save" },
        { id: "about", icon: "help-about" }
    ]

    RowLayout {
        anchors.fill: parent
        spacing: 0
        LayoutMirroring.enabled: win.rtl
        LayoutMirroring.childrenInherit: true

        // ── Kenar çubuğu ─────────────────────────────────────────────
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 230
            Kirigami.Theme.colorSet: Kirigami.Theme.View
            Kirigami.Theme.inherit: false
            color: Kirigami.Theme.backgroundColor

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing * 2
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.margins: Kirigami.Units.smallSpacing * 2
                    spacing: Kirigami.Units.largeSpacing
                    Kirigami.Icon {
                        source: "search"
                        implicitWidth: Kirigami.Units.iconSizes.medium
                        implicitHeight: Kirigami.Units.iconSizes.medium
                    }
                    Kirigami.Heading {
                        text: win.tr("app.name")
                        level: 2
                    }
                }

                ListView {
                    id: sidebar
                    objectName: "sidebar"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: win.pages
                    clip: true
                    spacing: 2
                    delegate: QQC2.ItemDelegate {
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        text: win.tr("page." + modelData.id)
                        icon.name: modelData.icon
                        highlighted: ListView.isCurrentItem
                        onClicked: sidebar.currentIndex = index
                    }
                }
            }

            Kirigami.Separator {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: parent.right
            }
        }

        // ── Sayfalar ─────────────────────────────────────────────────
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: sidebar.currentIndex

            // Genel
            Page {
                title: win.tr("page.general")
                Kirigami.FormLayout {
                    Layout.fillWidth: true

                    QQC2.ComboBox {
                        id: languageBox
                        Kirigami.FormData.label: win.tr("general.language")
                        Layout.preferredWidth: 280
                        textRole: "name"
                        valueRole: "code"
                        model: [{ code: "system", name: win.tr("general.languageSystem") }].concat(win.controller.languages())
                        currentIndex: Math.max(0, indexOfValue(win.cfg.language))
                        onActivated: win.setv("language", currentValue)
                    }
                    Kirigami.InlineMessage {
                        Layout.fillWidth: true
                        Layout.maximumWidth: 460
                        visible: win.needsRestart
                        type: Kirigami.MessageType.Information
                        text: win.tr("general.languageNote")
                        actions: [
                            Kirigami.Action {
                                text: win.tr("general.restart")
                                icon.name: "view-refresh"
                                onTriggered: {
                                    win.flush()
                                    win.controller.restart()
                                }
                            }
                        ]
                    }

                    Item { Kirigami.FormData.isSection: true }

                    KQuickControls.KeySequenceItem {
                        Kirigami.FormData.label: win.tr("general.shortcut")
                        keySequence: win.shortcutSeq
                        modifierlessAllowed: false
                        checkForConflictsAgainst: KQuickControls.ShortcutType.None
                        onKeySequenceModified: {
                            win.shortcutFailed = !win.controller.setShortcut(keySequence)
                            win.shortcutSeq = win.controller.shortcut()
                        }
                    }
                    QQC2.Label {
                        Layout.maximumWidth: 420
                        wrapMode: Text.WordWrap
                        opacity: 0.7
                        font: Kirigami.Theme.smallFont
                        text: win.tr("general.shortcutNote")
                    }
                    Kirigami.InlineMessage {
                        Layout.fillWidth: true
                        Layout.maximumWidth: 460
                        visible: win.shortcutFailed
                        type: Kirigami.MessageType.Error
                        text: win.tr("general.shortcutFailed")
                    }

                    QQC2.Switch {
                        Kirigami.FormData.label: win.tr("general.autostart")
                        checked: win.autostartOn
                        onToggled: {
                            win.controller.setAutostart(checked)
                            win.autostartOn = win.controller.autostart()
                        }
                    }

                    Item { Kirigami.FormData.isSection: true }

                    QQC2.Button {
                        Kirigami.FormData.label: win.tr("general.searchPlugins")
                        text: win.tr("general.searchPluginsButton")
                        icon.name: "preferences-plugin"
                        onClicked: win.controller.openSearchPlugins()
                    }
                    QQC2.Label {
                        Layout.maximumWidth: 420
                        wrapMode: Text.WordWrap
                        opacity: 0.7
                        font: Kirigami.Theme.smallFont
                        text: win.tr("general.searchPluginsNote")
                    }
                }
                Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.largeSpacing }
                UsageGuide {
                    title: win.tr("guide.title")
                    intro: win.tr("guide.general.intro", win.cfg.helpKey ?? "?")
                    rows: [["↑ ↓", win.tr("help.key.navigate")], ["Ctrl ↑ ↓", win.tr("help.key.category")], ["↵", win.tr("help.key.open")], ["⇧ ↵", win.tr("help.key.firstAction")], ["Tab", win.tr("help.key.actions")], ["Ctrl 1–9", win.tr("help.key.quick")], ["⇧ Del", win.tr("help.key.removeHistory")], ["⌫", win.tr("help.key.backspace")], ["Esc", win.tr("help.key.escape")]]
                }
            }

            // Görünüm
            Page {
                title: win.tr("page.appearance")
                Kirigami.FormLayout {
                    Layout.fillWidth: true

                    SliderRow { Kirigami.FormData.label: win.tr("appearance.panelWidth"); key: "panelWidth"; from: 520; to: 1200; stepSize: 10; unit: "px" }
                    SliderRow { Kirigami.FormData.label: win.tr("appearance.maxRows"); key: "maxVisibleRows"; from: 3; to: 15 }
                    SliderRow { Kirigami.FormData.label: win.tr("appearance.rowHeight"); key: "rowHeight"; from: 40; to: 76; unit: "px" }
                    SliderRow { Kirigami.FormData.label: win.tr("appearance.iconSize"); key: "iconSize"; from: 16; to: 48; unit: "px" }
                    SliderRow { Kirigami.FormData.label: win.tr("appearance.fontSize"); key: "searchFontSize"; from: 14; to: 34; unit: "px" }
                    SliderRow { Kirigami.FormData.label: win.tr("appearance.position"); key: "topRatio"; from: 0.05; to: 0.6; stepSize: 0.01; percent: true }

                    Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: win.tr("appearance.card") }

                    SliderRow { Kirigami.FormData.label: win.tr("appearance.radius"); key: "cardRadius"; from: 0; to: 32; unit: "px" }
                    SliderRow { Kirigami.FormData.label: win.tr("appearance.opacity"); key: "cardOpacity"; from: 0.3; to: 1; stepSize: 0.01; percent: true }
                    SwitchRow { Kirigami.FormData.label: win.tr("appearance.blur"); key: "blur" }
                    SwitchRow { Kirigami.FormData.label: win.tr("appearance.shadow"); key: "shadow" }
                    RowLayout {
                        Kirigami.FormData.label: win.tr("appearance.accent")
                        spacing: Kirigami.Units.largeSpacing
                        QQC2.CheckBox {
                            text: win.tr("appearance.accentSystem")
                            checked: win.cfg.accentColor === ""
                            onToggled: win.setv("accentColor", checked ? "" : String(Kirigami.Theme.highlightColor))
                        }
                        KQuickControls.ColorButton {
                            enabled: win.cfg.accentColor !== ""
                            showAlphaChannel: false
                            color: win.cfg.accentColor !== "" ? win.cfg.accentColor : Kirigami.Theme.highlightColor
                            onAccepted: color => win.setv("accentColor", String(color))
                        }
                    }

                    Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: win.tr("appearance.content") }

                    SwitchRow { Kirigami.FormData.label: win.tr("appearance.previewEnabled"); key: "previewEnabled" }
                    SliderRow { Kirigami.FormData.label: win.tr("appearance.previewWidth"); key: "previewWidth"; from: 220; to: 560; stepSize: 10; unit: "px"; enabled: win.cfg.previewEnabled }
                    SwitchRow { Kirigami.FormData.label: win.tr("appearance.heroCard"); key: "heroCard" }
                    SwitchRow { Kirigami.FormData.label: win.tr("appearance.showSections"); key: "showSectionHeaders" }
                    SwitchRow { Kirigami.FormData.label: win.tr("appearance.showFooter"); key: "showFooter" }
                }
            }

            // Animasyon
            Page {
                title: win.tr("page.animation")
                Kirigami.FormLayout {
                    Layout.fillWidth: true
                    SliderRow { Kirigami.FormData.label: win.tr("animation.duration"); key: "animationDuration"; from: 0; to: 800; stepSize: 10; unit: "ms" }
                    SwitchRow { Kirigami.FormData.label: win.tr("animation.open"); key: "openAnimation" }
                    QQC2.Label {
                        Layout.maximumWidth: 420
                        wrapMode: Text.WordWrap
                        opacity: 0.7
                        font: Kirigami.Theme.smallFont
                        text: win.tr("animation.note")
                    }
                }
            }

            // Davranış
            Page {
                title: win.tr("page.behavior")
                Kirigami.FormLayout {
                    Layout.fillWidth: true
                    SwitchRow { Kirigami.FormData.label: win.tr("behavior.closeOnFocusLoss"); key: "closeOnFocusLoss" }
                    SwitchRow { Kirigami.FormData.label: win.tr("behavior.hoverSelect"); key: "hoverSelect" }
                    SwitchRow { Kirigami.FormData.label: win.tr("behavior.rememberQuery"); key: "rememberQuery" }

                    Item { Kirigami.FormData.isSection: true }

                    SwitchRow { Kirigami.FormData.label: win.tr("behavior.history"); key: "historyEnabled" }
                    SpinRow { Kirigami.FormData.label: win.tr("behavior.historyCount"); key: "historyCount"; from: 2; to: 16; enabled: win.cfg.historyEnabled }
                    SpinRow { Kirigami.FormData.label: win.tr("behavior.resultLimit"); key: "resultLimit"; from: 5; to: 80 }

                    Item { Kirigami.FormData.isSection: true }

                    // Ten rengi seçenekleri dilden bağımsız olarak örnek emojilerle gösterilir
                    QQC2.ComboBox {
                        Kirigami.FormData.label: win.tr("behavior.emojiSkinTone")
                        model: ["🖐️", "🖐🏻", "🖐🏼", "🖐🏽", "🖐🏾", "🖐🏿"]
                        currentIndex: win.cfg.emojiSkinTone ?? 0
                        onActivated: win.setv("emojiSkinTone", currentIndex)
                    }
                }
            }

            // Önekler
            Page {
                title: win.tr("page.prefixes")
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 720
                    spacing: Kirigami.Units.largeSpacing

                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: win.tr("prefixes.note")
                    }

                    RowLayout {
                        spacing: Kirigami.Units.largeSpacing
                        QQC2.Label { text: win.tr("prefixes.helpKey") }
                        QQC2.TextField {
                            Layout.preferredWidth: 70
                            horizontalAlignment: Text.AlignHCenter
                            maximumLength: 4
                            text: win.cfg.helpKey
                            validator: RegularExpressionValidator { regularExpression: /\S{1,4}/ }
                            onEditingFinished: if (acceptableInput) win.setv("helpKey", text)
                        }
                        QQC2.Label {
                            opacity: 0.7
                            font: Kirigami.Theme.smallFont
                            text: win.tr("prefixes.helpKeyNote")
                        }
                    }

                    Kirigami.Separator { Layout.fillWidth: true }

                    Repeater {
                        model: win.cfg.modes
                        delegate: RowLayout {
                            id: modeRow
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.largeSpacing

                            Kirigami.Icon {
                                source: modeRow.modelData.icon
                                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                                implicitHeight: Kirigami.Units.iconSizes.smallMedium
                            }

                            // Yerleşik modun adı çeviriden gelir; özel modun adı düzenlenebilir
                            QQC2.Label {
                                Layout.preferredWidth: 180
                                visible: !modeRow.modelData.custom
                                text: win.modeLabel(modeRow.modelData)
                                elide: Text.ElideRight
                            }
                            QQC2.TextField {
                                Layout.preferredWidth: 180
                                visible: modeRow.modelData.custom === true
                                text: modeRow.modelData.label ?? ""
                                placeholderText: win.tr("prefixes.label")
                                onEditingFinished: if (text !== (modeRow.modelData.label ?? "")) win.updateMode(modeRow.index, { label: text })
                            }

                            QQC2.TextField {
                                Layout.preferredWidth: 64
                                horizontalAlignment: Text.AlignHCenter
                                maximumLength: 4
                                font.family: "monospace"
                                text: modeRow.modelData.key
                                validator: RegularExpressionValidator { regularExpression: /\S{1,4}/ }
                                onEditingFinished: if (acceptableInput && text !== modeRow.modelData.key) win.updateMode(modeRow.index, { key: text })
                                QQC2.ToolTip.text: win.tr("prefixes.key")
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: 500
                            }

                            QQC2.ComboBox {
                                Layout.fillWidth: true
                                visible: modeRow.modelData.custom === true
                                model: win.runnerModel
                                textRole: "name"
                                valueRole: "id"
                                currentIndex: indexOfValue(modeRow.modelData.runner)
                                onActivated: {
                                    const r = win.runnerModel[currentIndex]
                                    win.updateMode(modeRow.index, { runner: r.id, icon: r.icon || "search",
                                                                    label: modeRow.modelData.label || r.name })
                                }
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                visible: !modeRow.modelData.custom
                                opacity: 0.6
                                elide: Text.ElideRight
                                text: win.tr("help.mode." + modeRow.modelData.id)
                            }

                            Kirigami.Icon {
                                source: "dialog-warning"
                                visible: win.keyConflict(modeRow.index)
                                implicitWidth: Kirigami.Units.iconSizes.small
                                implicitHeight: Kirigami.Units.iconSizes.small
                                HoverHandler { id: warnHover }
                                QQC2.ToolTip.text: win.tr("prefixes.duplicate")
                                QQC2.ToolTip.visible: warnHover.hovered
                            }

                            QQC2.Switch {
                                checked: modeRow.modelData.enabled
                                onToggled: win.updateMode(modeRow.index, { enabled: checked })
                                QQC2.ToolTip.text: win.tr("prefixes.enabled")
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: 500
                            }

                            QQC2.ToolButton {
                                visible: modeRow.modelData.custom === true
                                icon.name: "edit-delete"
                                onClicked: win.setv("modes", win.cfg.modes.filter((_, j) => j !== modeRow.index))
                                QQC2.ToolTip.text: win.tr("prefixes.remove")
                                QQC2.ToolTip.visible: hovered
                            }
                        }
                    }

                    Kirigami.Separator { Layout.fillWidth: true }

                    RowLayout {
                        spacing: Kirigami.Units.largeSpacing
                        QQC2.Button {
                            text: win.tr("prefixes.add")
                            icon.name: "list-add"
                            onClicked: {
                                const r = win.runnerModel[0] ?? { id: "krunner_services", icon: "search", name: "" }
                                const used = win.cfg.modes.map(m => m.key)
                                let key = "x"
                                for (const c of "bdeghijklmnopqrtuvxyz") if (!used.includes(c)) { key = c; break }
                                win.setv("modes", win.cfg.modes.concat([{ id: "custom-" + Date.now(), key: key, runner: r.id,
                                                                          icon: r.icon || "search", label: r.name,
                                                                          enabled: true, custom: true }]))
                            }
                        }
                        QQC2.Button {
                            text: win.tr("prefixes.reset")
                            icon.name: "edit-reset"
                            onClicked: {
                                win.setv("modes", win.controller.defaultModes())
                                win.setv("helpKey", "?")
                            }
                        }
                    }
                }
                Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.largeSpacing }
                UsageGuide {
                    title: win.tr("mode.browse")
                    intro: win.tr("guide.browse.intro", win.modeKey("browse"))
                    rows: [["↵  Tab", win.tr("guide.browse.enter")], ["Alt ↑", win.tr("guide.browse.up")], ["Ctrl ↵", win.tr("guide.browse.fm")], ["Alt C", win.tr("guide.browse.copy")], ["Ctrl T", win.tr("guide.browse.terminal")]]
                }
                UsageGuide {
                    title: win.tr("mode.emoji")
                    intro: win.tr("guide.emoji.intro", win.modeKey("emoji"))
                    rows: [["↵", win.tr("guide.emoji.copy")], ["⇧ ↵", win.tr("guide.emoji.name")], ["Ctrl ↑ ↓", win.tr("guide.emoji.category")]]
                }
                UsageGuide {
                    title: win.tr("mode.clipboard")
                    intro: win.tr("guide.clip.intro", win.modeKey("clipboard"))
                    rows: [["↵", win.tr("guide.clip.copy")]]
                }
                UsageGuide {
                    title: win.tr("mode.calc")
                    intro: win.tr("guide.calc.intro", win.modeKey("calc"))
                    rows: []
                }
            }

            // Arama motorları
            Page {
                title: win.tr("page.engines")
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 900
                    spacing: Kirigami.Units.largeSpacing

                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: win.tr("engines.note")
                    }

                    Kirigami.Separator { Layout.fillWidth: true }

                    Repeater {
                        model: win.cfg.searchEngines
                        delegate: RowLayout {
                            id: engineRow
                            required property var modelData
                            required property int index
                            readonly property bool noPlaceholder: !modelData.url.includes("%s")
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.largeSpacing

                            Kirigami.Icon {
                                source: win.engineIcon(engineRow.modelData.url)
                                fallback: "internet-web-browser"
                                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                                implicitHeight: Kirigami.Units.iconSizes.smallMedium
                            }
                            QQC2.TextField {
                                Layout.preferredWidth: 150
                                text: engineRow.modelData.name
                                placeholderText: win.tr("engines.name")
                                onEditingFinished: if (text.trim() && text !== engineRow.modelData.name) win.updateEngine(engineRow.index, { name: text.trim() })
                            }
                            QQC2.TextField {
                                Layout.preferredWidth: 72
                                horizontalAlignment: Text.AlignHCenter
                                maximumLength: 8
                                font.family: "monospace"
                                text: engineRow.modelData.key
                                validator: RegularExpressionValidator { regularExpression: /\S{1,8}/ }
                                onEditingFinished: if (acceptableInput && text !== engineRow.modelData.key) win.updateEngine(engineRow.index, { key: text })
                                QQC2.ToolTip.text: win.tr("engines.key")
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: 500
                            }
                            QQC2.TextField {
                                Layout.fillWidth: true
                                font.family: "monospace"
                                text: engineRow.modelData.url
                                placeholderText: "https://example.com/search?q=%s"
                                validator: RegularExpressionValidator { regularExpression: /https?:\/\/\S+/ }
                                onEditingFinished: if (acceptableInput && text !== engineRow.modelData.url) win.updateEngine(engineRow.index, { url: text })
                                QQC2.ToolTip.text: win.tr("engines.url")
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: 500
                            }
                            Kirigami.Icon {
                                source: "dialog-warning"
                                visible: win.engineConflict(engineRow.index) || engineRow.noPlaceholder
                                implicitWidth: Kirigami.Units.iconSizes.small
                                implicitHeight: Kirigami.Units.iconSizes.small
                                HoverHandler { id: engineWarnHover }
                                QQC2.ToolTip.text: win.engineConflict(engineRow.index) ? win.tr("prefixes.duplicate") : win.tr("engines.noPlaceholder")
                                QQC2.ToolTip.visible: engineWarnHover.hovered
                            }
                            QQC2.Switch {
                                checked: engineRow.modelData.enabled
                                onToggled: win.updateEngine(engineRow.index, { enabled: checked })
                                QQC2.ToolTip.text: win.tr("prefixes.enabled")
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: 500
                            }
                            QQC2.ToolButton {
                                icon.name: "edit-delete"
                                onClicked: win.setv("searchEngines", win.cfg.searchEngines.filter((_, j) => j !== engineRow.index))
                                QQC2.ToolTip.text: win.tr("prefixes.remove")
                                QQC2.ToolTip.visible: hovered
                            }
                        }
                    }

                    Kirigami.Separator { Layout.fillWidth: true }

                    RowLayout {
                        spacing: Kirigami.Units.largeSpacing
                        QQC2.Button {
                            text: win.tr("engines.add")
                            icon.name: "list-add"
                            onClicked: {
                                const used = win.cfg.searchEngines.map(e => e.key).concat(win.cfg.modes.map(m => m.key))
                                let n = 1
                                while (used.includes("e" + n)) n++
                                win.setv("searchEngines", win.cfg.searchEngines.concat([{ id: "engine-" + Date.now(), key: "e" + n,
                                                                                          name: win.tr("engines.newName"),
                                                                                          url: "https://", enabled: true }]))
                            }
                        }
                        QQC2.Button {
                            text: win.tr("prefixes.reset")
                            icon.name: "edit-reset"
                            onClicked: win.setv("searchEngines", win.controller.defaultSearchEngines())
                        }
                    }
                }
                Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.largeSpacing }
                UsageGuide {
                    title: win.tr("mode.web")
                    intro: win.tr("guide.web.intro", win.modeKey("web"))
                    rows: [["↵", win.tr("guide.web.open")]]
                }
                UsageGuide {
                    title: win.tr("help.engines")
                    intro: win.tr("engines.note")
                    rows: [["↵", win.tr("guide.engine.open")]]
                }
            }

            // Yapay zekâ
            Page {
                title: win.tr("page.ai")
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 900
                    spacing: Kirigami.Units.largeSpacing

                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: win.tr("aiset.note")
                    }
                    Kirigami.UrlButton {
                        text: win.tr("aiset.guide")
                        url: "https://github.com/Vialeth/kandil/blob/main/docs/local-ai.md"
                    }

                    Repeater {
                        model: win.cfg.aiProviders
                        delegate: QQC2.Frame {
                            id: providerCard
                            required property var modelData
                            required property int index
                            readonly property bool anthropic: modelData.type === "anthropic"
                            Layout.fillWidth: true

                            GridLayout {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                columns: 2
                                columnSpacing: Kirigami.Units.largeSpacing
                                rowSpacing: Kirigami.Units.smallSpacing

                                QQC2.Label { text: win.tr("engines.name") }
                                RowLayout {
                                    Layout.fillWidth: true
                                    QQC2.TextField {
                                        Layout.fillWidth: true
                                        text: providerCard.modelData.name
                                        onEditingFinished: if (text.trim() && text !== providerCard.modelData.name) win.updateProvider(providerCard.index, { name: text.trim() })
                                    }
                                    QQC2.Switch {
                                        checked: providerCard.modelData.enabled
                                        onToggled: win.updateProvider(providerCard.index, { enabled: checked })
                                        QQC2.ToolTip.text: win.tr("prefixes.enabled")
                                        QQC2.ToolTip.visible: hovered
                                        QQC2.ToolTip.delay: 500
                                    }
                                    QQC2.ToolButton {
                                        icon.name: "edit-delete"
                                        onClicked: win.setv("aiProviders", win.cfg.aiProviders.filter((_, j) => j !== providerCard.index))
                                        QQC2.ToolTip.text: win.tr("prefixes.remove")
                                        QQC2.ToolTip.visible: hovered
                                    }
                                }

                                QQC2.Label { text: win.tr("engines.key") }
                                RowLayout {
                                    QQC2.TextField {
                                        Layout.preferredWidth: 90
                                        horizontalAlignment: Text.AlignHCenter
                                        font.family: "monospace"
                                        maximumLength: 12
                                        text: providerCard.modelData.key
                                        validator: RegularExpressionValidator { regularExpression: /\S{1,12}/ }
                                        onEditingFinished: if (acceptableInput && text !== providerCard.modelData.key) win.updateProvider(providerCard.index, { key: text })
                                    }
                                    Kirigami.Icon {
                                        source: "dialog-warning"
                                        visible: win.providerConflict(providerCard.index)
                                        implicitWidth: Kirigami.Units.iconSizes.small
                                        implicitHeight: Kirigami.Units.iconSizes.small
                                        HoverHandler { id: providerWarn }
                                        QQC2.ToolTip.text: win.tr("engines.duplicate")
                                        QQC2.ToolTip.visible: providerWarn.hovered
                                    }
                                }

                                QQC2.Label { text: win.tr("aiset.type") }
                                QQC2.ComboBox {
                                    model: [win.tr("aiset.typeOpenai"), "Anthropic (Claude)"]
                                    currentIndex: providerCard.anthropic ? 1 : 0
                                    onActivated: win.updateProvider(providerCard.index, { type: currentIndex === 1 ? "anthropic" : "openai" })
                                }

                                QQC2.Label { text: win.tr("aiset.url") }
                                QQC2.TextField {
                                    Layout.fillWidth: true
                                    font.family: "monospace"
                                    text: providerCard.modelData.url
                                    validator: RegularExpressionValidator { regularExpression: /https?:\/\/\S+/ }
                                    onEditingFinished: if (acceptableInput && text !== providerCard.modelData.url) win.updateProvider(providerCard.index, { url: text })
                                }

                                QQC2.Label { text: win.tr("aiset.key") }
                                QQC2.TextField {
                                    Layout.fillWidth: true
                                    echoMode: TextInput.Password
                                    placeholderText: { win.aiKeyTick; return win.controller.aiHasKey(providerCard.modelData.id) ? win.tr("aiset.keySaved") : win.tr("aiset.keyNone") }
                                    onEditingFinished: if (text) {
                                        win.controller.setAiKey(providerCard.modelData.id, text)
                                        text = ""
                                        win.aiKeyTick++
                                    }
                                }

                                QQC2.Label { text: win.tr("aiset.model") }
                                RowLayout {
                                    Layout.fillWidth: true
                                    QQC2.ComboBox {
                                        id: modelBox
                                        Layout.fillWidth: true
                                        editable: true
                                        model: win.aiModelLists[providerCard.modelData.id] ?? []
                                        editText: providerCard.modelData.model
                                        onAccepted: if (editText !== providerCard.modelData.model) win.updateProvider(providerCard.index, { model: editText.trim() })
                                        onActivated: win.updateProvider(providerCard.index, { model: currentText })
                                        QQC2.ToolTip.text: win.tr("aiset.modelAuto")
                                        QQC2.ToolTip.visible: hovered && !providerCard.modelData.model
                                        QQC2.ToolTip.delay: 500
                                    }
                                    QQC2.Button {
                                        icon.name: "view-refresh"
                                        text: win.tr("aiset.fetchModels")
                                        onClicked: win.controller.aiModels(providerCard.modelData.id)
                                    }
                                }
                                Item { visible: !!win.aiModelErrors[providerCard.modelData.id] }
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    visible: !!win.aiModelErrors[providerCard.modelData.id]
                                    text: win.aiModelErrors[providerCard.modelData.id] ?? ""
                                    color: Kirigami.Theme.negativeTextColor
                                    wrapMode: Text.WordWrap
                                }

                                QQC2.Label { text: win.tr("aiset.effort"); visible: providerCard.anthropic }
                                QQC2.ComboBox {
                                    visible: providerCard.anthropic
                                    model: [win.tr("aiset.effortDefault"), "low", "medium", "high", "xhigh", "max"]
                                    currentIndex: Math.max(0, ["", "low", "medium", "high", "xhigh", "max"].indexOf(providerCard.modelData.effort))
                                    onActivated: win.updateProvider(providerCard.index, { effort: ["", "low", "medium", "high", "xhigh", "max"][currentIndex] })
                                }
                            }
                        }
                    }

                    RowLayout {
                        spacing: Kirigami.Units.largeSpacing
                        QQC2.Button {
                            text: win.tr("aiset.add")
                            icon.name: "list-add"
                            onClicked: presetMenu.popup()
                            QQC2.Menu {
                                id: presetMenu
                                Instantiator {
                                    model: ["ollama", "lmstudio", "llamacpp", "openai", "openrouter", "anthropic"]
                                    delegate: QQC2.MenuItem {
                                        required property string modelData
                                        text: win.controller.aiPresets()[modelData].name
                                        onTriggered: win.addProvider(modelData)
                                    }
                                    onObjectAdded: (index, object) => presetMenu.insertItem(index, object)
                                    onObjectRemoved: (index, object) => presetMenu.removeItem(object)
                                }
                            }
                        }
                    }

                    Kirigami.Separator { Layout.fillWidth: true }

                    QQC2.Label { text: win.tr("aiset.systemPrompt") }
                    QQC2.TextArea {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 90
                        wrapMode: TextEdit.Wrap
                        text: win.cfg.aiSystemPrompt
                        placeholderText: win.tr("aiset.systemPromptDefault")
                        onEditingFinished: if (text !== win.cfg.aiSystemPrompt) win.setv("aiSystemPrompt", text)
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        opacity: 0.7
                        font: Kirigami.Theme.smallFont
                        text: win.tr("aiset.keysNote")
                    }
                }
                Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.largeSpacing }
                UsageGuide {
                    title: win.tr("guide.title")
                    intro: win.tr("guide.ai.intro", win.aiKey())
                    rows: [["↵", win.tr("guide.ai.send")], ["Esc", win.tr("guide.ai.stop")], ["Alt C", win.tr("guide.ai.copy")], ["Ctrl N", win.tr("guide.ai.newChat")]]
                }
            }

            // Komutlar
            Page {
                title: win.tr("page.command")
                Kirigami.FormLayout {
                    Layout.fillWidth: true
                    SpinRow { Kirigami.FormData.label: win.tr("command.timeout"); key: "commandTimeout"; from: 1; to: 600; suffix: " " + win.tr("command.secondsUnit") }
                    QQC2.TextField {
                        Kirigami.FormData.label: win.tr("command.shell")
                        Layout.preferredWidth: 280
                        font.family: "monospace"
                        text: win.cfg.commandShell
                        onEditingFinished: if (text.trim()) win.setv("commandShell", text.trim())
                    }
                    QQC2.TextField {
                        Kirigami.FormData.label: win.tr("command.terminal")
                        Layout.preferredWidth: 280
                        font.family: "monospace"
                        text: win.cfg.terminalCommand
                        onEditingFinished: if (text.trim()) win.setv("terminalCommand", text.trim())
                    }
                    QQC2.Label {
                        Layout.maximumWidth: 420
                        wrapMode: Text.WordWrap
                        opacity: 0.7
                        font: Kirigami.Theme.smallFont
                        text: win.tr("command.terminalNote")
                    }
                }
                Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.largeSpacing }
                UsageGuide {
                    title: win.tr("guide.title")
                    intro: win.tr("guide.cmd.intro", win.modeKey("command"))
                    rows: [["↵", win.tr("guide.cmd.run")], ["Ctrl ↵", win.tr("guide.cmd.terminal")], ["Alt C", win.tr("guide.cmd.copy")]]
                }
            }

            // Veriler
            Page {
                title: win.tr("page.data")
                Kirigami.FormLayout {
                    Layout.fillWidth: true

                    RowLayout {
                        Kirigami.FormData.label: win.tr("data.history")
                        spacing: Kirigami.Units.largeSpacing
                        QQC2.Label { text: win.tr("data.historyCount", win.historySize) }
                        ConfirmButton {
                            text: win.tr("data.clearHistory")
                            icon.name: "edit-clear-history"
                            enabled: win.historySize > 0
                            onConfirmed: {
                                win.controller.clearHistory()
                                win.historySize = 0
                            }
                        }
                    }

                    ConfirmButton {
                        Kirigami.FormData.label: win.tr("data.emojiRecent")
                        text: win.tr("data.clearEmoji")
                        icon.name: "edit-clear-history"
                        onConfirmed: win.controller.clearEmojiRecent()
                    }

                    QQC2.Button {
                        Kirigami.FormData.label: win.tr("data.config")
                        text: win.tr("data.openConfig")
                        icon.name: "document-edit"
                        onClicked: win.controller.openConfigFile()
                    }

                    ConfirmButton {
                        Kirigami.FormData.label: win.tr("data.reset")
                        text: win.tr("data.resetButton")
                        icon.name: "edit-reset"
                        onConfirmed: {
                            win.dirty = false
                            saveTimer.stop()
                            win.controller.resetConfig()
                            win.cfg = win.controller.currentConfig()
                        }
                    }
                }
            }

            // Hakkında
            Page {
                title: win.tr("page.about")
                ColumnLayout {
                    spacing: Kirigami.Units.largeSpacing
                    RowLayout {
                        spacing: Kirigami.Units.largeSpacing * 2
                        Kirigami.Icon {
                            source: "search"
                            implicitWidth: Kirigami.Units.iconSizes.huge
                            implicitHeight: Kirigami.Units.iconSizes.huge
                        }
                        ColumnLayout {
                            Kirigami.Heading { text: win.tr("app.name"); level: 1 }
                            QQC2.Label { text: win.tr("about.version", win.controller.version()); opacity: 0.7 }
                        }
                    }
                    QQC2.Label {
                        Layout.maximumWidth: 520
                        wrapMode: Text.WordWrap
                        text: win.tr("about.description")
                    }
                    QQC2.Label {
                        Layout.maximumWidth: 520
                        wrapMode: Text.WordWrap
                        opacity: 0.7
                        text: win.tr("about.builtWith")
                    }
                    Kirigami.FormLayout {
                        readonly property var p: win.controller.paths()
                        QQC2.Label { Kirigami.FormData.label: win.tr("about.configFile"); text: parent.p.config; font.family: "monospace" }
                        QQC2.Label { Kirigami.FormData.label: win.tr("about.historyFile"); text: parent.p.history; font.family: "monospace" }
                        QQC2.Label { Kirigami.FormData.label: win.tr("about.programDir"); text: parent.p.program; font.family: "monospace" }
                    }
                }
            }
        }
    }

    // ── Yardımcı bileşenler ──────────────────────────────────────────
    component Page: QQC2.ScrollView {
        id: page
        property string title
        default property alias content: body.data
        contentWidth: availableWidth
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            id: body
            width: page.availableWidth - Kirigami.Units.gridUnit * 2
            x: Kirigami.Units.gridUnit
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Heading {
                Layout.topMargin: Kirigami.Units.gridUnit
                Layout.bottomMargin: Kirigami.Units.smallSpacing
                text: page.title
                level: 1
            }
        }
    }

    // Bir özelliğin kullanımı: kısa açıklama ve tuş satırları
    component UsageGuide: ColumnLayout {
        id: usage
        property string title
        property string intro
        property var rows: []
        Layout.fillWidth: true
        Layout.maximumWidth: 720
        Layout.bottomMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            text: usage.title
            level: 3
        }
        QQC2.Label {
            Layout.fillWidth: true
            visible: usage.intro !== ""
            text: usage.intro
            wrapMode: Text.WordWrap
            opacity: 0.85
        }
        Repeater {
            model: usage.rows
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing
                Item {
                    Layout.preferredWidth: 96
                    Layout.preferredHeight: keyCap.height
                    Rectangle {
                        id: keyCap
                        width: keyText.implicitWidth + 14
                        height: keyText.implicitHeight + 6
                        radius: 4
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.06)
                        border.width: 1
                        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.25)
                        QQC2.Label {
                            id: keyText
                            anchors.centerIn: parent
                            text: modelData[0]
                            font.family: "monospace"
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                    }
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    text: modelData[1]
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    component SliderRow: RowLayout {
        id: sr
        property string key
        property real from: 0
        property real to: 100
        property real stepSize: 1
        property string unit: ""
        property bool percent: false
        spacing: Kirigami.Units.largeSpacing

        QQC2.Slider {
            id: slider
            Layout.preferredWidth: 280
            from: sr.from
            to: sr.to
            // stepSize verilmez: Breeze her adım için çentik çiziyor; yuvarlama burada yapılır
            readonly property real snapped: Math.round(value / sr.stepSize) * sr.stepSize
            value: win.cfg[sr.key] ?? sr.from
            onMoved: win.setv(sr.key, sr.stepSize < 1 ? Math.round(snapped * 100) / 100 : Math.round(snapped))
        }
        QQC2.Label {
            Layout.minimumWidth: 64
            text: sr.percent ? Math.round(slider.snapped * 100) + " %"
                             : Math.round(slider.snapped) + (sr.unit ? " " + sr.unit : "")
        }
    }

    component SwitchRow: QQC2.Switch {
        property string key
        checked: win.cfg[key] === true
        onToggled: win.setv(key, checked)
    }

    component SpinRow: QQC2.SpinBox {
        property string key
        property string suffix: ""
        editable: true
        value: win.cfg[key] ?? from
        onValueModified: win.setv(key, value)
        textFromValue: (v, locale) => Number(v).toLocaleString(locale, "f", 0) + suffix
        valueFromText: (text, locale) => Number.fromLocaleString(locale, text.replace(suffix, "").trim())
    }

    // İlk tıklamada onay ister, ikinci tıklamada işlemi yapar
    component ConfirmButton: QQC2.Button {
        id: cb
        property bool armed: false
        signal confirmed()
        onClicked: {
            if (armed) {
                armed = false
                confirmed()
            } else {
                armed = true
                disarm.restart()
            }
        }
        Binding on text {
            when: cb.armed
            value: win.tr("common.confirm")
        }
        Timer {
            id: disarm
            interval: 4000
            onTriggered: cb.armed = false
        }
    }
}
