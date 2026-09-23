import SwiftUI
import SwiftData

/// The two minutes after a meeting that decide whether any of it survives.
///
/// Everything here is editable and nothing is written until the person saves.
/// What they keep becomes ordinary notes plus marks that the browser shows in
/// its margin.
struct MeetingRecapView: View {
    @Environment(\.modelContext) private var context
    @Environment(NotebookSync.self) private var sync
    @Environment(MeetingSession.self) private var session
    @Environment(MeetingReminders.self) private var reminders
    @Environment(SideleafRouter.self) private var router
    @Query(sort: \LocalPage.updatedAt, order: .reverse) private var pages: [LocalPage]

    @State private var useAttachedPage = true
    @State private var saving = false
    @State private var savedTitle: String?
    @State private var savedPageID: UUID?
    @State private var message: String?
    @State private var reminderDates: [UUID: Date] = [:]
    @State private var confirmDiscard = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let savedTitle {
                    savedState(savedTitle)
                } else {
                    sections
                    destination
                    if let message {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.sideleafPaper)
        .safeAreaInset(edge: .bottom) {
            if savedTitle == nil { saveBar }
        }
        .navigationTitle("Recap")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Discard this meeting?",
            isPresented: $confirmDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard everything", role: .destructive) { session.reset() }
            Button("Keep reviewing", role: .cancel) {}
        } message: {
            Text("The transcript, the questions and everything Sideleaf kept are dropped. This cannot be undone.")
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.plan.displayTitle)
                .font(.largeTitle)
                .fontDesign(.serif)
                .foregroundStyle(Color.sideleafInk)
            Text(summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        let duration = MeetingRecapBuilder.durationText(session.elapsed)
        let asks = keptCues(role: .ask).count
        let remembers = keptCues(role: .remember).count
        return "\(session.plan.kind.title) · \(duration) · \(asks) to ask · \(remembers) to remember"
    }

    @ViewBuilder
    private var sections: some View {
        section(
            MeetingRecapBuilder.questionsHeading,
            "Nothing was left open.",
            session.cues.filter {
                $0.role == .ask && $0.kind != .coverage && $0.state != .resolved
            }
        )
        section(
            MeetingRecapBuilder.nextStepsHeading,
            nil,
            session.cues.filter { isWork($0) && $0.owedBy != .other }
        )
        section(
            MeetingRecapBuilder.theirStepsHeading,
            nil,
            session.cues.filter { isWork($0) && $0.owedBy == .other }
        )
        section(
            MeetingRecapBuilder.decidedHeading,
            nil,
            session.cues.filter { $0.kind == .decision && $0.state != .resolved }
        )
        section(MeetingRecapBuilder.markedHeading, nil, session.cues.filter { $0.kind == .note })
        section(
            MeetingRecapBuilder.answeredHeading,
            nil,
            session.cues.filter {
                $0.role == .ask && $0.kind != .coverage && $0.state == .resolved
            }
        )
        section(
            MeetingRecapBuilder.reversedHeading,
            nil,
            session.cues.filter { $0.kind == .decision && $0.state == .resolved }
        )
        section(
            MeetingRecapBuilder.notCoveredHeading,
            nil,
            session.cues.filter { $0.kind == .coverage && $0.state != .resolved }
        )
    }

