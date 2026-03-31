import AppKit
import Carbon.HIToolbox

final class GlobalFnKeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isHotKeyPressed = false
    private let diagnostics: FnKeyDiagnostics
    private let onPress: @MainActor () -> Void
    private let onRelease: @MainActor () -> Void
    private let onPermissionIssue: @MainActor () -> Void
    private let leftOptionKeyCode: Int64 = 58
    private let rightOptionKeyCode: Int64 = 61

    init(
        diagnostics: FnKeyDiagnostics,
        onPress: @escaping @MainActor () -> Void,
        onRelease: @escaping @MainActor () -> Void,
        onPermissionIssue: @escaping @MainActor () -> Void
    ) {
        self.diagnostics = diagnostics
        self.onPress = onPress
        self.onRelease = onRelease
        self.onPermissionIssue = onPermissionIssue
    }

    func start() {
        guard eventTap == nil else { return }

        let mask = (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passRetained(event) }

            let monitor = Unmanaged<GlobalFnKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handle(event: event, type: type)
        }

        let unmanaged = Unmanaged.passUnretained(self)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: unmanaged.toOpaque()
        ) else {
            Task { @MainActor [diagnostics, onPermissionIssue] in
                diagnostics.setTapInstalled(false)
                diagnostics.record("事件监听创建失败")
                onPermissionIssue()
            }
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Task { @MainActor [diagnostics] in
            diagnostics.setTapInstalled(true)
            diagnostics.record("等待 Option 键")
        }
    }

    func stop() {
        guard let eventTap, let runLoopSource else { return }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        self.eventTap = nil
        self.runLoopSource = nil
        Task { @MainActor [diagnostics] in
            diagnostics.setTapInstalled(false)
            diagnostics.record("事件监听已停止")
        }
    }

    private func handle(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput,
           let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            Task { @MainActor [diagnostics] in
                diagnostics.record("事件监听已重新启用")
            }
            return Unmanaged.passRetained(event)
        }

        guard type == .flagsChanged else {
            return Unmanaged.passRetained(event)
        }

        let flags = event.flags
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let isOptionKey = keycode == leftOptionKeyCode || keycode == rightOptionKeyCode
        let optionPressed = isOptionKey && flags.contains(.maskAlternate)
        let optionReleased = isOptionKey && !flags.contains(.maskAlternate)

        if isOptionKey {
            let side = keycode == rightOptionKeyCode ? "右侧" : "左侧"
            Task { @MainActor [diagnostics] in
                diagnostics.record("\(side) Option \((optionPressed ? "按下" : "抬起")) keycode=\(keycode)")
            }
        }

        let hotKeyPressed = optionPressed
        let hotKeyChanged = (optionPressed || optionReleased) && hotKeyPressed != isHotKeyPressed
        guard hotKeyChanged else {
            return Unmanaged.passRetained(event)
        }

        isHotKeyPressed = hotKeyPressed
        Task { @MainActor [onPress, onRelease] in
            if hotKeyPressed {
                onPress()
            } else {
                onRelease()
            }
        }

        // Swallow the dedicated hotkey so it does not leak into the focused app.
        return nil
    }
}
