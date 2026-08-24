import AVFoundation
import Speech

// Push-to-talk transcription. SFSpeechRecognizer with on-device recognition forced
// wherever the locale supports it (en_AU does), so audio never leaves the Mac —
// matching the FoundationModels promise on the interpretation side.
@MainActor
final class Dictation: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var partial = ""
    @Published var lastError: String?

    /// Called once per recording with the final transcript.
    var onFinal: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private lazy var recognizer: SFSpeechRecognizer? =
        SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en_US"))

    func toggle() {
        if isRecording { stop(send: true) } else { Task { await start() } }
    }

    private func start() async {
        lastError = nil

        let speechAuth = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speechAuth == .authorized else {
            lastError = "Speech recognition was declined — System Settings → Privacy & Security → Speech Recognition."
            return
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            lastError = "Microphone access was declined — System Settings → Privacy & Security → Microphone."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            lastError = "Speech recognition isn't available right now."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            lastError = "No usable microphone input."
            return
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch {
            lastError = "Couldn't start the microphone: \(error.localizedDescription)"
            return
        }

        partial = ""
        isRecording = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.partial = result.bestTranscription.formattedString
                    if result.isFinal, self.isRecording { self.stop(send: true) }
                }
                if error != nil, self.isRecording {
                    self.stop(send: !self.partial.isEmpty)
                }
            }
        }
    }

    func stop(send: Bool) {
        guard isRecording else { return }
        isRecording = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        if send, !partial.isEmpty { onFinal?(partial) }
    }
}
