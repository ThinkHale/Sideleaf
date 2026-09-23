@preconcurrency import AVFoundation
import Observation
import SwiftUI
import UIKit

/// Records the one stretch of speech Sideleaf keeps.
///
/// It runs its own short-lived audio engine rather than borrowing the meeting's,
/// because enrolling and listening never happen at the same time and the
/// transcription path is not worth disturbing for this.
@MainActor
@Observable
final class VoiceEnrollmentRecorder {
    enum Phase: Equatable {
        case idle
        case preparing
        case recording(remaining: TimeInterval)
        case finishing

        var isBusy: Bool { self != .idle }
    }

    private(set) var phase: Phase = .idle

    @ObservationIgnored private let sink = VoiceAudioSink()
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private let audioSession = AVAudioSession.sharedInstance()

    /// Records for the requested time and hands back what the microphone heard.
    func record(
        seconds: TimeInterval = VoiceProfile.requestedSeconds
    ) async -> Result<(samples: [Float], sampleRate: Double), VoiceEnrollmentFailure> {
        guard phase == .idle else { return .failure(.failed("Already recording.")) }
        phase = .preparing
        guard await requestMicrophone() else {
            phase = .idle
            return .failure(.microphoneDenied)
        }

        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            teardown()
            return .failure(.failed("This device offered no microphone input."))
        }
        sink.reset()
        sink.prepare(sampleRate: format.sampleRate)

        do {
            try audioSession.setCategory(.record, mode: .spokenAudio, options: .allowBluetoothHFP)
            try audioSession.setActive(true)
            input.installTap(onBus: 0, bufferSize: 4_096, format: format) {
                @Sendable [sink] buffer, _ in
                sink.receive(buffer)
            }
            engine.prepare()
            try engine.start()
        } catch {
            teardown()
            return .failure(.failed(error.localizedDescription))
        }

        var remaining = seconds
        phase = .recording(remaining: remaining)
        while remaining > 0, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            remaining -= 0.25
            if case .recording = phase {
                phase = .recording(remaining: max(0, remaining))
            } else {
                break
            }
        }

        phase = .finishing
        teardown()
        let captured = sink.drain()
        phase = .idle
        guard !captured.samples.isEmpty else {
            return .failure(.failed("Nothing was recorded. Check the microphone and try again."))
        }
        return .success(captured)
    }

    /// Stops early. Whatever was captured is discarded.
    func cancel() {
        teardown()
        sink.reset()
        phase = .idle
    }

    private func teardown() {
        if let engine {
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestMicrophone() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default: return false
        }
    }
}

/// The settings screen where you teach Sideleaf your voice.
struct VoiceProfileView: View {
    @Environment(MeetingSession.self) private var session
    @State private var recorder = VoiceEnrollmentRecorder()
    @State private var message: String?
    @State private var working = false
    @State private var confirmDelete = false

    var body: some View {
        Form {
            stateSection
            explanationSection
            storageSection
            if let message {
                Section {
                    Label(message, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Your voice")
        .navigationBarTitleDisplayMode(.inline)
        .task { await session.recognizer.prepare() }
        .confirmationDialog(
            "Delete your voice profile?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete the recording", role: .destructive) {
                session.recognizer.forget()
                message = "Deleted. Sideleaf will go back to assuming you are the one talking."
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("The recording is removed from this device. Meetings keep working; Sideleaf just stops telling your voice from anyone else's.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var stateSection: some View {
        Section {
            switch recorder.phase {
            case .recording(let remaining):
                VStack(alignment: .leading, spacing: 8) {
                    Label("Listening. Keep talking.", systemImage: "waveform")
                        .foregroundStyle(.red)
                    ProgressView(
                        value: max(0, VoiceProfile.requestedSeconds - remaining),
                        total: VoiceProfile.requestedSeconds
                    )
                    Text("\(Int(remaining.rounded())) seconds to go")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Stop", role: .destructive) { recorder.cancel() }
                }
            case .preparing, .finishing:
                ProgressView("Getting ready…")
            case .idle:
                idleControls
            }
        } header: {
            Text("Voice profile")
        } footer: {
            if case .recording = recorder.phase {
                Text("Read anything at all, in your ordinary speaking voice. What you say does not matter; how you sound does.")
            }
        }
    }

    @ViewBuilder
    private var idleControls: some View {
        if let profile = session.recognizer.profile {
            LabeledContent("Recorded", value: profile.enrolledAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Length", value: "\(Int(profile.seconds.rounded())) seconds")
            Button(working ? "Working…" : "Record it again") { enroll() }
                .disabled(working || session.isActive)
            Button("Delete voice profile", role: .destructive) { confirmDelete = true }
                .disabled(working)
        } else {
            Text("Sideleaf does not know your voice yet, so it assumes every promise in the room is yours.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(working ? "Working…" : "Record my voice") { enroll() }
                .disabled(working || session.isActive)
        }
        if session.isActive {
            Label("Finish the meeting first. Sideleaf cannot record your profile while it is listening.", systemImage: "waveform")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
        if case .unavailable(let reason) = session.recognizer.state {
            Label(reason, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    private var explanationSection: some View {
        Section {
            Text("Record about \(Int(VoiceProfile.requestedSeconds)) seconds of yourself talking. Sideleaf then knows which voice in a meeting is yours.")
                .font(.callout)
            Label("A promise you make lands on your list. A promise they make lands on theirs.", systemImage: "arrow.left.arrow.right")
                .font(.footnote)
            Label("\"Can you send that over\" means one thing when you say it and the opposite when they do.", systemImage: "questionmark.bubble")
                .font(.footnote)
        } header: {
            Text("What it changes")
        } footer: {
            Text("Sideleaf never guesses silently. Anything it was unsure about says so on the card, and one tap moves it.")
        }
    }

    private var storageSection: some View {
        Section {
            Label("The recording stays in this app on this device and is never uploaded.", systemImage: "iphone")
                .font(.footnote)
            Label("Meeting audio is still never saved. Your profile is the one recording Sideleaf keeps, and deleting it removes the file.", systemImage: "waveform.slash")
                .font(.footnote)
            Label("Other people in the room are told apart from you for the length of the meeting and are never stored or identified.", systemImage: "person.2")
                .font(.footnote)
            Label("Setting this up the first time downloads the voice model from its publisher. No audio is sent.", systemImage: "arrow.down.circle")
                .font(.footnote)
            if let fluid = session.recognizer as? FluidAudioSpeakerRecognizer,
               !fluid.heardSpeakers.isEmpty
            {
                LabeledContent("Voices heard last meeting", value: fluid.heardSpeakers.joined(separator: ", "))
                    .font(.footnote)
            }
        } header: {
            Text("What is stored")
        }
    }

    private func enroll() {
        guard !working else { return }
        working = true
        message = nil
        Task {
            let recording = await recorder.record()
            switch recording {
            case .failure(let failure):
                message = failure.errorDescription
            case .success(let captured):
                let outcome = await session.recognizer.enroll(
                    samples: captured.samples,
                    sampleRate: captured.sampleRate
                )
                switch outcome {
                case .success:
                    message = "Done. Sideleaf will tell your voice from the room's in your next meeting."
                case .failure(let failure):
                    message = failure.errorDescription
                }
            }
            working = false
        }
    }
}
