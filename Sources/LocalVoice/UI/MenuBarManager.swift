import AppKit
import Sparkle

protocol MenuBarDelegate: AnyObject {
    func modeChanged(to mode: AppMode)
    func llmModelChanged(to model: String)
    func whisperModelChanged(to model: String)
    func languageChanged(to language: TranscriptionLanguage)
    func promptChanged(to id: UUID)
    func showHistory()
    func showSettings()
    func quitApp()
}

final class MenuBarManager: NSObject {
    private let statusItem: NSStatusItem
    private let settings: AppSettings
    private let promptStore: PromptStore
    private weak var delegate: MenuBarDelegate?
    private weak var updaterController: SPUStandardUpdaterController?

    private var statusButton: NSStatusBarButton? { statusItem.button }

    init(settings: AppSettings, promptStore: PromptStore, delegate: MenuBarDelegate, updaterController: SPUStandardUpdaterController) {
        self.settings = settings
        self.promptStore = promptStore
        self.delegate = delegate
        self.updaterController = updaterController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        buildMenu()
    }

    private func configureButton() {
        statusButton?.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "LocalVoice")
        statusButton?.image?.isTemplate = true
    }

    func setLoading(_ loading: Bool) {
        DispatchQueue.main.async {
            self.statusButton?.appearsDisabled = loading
        }
    }

    func setRecording(_ recording: Bool) {
        DispatchQueue.main.async {
            let symbolName = recording ? "waveform.circle.fill" : "waveform.circle"
            self.statusButton?.image = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: recording ? "Recording…" : "LocalVoice"
            )
            self.statusButton?.image?.isTemplate = true
        }
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        // Mode
        let modeItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        let modeSubmenu = NSMenu()

        for mode in AppMode.allCases {
            let item = NSMenuItem(
                title: mode.rawValue,
                action: #selector(modeSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode
            item.state = (mode == settings.mode) ? .on : .off
            modeSubmenu.addItem(item)
        }
        modeItem.submenu = modeSubmenu
        menu.addItem(modeItem)

        // Language
        let langItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        let langSubmenu = NSMenu()
        for language in TranscriptionLanguage.allCases {
            let item = NSMenuItem(
                title: language.displayName,
                action: #selector(languageSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = language
            item.state = (language == settings.transcriptionLanguage) ? .on : .off
            langSubmenu.addItem(item)
        }
        langItem.submenu = langSubmenu
        menu.addItem(langItem)

        // Whisper model
        let whisperItem = NSMenuItem(title: "Whisper Model", action: nil, keyEquivalent: "")
        let whisperSubmenu = NSMenu()
        for model in TranscriptionEngine.availableModels {
            let item = NSMenuItem(
                title: TranscriptionEngine.displayName(for: model),
                action: #selector(whisperModelSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = model
            item.state = (model == settings.whisperModel) ? .on : .off
            whisperSubmenu.addItem(item)
        }
        whisperItem.submenu = whisperSubmenu
        menu.addItem(whisperItem)

        // Prompt
        let promptItem = NSMenuItem(title: "Prompt", action: nil, keyEquivalent: "")
        let promptSubmenu = NSMenu()
        for p in promptStore.prompts {
            let label = p.keyNumber.map { "\(p.name)  [\($0)]" } ?? p.name
            let item = NSMenuItem(title: label, action: #selector(promptSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = p.id
            item.state = (p.id == settings.activePromptID) ? .on : .off
            promptSubmenu.addItem(item)
        }
        promptItem.submenu = promptSubmenu
        menu.addItem(promptItem)

        menu.addItem(.separator())

        // History
        let historyItem = NSMenuItem(title: "History…", action: #selector(historySelected), keyEquivalent: "h")
        historyItem.target = self
        menu.addItem(historyItem)

        // Settings
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(settingsSelected), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Check for Updates
        if let updater = updaterController?.updater {
            let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
            updateItem.target = updaterController
            updateItem.isEnabled = updater.canCheckForUpdates
            menu.addItem(updateItem)
        }

        menu.addItem(.separator())

        // Hotkey hint
        let hotkeyHint = NSMenuItem(title: "Hold Right ⌘ to record", action: nil, keyEquivalent: "")
        hotkeyHint.isEnabled = false
        menu.addItem(hotkeyHint)

        menu.addItem(.separator())

        // Quit
        let quit = NSMenuItem(title: "Quit LocalVoice", action: #selector(quitSelected), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func modeSelected(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? AppMode else { return }
        delegate?.modeChanged(to: mode)
        rebuildMenuCheckmarks()
    }

    @objc private func whisperModelSelected(_ sender: NSMenuItem) {
        guard let model = sender.representedObject as? String else { return }
        delegate?.whisperModelChanged(to: model)
        rebuildMenuCheckmarks()
    }

    @objc private func languageSelected(_ sender: NSMenuItem) {
        guard let language = sender.representedObject as? TranscriptionLanguage else { return }
        delegate?.languageChanged(to: language)
        rebuildMenuCheckmarks()
    }

    @objc private func promptSelected(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        delegate?.promptChanged(to: id)
        rebuildMenuCheckmarks()
    }

    @objc private func historySelected() {
        delegate?.showHistory()
    }

    @objc private func settingsSelected() {
        delegate?.showSettings()
    }

    @objc private func quitSelected() {
        delegate?.quitApp()
    }

    private func rebuildMenuCheckmarks() {
        buildMenu()
    }
}
