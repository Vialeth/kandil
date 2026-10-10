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
