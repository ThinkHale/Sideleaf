import SwiftUI

/// The whole watch app: start, stop, and the questions worth asking right now.
struct WatchMeetingView: View {
    @Environment(WatchConnection.self) private var connection
    @State private var kind: MeetingKind = .meeting

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if connection.snapshot.isLive {
                        liveContent
                    } else {
                        idleContent
                    }
                    if let notice = connection.notice {
                        Text(notice)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
            }
            .navigationTitle(connection.snapshot.isLive ? "Listening" : "Sideleaf")
        }
        .tint(.sideleafOlive)
    }

    @ViewBuilder
    private var idleContent: some View {
        Picker("Kind", selection: $kind) {
            ForEach(MeetingKind.allCases) { option in
                Label(option.title, systemImage: option.symbol).tag(option)
            }
        }
        .pickerStyle(.navigationLink)

        Button {
            connection.send(MeetingRequest(action: .start, kind: kind))
        } label: {
            Label(
                connection.isPending(.start) ? "Starting…" : "Start",
                systemImage: "waveform"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(connection.isPending(.start))

        Text("Your iPhone listens and sends questions here. It never sends the transcript to this watch.")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var liveContent: some View {
        if let startedAt = connection.snapshot.startedAt {
            Text(startedAt, style: .timer)
                .font(.system(.title2, design: .rounded))
                .monospacedDigit()
        }
        Text(connection.snapshot.displayTitle)
            .font(.caption)
            .foregroundStyle(.secondary)

        HStack(spacing: 8) {
            Button {
                connection.send(MeetingRequest(action: .stop))
            } label: {
                Label("End", systemImage: "stop.fill").labelStyle(.iconOnly)
            }
            .tint(.red)
            .disabled(connection.isPending(.stop))

            Button {
                connection.send(MeetingRequest(action: .markMoment))
            } label: {
                Label("Mark this", systemImage: "star.fill").labelStyle(.iconOnly)
            }
            .tint(.sideleafOlive)
        }
        .buttonStyle(.bordered)

        if connection.snapshot.topCues.isEmpty {
            Text("Nothing to ask yet. Sideleaf is listening.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            ForEach(connection.snapshot.topCues) { cue in
                cueCard(cue)
            }
        }

        if !connection.snapshot.planRemaining.isEmpty {
            Divider()
            Text("Still to cover")
                .font(.caption2.weight(.semibold))
            ForEach(connection.snapshot.planRemaining, id: \.self) { point in
                Text("• \(point)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func cueCard(_ cue: MeetingCue) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(cue.label, systemImage: cue.symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.sideleafOlive)
            Text(cue.prompt)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Button("Asked") {
                connection.send(MeetingRequest(action: .markAsked, cueID: cue.id))
            }
            .font(.caption2)
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.sideleafOlive.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
    }
}

extension ShapeStyle where Self == Color {
    /// The supplied Sideleaf sage, used for anything Sideleaf itself suggests.
    static var sideleafOlive: Color { Color(red: 0.41, green: 0.45, blue: 0.33) }
}
