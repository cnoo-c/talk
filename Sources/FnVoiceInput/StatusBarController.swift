import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject {
    private let preferences: AppPreferences
    private let permissionState: PermissionState
    private let fnKeyDiagnostics: FnKeyDiagnostics
    private let onOpenSettings: () -> Void
    private let onRequestAccessibility: () -> Void
    private let onOpenAccessibilitySettings: () -> Void
    private let onOpenMicrophoneSettings: () -> Void
    private let onOpenSpeechSettings: () -> Void
    private let onRequestMicrophonePermission: () -> Void
    private let onRequestSpeechPermission: () -> Void
    private let onQuit: () -> Void
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    init(
        preferences: AppPreferences,
        permissionState: PermissionState,
        fnKeyDiagnostics: FnKeyDiagnostics,
        onOpenSettings: @escaping () -> Void,
        onRequestAccessibility: @escaping () -> Void,
        onOpenAccessibilitySettings: @escaping () -> Void,
        onOpenMicrophoneSettings: @escaping () -> Void,
        onOpenSpeechSettings: @escaping () -> Void,
        onRequestMicrophonePermission: @escaping () -> Void,
        onRequestSpeechPermission: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.permissionState = permissionState
        self.fnKeyDiagnostics = fnKeyDiagnostics
        self.onOpenSettings = onOpenSettings
        self.onRequestAccessibility = onRequestAccessibility
        self.onOpenAccessibilitySettings = onOpenAccessibilitySettings
        self.onOpenMicrophoneSettings = onOpenMicrophoneSettings
        self.onOpenSpeechSettings = onOpenSpeechSettings
        self.onRequestMicrophonePermission = onRequestMicrophonePermission
        self.onRequestSpeechPermission = onRequestSpeechPermission
        self.onQuit = onQuit
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "waveform.badge.mic", accessibilityDescription: "语音输入")
        item.button?.imagePosition = .imageOnly
        statusItem = item
        rebuildMenu()

        preferences.$language
            .combineLatest(preferences.$llmConfiguration, permissionState.$accessibilityGranted)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        permissionState.$microphoneAuthorized
            .combineLatest(permissionState.$speechAuthorized)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        fnKeyDiagnostics.$tapInstalled
            .combineLatest(fnKeyDiagnostics.$lastEventSummary)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "按住 Option 键开始语音输入", action: nil, keyEquivalent: ""))
        let accessItem = NSMenuItem(
            title: permissionState.accessibilityGranted ? "辅助功能：已授权" : "辅助功能：未授权",
            action: permissionState.accessibilityGranted ? nil : #selector(requestAccessibility),
            keyEquivalent: ""
        )
        accessItem.target = self
        menu.addItem(accessItem)
        let microphoneItem = NSMenuItem(
            title: permissionState.microphoneAuthorized ? "麦克风：已授权" : "麦克风：未授权",
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(microphoneItem)
        let speechItem = NSMenuItem(
            title: permissionState.speechAuthorized ? "语音识别：已授权" : "语音识别：未授权",
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(speechItem)
        menu.addItem(NSMenuItem(
            title: fnKeyDiagnostics.tapInstalled ? "事件监听：已启用" : "事件监听：未启用",
            action: nil,
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: "最近热键事件：\(fnKeyDiagnostics.lastEventSummary)",
            action: nil,
            keyEquivalent: ""
        ))
        let openAccessibilityItem = NSMenuItem(title: "打开辅助功能设置", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        openAccessibilityItem.target = self
        menu.addItem(openAccessibilityItem)
        let openMicrophoneItem = NSMenuItem(title: "打开麦克风设置", action: #selector(openMicrophoneSettings), keyEquivalent: "")
        openMicrophoneItem.target = self
        menu.addItem(openMicrophoneItem)
        let openSpeechItem = NSMenuItem(title: "打开语音识别设置", action: #selector(openSpeechSettings), keyEquivalent: "")
        openSpeechItem.target = self
        menu.addItem(openSpeechItem)
        let requestMicrophoneItem = NSMenuItem(title: "请求麦克风权限", action: #selector(requestMicrophonePermission), keyEquivalent: "")
        requestMicrophoneItem.target = self
        menu.addItem(requestMicrophoneItem)
        let requestSpeechItem = NSMenuItem(title: "请求语音识别权限", action: #selector(requestSpeechPermission), keyEquivalent: "")
        requestSpeechItem.target = self
        menu.addItem(requestSpeechItem)
        menu.addItem(.separator())

        let languageItem = NSMenuItem(title: "识别语言", action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()
        for option in RecognitionLanguage.allCases {
            let item = NSMenuItem(title: option.title, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = preferences.language == option ? .on : .off
            languageMenu.addItem(item)
        }
        menu.setSubmenu(languageMenu, for: languageItem)
        menu.addItem(languageItem)

        let llmItem = NSMenuItem(title: "LLM 纠错润色", action: nil, keyEquivalent: "")
        let llmMenu = NSMenu()
        let enableItem = NSMenuItem(
            title: preferences.llmConfiguration.enabled ? "关闭" : "开启",
            action: #selector(toggleLLM),
            keyEquivalent: ""
        )
        enableItem.target = self
        llmMenu.addItem(enableItem)
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        llmMenu.addItem(settingsItem)
        menu.setSubmenu(llmMenu, for: llmItem)
        menu.addItem(llmItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem?.menu = menu
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let language = RecognitionLanguage(rawValue: raw) else { return }
        preferences.language = language
    }

    @objc private func toggleLLM() {
        var config = preferences.llmConfiguration
        config.enabled.toggle()
        preferences.llmConfiguration = config
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func requestAccessibility() {
        onRequestAccessibility()
    }

    @objc private func openAccessibilitySettings() {
        onOpenAccessibilitySettings()
    }

    @objc private func openMicrophoneSettings() {
        onOpenMicrophoneSettings()
    }

    @objc private func openSpeechSettings() {
        onOpenSpeechSettings()
    }

    @objc private func requestMicrophonePermission() {
        onRequestMicrophonePermission()
    }

    @objc private func requestSpeechPermission() {
        onRequestSpeechPermission()
    }

    @objc private func quit() {
        onQuit()
    }
}
