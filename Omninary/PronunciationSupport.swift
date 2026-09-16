import SwiftUI
import AVFoundation

struct PronunciationScore {
    let finalScore: Double
    let accuracyScore: Double
    let fluencyScore: Double
    let completenessScore: Double

    init(assessment: AzurePronunciationAssessment) {
        finalScore = assessment.scores.pronunciation
        accuracyScore = assessment.scores.accuracy
        fluencyScore = assessment.scores.fluency
        completenessScore = assessment.scores.completeness
    }
}

final class PronunciationManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private let audioEngine = AVAudioEngine()

    private var audioFile: AVAudioFile?
    private var audioConverter: AVAudioConverter?
    private var hasAudioTap = false
    private var audioPlayer: AVAudioPlayer?
    private var scheduledPlaybackStop: DispatchWorkItem?

    @Published var isRecording = false
    @Published var hasRecorded = false
    @Published var isPlaying = false

    func resetRecordingState() {
        stopAudioCapture()
        stopPlayback()

        hasRecorded = false
        isRecording = false

        try? FileManager.default.removeItem(at: recordingURL)
    }

    func startRecording() throws {
        resetRecordingState()

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0,
              let azureRecordingFormat = AVAudioFormat(
                  commonFormat: .pcmFormatInt16,
                  sampleRate: 16_000,
                  channels: 1,
                  interleaved: true
              ),
              let converter = AVAudioConverter(from: recordingFormat, to: azureRecordingFormat) else {
            throw PronunciationError.unsupportedRecordingFormat
        }

        do {
            audioFile = try AVAudioFile(
                forWriting: recordingURL,
                settings: azureRecordingFormat.settings,
                commonFormat: .pcmFormatInt16,
                interleaved: true
            )
            audioConverter = converter
        } catch {
            throw PronunciationError.cannotCreateRecording
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.appendRecording(buffer)
        }
        hasAudioTap = true

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    func stopRecording() {
        guard isRecording else { return }
        stopAudioCapture()
        isRecording = false
        hasRecorded = true
    }

    func playRecordedAudio() {
        guard let player = prepareAudioPlayer() else { return }
        player.currentTime = 0
        isPlaying = player.play()
    }

    func playRecordedAudio(offsetMilliseconds: Int, durationMilliseconds: Int) {
        guard durationMilliseconds > 0,
              let player = prepareAudioPlayer() else {
            return
        }

        let startTime = max(Double(offsetMilliseconds) / 1_000, 0)
        guard startTime < player.duration else {
            return
        }

        let requestedDuration = Double(durationMilliseconds) / 1_000
        let playableDuration = min(requestedDuration, player.duration - startTime)
        guard playableDuration > 0 else { return }

        player.currentTime = startTime
        isPlaying = player.play()

        let stopWorkItem = DispatchWorkItem { [weak self, weak player] in
            guard let self, let player, self.audioPlayer === player else { return }
            self.stopPlayback()
        }
        scheduledPlaybackStop = stopWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + playableDuration, execute: stopWorkItem)
    }

    func stopPlayback() {
        scheduledPlaybackStop?.cancel()
        scheduledPlaybackStop = nil
        audioPlayer?.stop()
        isPlaying = false
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.scheduledPlaybackStop?.cancel()
            self.scheduledPlaybackStop = nil
            self.isPlaying = false
        }
    }

    var recordedAudioURL: URL? {
        FileManager.default.fileExists(atPath: recordingURL.path) ? recordingURL : nil
    }

    private var recordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("omninary-pronunciation.wav")
    }

    private func prepareAudioPlayer() -> AVAudioPlayer? {
        guard FileManager.default.fileExists(atPath: recordingURL.path) else { return nil }

        stopPlayback()

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)

            let player = try AVAudioPlayer(contentsOf: recordingURL)
            player.delegate = self
            player.prepareToPlay()
            audioPlayer = player
            return player
        } catch {
            isPlaying = false
            return nil
        }
    }

    private func stopAudioCapture() {
        audioEngine.stop()
        if hasAudioTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasAudioTap = false
        }
        audioFile = nil
        audioConverter = nil
    }

    private func appendRecording(_ inputBuffer: AVAudioPCMBuffer) {
        guard let audioConverter,
              let audioFile,
              inputBuffer.frameLength > 0 else {
            return
        }

        let outputFormat = audioConverter.outputFormat
        let frameRatio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let outputCapacity = AVAudioFrameCount((Double(inputBuffer.frameLength) * frameRatio).rounded(.up)) + 1
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
            return
        }

        var didProvideInput = false
        var conversionError: NSError?
        audioConverter.convert(to: outputBuffer, error: &conversionError) { _, status in
            if didProvideInput {
                status.pointee = .noDataNow
                return nil
            }

            didProvideInput = true
            status.pointee = .haveData
            return inputBuffer
        }

        guard conversionError == nil, outputBuffer.frameLength > 0 else { return }
        try? audioFile.write(from: outputBuffer)
    }
}

private enum PronunciationError: LocalizedError {
    case unsupportedRecordingFormat
    case cannotCreateRecording

    var errorDescription: String? {
        switch self {
        case .unsupportedRecordingFormat:
            return "Thiết bị không hỗ trợ định dạng ghi âm cần thiết."
        case .cannotCreateRecording:
            return "Không thể lưu bản ghi âm. Vui lòng thử lại."
        }
    }
}

struct ScoreCircle: View {
    let title: String
    let score: Double
    let color: Color

    private var boundedScore: Double {
        min(max(score, 0), 100)
    }

    var body: some View {
        VStack {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(boundedScore / 100))
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text("\(Int(boundedScore.rounded()))")
                    .font(.system(size: 16, weight: .bold))
            }
            .frame(width: 50, height: 50)

            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
