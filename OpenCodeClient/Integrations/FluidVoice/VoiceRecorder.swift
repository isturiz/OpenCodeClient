@preconcurrency import AVFoundation
import Foundation
import Observation

enum VoiceRecordingError: Error, Equatable, LocalizedError, Sendable {
    case permissionDenied
    case couldNotStart
    case emptyRecording
    case recordingTooLarge
    case recordingTooLong

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            String(localized: "Microphone access is required to dictate a prompt.")
        case .couldNotStart:
            String(localized: "The microphone could not start recording.")
        case .emptyRecording:
            String(localized: "No audio was recorded.")
        case .recordingTooLarge:
            String(localized: "The recording exceeds FluidVoice's 25 MB limit.")
        case .recordingTooLong:
            String(localized: "FluidVoice recordings are limited to five minutes.")
        }
    }
}

enum VoiceRecordingState: Equatable, Sendable {
    case idle
    case recording
}

@MainActor
@Observable
final class VoiceRecorder {
    static let maximumDuration: TimeInterval = 300

    private(set) var state: VoiceRecordingState = .idle
    private(set) var level: Double = 0
    private(set) var duration: TimeInterval = 0

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored private var startedAt: Date?

    func start() async throws {
        guard state == .idle else { return }
        guard await requestPermission() else {
            throw VoiceRecordingError.permissionDenied
        }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try audioSession.setActive(true)

        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "opencode-dictation-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record(forDuration: Self.maximumDuration) else {
            try? audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
            throw VoiceRecordingError.couldNotStart
        }

        self.recorder = recorder
        startedAt = .now
        duration = 0
        level = 0
        state = .recording
        startMetering()
    }

    func stop() throws -> URL {
        guard let recorder, state == .recording else {
            throw VoiceRecordingError.emptyRecording
        }
        recorder.stop()
        meterTask?.cancel()
        meterTask = nil
        self.recorder = nil
        state = .idle
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])

        let url = recorder.url
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 44 else {
            try? FileManager.default.removeItem(at: url)
            throw VoiceRecordingError.emptyRecording
        }
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        return url
    }

    func cancel() {
        meterTask?.cancel()
        meterTask = nil
        if let recorder {
            recorder.stop()
            try? FileManager.default.removeItem(at: recorder.url)
        }
        recorder = nil
        startedAt = nil
        duration = 0
        level = 0
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func remove(fileURL: URL) {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                guard let self, let recorder = self.recorder, recorder.isRecording else { return }
                recorder.updateMeters()
                let rawLevel = recorder.averagePower(forChannel: 0)
                self.level = min(max(pow(10, Double(rawLevel) / 40), 0), 1)
                if let startedAt = self.startedAt {
                    self.duration = Date.now.timeIntervalSince(startedAt)
                }
            }
        }
    }
}
