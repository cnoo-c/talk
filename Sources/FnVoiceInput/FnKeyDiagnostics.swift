import Foundation

@MainActor
final class FnKeyDiagnostics: ObservableObject {
    @Published private(set) var tapInstalled = false
    @Published private(set) var lastEventSummary = "尚未收到 Option 键事件"

    func setTapInstalled(_ installed: Bool) {
        tapInstalled = installed
    }

    func record(_ summary: String) {
        lastEventSummary = summary
    }
}
