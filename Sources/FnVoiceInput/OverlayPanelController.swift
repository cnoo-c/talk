import AppKit
import SwiftUI

@MainActor
final class OverlayPanelController {
    private let panelHeight: CGFloat = 56
    private let model = OverlayViewModel()
    private let panel: NSPanel
    private var isPresented = false

    init() {
        let content = OverlayContentView(model: model)
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(hosting)

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: panelHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = container

        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    func present() {
        isPresented = true
        model.isVisible = true
        positionPanel(width: model.panelWidth)
        panel.alphaValue = 0
        panel.setFrameOrigin(origin(for: model.panelWidth))
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(NSRect(origin: origin(for: model.panelWidth), size: NSSize(width: model.panelWidth, height: panelHeight)), display: true)
        }
    }

    func updateText(_ text: String) {
        model.text = text
        guard isPresented, panel.contentView != nil, panel.isVisible else { return }
        let width = model.panelWidth
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(NSRect(origin: origin(for: width), size: NSSize(width: width, height: panelHeight)), display: true)
        }
    }

    func updateLevel(_ level: CGFloat) {
        model.level = level
    }

    func dismiss(after delay: TimeInterval = 0) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard self.isPresented else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.panel.animator().alphaValue = 0
                self.panel.animator().setFrame(
                    NSRect(
                        origin: self.origin(for: max(self.model.panelWidth - 24, 260)),
                        size: NSSize(width: max(self.model.panelWidth - 24, 260), height: self.panelHeight - 2)
                    ),
                    display: true
                )
            }, completionHandler: {
                Task { @MainActor in
                    self.isPresented = false
                    self.panel.orderOut(nil)
                    self.model.level = 0
                    self.model.text = ""
                }
            })
        }
    }

    private func positionPanel(width: CGFloat) {
        panel.setFrame(NSRect(origin: origin(for: width), size: NSSize(width: width, height: panelHeight)), display: true)
    }

    private func origin(for width: CGFloat) -> CGPoint {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return CGPoint(x: 200, y: 80)
        }
        let x = screen.frame.midX - (width / 2)
        let y = screen.visibleFrame.minY + 56
        return CGPoint(x: x, y: y)
    }
}

@MainActor
final class OverlayViewModel: ObservableObject {
    @Published var text = ""
    @Published var level: CGFloat = 0
    @Published var isVisible = false

    var panelWidth: CGFloat {
        let measured = max(160, min(560, CGFloat(text.count) * 11 + 140))
        return measured
    }
}

struct OverlayContentView: View {
    @ObservedObject var model: OverlayViewModel

    var body: some View {
        HStack(spacing: 16) {
            WaveformView(level: model.level)
                .frame(width: 44, height: 32)

            Text(model.text.isEmpty ? "正在聆听…" : model.text)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.965, green: 0.972, blue: 0.988).opacity(0.95),
                            Color(red: 0.84, green: 0.875, blue: 0.94).opacity(0.82)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.25), value: model.text)
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background {
            LiquidGlassCapsule(emphasis: model.level, widthBias: model.panelWidth)
        }
        .clipShape(Capsule(style: .continuous))
        .compositingGroup()
    }
}

struct LiquidGlassCapsule: View {
    let emphasis: CGFloat
    let widthBias: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let drift = sin(t * 0.42 + Double(widthBias) * 0.0012) * 0.018
            let shimmer = sin(t * 0.76 + Double(widthBias) * 0.0011) * 0.014
            let reactiveBoost = emphasis * 0.016

            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.965, green: 0.972, blue: 0.988).opacity(0.11 + reactiveBoost * 0.22),
                                    Color(red: 0.90, green: 0.925, blue: 0.965).opacity(0.035),
                                    Color.white.opacity(0.008)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .overlay {
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        let height = proxy.size.height
                        ZStack {
                            Capsule(style: .continuous)
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color(red: 0.98, green: 0.985, blue: 0.995).opacity(0.10 + reactiveBoost),
                                            Color(red: 0.91, green: 0.93, blue: 0.97).opacity(0.035),
                                            Color.clear
                                        ],
                                        center: .center,
                                        startRadius: 6,
                                        endRadius: width * 0.42
                                    )
                                )
                                .frame(width: width * 0.72, height: height * 0.82)
                                .offset(x: width * drift * 0.16, y: -height * 0.01)
                                .blur(radius: 16)

                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.22 + reactiveBoost * 0.10),
                                            Color(red: 0.95, green: 0.965, blue: 0.99).opacity(0.08),
                                            Color.clear
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: width * 0.94, height: height * 0.34)
                                .offset(x: width * drift * 0.28, y: -height * (0.20 + shimmer))
                                .blur(radius: 9)
                                .blendMode(.screen)

                            Ellipse()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color(red: 0.985, green: 0.988, blue: 1.0).opacity(0.09 + reactiveBoost * 0.08),
                                            Color(red: 0.90, green: 0.93, blue: 0.98).opacity(0.035),
                                            Color.clear
                                        ],
                                        center: .center,
                                        startRadius: 4,
                                        endRadius: width * 0.18
                                    )
                                )
                                .frame(width: width * 0.26, height: height * 0.52)
                                .offset(x: width * (-0.18 + drift * 0.5), y: -height * 0.06)
                                .blur(radius: 14)
                                .blendMode(.screen)

                            Ellipse()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.96, green: 0.972, blue: 0.992).opacity(0.055),
                                            Color(red: 0.88, green: 0.91, blue: 0.97).opacity(0.022),
                                            Color.clear
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: width * 0.68, height: height * 0.28)
                                .offset(x: width * (0.08 - drift * 0.28), y: height * 0.18)
                                .blur(radius: 14)
                        }
                    }
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.985, green: 0.99, blue: 1.0).opacity(0.16),
                                    Color(red: 0.92, green: 0.94, blue: 0.98).opacity(0.035),
                                    Color.white.opacity(0.025)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.4
                        )
                        .padding(1.0)
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.10),
                                    Color.clear,
                                    Color(red: 0.88, green: 0.91, blue: 0.96).opacity(0.02)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.9
                        )
                        .padding(1.8)
                        .blur(radius: 2.4)
                }
                .shadow(color: Color.black.opacity(0.038), radius: 20, x: 0, y: 12)
                .shadow(color: Color.black.opacity(0.016), radius: 6, x: 0, y: 2)
                .shadow(color: Color.white.opacity(0.022), radius: 8, x: 0, y: -1)
        }
    }
}

struct WaveformView: View {
    let level: CGFloat
    private let weights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            HStack(alignment: .center, spacing: 5) {
                ForEach(Array(weights.enumerated()), id: \.offset) { index, weight in
                    let jitter = 1 + organicJitter(seed: index, date: context.date)
                    let baseHeight = max(8, 10 + level * 22 * weight * jitter)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.96),
                                    Color(red: 0.86, green: 0.90, blue: 0.98).opacity(0.74),
                                    Color(red: 0.72, green: 0.79, blue: 0.95).opacity(0.42)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Color.white.opacity(0.10), radius: 3, x: 0, y: 0)
                        .frame(width: 4.8, height: min(30, baseHeight))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func organicJitter(seed: Int, date: Date) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate
        let value = sin(t * 8 + Double(seed) * 1.7) * 0.04
        return CGFloat(value)
    }
}
