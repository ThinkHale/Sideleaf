import AppIntents
import SwiftUI
import WidgetKit

struct MeetingEntry: TimelineEntry {
    var date: Date
    var snapshot: MeetingSnapshot
    var kind: MeetingKind

    var isLive: Bool { snapshot.showsLiveMeeting(now: date) }
}

/// Reads the snapshot the app leaves in the shared container. The widget never
/// records anything itself; starting always hands off to the app.
struct MeetingProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MeetingEntry {
        MeetingEntry(date: Date(), snapshot: .idle, kind: .meeting)
    }

    func snapshot(
        for configuration: MeetingWidgetConfiguration,
        in context: Context
    ) async -> MeetingEntry {
        MeetingEntry(
            date: Date(),
            snapshot: MeetingSharedStore.loadSnapshot(),
            kind: configuration.kind
        )
    }

    func timeline(
        for configuration: MeetingWidgetConfiguration,
        in context: Context
    ) async -> Timeline<MeetingEntry> {
        let now = Date()
        let entry = MeetingEntry(
            date: now,
            snapshot: MeetingSharedStore.loadSnapshot(),
            kind: configuration.kind
        )
        // The elapsed time draws itself; a refresh is only needed to notice a
        // meeting that has gone stale.
        let next = entry.isLive ? now.addingTimeInterval(300) : now.addingTimeInterval(3_600)
        return Timeline(entries: [entry], policy: .after(next))
    }
}

struct MeetingWidget: Widget {
    static let kind = "SideleafMeetingWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: MeetingWidgetConfiguration.self,
            provider: MeetingProvider()
        ) { entry in
            MeetingWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Sideleaf meeting")
        .description("Start listening, and see what to ask while a meeting runs.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryInline,
        ])
    }
}

struct MeetingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MeetingEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(entry.isLive ? "Sideleaf listening" : "Sideleaf")
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .systemSmall:
            small
        case .systemMedium:
            medium
        default:
            large
        }
    }

    // MARK: - Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if entry.isLive {
                elapsed.font(.system(.title2, design: .rounded)).monospacedDigit()
                Text(askSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                endButton
            } else {
                Spacer(minLength: 0)
                Text(entry.kind.focus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                startButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                header
                if entry.isLive {
                    elapsed.font(.system(.title2, design: .rounded)).monospacedDigit()
                    Text(askSummary).font(.caption2).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    endButton
                } else {
                    Spacer(minLength: 0)
                    startButton
                }
            }
            .frame(maxWidth: 130, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                if let cue = entry.snapshot.topCues.first, entry.isLive {
                    cueBlock(cue, lines: 3)
                } else {
                    Text(entry.isLive ? "Listening. Nothing to ask yet." : "Sideleaf listens for the questions you would have missed, and keeps what you agreed to.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !entry.isLive {
                        Text(entry.kind.focus)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.sideleafOlive)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if entry.isLive {
                HStack {
                    elapsed.font(.system(.title, design: .rounded)).monospacedDigit()
                    Spacer()
                    endButton
                }
                Text(askSummary).font(.caption).foregroundStyle(.secondary)
                Divider()
                if entry.snapshot.topCues.isEmpty {
                    Text("Listening. Sideleaf will put questions here as they come up.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entry.snapshot.topCues.prefix(3)) { cue in
                        cueBlock(cue, lines: 2)
                    }
                }
                if !entry.snapshot.planRemaining.isEmpty {
                    Divider()
                    Text("Still to cover: " + entry.snapshot.planRemaining.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Second brain for the room.")
                    .font(.headline)
                    .fontDesign(.serif)
                Text("Sideleaf listens on this device, offers the follow-up questions worth asking, and remembers what you agreed to.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                startButton
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Lock Screen

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if entry.isLive {
                VStack(spacing: 0) {
                    Image(systemName: "waveform")
                        .font(.caption2)
                    Text("\(entry.snapshot.openAskCount)")
                        .font(.system(.headline, design: .rounded))
                        .monospacedDigit()
                }
            } else {
                Image(systemName: "waveform.badge.plus").font(.title3)
            }
        }
        .widgetLabel(entry.isLive ? "Listening" : "Sideleaf")
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(entry.isLive ? "Listening" : "Sideleaf", systemImage: "waveform")
                .font(.caption2.weight(.semibold))
            if entry.isLive, let cue = entry.snapshot.topCues.first {
                Text(cue.prompt)
                    .font(.caption2)
                    .lineLimit(2)
            } else if entry.isLive {
                Text(askSummary).font(.caption2)
            } else {
                Text("Tap to start listening.").font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: entry.isLive ? "waveform" : entry.kind.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(entry.isLive ? Color.red : .sideleafOlive)
            Text(entry.isLive ? entry.snapshot.displayTitle : "Sideleaf")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var elapsed: some View {
        if let startedAt = entry.snapshot.startedAt {
            Text(startedAt, style: .timer)
        } else {
            Text("0:00")
        }
    }

    private var askSummary: String {
        let asks = entry.snapshot.openAskCount
        let kept = entry.snapshot.rememberCount
        if asks == 0 && kept == 0 { return "Listening on this device" }
        let askText = asks == 1 ? "1 question" : "\(asks) questions"
        let keptText = kept == 1 ? "1 to remember" : "\(kept) to remember"
        return "\(askText) · \(keptText)"
    }

    private func cueBlock(_ cue: MeetingCue, lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(cue.label, systemImage: cue.symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.sideleafOlive)
            Text(cue.prompt)
                .font(.caption)
                .lineLimit(lines)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var startButton: some View {
        Button(intent: StartMeetingIntent(kind: entry.kind)) {
            Label("Start \(entry.kind.title.lowercased())", systemImage: "waveform")
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.sideleafOlive)
    }

    private var endButton: some View {
        Button(intent: StopMeetingIntent()) {
            Label("End", systemImage: "stop.fill")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }
}

extension ShapeStyle where Self == Color {
    /// The supplied Sideleaf sage, used for anything Sideleaf itself suggests.
    static var sideleafOlive: Color { Color(red: 0.41, green: 0.45, blue: 0.33) }
}
