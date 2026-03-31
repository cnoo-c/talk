import AVFoundation
import Combine
import Foundation
import Speech

final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func read() -> Value {
        lock.lock()
        let current = value
        lock.unlock()
        return current
    }

    func write(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}

final class StreamingSpeechPipeline: @unchecked Sendable {
    private let recognizer: SFSpeechRecognizer
    private let request = SFSpeechAudioBufferRecognitionRequest()
    private let audioEngine = AVAudioEngine()
    private let levelBox = LockedBox<Float>(0)
    private let textBox = LockedBox<String>("")
    private let stopped = LockedBox<Bool>(false)
    private let continuationBox = LockedBox<CheckedContinuation<String, Never>?>(nil)
    private let onPartialText: @Sendable (String) -> Void

    private var recognitionTask: SFSpeechRecognitionTask?

    init(recognizer: SFSpeechRecognizer, onPartialText: @escaping @Sendable (String) -> Void) {
        self.recognizer = recognizer
        self.onPartialText = onPartialText
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
    }

    func start() throws {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let request = self.request
        let levelBox = self.levelBox
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            levelBox.write(Self.calculateRMSLevel(from: buffer))
        }

        audioEngine.prepare()
        try audioEngine.start()

        let onPartialText = self.onPartialText
        let textBox = self.textBox
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                textBox.write(text)
                onPartialText(text)
                if result.isFinal {
                    self.finish(with: text)
                    return
                }
            }

            if error != nil {
                self.finish(with: textBox.read())
            }
        }
    }

    func level() -> Float {
        levelBox.read()
    }

    func stop() async -> String {
        stopAudioCapture()
        return await withCheckedContinuation { continuation in
            continuationBox.write(continuation)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self else { return }
                self.finish(with: self.textBox.read())
            }
        }
    }

    func cancel() {
        stopAudioCapture()
        recognitionTask?.cancel()
        recognitionTask = nil
        finish(with: textBox.read())
    }

    private func stopAudioCapture() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request.endAudio()
        levelBox.write(0)
    }

    private func finish(with text: String) {
        if stopped.read() { return }
        stopped.write(true)
        recognitionTask?.cancel()
        recognitionTask = nil
        if let continuation = continuationBox.read() {
            continuationBox.write(nil)
            continuation.resume(returning: text)
        }
    }

    nonisolated static func calculateRMSLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<frameLength {
            let sample = data[index]
            sum += sample * sample
        }
        return sqrt(sum / Float(frameLength))
    }
}

@MainActor
final class SpeechRecognizerService: ObservableObject {
    @Published private(set) var displayText = ""
    @Published private(set) var meterLevel: CGFloat = 0

    private let localeProvider: () -> String
    private var pipeline: StreamingSpeechPipeline?
    private var meterTimer: Timer?

    nonisolated private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    init(localeProvider: @escaping () -> String) {
        self.localeProvider = localeProvider
    }

    func startRecording() async throws {
        cancel()
        latestReset()

        let auth = await Self.requestSpeechAuthorization()
        guard auth == .authorized else {
            throw NSError(domain: "Speech", code: 1)
        }

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeProvider()))
        recognizer?.defaultTaskHint = .dictation
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "Speech", code: 2)
        }

        let pipeline = StreamingSpeechPipeline(recognizer: recognizer) { [weak self] partial in
            DispatchQueue.main.async {
                guard let self else { return }
                self.displayText = partial.isEmpty ? "正在聆听…" : partial
            }
        }
        try pipeline.start()
        self.pipeline = pipeline
        displayText = "正在聆听…"
        startMeterTimer()
    }

    func stopRecording() async -> String {
        guard let pipeline else { return "" }
        stopMeterTimer()
        let transcript = await pipeline.stop()
        self.pipeline = nil
        meterLevel = 0
        return transcript
    }

    func cancel() {
        stopMeterTimer()
        pipeline?.cancel()
        pipeline = nil
        latestReset()
    }

    private func startMeterTimer() {
        stopMeterTimer()
        meterTimer = Timer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(pollMeter), userInfo: nil, repeats: true)
        RunLoop.main.add(meterTimer!, forMode: .common)
    }

    private func stopMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
        meterLevel = 0
    }

    @objc private func pollMeter() {
        guard let pipeline else { return }
        let normalized = normalizeLevel(pipeline.level())
        let smoothingUp: CGFloat = 0.40
        let smoothingDown: CGFloat = 0.15
        let factor = normalized > meterLevel ? smoothingUp : smoothingDown
        meterLevel += (normalized - meterLevel) * factor
    }

    private func normalizeLevel(_ rms: Float) -> CGFloat {
        min(max(CGFloat(rms) * 12.0, 0), 1)
    }

    private func latestReset() {
        displayText = ""
        meterLevel = 0
    }
}
