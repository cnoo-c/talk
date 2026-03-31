import ApplicationServices
import AppKit
import AVFoundation
import Foundation
import Speech

@MainActor
final class PermissionState: ObservableObject {
    private static let accessibilityPromptKey = "AXTrustedCheckOptionPrompt"

    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    @Published private(set) var microphoneAuthorized = false
    @Published private(set) var speechAuthorized = false

    func refresh() {
        accessibilityGranted = AXIsProcessTrusted()
        microphoneAuthorized = Self.currentMicrophoneAuthorizationIsUsable()
        speechAuthorized = Self.currentSpeechAuthorizationIsUsable()
    }

    func requestAccessibilityPrompt() {
        let options = [Self.accessibilityPromptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
    }

    func openAccessibilitySettings() {
        openSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openMicrophoneSettings() {
        openSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    func openSpeechSettings() {
        openSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
    }

    func requestMicrophonePermission() async {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        refresh()
    }

    func requestSpeechPermission() async {
        let _ = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { _ in
                continuation.resume(returning: ())
            }
        }
        refresh()
    }

    func requestInputPermissionsIfNeeded() async {
        refresh()
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            await requestMicrophonePermission()
        }
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            await requestSpeechPermission()
        }
    }

    private static func currentMicrophoneAuthorizationIsUsable() -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        default:
            return false
        }
    }

    private static func currentSpeechAuthorizationIsUsable() -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        default:
            return false
        }
    }

    private func openSettingsPane(_ rawURL: String) {
        guard let url = URL(string: rawURL) else { return }
        NSWorkspace.shared.open(url)
    }
}
