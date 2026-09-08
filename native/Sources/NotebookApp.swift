import SwiftUI
import SwiftData
import UIKit

@main
struct SideleafApp: App {
    var body: some Scene {
        WindowGroup { NotebookLibrary() }
            .modelContainer(for: LocalPage.self)
    }
}

@Model
final class LocalPage {
    @Attribute(.unique) var id: UUID
    var title: String
    var text: String
    var textRevision: Int
    var ink: Data
    @Attribute(.externalStorage) var inkPreview: Data?
    var annotationData: Data
    var updatedAt: Date

    init(title: String = "Untitled page") {
        id = UUID(); self.title = title; text = ""; textRevision = 1
        ink = Data(); annotationData = Data(); updatedAt = Date()
    }
    var annotations: [NativeAnnotation] {
        get { (try? JSONDecoder().decode([NativeAnnotation].self, from: annotationData)) ?? [] }
        set { annotationData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

struct NotebookLibrary: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LocalPage.updatedAt, order: .reverse) private var pages: [LocalPage]
    @State private var selected: UUID?
    @State private var search = ""
    @State private var preferredCompactColumn = NavigationSplitViewColumn.sidebar

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            List(selection: $selected) {
                ForEach(pages.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.text.localizedCaseInsensitiveContains(search) }) { page in
                    NavigationLink(value: page.id) {
                        Label(page.title, systemImage: "doc.text")
                    }
                }
            }
            .navigationTitle("Sideleaf")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search typed notes")
            .toolbar {
                ToolbarItem(placement: .principal) { SideleafWordmark() }
                ToolbarItem(placement: .primaryAction) {
                    Button("New page", systemImage: "plus") {
                        let page = LocalPage()
                        context.insert(page)
                        selected = page.id
                        preferredCompactColumn = .detail
                    }
                    .labelStyle(.iconOnly)
                }
            }
        } detail: {
            if let page = pages.first(where: { $0.id == selected }) { NativeNotebookPage(page: page) }
            else { SideleafEmptyPage() }
        }
        .tint(Color(red: 0.41, green: 0.45, blue: 0.33))
        .onChange(of: selected) { _, pageID in
            if pageID != nil { preferredCompactColumn = .detail }
        }
    }
}

enum NotebookTool: String, CaseIterable { case type = "Type", write = "Write", mark = "Mark", select = "Select", erase = "Erase" }

struct NativeNotebookPage: View {
    @Bindable var page: LocalPage
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var tool: NotebookTool = .type
    @State private var readiness = OnDeviceReadiness()
    @State private var message = "Saved on this device. Account sync is not connected in this native slice."
    @State private var showReadiness = false
    @State private var undoSignal = 0
    @State private var redoSignal = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TextField("Page title", text: $page.title)
                    .font(.largeTitle)
                    .fontDesign(.serif)
                Text(message).font(.caption).foregroundStyle(.secondary)
                if horizontalSizeClass != .compact { regularEditorControls }
                Text(toolHelp).font(.caption).foregroundStyle(.secondary)
                NativePaper(page: page, tool: tool, undoSignal: undoSignal, redoSignal: redoSignal) {
                    do { try context.save(); message = "Saved on this device. Sync is not connected." }
                    catch { message = "Could not save. Keep the app open and preserve your note." }
                }
                .frame(minHeight: 1200)
                if !page.annotations.isEmpty {
                    Text("Important").font(.title2).fontDesign(.serif)
                    ForEach(page.annotations) { mark in
                        HStack(alignment: .top) {
                            Image(systemName: "star")
                            VStack(alignment: .leading) {
                                Text(mark.anchor.quote)
                                if !mark.anchor.resolved { Text("Source changed. Original quote preserved.").font(.caption).foregroundStyle(.orange) }
                            }
                            Spacer()
                            Button("Remove mark", systemImage: "trash") {
                                page.annotations.removeAll { $0.id == mark.id }
                                try? context.save()
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                }
            }
            .padding(horizontalSizeClass == .compact ? 16 : 30)
            .background(Color(red: 1, green: 0.99, blue: 0.97))
        }
        .safeAreaInset(edge: .bottom) {
            if horizontalSizeClass == .compact { compactEditorControls }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Label("Microphone off", systemImage: "mic.slash")
                    .labelStyle(.iconOnly)
                Button("On-device readiness", systemImage: "waveform") {
                    showReadiness = true
                    Task { await readiness.check() }
                }
                .labelStyle(.iconOnly)
            }
        }
        .sheet(isPresented: $showReadiness) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("On-device transcription").font(.largeTitle).fontDesign(.serif)
                        Text(readiness.message)
                        if readiness.needsAssets { Button("Download language assets") { Task { await readiness.installAssets() } } }
                        Text("Only model assets are downloaded. No microphone access is requested by this readiness check. Live capture and backend entitlements are not connected in this native slice.").font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(horizontalSizeClass == .compact ? 16 : 30)
                }
                .toolbar { Button("Done") { showReadiness = false } }
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: page.title) { page.updatedAt = Date(); try? context.save() }
    }

    private var compactEditorControls: some View {
        HStack(spacing: 12) {
            Picker(selection: $tool) {
                ForEach(NotebookTool.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            } label: {
                Label("Tool: \(tool.rawValue)", systemImage: "slider.horizontal.3")
            }
            .pickerStyle(.menu)
            .buttonStyle(.bordered)
            Spacer(minLength: 0)
            historyControls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var regularEditorControls: some View {
        HStack {
            ForEach(NotebookTool.allCases, id: \.self) { item in
                Button(item.rawValue) { tool = item }
                    .buttonStyle(.bordered)
                    .tint(tool == item ? .olive : .secondary)
                    .accessibilityAddTraits(tool == item ? .isSelected : [])
            }
            Spacer(minLength: 0)
            historyControls
        }
    }

    private var historyControls: some View {
        HStack {
            Button("Undo", systemImage: "arrow.uturn.backward") { undoSignal += 1 }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
            Button("Redo", systemImage: "arrow.uturn.forward") { redoSignal += 1 }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
        }
    }

    private var toolHelp: String {
        switch tool {
        case .mark:
            horizontalSizeClass == .compact
                ? "Circle text to mark it important. Switch to Select to scroll."
                : "Circle text to mark it important. Your original quote is retained."
        case .write:
            UIDevice.current.userInterfaceIdiom == .phone
                ? "Draw with a finger. Switch to Type or Select to scroll."
                : "Apple Pencil writes ordinary ink. Fingers scroll."
        case .erase:
            UIDevice.current.userInterfaceIdiom == .phone
                ? "Erase ink with a finger. Switch tools to scroll."
                : "Apple Pencil erases ink. Fingers scroll."
        default:
            "Personal notes stay separate from meeting preparation."
        }
    }
}

private extension Color { static let olive = Color(red: 0.41, green: 0.45, blue: 0.33) }
