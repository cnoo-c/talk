import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(preferences: AppPreferences, llmRefiner: LLMRefiner) {
        let view = SettingsView(preferences: preferences, llmRefiner: llmRefiner)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "LLM 设置"
        window.setContentSize(NSSize(width: 520, height: 260))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        super.init(window: window)
        shouldCascadeWindows = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences
    let llmRefiner: LLMRefiner

    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var model = ""
    @State private var status = ""
    @State private var isTesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("OpenAI 兼容 LLM")
                .font(.title3.weight(.semibold))

            VStack(spacing: 12) {
                labeledField("API Base URL", text: $baseURL)
                labeledField("API Key", text: $apiKey)
                labeledField("模型名称", text: $model)
            }

            HStack {
                if !status.isEmpty {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("测试") {
                    runTest()
                }
                .disabled(isTesting)

                Button("保存") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            load()
        }
    }

    @ViewBuilder
    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.callout.weight(.medium))
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func load() {
        let config = preferences.llmConfiguration
        baseURL = config.apiBaseURL
        apiKey = config.apiKey
        model = config.model
    }

    private func save() {
        preferences.llmConfiguration.apiBaseURL = baseURL
        preferences.llmConfiguration.apiKey = apiKey
        preferences.llmConfiguration.model = model
        status = "已保存"
    }

    private func runTest() {
        status = "测试中…"
        isTesting = true
        Task { @MainActor in
            defer { isTesting = false }
            do {
                let result = try await llmRefiner.testConfiguration(baseURL: baseURL, apiKey: apiKey, model: model)
                status = "测试成功：\(result)"
            } catch {
                status = "测试失败"
            }
        }
    }
}
