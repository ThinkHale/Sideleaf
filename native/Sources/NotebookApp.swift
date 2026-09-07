import SwiftUI
import SwiftData

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

    var body: some View {
        NavigationSplitView {
            List(selection: $selected) {
                ForEach(pages.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.text.localizedCaseInsensitiveContains(search) }) { page in
                    Label(page.title, systemImage: "doc.text").tag(page.id)
                }
            }
            .navigationTitle("Sideleaf")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search typed notes")
            .toolbar {
                ToolbarItem(placement: .principal) { SideleafWordmark() }
                ToolbarItem(placement: .primaryAction) {
                    Button("New page", systemImage: "plus") { let page = LocalPage(); context.insert(page); selected = page.id }
                }
            }
        } detail: {
            if let page = pages.first(where: { $0.id == selected }) { NativeNotebookPage(page: page) }
            else { SideleafEmptyPage() }
        }
        .tint(Color(red: 0.41, green: 0.45, blue: 0.33))
    }
}

enum NotebookTool: String, CaseIterable { case type = "Type", write = "Write", mark = "Mark", select = "Select", erase = "Erase" }

struct NativeNotebookPage: View {
    @Bindable var page: LocalPage
    @Environment(\.modelContext) private var context
    @State private var tool: NotebookTool = .type
    @State private var readiness = OnDeviceReadiness()
    @State private var message = "Saved on this iPad. Account sync is not connected in this native slice."
    @State private var showReadiness = false
    @State private var undoSignal = 0
    @State private var redoSignal = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TextField("Page title", text: $page.title).font(.system(size: 38, design: .serif))
                Text(message).font(.caption).foregroundStyle(.secondary)
                HStack {
                    ForEach(NotebookTool.allCases, id: \.self) { item in
                        Button(item.rawValue) { tool = item }
                            .buttonStyle(.bordered).tint(tool == item ? .olive : .secondary)
                            .accessibilityAddTraits(tool == item ? .isSelected : [])
                    }
                    Button("Undo", systemImage: "arrow.uturn.backward") { undoSignal += 1 }.labelStyle(.iconOnly)
                    Button("Redo", systemImage: "arrow.uturn.forward") { redoSignal += 1 }.labelStyle(.iconOnly)
                }
                Text(tool == .mark ? "Circle text to mark it important. Your original quote is retained." : tool == .write ? "Apple Pencil writes ordinary ink. Fingers scroll." : "Personal notes stay separate from meeting preparation.").font(.caption).foregroundStyle(.secondary)
                NativePaper(page: page, tool: tool, undoSignal: undoSignal, redoSignal: redoSignal) {
                    do { try context.save(); message = "Saved on this iPad. Sync is not connected." }
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
                            Button("Remove mark") { page.annotations.removeAll { $0.id == mark.id }; try? context.save() }
                        }
                    }
                }
            }.padding(30).background(Color(red: 1, green: 0.99, blue: 0.97))
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Label("Microphone off", systemImage: "mic.slash").font(.caption) }
            ToolbarItem(placement: .topBarTrailing) { Button("On-device readiness") { showReadiness = true; Task { await readiness.check() } } }
        }
        .sheet(isPresented: $showReadiness) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 20) {
                    Text("On-device transcription").font(.largeTitle).fontDesign(.serif)
                    Text(readiness.message)
                    if readiness.needsAssets { Button("Download language assets") { Task { await readiness.installAssets() } } }
                    Text("Only model assets are downloaded. No microphone access is requested by this readiness check. Live capture and backend entitlements are not connected in this native slice.").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }.padding(30).toolbar { Button("Done") { showReadiness = false } }
            }.presentationDetents([.medium, .large])
        }
        .onChange(of: page.title) { page.updatedAt = Date(); try? context.save() }
    }
}

private extension Color { static let olive = Color(red: 0.41, green: 0.45, blue: 0.33) }
