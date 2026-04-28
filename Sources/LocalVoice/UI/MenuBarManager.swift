import AppKit
import Sparkle

enum MenuBarCopy {
    static let modeTitle = "Mode"
    static let languageTitle = "Language"
    static let whisperTitle = "Whisper"
    static let refineModelTitle = "Refine Model"
    static let promptTitle = "Prompt"

    static func promptShortcutHint() -> String {
        "Press 1-9 during recording"
    }
}

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
    private var permissionPollTimer: Timer?
    private var isRecording = false
    private var isLoading = false
    private var hasMissingPermissions = false

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
        refreshPermissionsState()
        startPermissionPolling()
    }

    private func configureButton() {
        updateStatusIcon()
    }

    func setLoading(_ loading: Bool) {
        DispatchQueue.main.async {
            self.isLoading = loading
            self.updateStatusIcon()
            self.buildMenu()
        }
    }

    func setRecording(_ recording: Bool) {
        DispatchQueue.main.async {
            self.isRecording = recording
            self.updateStatusIcon()
            self.buildMenu()
        }
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        let statusTitle: String
        if hasMissingPermissions {
            statusTitle = "LocalVoice - permissions required"
        } else if isRecording {
            statusTitle = "LocalVoice - recording"
        } else if isLoading {
            statusTitle = "LocalVoice - loading Whisper"
        } else {
            statusTitle = "LocalVoice - ready"
        }
        let statusHeaderItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusHeaderItem.isEnabled = false
        menu.addItem(statusHeaderItem)
        menu.addItem(.separator())

        if hasMissingPermissions {
            let permissionsWarning = NSMenuItem(
                title: "Open Settings to finish permissions...",
                action: #selector(settingsSelected),
                keyEquivalent: ""
            )
            permissionsWarning.target = self
            menu.addItem(permissionsWarning)
            menu.addItem(.separator())
        }

        // Mode
        let modeItem = NSMenuItem(title: MenuBarCopy.modeTitle, action: nil, keyEquivalent: "")
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
        let langItem = NSMenuItem(title: MenuBarCopy.languageTitle, action: nil, keyEquivalent: "")
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
        let whisperItem = NSMenuItem(title: MenuBarCopy.whisperTitle, action: nil, keyEquivalent: "")
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

        // Refine model
        let refineModelItem = NSMenuItem(title: MenuBarCopy.refineModelTitle, action: nil, keyEquivalent: "")
        let refineModelSubmenu = NSMenu()
        for model in MLXModelCatalog.models {
            let item = NSMenuItem(
                title: model.displayName,
                action: #selector(llmModelSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = model.id
            item.state = (model.id == settings.llmModel) ? .on : .off
            refineModelSubmenu.addItem(item)
        }
        refineModelItem.submenu = refineModelSubmenu
        menu.addItem(refineModelItem)

        // Prompt
        let activePrompt = promptStore.activePrompt(id: settings.activePromptID)
        let promptItem = NSMenuItem(title: MenuBarCopy.promptTitle, action: nil, keyEquivalent: "")
        let promptSubmenu = NSMenu()
        for p in promptStore.prompts {
            let item = NSMenuItem(title: p.name, action: #selector(promptSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = p.id
            item.state = (p.id == activePrompt.id) ? .on : .off
            promptSubmenu.addItem(item)
        }
        promptItem.submenu = promptSubmenu
        menu.addItem(promptItem)

        menu.addItem(.separator())

        // History
        let historyItem = NSMenuItem(title: "History...", action: #selector(historySelected), keyEquivalent: "h")
        historyItem.target = self
        menu.addItem(historyItem)

        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(settingsSelected), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Check for Updates
        if let updater = updaterController?.updater {
            let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
            updateItem.target = updaterController
            updateItem.isEnabled = updater.canCheckForUpdates
            menu.addItem(updateItem)
        }

        menu.addItem(.separator())

        // Hotkey hint
        let hotkeyHint = NSMenuItem(title: "Hold \(settings.recordingHotkey.label) to record", action: nil, keyEquivalent: "")
        hotkeyHint.isEnabled = false
        menu.addItem(hotkeyHint)

        let promptHint = NSMenuItem(title: MenuBarCopy.promptShortcutHint(), action: nil, keyEquivalent: "")
        promptHint.isEnabled = false
        menu.addItem(promptHint)

        menu.addItem(.separator())

        // Quit
        let quit = NSMenuItem(title: "Quit LocalVoice", action: #selector(quitSelected), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        self.statusItem.menu = menu
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

    @objc private func llmModelSelected(_ sender: NSMenuItem) {
        guard let model = sender.representedObject as? String else { return }
        delegate?.llmModelChanged(to: model)
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

    private func startPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshPermissionsState()
        }
    }

    private func refreshPermissionsState() {
        DispatchQueue.main.async {
            let missingNow = !PermissionManager.current().allGranted
            guard missingNow != self.hasMissingPermissions else { return }
            self.hasMissingPermissions = missingNow
            self.updateStatusIcon()
            self.buildMenu()
        }
    }

    private func updateStatusIcon() {
        let symbolName: String
        let description: String

        if hasMissingPermissions {
            symbolName = "exclamationmark.triangle.fill"
            description = "LocalVoice needs permissions"
        } else if isLoading {
            symbolName = "hourglass"
            description = "LocalVoice is loading"
        } else if isRecording {
            symbolName = "waveform.circle.fill"
            description = "Recording"
        } else {
            symbolName = "waveform.circle"
            description = "LocalVoice"
        }

        statusButton?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        statusButton?.image?.isTemplate = true
    }

    deinit {
        permissionPollTimer?.invalidate()
    }
}
