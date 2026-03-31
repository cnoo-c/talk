import Carbon
import Foundation

enum InputSourceManager {
    static func currentInputSource() -> TISInputSource? {
        TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    }

    static func restore(_ source: TISInputSource?) {
        guard let source else { return }
        TISSelectInputSource(source)
    }

    static func shouldTemporarilySwitchToASCII(source: TISInputSource?) -> Bool {
        guard let source else { return false }
        let sourceID = property(source, key: kTISPropertyInputSourceID) as? String ?? ""
        let languages = property(source, key: kTISPropertyInputSourceLanguages) as? [String] ?? []
        if sourceID.contains("inputmethod") {
            return true
        }
        return languages.contains { ["zh", "ja", "ko"].contains($0.prefix(2)) }
    }

    static func selectASCIIInputSource() {
        let keys = [
            kTISPropertyInputSourceIsASCIICapable as String: true
        ] as CFDictionary

        guard let inputSources = TISCreateInputSourceList(keys, false)?.takeRetainedValue() as? [TISInputSource] else {
            return
        }

        if let preferred = inputSources.first(where: {
            let id = property($0, key: kTISPropertyInputSourceID) as? String ?? ""
            return id == "com.apple.keylayout.ABC" || id == "com.apple.keylayout.US"
        }) ?? inputSources.first {
            TISSelectInputSource(preferred)
        }
    }

    private static func property(_ source: TISInputSource, key: CFString) -> AnyObject? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
    }
}
