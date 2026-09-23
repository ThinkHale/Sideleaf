import Foundation
import os

/// What Sideleaf keeps so it can tell your voice from everyone else's.
///
/// This is the one recording Sideleaf stores. Meeting audio is still never
/// written to disk; the profile you record in settings is a deliberate
/// exception, it stays in this app's container on this device, and deleting it
/// in settings removes the file.
struct VoiceProfile: Codable, Equatable, Sendable {
    var enrolledAt: Date
    var seconds: TimeInterval
    var sampleRate: Double

    /// The name the diarizer knows you by. Only ever used locally.
    static let speakerName = "You"
    /// Below this, there is not enough voice to match against.
    static let minimumSeconds: TimeInterval = 12
    /// What the enrollment screen asks for.
    static let requestedSeconds: TimeInterval = 25
}

enum VoiceRecognizerState: Equatable, Sendable {
    case idle
    case preparing
    /// Models loaded. Attribution works if a profile is enrolled.
    case ready
    /// Why voice attribution cannot run. Everything else still works.
    case unavailable(String)

    var isReady: Bool { self == .ready }
}

enum VoiceEnrollmentFailure: LocalizedError, Equatable {
    case microphoneDenied
    case tooShort(TimeInterval)
    case modelsUnavailable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Sideleaf needs the microphone to record your voice. Turn it on in Settings."
        case .tooShort(let seconds):
            "Keep talking for about \(Int(VoiceProfile.minimumSeconds)) seconds. That recording was \(Int(seconds))."
        case .modelsUnavailable(let reason):
            "The voice model could not be loaded. \(reason)"
        case .failed(let reason):
            "Your voice profile could not be saved. \(reason)"
        }
    }
}

/// Anything that can tell your voice from the room's.
///
/// The app talks to this and never to the model behind it, so the speech
/// recognition library stays in one file.
@MainActor
protocol SpeakerRecognizing: AnyObject {
    var state: VoiceRecognizerState { get }
    var profile: VoiceProfile? { get }

    /// Loads models and applies a stored profile. Safe to call repeatedly.
    func prepare() async

    func enroll(
        samples: [Float],
        sampleRate: Double
    ) async -> Result<VoiceProfile, VoiceEnrollmentFailure>

    func forget()

    /// Starts attributing. The sink is filled by the transcriber's tap.
    func beginMeeting(sink: VoiceAudioSink) async

    func endMeeting()

    /// Who held the floor during a stretch of the meeting, in seconds from its
    /// start. `unknown` whenever the answer is not clear enough to act on.
    func speaker(during window: ClosedRange<TimeInterval>) -> MeetingSpeaker
}

/// Where the enrollment recording lives.
enum VoiceProfileStore {
    private static let folderName = "VoiceProfile"
    private static let metadataName = "profile.json"
    private static let samplesName = "profile.pcm"

    static func directory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = base.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        }
        return folder
    }

    @discardableResult
    static func save(samples: [Float], sampleRate: Double) throws -> VoiceProfile {
        let folder = try directory()
        let profile = VoiceProfile(
            enrolledAt: Date(),
            seconds: sampleRate > 0 ? Double(samples.count) / sampleRate : 0,
            sampleRate: sampleRate
        )
        let audio = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        try audio.write(
            to: folder.appendingPathComponent(samplesName),
            options: [.atomic, .completeFileProtection]
        )
        try JSONEncoder().encode(profile).write(
            to: folder.appendingPathComponent(metadataName),
            options: [.atomic, .completeFileProtection]
        )
        return profile
    }

    static func profile() -> VoiceProfile? {
        guard let folder = try? directory(),
              let data = try? Data(contentsOf: folder.appendingPathComponent(metadataName))
        else { return nil }
        return try? JSONDecoder().decode(VoiceProfile.self, from: data)
    }

    static func samples() -> [Float]? {
        guard let folder = try? directory(),
              let data = try? Data(contentsOf: folder.appendingPathComponent(samplesName)),
              !data.isEmpty
        else { return nil }
        return data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }
    }

    static func delete() {
        guard let folder = try? directory() else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(samplesName))
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(metadataName))
    }
}

/// Used where there is no model: previews, tests, and any build that leaves the
/// speech library out. Everything keeps working; nothing is attributed.
@MainActor
final class UnavailableSpeakerRecognizer: SpeakerRecognizing {
    let state: VoiceRecognizerState = .unavailable("Voice recognition is not part of this build.")
    let profile: VoiceProfile? = nil

    func prepare() async {}

    func enroll(
        samples: [Float],
        sampleRate: Double
    ) async -> Result<VoiceProfile, VoiceEnrollmentFailure> {
        .failure(.modelsUnavailable("This build has no voice model."))
    }

    func forget() {}
    func beginMeeting(sink: VoiceAudioSink) async {}
    func endMeeting() {}
    func speaker(during window: ClosedRange<TimeInterval>) -> MeetingSpeaker { .unknown }
}
