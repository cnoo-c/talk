import Foundation

struct OpenAICompatibleRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let temperature: Double
    let messages: [Message]
}

struct OpenAICompatibleResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }

    let choices: [Choice]
}

enum LLMRefinerError: Error {
    case invalidURL
    case invalidResponse
}

@MainActor
final class LLMRefiner {
    private let preferences: AppPreferences

    init(preferences: AppPreferences) {
        self.preferences = preferences
    }

    func refine(text: String, language: RecognitionLanguage) async throws -> String {
        let config = preferences.llmConfiguration
        guard config.isConfigured else { return text }
        guard let endpoint = URL(string: normalizedBaseURL(from: config.apiBaseURL)) else {
            throw LLMRefinerError.invalidURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        let systemPrompt = """
        你是一个极其保守的语音转录纠错器。你的任务只有一个：只修复明显的语音识别错误。
        规则：
        1. 绝对不要改写、润色、总结、压缩、扩写或删除看起来正确的内容。
        2. 只在错误非常明显时才修改，例如中文谐音词、被错误转写成中文的英文技术术语、明显错别字。
        3. 中英文混杂时，保留原意和原有顺序。
        4. 如果输入看起来已经正确，必须逐字原样返回。
        5. 只返回修正后的文本本身，不要解释，不要加引号。
        当前语言偏好：\(language.rawValue)
        """

        let body = OpenAICompatibleRequest(
            model: config.model,
            temperature: 0,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: text)
            ]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LLMRefinerError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(OpenAICompatibleResponse.self, from: data)
        return decoded.choices.first?.message.content ?? text
    }

    func testConfiguration(baseURL: String, apiKey: String, model: String) async throws -> String {
        let existing = preferences.llmConfiguration
        let temp = LLMConfiguration(enabled: true, apiBaseURL: baseURL, apiKey: apiKey, model: model)
        preferences.llmConfiguration = temp
        defer { preferences.llmConfiguration = existing }
        return try await refine(text: "配森 数据结构 杰森", language: .simplifiedChinese)
    }

    private func normalizedBaseURL(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/chat/completions") {
            return trimmed
        }
        return trimmed.replacingOccurrences(of: "/+$", with: "", options: .regularExpression) + "/chat/completions"
    }
}
