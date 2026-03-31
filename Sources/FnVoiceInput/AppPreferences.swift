import Foundation

enum RecognitionLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-CN"
    case english = "en-US"
    case traditionalChinese = "zh-TW"
    case japanese = "ja-JP"
    case korean = "ko-KR"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .english: "英语"
        case .traditionalChinese: "繁体中文"
        case .japanese: "日本語"
        case .korean: "한국어"
        }
    }
}

struct LLMConfiguration: Codable, Equatable {
    var enabled: Bool = false
    var apiBaseURL: String = ""
    var apiKey: String = ""
    var model: String = ""

    var isConfigured: Bool {
        !apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.isEmpty &&
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    @Published var language: RecognitionLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    @Published var llmConfiguration: LLMConfiguration {
        didSet { persistLLMConfiguration() }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let language = "recognitionLanguage"
        static let llmConfiguration = "llmConfiguration"
    }

    private init() {
        let storedLanguage = defaults.string(forKey: Keys.language)
        language = RecognitionLanguage(rawValue: storedLanguage ?? "") ?? .simplifiedChinese

        if let data = defaults.data(forKey: Keys.llmConfiguration),
           let decoded = try? JSONDecoder().decode(LLMConfiguration.self, from: data) {
            llmConfiguration = decoded
        } else {
            llmConfiguration = LLMConfiguration()
        }
    }

    private func persistLLMConfiguration() {
        guard let data = try? JSONEncoder().encode(llmConfiguration) else { return }
        defaults.set(data, forKey: Keys.llmConfiguration)
    }
}
