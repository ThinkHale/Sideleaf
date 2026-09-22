import SwiftUI
import SwiftData
import UIKit

enum RootTab: Hashable { case meeting, notes }

/// Small pieces of navigation state the meeting flow and the notebook share.
@MainActor
@Observable
final class SideleafRouter {
    var tab: RootTab = .meeting
    var showAccount = false
    var showPlanSheet = false
    /// The page a planned meeting will be written to, when it was started from
    /// an existing page.
    var planPageID: UUID?
    /// A page the notebook tab should open as soon as it appears.
    var selectedPageID: UUID?

    func planMeeting(on pageID: UUID? = nil) {
        planPageID = pageID
        tab = .meeting
        showPlanSheet = true
    }

    func openAccount() {
        showAccount = true
    }

    func openPage(_ id: UUID) {
        selectedPageID = id
        tab = .notes
    }
}

// MARK: - Home

/// The first thing Sideleaf shows: one action, and what it will do for you.
struct MeetingHomeView: View {
    @Environment(NotebookSync.self) private var sync
    @Environment(MeetingSession.self) private var session
    @Environment(SideleafRouter.self) private var router
    @Query(sort: \LocalPage.updatedAt, order: .reverse) private var pages: [LocalPage]
    @State private var kind: MeetingKind = .meeting

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                masthead
                startFailure
                kindPicker
                startControls
                plannerLink
                recents
                assurance
            }
            .padding(20)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.sideleafPaper)
        .navigationTitle("Sideleaf")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { SideleafWordmark() }
            ToolbarItem(placement: .primaryAction) {
                Button(sync.accountActionLabel, systemImage: accountSymbol) {
                    router.openAccount()
                }
                .labelStyle(.iconOnly)
                .accessibilityHint(sync.accountActionHint)
            }
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your second brain in the room.")
                .font(.largeTitle)
                .fontDesign(.serif)
                .foregroundStyle(Color.sideleafInk)
            Text("Sideleaf listens on this device, offers the follow-up questions worth asking, and keeps what you agreed to. Typing and ink are here when you want them.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var startFailure: some View {
        if let message = session.startFailure {
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                HStack(spacing: 10) {
                    if session.shouldOfferMicrophoneSettings,
                       let settings = URL(string: UIApplication.openSettingsURLString)
                    {
                        Link("Open Sideleaf settings", destination: settings)
                            .font(.footnote.weight(.semibold))
                    }
                    Button("Dismiss") { session.clearStartFailure() }
                        .font(.footnote)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What are you walking into?")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(MeetingKind.allCases) { option in
                        Button {
                            kind = option
                        } label: {
                            Label(option.title, systemImage: option.symbol)
                                .font(.callout)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)
                        .background(
                            kind == option ? Color.sideleafOlive : Color.sideleafOlive.opacity(0.12),
                            in: Capsule()
                        )
                        .foregroundStyle(kind == option ? Color.white : Color.sideleafInk)
                        .accessibilityAddTraits(kind == option ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            Text(kind.focus)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var startControls: some View {
        if sync.canUseLiveTranscription {
            Button {
                Task { await startImmediately() }
            } label: {
                Label("Start listening", systemImage: "waveform")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.sideleafOlive)
            .accessibilityHint("Starts on-device transcription and live meeting cues.")
        } else {
            Button {
                router.openAccount()
            } label: {
                Label(gateTitle, systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.sideleafOlive)
            Text(gateExplanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var plannerLink: some View {
        Button {
            router.planMeeting()
        } label: {
            Label("Plan it first", systemImage: "list.bullet.rectangle")
                .font(.callout)
        }
        .buttonStyle(.bordered)
        .tint(.sideleafOlive)
        .accessibilityHint("Set what you want out of this conversation and the points to cover.")
    }

    @ViewBuilder
    private var recents: some View {
        let meetings = sync.meetingPages(from: pages)
        if !meetings.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent meetings")
                    .font(.headline)
                    .fontDesign(.serif)
                ForEach(meetings) { page in
                    Button {
                        router.openPage(page.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(page.title)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(Color.sideleafInk)
                            Text(recentSummary(page))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var assurance: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("On this device", systemImage: "lock.shield")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.sideleafOlive)
            Text("Speech is transcribed by Apple's on-device model. No audio file is created, no audio is uploaded, and questions come from written rules over what was said, not from a model's guess.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func recentSummary(_ page: LocalPage) -> String {
        let followUps = page.annotations.filter { $0.kind != "important" }.count
        let ended = page.meetingEndedAt ?? page.updatedAt
        let kindTitle = MeetingKind(rawValue: page.meetingKind ?? "")?.title ?? "Meeting"
        let followUpText = followUps == 1 ? "1 follow-up" : "\(followUps) follow-ups"
        return "\(kindTitle) · \(ended.formatted(date: .abbreviated, time: .shortened)) · \(followUpText)"
    }

    private var gateTitle: String {
        sync.hasAccount ? "Review the terms" : "Sign in to listen"
    }

    private var gateExplanation: String {
        sync.hasAccount
            ? "Sideleaf records your acceptance of the current Terms before it will use the microphone."
            : "Live capture needs an account and an accepted recording responsibility acknowledgement. Notes and ink work without one."
    }

    private var accountSymbol: String {
        if sync.requiresTermsAcceptance { return "person.crop.circle.badge.exclamationmark" }
        if sync.isOffline { return "icloud.slash" }
        return sync.isConnected ? "person.crop.circle.badge.checkmark" : "person.crop.circle"
    }

    private func startImmediately() async {
        await session.start(plan: MeetingPlan(kind: kind, title: kind.defaultTitle))
    }
}

// MARK: - Planning

/// The optional minute before a meeting: what you want out of it, and what has
/// to be covered. Sideleaf uses both while it listens.
struct MeetingPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MeetingSession.self) private var session
    @Environment(NotebookSync.self) private var sync
    @Query(sort: \LocalPage.updatedAt, order: .reverse) private var pages: [LocalPage]
    let pageID: UUID?

    @State private var kind: MeetingKind = .meeting
    @State private var title = ""
    @State private var goal = ""
    @State private var points = ""
    @State private var starting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kind", selection: $kind) {
                        ForEach(MeetingKind.allCases) { option in
                            Label(option.title, systemImage: option.symbol).tag(option)
                        }
                    }
                    TextField("Title", text: $title, prompt: Text(kind.defaultTitle))
                } header: {
                    Text("This conversation")
                } footer: {
                    if let pageTitle = attachedPageTitle {
                        Text("Saves into “\(pageTitle)” when the meeting ends.")
                    } else {
                        Text("A new page is created when you save the recap.")
                    }
                }

                Section {
                    TextField(
                        "What do you want out of it?",
                        text: $goal,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                } header: {
                    Text("Your goal")
                }

                Section {
                    TextField("One point per line", text: $points, axis: .vertical)
                        .lineLimit(3...8)
                        .font(.body.monospaced())
                } header: {
                    Text("Points to cover")
                } footer: {
                    Text("Sideleaf tracks these while you talk and tells you what has not come up.")
                }

                Section {
                    Label(
                        "Audio is transcribed by Apple's on-device model. Sideleaf never creates an audio file and never uploads audio.",
                        systemImage: "waveform.badge.magnifyingglass"
                    )
                    .font(.footnote)
                    Label(
                        "You are responsible for following applicable recording and interception laws, informing participants, and obtaining any permission this conversation needs.",
                        systemImage: "person.2.badge.gearshape"
                    )
                    .font(.footnote)
                    Link("View Terms of Service", destination: sync.termsURL)
                        .font(.footnote.weight(.semibold))
                } header: {
                    Text("Before you start")
                }
            }
            .navigationTitle("Plan the meeting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(starting ? "Starting…" : "Start") {
                        start()
                    }
                    .disabled(starting || !sync.canUseLiveTranscription)
                }
            }
            .onChange(of: kind) { _, newKind in
                if points.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    points = newKind.suggestedPlan.joined(separator: "\n")
                }
            }
            .onAppear {
                if points.isEmpty { points = kind.suggestedPlan.joined(separator: "\n") }
            }
        }
    }

    private var attachedPageTitle: String? {
        guard let pageID else { return nil }
        return pages.first { $0.id == pageID }?.title
    }

    private func start() {
        guard !starting else { return }
        starting = true
        let plan = MeetingPlan(
            kind: kind,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            goal: goal.trimmingCharacters(in: .whitespacesAndNewlines),
            points: points.split(separator: "\n").map(String.init)
        )
        let attachedPage = pageID
        dismiss()
        Task { await session.start(plan: plan, attachedTo: attachedPage) }
    }
}

// MARK: - Live

/// The meeting itself. Questions to ask come first; the transcript is tucked
/// away until someone asks for it.
struct LiveMeetingView: View {
    @Environment(MeetingSession.self) private var session
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showTranscript = false
    @State private var noteText = ""
    @State private var showNoteField = false
    @State private var confirmEnd = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                statusHeader
                if let message = session.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                askRail
                capturedList
                coverage
                quickActions
                transcriptPanel
            }
            .padding(20)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.sideleafPaper)
        .safeAreaInset(edge: .bottom) { endBar }
        .navigationTitle(session.plan.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: session.latestCueID) { _, id in
            guard let id, let cue = session.cues.first(where: { $0.id == id }) else { return }
            AccessibilityNotification.Announcement("\(cue.label). \(cue.prompt)").post()
            session.acknowledgeLatestCue()
        }
        .confirmationDialog(
            "End this meeting?",
            isPresented: $confirmEnd,
            titleVisibility: .visible
        ) {
            Button("End and review") { Task { await session.finish() } }
            Button("Keep listening", role: .cancel) {}
        } message: {
            Text("Sideleaf stops the microphone and shows you what it kept. Nothing is saved until you choose a page.")
        }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: session.isListening ? "waveform" : "mic.slash")
                    .foregroundStyle(session.isListening ? Color.red : Color.secondary)
                    .symbolEffect(.pulse, isActive: session.isListening)
                if let startedAt = session.startedAt {
                    Text(startedAt, style: .timer)
                        .font(.system(.largeTitle, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.sideleafInk)
                }
            }
            Text(session.status)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Transcription status")
                .accessibilityValue(session.status)
        }
    }

    @ViewBuilder
    private var askRail: some View {
        let asks = session.liveAsks
        VStack(alignment: .leading, spacing: 10) {
            Text(asks.isEmpty ? "Nothing to ask yet" : "Ask now")
                .font(.headline)
                .fontDesign(.serif)
            if asks.isEmpty {
                Text("Sideleaf is listening. Questions appear here the moment something is left open, vague or unowned.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(asks.prefix(4)) { cue in
                    CueCardView(cue: cue, isPrimary: true)
                }
                if asks.count > 4 {
                    Text("\(asks.count - 4) more waiting")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var capturedList: some View {
        let captured = session.captured
        if !captured.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Keeping for you")
                    .font(.headline)
                    .fontDesign(.serif)
                ForEach(captured.prefix(6)) { cue in
                    CueCardView(cue: cue, isPrimary: false)
                }
            }
        }
    }

    @ViewBuilder
    private var coverage: some View {
        let remaining = session.planPoints.filter { !$0.covered }
        if !remaining.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Still to cover")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(remaining) { point in
                    Label(point.text, systemImage: "circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { quickButtons }
                VStack(alignment: .leading, spacing: 10) { quickButtons }
            }
            if showNoteField {
                HStack {
                    TextField("What should Sideleaf keep?", text: $noteText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(commitNote)
                    Button("Keep", action: commitNote)
                        .buttonStyle(.borderedProminent)
                        .tint(.sideleafOlive)
                        .disabled(noteText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var quickButtons: some View {
        Button {
            session.markMoment()
        } label: {
            Label("Mark this moment", systemImage: "star")
        }
        .buttonStyle(.bordered)
        .tint(.sideleafOlive)

        Button {
            showNoteField.toggle()
        } label: {
            Label("Add a note", systemImage: "square.and.pencil")
        }
        .buttonStyle(.bordered)
        .tint(.sideleafOlive)
    }

    private var transcriptPanel: some View {
        DisclosureGroup(isExpanded: $showTranscript) {
            Text(session.transcript.isEmpty ? "Nothing yet." : session.transcript)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        } label: {
            Label("Live transcript", systemImage: "text.alignleft")
                .font(.footnote.weight(.semibold))
        }
        .tint(.sideleafOlive)
    }

    private var endBar: some View {
        HStack(spacing: 12) {
            Button {
                confirmEnd = true
            } label: {
                Label("End meeting", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func commitNote() {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        session.markMoment(note: trimmed)
        noteText = ""
        showNoteField = false
    }
}

/// One suggestion, with the words that produced it and the three things a
/// person can do about it.
struct CueCardView: View {
    @Environment(MeetingSession.self) private var session
    let cue: MeetingCue
    let isPrimary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(cue.label, systemImage: cue.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.sideleafOlive)
                Spacer()
                if let due = cue.dueDate {
                    Label(
                        due.formatted(date: .abbreviated, time: .shortened),
                        systemImage: "calendar"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            Text(cue.prompt)
                .font(isPrimary ? .body.weight(.medium) : .callout)
                .foregroundStyle(Color.sideleafInk)
                .fixedSize(horizontal: false, vertical: true)
            if !cue.quote.isEmpty {
                Text("Heard: \u{201C}\(cue.quote)\u{201D}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                if cue.role == .ask {
                    Button("Asked") { session.markAsked(cue) }
                        .buttonStyle(.borderedProminent)
                        .tint(.sideleafOlive)
                    Button("Keep") { session.keep(cue) }
                        .buttonStyle(.bordered)
                }
                Button(role: .destructive) {
                    session.dismiss(cue)
                } label: {
                    Label("Dismiss", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Dismiss this suggestion")
            }
            .font(.footnote)
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isPrimary ? Color.white.opacity(0.9) : Color.sideleafOlive.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.sideleafOlive.opacity(isPrimary ? 0.35 : 0.15), lineWidth: 1)
        )
    }
}
