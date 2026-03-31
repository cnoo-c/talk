import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = AppPreferences.shared
    private let permissionState = PermissionState()
    private let fnKeyDiagnostics = FnKeyDiagnostics()
    private lazy var overlayController = OverlayPanelController()
    private lazy var speechService = SpeechRecognizerService(localeProvider: { [weak self] in
        self?.preferences.language.rawValue ?? RecognitionLanguage.simplifiedChinese.rawValue
    })
    private lazy var llmRefiner = LLMRefiner(preferences: preferences)
    private lazy var settingsWindowController = SettingsWindowController(
        preferences: preferences,
        llmRefiner: llmRefiner
    )
    private lazy var statusBarController = StatusBarController(
        preferences: preferences,
        permissionState: permissionState,
        fnKeyDiagnostics: fnKeyDiagnostics,
        onOpenSettings: { [weak self] in self?.settingsWindowController.showWindow(nil) },
        onRequestAccessibility: { [weak self] in self?.permissionState.requestAccessibilityPrompt() },
        onOpenAccessibilitySettings: { [weak self] in self?.permissionState.openAccessibilitySettings() },
        onOpenMicrophoneSettings: { [weak self] in self?.permissionState.openMicrophoneSettings() },
        onOpenSpeechSettings: { [weak self] in self?.permissionState.openSpeechSettings() },
        onRequestMicrophonePermission: { [weak self] in self?.requestMicrophonePermission() },
        onRequestSpeechPermission: { [weak self] in self?.requestSpeechPermission() },
        onQuit: { NSApp.terminate(nil) }
    )
    private lazy var fnKeyMonitor = GlobalFnKeyMonitor(
        diagnostics: fnKeyDiagnostics,
        onPress: { [weak self] in self?.beginRecordingFlow() },
        onRelease: { [weak self] in self?.endRecordingFlow() },
        onPermissionIssue: { [weak self] in self?.permissionState.requestAccessibilityPrompt() }
    )

    private var cancellables = Set<AnyCancellable>()
    private var recordingTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        permissionState.refresh()
        statusBarController.install()
        bindOverlay()
        if !permissionState.accessibilityGranted {
            permissionState.requestAccessibilityPrompt()
        }
        Task { @MainActor [weak self] in
            await self?.permissionState.requestInputPermissionsIfNeeded()
        }
        fnKeyMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        fnKeyMonitor.stop()
        speechService.cancel()
    }

    private func bindOverlay() {
        speechService.$displayText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                self?.overlayController.updateText(text)
            }
            .store(in: &cancellables)

        speechService.$meterLevel
            .receive(on: RunLoop.main)
            .sink { [weak self] level in
                self?.overlayController.updateLevel(level)
            }
            .store(in: &cancellables)
    }

    private func beginRecordingFlow() {
        guard recordingTask == nil else { return }
        permissionState.refresh()
        guard permissionState.accessibilityGranted else {
            overlayController.present()
            overlayController.updateText("请先开启辅助功能权限")
            overlayController.dismiss(after: 1.4)
            permissionState.requestAccessibilityPrompt()
            return
        }
        overlayController.present()
        overlayController.updateText("正在聆听…")
        recordingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.speechService.startRecording()
            } catch {
                self.permissionState.refresh()
                self.overlayController.updateText("语音识别权限不可用")
                self.overlayController.dismiss(after: 1.0)
                self.recordingTask = nil
            }
        }
    }

    private func endRecordingFlow() {
        guard let activeTask = recordingTask else { return }
        activeTask.cancel()
        recordingTask = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            let transcript = await self.speechService.stopRecording()
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                self.overlayController.dismiss(after: 0.12)
                return
            }

            var finalText = trimmed
            let llmConfig = self.preferences.llmConfiguration
            if llmConfig.enabled && llmConfig.isConfigured {
                self.overlayController.updateText("正在润色纠错…")
                if let refined = try? await self.llmRefiner.refine(text: trimmed, language: self.preferences.language) {
                    let candidate = refined.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !candidate.isEmpty {
                        finalText = candidate
                    }
                }
            }

            self.overlayController.updateText(finalText)
            do {
                try await PasteInjector.inject(text: finalText)
            } catch {
                self.overlayController.updateText("文字注入失败")
                self.overlayController.dismiss(after: 1.0)
                return
            }
            self.overlayController.dismiss(after: 0.18)
        }
    }

    private func requestMicrophonePermission() {
        Task { @MainActor [weak self] in
            await self?.permissionState.requestMicrophonePermission()
        }
    }

    private func requestSpeechPermission() {
        Task { @MainActor [weak self] in
            await self?.permissionState.requestSpeechPermission()
        }
    }
}
