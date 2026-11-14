import Foundation
import Speech
import AVFoundation

/// 本机中文语音识别（不上传云端），实时回调转写文本。
@MainActor
final class SpeechController: ObservableObject {

    @Published var transcribing = false

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    func start(onText: @escaping (String) -> Void,
               onError: @escaping (String) -> Void) {
        guard !transcribing else { return }
        let locale = Locale(identifier: "zh-CN")
        guard let rec = SFSpeechRecognizer(locale: locale), rec.isAvailable else {
            onError("此设备不支持中文语音识别")
            return
        }
        recognizer = rec

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else {
                Task { @MainActor in onError("请在设置里允许语音识别") }
                return
            }
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                Task { @MainActor in
                    if granted { self?.begin(onText: onText, onError: onError) }
                    else { onError("请在设置里允许麦克风") }
                }
            }
        }
    }

    private func begin(onText: @escaping (String) -> Void,
                       onError: @escaping (String) -> Void) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if recognizer?.supportsOnDeviceRecognition == true {
                req.requiresOnDeviceRecognition = true   // 本机识别，不联网
            }
            request = req

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                req.append(buffer)
            }
            engine.prepare()
            try engine.start()
            transcribing = true

            task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor in
                    if let result {
                        onText(result.bestTranscription.formattedString)
                    }
                    if error != nil || (result?.isFinal ?? false) {
                        self?.stop()
                    }
                }
            }
        } catch {
            onError("麦克风启动失败")
            stop()
        }
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task = nil
        transcribing = false
    }
}
