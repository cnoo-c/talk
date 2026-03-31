import AppKit
import Carbon
import Foundation

enum PasteInjectorError: Error {
    case eventSourceUnavailable
}

enum PasteInjector {
    static func inject(text: String) async throws {
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboard(pasteboard)
        let originalSource = InputSourceManager.currentInputSource()

        if InputSourceManager.shouldTemporarilySwitchToASCII(source: originalSource) {
            InputSourceManager.selectASCIIInputSource()
            try? await Task.sleep(for: .milliseconds(80))
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        try sendCommandV()
        try? await Task.sleep(for: .milliseconds(120))

        InputSourceManager.restore(originalSource)
        restorePasteboard(snapshot, on: pasteboard)
    }

    private static func sendCommandV() throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw PasteInjectorError.eventSourceUnavailable
        }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private static func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
    }

    private static func restorePasteboard(_ snapshot: [[NSPasteboard.PasteboardType: Data]], on pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        for item in snapshot {
            let pbItem = NSPasteboardItem()
            for (type, data) in item {
                pbItem.setData(data, forType: type)
            }
            pasteboard.writeObjects([pbItem])
        }
    }
}