    @ViewBuilder
    private func section(_ title: String, _ empty: String?, _ cues: [MeetingCue]) -> some View {
        let ordered = cues.sorted { $0.offset < $1.offset }
        if !ordered.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                    .fontDesign(.serif)
                ForEach(ordered) { cue in
                    row(cue)
                }
            }
        } else if let empty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).fontDesign(.serif)
                Text(empty).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ cue: MeetingCue) -> some View {
        let included = cue.state != .dismissed
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    included ? session.dismiss(cue) : session.reopen(cue)
                } label: {
                    Image(systemName: included ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(included ? Color.sideleafOlive : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(included ? "Included. Tap to leave out." : "Left out. Tap to include.")

                VStack(alignment: .leading, spacing: 6) {
                    TextField(
                        "Follow-up",
                        text: Binding(
                            get: { cue.prompt },
                            set: { session.edit(cue, prompt: $0) }
                        ),
                        axis: .vertical
                    )
                    .font(.callout)
                    .disabled(!included)
                    if !cue.quote.isEmpty {
                        Text("Heard: \u{201C}\(cue.quote)\u{201D}")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let note = cue.resolutionNote {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Label(note, systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(Color.sideleafOlive)
                            Button("Still open") { session.reopen(cue) }
                                .font(.caption)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    if included, cue.carriesWork {
                        ownerControls(cue)
                    }
                    if included, cue.role == .remember {
                        reminderControls(cue)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(included ? 0.85 : 0.4), in: RoundedRectangle(cornerRadius: 12))
        .opacity(included ? 1 : 0.6)
    }

    private func isWork(_ cue: MeetingCue) -> Bool {
        cue.kind == .commitment || cue.kind == .request || cue.kind == .deadline
    }

    /// Whose job this is. Sideleaf guesses; the person decides.
    @ViewBuilder
    private func ownerControls(_ cue: MeetingCue) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(
                "Who owes this",
                selection: Binding(
                    get: { cue.owedBy == .other ? MeetingSpeaker.other : .you },
                    set: { session.setOwner($0, for: cue) }
                )
            ) {
                Text("Mine").tag(MeetingSpeaker.you)
                Text("Theirs").tag(MeetingSpeaker.other)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
            if cue.attributionSource == .assumed {
                Text("Assumed, because Sideleaf could not tell who was speaking.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func reminderControls(_ cue: MeetingCue) -> some View {
        if let date = reminderDates[cue.id] {
            HStack(spacing: 8) {
                DatePicker(
                    "Remind me",
                    selection: Binding(
                        get: { date },
                        set: { reminderDates[cue.id] = $0 }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .font(.footnote)
                Button("Remove", systemImage: "bell.slash") {
                    reminderDates[cue.id] = nil
                    reminders.cancel(cue)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else {
            Button("Remind me", systemImage: "bell") {
                reminderDates[cue.id] = MeetingReminders.suggestedDate(for: cue)
            }
            .font(.footnote)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.sideleafOlive)
            .disabled(!reminders.canSchedule)
        }
    }

    @ViewBuilder
    private var destination: some View {
        if let attached = attachedPage {
            VStack(alignment: .leading, spacing: 6) {
                Text("Where it goes")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Where it goes", selection: $useAttachedPage) {
                    Text(attached.title).tag(true)
                    Text("A new page").tag(false)
                }
                .pickerStyle(.segmented)
            }
        } else {
            Text("Saved to a new page in your notebook.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var saveBar: some View {
        HStack(spacing: 12) {
            Button("Discard", role: .destructive) { confirmDiscard = true }
                .buttonStyle(.bordered)
            Button {
                save()
            } label: {
                Label(saving ? "Saving…" : "Save recap", systemImage: "tray.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.sideleafOlive)
            .disabled(saving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func savedState(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Saved to “\(title)”", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(Color.sideleafOlive)
            if let message {
                Text(message).font(.footnote).foregroundStyle(.orange)
            }
            Text("Your follow-ups are marks on that page, so they travel to the web notebook with their source quotes.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Open the page") {
                    let pageID = savedPageID
                    session.reset()
                    if let pageID { router.openPage(pageID) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.sideleafOlive)
                Button("Done") { session.reset() }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Actions

    private var attachedPage: LocalPage? {
        guard let id = session.attachedPageID else { return nil }
        return pages.first { $0.id == id }
    }

    private func keptCues(role: MeetingCue.Role) -> [MeetingCue] {
        session.cues.filter { $0.role == role && $0.survivesRecap }
    }

    private func save() {
        guard !saving, let draft = session.recapDraft() else { return }
        saving = true
        message = nil
        let page = (useAttachedPage ? attachedPage : nil)
            ?? sync.newPage(titled: draft.suggestedTitle, context: context)
        let outcome = sync.saveMeeting(
            draft: draft,
            transcript: session.transcript,
            plan: session.plan,
            endedAt: session.endedAt ?? Date(),
            to: page,
            context: context
        )
        saving = false
        message = outcome.message
        guard outcome.savedRecap else { return }
        savedTitle = page.title
        savedPageID = page.id
        scheduleReminders(title: page.title)
    }

    private func scheduleReminders(title: String) {
        let requested = reminderDates
        guard !requested.isEmpty else { return }
        let cues = session.cues.filter { requested[$0.id] != nil && $0.survivesRecap }
        Task {
            for cue in cues {
                guard let date = requested[cue.id] else { continue }
                await reminders.schedule(cue, at: date, meetingTitle: title)
            }
        }
    }
}
