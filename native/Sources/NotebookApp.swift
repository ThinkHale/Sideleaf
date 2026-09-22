import Combine
import SwiftUI
import SwiftData
import UIKit

@main
struct SideleafApp: App {
    @State private var sync = NotebookSync()
    @State private var session = MeetingSession()
    @State private var reminders = MeetingReminders()
    @State private var router = SideleafRouter()

    var body: some Scene {
        WindowGroup {
            SideleafRootView()
                .environment(sync)
                .environment(session)
                .environment(reminders)
                .environment(router)
        }
        .modelContainer(for: LocalPage.self)
    }
}

/// Sideleaf opens on the meeting, not on the notebook.
///
/// The first tab is the whole product: start listening, see what to ask, decide
/// what to keep. Typed notes and ink live in the second tab, and a live meeting
/// keeps running while the person writes there.
struct SideleafRootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(NotebookSync.self) private var sync
    @Environment(MeetingSession.self) private var session
    @Environment(MeetingReminders.self) private var reminders
    @Environment(SideleafRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        return TabView(selection: $router.tab) {
            Tab("Meeting", systemImage: "waveform", value: RootTab.meeting) {
                NavigationStack { meetingTab }
            }
            .badge(session.isActive ? session.openAskCount : 0)
            Tab("Notes", systemImage: "book.closed", value: RootTab.notes) {
                NotebookLibrary()
            }
        }
        .tint(.sideleafOlive)
        .task {
            WatchLink.shared.activate()
            session.publishTo { snapshot in WatchLink.shared.send(snapshot) }
            await sync.restore(context: context)
            await reminders.refresh()
            consumePendingRequest()
        }
        .onReceive(
            NotificationCenter.default
                .publisher(for: .sideleafMeetingRequest)
                .receive(on: DispatchQueue.main)
        ) { _ in
            consumePendingRequest()
        }
        .onChange(of: WatchLink.shared.pendingRequest) { _, request in
            guard let request else { return }
            WatchLink.shared.clearPendingRequest()
            handle(request)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { consumePendingRequest() }
        }
        .onChange(of: sync.shouldPresentTermsAcceptance) { _, required in
            if required { router.showAccount = true }
        }
        .onChange(of: sync.canUseLiveTranscription) { _, permitted in
            if !permitted, session.isActive { Task { await session.finish() } }
        }
        .sheet(isPresented: $router.showAccount) { NativeAccountSheet() }
        .sheet(isPresented: $router.showPlanSheet) {
            MeetingPlanSheet(pageID: router.planPageID)
        }
    }

    @ViewBuilder
    private var meetingTab: some View {
        if session.hasRecap {
            MeetingRecapView()
        } else if session.isActive {
            LiveMeetingView()
        } else {
            MeetingHomeView()
        }
    }

    /// Handles a start or stop that came from a widget, a control, Siri or the
    /// Apple Watch. The microphone only ever opens here, in the app.
    private func handle(_ request: MeetingRequest) {
        switch request.action {
        case .open:
            router.tab = .meeting
        case .start:
            router.tab = .meeting
            guard !session.isActive, !session.hasRecap else { return }
            guard sync.canUseLiveTranscription else {
                router.showAccount = true
                return
            }
            let kind = request.kind ?? .meeting
            Task {
                await session.start(plan: MeetingPlan(kind: kind, title: kind.defaultTitle))
            }
        case .stop:
            router.tab = .meeting
            guard session.isActive else { return }
            Task { await session.finish() }
        case .markMoment:
            guard session.isActive else { return }
            session.markMoment()
        case .markAsked:
            guard let id = request.cueID,
                  let cue = session.cues.first(where: { $0.id == id })
            else { return }
            session.markAsked(cue)
        }
    }

    private func consumePendingRequest() {
        guard let request = MeetingSharedStore.takeRequest() else { return }
        handle(request)
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
    var ownerUserID: String?
    var notebookID: UUID?
    var serverVersion: Int?
    var pendingMutationID: UUID?
    var lastSyncedAt: Date?
    var syncError: String?
    @Attribute(.externalStorage) var cloudDocumentData: Data?
    var cloudBlockID: UUID?
    @Attribute(.externalStorage) var conflictDocumentData: Data?
    @Attribute(.externalStorage) var recoveryDocumentData: Data?
    var transcriptBlockID: UUID?
    var localTranscript: String?
    /// Set when this page holds a saved meeting, so the meeting tab can list it.
    var meetingKind: String?
    var meetingEndedAt: Date?

    init(id: UUID = UUID(), title: String = "Untitled page") {
        self.id = id; self.title = title; text = ""; textRevision = 1
        ink = Data(); annotationData = Data(); updatedAt = Date()
        ownerUserID = nil; notebookID = nil; serverVersion = nil
        pendingMutationID = nil; lastSyncedAt = nil; syncError = nil
        cloudDocumentData = nil; cloudBlockID = nil; conflictDocumentData = nil
        recoveryDocumentData = nil
        transcriptBlockID = nil; localTranscript = nil
        meetingKind = nil; meetingEndedAt = nil
    }
    var annotations: [NativeAnnotation] {
        get { (try? JSONDecoder().decode([NativeAnnotation].self, from: annotationData)) ?? [] }
        set { annotationData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

struct NotebookLibrary: View {
    @Environment(\.modelContext) private var context
    @Environment(NotebookSync.self) private var sync
    @Query(sort: \LocalPage.updatedAt, order: .reverse) private var pages: [LocalPage]
    @Environment(SideleafRouter.self) private var router
    @State private var selected: UUID?
    @State private var search = ""
    @State private var preferredCompactColumn = NavigationSplitViewColumn.sidebar

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            List(selection: $selected) {
                if case .restoring = sync.account {
                    HStack {
                        ProgressView()
                        Text("Restoring your Sideleaf account…")
                    }
                }
                if sync.hasAccount {
                    Section(accountPagesSectionTitle) {
                        pageRows(accountPages)
                    }
                    if !guestPages.isEmpty {
                        Section("On this device") { pageRows(guestPages) }
                    }
                } else {
                    Section("On this device") { pageRows(guestPages) }
                }
            }
            .navigationTitle("Sideleaf")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search typed notes")
            .refreshable {
                await sync.refresh(context: context)
                await sync.syncPending(context: context)
            }
            .toolbar {
                ToolbarItem(placement: .principal) { SideleafWordmark() }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(sync.accountActionLabel, systemImage: accountSymbol) {
                        router.openAccount()
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityHint(sync.accountActionHint)
                    Button("New page", systemImage: "plus") {
                        let page = sync.newPage(titled: "Untitled page", context: context)
                        sync.pageDidChange(page, context: context)
                        selected = page.id
                        preferredCompactColumn = .detail
                    }
                    .labelStyle(.iconOnly)
                }
            }
        } detail: {
            if let page = visiblePages.first(where: { $0.id == selected }) {
                NativeNotebookPage(page: page)
                    .id(page.id)
            }
            else { SideleafEmptyPage() }
        }
        .tint(.sideleafOlive)
        .onChange(of: selected) { _, pageID in
            if pageID != nil { preferredCompactColumn = .detail }
        }
        .onChange(of: router.selectedPageID, initial: true) { _, pageID in
            guard let pageID else { return }
            selected = pageID
            preferredCompactColumn = .detail
            router.selectedPageID = nil
        }
        .onChange(of: sync.identity?.id) {
            if let selected, !visiblePages.contains(where: { $0.id == selected }) {
                self.selected = nil
                preferredCompactColumn = .sidebar
            }
        }
    }

    private var visiblePages: [LocalPage] {
        sync.visiblePages(from: pages).filter { page in
            search.isEmpty
                || page.title.localizedCaseInsensitiveContains(search)
                || page.text.localizedCaseInsensitiveContains(search)
                || (page.localTranscript?.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    private var accountPages: [LocalPage] {
        guard let userID = sync.identity?.id else { return [] }
        return visiblePages.filter { $0.ownerUserID == userID }
    }

    private var guestPages: [LocalPage] {
        visiblePages.filter { $0.ownerUserID == nil }
    }

    private var accountPagesSectionTitle: String {
        if sync.isVerifyingRestoredSession { return "Account pages · Verifying" }
        if sync.requiresTermsAcceptance { return "Account pages · Review terms" }
        return sync.isOffline ? "Account pages · Offline" : "Synced pages"
    }

    private var accountSymbol: String {
        if sync.isVerifyingRestoredSession { return "person.crop.circle.badge.clock" }
        if sync.requiresTermsAcceptance { return "person.crop.circle.badge.exclamationmark" }
        if sync.isOffline { return "icloud.slash" }
        return sync.isConnected ? "person.crop.circle.badge.checkmark" : "person.crop.circle"
    }

    @ViewBuilder
    private func pageRows(_ rows: [LocalPage]) -> some View {
        if rows.isEmpty {
            Text(search.isEmpty ? "No pages yet" : "No matching pages")
                .foregroundStyle(.secondary)
        } else {
            ForEach(rows) { page in
                NavigationLink(value: page.id) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(page.title, systemImage: "doc.text")
                        Text(sync.status(for: page).message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

enum NotebookTool: String, CaseIterable { case type = "Type", write = "Write", mark = "Mark", select = "Select", erase = "Erase" }

struct NativeNotebookPage: View {
    @Bindable var page: LocalPage
    @Environment(\.modelContext) private var context
    @Environment(NotebookSync.self) private var sync
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(SideleafRouter.self) private var router
    @Environment(MeetingSession.self) private var session
    @State private var tool: NotebookTool = .type
    @State private var undoSignal = 0
    @State private var redoSignal = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TextField("Page title", text: titleBinding)
                    .font(.largeTitle)
                    .fontDesign(.serif)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { pageStatusContent }
                    VStack(alignment: .leading, spacing: 8) { pageStatusContent }
                }
                .font(.caption)
                .foregroundStyle(statusColor)
                if page.conflictDocumentData != nil { conflictActions }
                if !prefersCompactControls {
                    ViewThatFits(in: .horizontal) {
                        regularEditorControls
                        compactEditorControls
                    }
                }
                Text(toolHelp).font(.caption).foregroundStyle(.secondary)
                if let transcript = page.localTranscript, !transcript.isEmpty {
                    GroupBox("On-device transcript") {
                        Text(transcript)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                NativePaper(page: page, tool: tool, undoSignal: undoSignal, redoSignal: redoSignal) {
                    change in
                    if change == .ink {
                        page.updatedAt = Date()
                        do { try context.save() }
                        catch { page.syncError = "Could not save on this device. Keep Sideleaf open." }
                    } else {
                        sync.pageDidChange(page, context: context)
                    }
                }
                .frame(minHeight: 1200)
                annotationSection(
                    "Follow-ups and next steps",
                    page.annotations.filter { $0.kind != "important" }
                )
                annotationSection(
                    "Important",
                    page.annotations.filter { $0.kind == "important" }
                )
            }
            .padding(horizontalSizeClass == .compact ? 16 : 30)
            .background(Color(red: 1, green: 0.99, blue: 0.97))
        }
        .safeAreaInset(edge: .bottom) {
            if prefersCompactControls { compactEditorControls }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(meetingToolbarLabel, systemImage: meetingToolbarSymbol) {
                    if session.isActive || session.hasRecap {
                        router.tab = .meeting
                    } else if sync.canUseLiveTranscription {
                        router.planMeeting(on: page.id)
                    } else {
                        router.openAccount()
                    }
                }
                .tint(session.isActive ? .red : (sync.canUseLiveTranscription ? .sideleafOlive : .secondary))
                .labelStyle(.iconOnly)
                .accessibilityHint(meetingToolbarHint)
                Button(sync.accountActionLabel, systemImage: "person.crop.circle") {
                    router.openAccount()
                }
                .labelStyle(.iconOnly)
                .accessibilityHint(sync.accountActionHint)
            }
        }
    }

    /// Marks saved from a meeting keep the shared contract's kinds, so the page
    /// shows follow-ups and next steps separately from plain highlights.
    @ViewBuilder
    private func annotationSection(_ title: String, _ marks: [NativeAnnotation]) -> some View {
        if !marks.isEmpty {
            Text(title).font(.title2).fontDesign(.serif)
            ForEach(marks) { mark in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: mark.kind == "action" ? "checkmark.circle" : (mark.kind == "important" ? "star" : "questionmark.bubble"))
                        .foregroundStyle(.sideleafOlive)
                    VStack(alignment: .leading, spacing: 3) {
                        if !mark.question.isEmpty {
                            Text(mark.question)
                        }
                        Text(mark.anchor.quote)
                            .font(mark.question.isEmpty ? .body : .caption)
                            .foregroundStyle(mark.question.isEmpty ? .primary : .secondary)
                        if mark.state == "addressed" {
                            Text("Asked during the meeting.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if !mark.anchor.resolved {
                            Text("Source changed. Original quote preserved.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    Button("Remove mark", systemImage: "trash") {
                        page.annotations.removeAll { $0.id == mark.id }
                        sync.pageDidChange(page, context: context)
                    }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
    }

    @ViewBuilder
    private var pageStatusContent: some View {
        Label(sync.status(for: page).message, systemImage: statusSymbol)
            .fixedSize(horizontal: false, vertical: true)
        if canRestoreCloudCopy {
            Button("Restore to cloud") {
                Task { await sync.restoreDeviceCopyToCloud(page, context: context) }
            }
            .frame(minHeight: 44)
        } else if canRetrySync {
            Button("Retry") { Task { await sync.syncNow(page, context: context) } }
                .frame(minHeight: 44)
        }
    }

    private var prefersCompactControls: Bool {
        horizontalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
    }

    private var meetingToolbarLabel: String {
        if session.isActive { return "Meeting in progress, microphone active" }
        if session.hasRecap { return "Review the meeting recap" }
        if !sync.canUseLiveTranscription { return "Review terms to start a meeting" }
        return "Start a meeting on this page"
    }

    private var meetingToolbarSymbol: String {
        if session.isActive { return "waveform" }
        if session.hasRecap { return "text.badge.checkmark" }
        return sync.canUseLiveTranscription ? "waveform.badge.plus" : "mic.slash"
    }

    private var meetingToolbarHint: String {
        if session.isActive || session.hasRecap { return "Returns to the live meeting." }
        if !sync.canUseLiveTranscription {
            return "Opens account settings for the required Terms review."
        }
        return "Sideleaf listens on this device and saves its recap into this page."
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { page.title },
            set: {
                page.title = $0
                sync.pageDidChange(page, context: context)
            }
        )
    }

    private var canRetrySync: Bool {
        page.ownerUserID == sync.identity?.id
            && page.conflictDocumentData == nil
            && (page.pendingMutationID != nil || page.syncError != nil)
    }

    private var canRestoreCloudCopy: Bool {
        page.ownerUserID == sync.identity?.id
            && page.serverVersion == nil
            && page.notebookID == nil
            && page.pendingMutationID == nil
            && page.syncError != nil
    }

    private var statusSymbol: String {
        switch sync.status(for: page) {
        case .deviceOnly, .differentAccount: "iphone"
        case .waiting: "clock"
        case .syncing: "arrow.triangle.2.circlepath"
        case .synced: "checkmark.icloud"
        case .textSyncedInkLocal: "pencil.and.outline"
        case .offline: "icloud.slash"
        case .conflict: "exclamationmark.triangle"
        case .failed: "icloud.slash"
        }
    }

    private var statusColor: Color {
        switch sync.status(for: page) {
        case .conflict, .failed, .offline: .orange
        default: .secondary
        }
    }

    private var conflictActions: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("This page changed on another device. Both versions are still preserved.")
                    .font(.callout)
                ViewThatFits(in: .horizontal) {
                    HStack { conflictButtons }
                    VStack(alignment: .leading, spacing: 10) { conflictButtons }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Sync conflict", systemImage: "exclamationmark.triangle.fill")
        }
        .tint(.orange)
    }

    @ViewBuilder
    private var conflictButtons: some View {
        Button("Keep both") {
            _ = sync.resolveConflictKeepingBoth(page, context: context)
        }
        .buttonStyle(.borderedProminent)
        Button("Use cloud") {
            _ = sync.resolveConflictUsingCloud(page, context: context)
        }
        .buttonStyle(.bordered)
        Menu("More") {
            Button("Keep this device version") {
                sync.resolveConflictKeepingLocal(page, context: context)
            }
        }
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
                    .tint(tool == item ? .sideleafOlive : .secondary)
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

private enum NativeAccountMode: String, CaseIterable, Identifiable {
    case signIn = "Sign in"
    case create = "Create account"
    var id: Self { self }
}

private struct NativeAccountSheet: View {
    @Query(sort: \LocalPage.updatedAt, order: .reverse) private var pages: [LocalPage]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(NotebookSync.self) private var sync
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var mode = NativeAccountMode.signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var acceptedTerms = false
    @State private var recordingLawAcknowledged = false
    @State private var working = false
    @State private var confirmAdoption = false
    @State private var confirmAccountDeletion = false

    var body: some View {
        NavigationStack {
            Form {
                switch sync.account {
                case .restoring:
                    Section { ProgressView("Restoring your account…") }
                case .signedOut:
                    signedOutContent
                case .termsRequired(let identity, let offline):
                    termsRequiredContent(identity, offline: offline)
                case .signedIn(let identity):
                    signedInContent(identity, offline: false)
                case .signedInOffline(let identity):
                    signedInContent(identity, offline: true)
                }
                if sync.hasPendingDeletedAccountPageCleanup {
                    deletedAccountPageCleanupSection
                }
                if let error = sync.accountError ?? sync.syncError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Account & Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(working)
                }
            }
            .confirmationDialog(
                "Add device pages to this account?",
                isPresented: $confirmAdoption,
                titleVisibility: .visible
            ) {
                Button("Add \(guestPages.count) page\(guestPages.count == 1 ? "" : "s")") {
                    run { await sync.adoptGuestPages(guestPages, context: context) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Sideleaf will upload their typed notes, marks, and on-device transcript text. PencilKit ink remains only on this device.")
            }
            .confirmationDialog(
                "Permanently delete this Sideleaf account?",
                isPresented: $confirmAccountDeletion,
                titleVisibility: .visible
            ) {
                Button("Delete account and cached pages", role: .destructive) {
                    run(clearPassword: false) {
                        let success = await sync.deleteAccount(context: context)
                        if success, sync.accountError == nil { dismiss() }
                        return success
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes the account and its cloud data, then removes this account's cached pages from this device. Unrelated device-only drafts remain. If you began an existing subscription on the Sideleaf website, manage it there before retrying. For security, the server may ask you to sign out and sign in again before retrying.")
            }
            .onChange(of: mode) {
                acceptedTerms = false
                recordingLawAcknowledged = false
            }
            .onChange(of: sync.legalMetadata?.termsVersion) {
                acceptedTerms = false
                recordingLawAcknowledged = false
            }
        }
        .interactiveDismissDisabled(working)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
    }

    @ViewBuilder
    private var signedOutContent: some View {
        Section {
            accountModePicker
            if mode == .create {
                TextField("Name", text: $name)
                    .textContentType(.name)
            }
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
            SecureField("Password", text: $password)
                .textContentType(mode == .create ? .newPassword : .password)
        }
        if mode == .create {
            Section {
                legalAcknowledgementRows
            } header: {
                Text("Required acknowledgements")
            } footer: {
                Text("These acknowledgements apply to your Sideleaf account. Sideleaf does not replace any notice or permission required for a particular conversation.")
            }
        }
        Section {
            Button(working ? "Please wait…" : mode.rawValue) {
                run {
                    if mode == .signIn {
                        return await sync.signIn(email: email, password: password, context: context)
                    }
                    return await sync.createAccount(
                        name: name,
                        email: email,
                        password: password,
                        acceptedTerms: acceptedTerms,
                        recordingLawAcknowledged: recordingLawAcknowledged,
                        context: context
                    )
                }
            }
            .disabled(
                !credentialsAreValid
                    || (mode == .create && !legalAcknowledgementsAreComplete)
                    || working
                    || sync.configuration?.passwordAuth == false
            )
        } footer: {
            Text("Your session is kept in this device's Keychain. Sideleaf server credentials are never stored in the app.")
        }
        if sync.configuration?.passwordAuth == false {
            Section { Text("Email and password sign-in is unavailable on the server right now.") }
        }
    }

    @ViewBuilder
    private var accountModePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker("Account action", selection: $mode) {
                ForEach(NativeAccountMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
        } else {
            Picker("Account action", selection: $mode) {
                ForEach(NativeAccountMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private func termsRequiredContent(_ identity: CloudIdentity, offline: Bool) -> some View {
        Section {
            LabeledContent("Name", value: identity.name)
            LabeledContent("Email", value: identity.email)
            Text("Review and accept the current Terms of Service before Sideleaf syncs or starts live transcription. Your existing device notes remain available.")
                .foregroundStyle(.secondary)
        } header: {
            Text("Terms review required")
        } footer: {
            if offline {
                Text("Connect to Sideleaf to record your acceptance. You can continue reading and editing device copies while offline.")
            }
        }

        Section {
            legalAcknowledgementRows
            Button(working ? "Recording acceptance…" : "Accept and continue") {
                run {
                    await sync.acceptTerms(
                        acceptedTerms: acceptedTerms,
                        recordingLawAcknowledged: recordingLawAcknowledged,
                        context: context
                    )
                }
            }
            .disabled(!legalAcknowledgementsAreComplete || working)
        } header: {
            Text("Required acknowledgements")
        } footer: {
            Text("Sideleaf records the Terms version and acceptance time. You remain responsible for each conversation you transcribe.")
        }

        Section {
            Button("Sign out", role: .destructive) {
                run {
                    let success = await sync.signOut()
                    if success { dismiss() }
                    return success
                }
            }
            .disabled(working)
        } footer: {
            Text("Signed-out pages stay on this device and reappear when this account signs in again.")
        }
        accountDeletionSection
    }

    @ViewBuilder
    private var legalAcknowledgementRows: some View {
        if let version = sync.legalMetadata?.termsVersion {
            Toggle("I agree to the Terms of Service", isOn: $acceptedTerms)
            Link("View Terms of Service", destination: sync.termsURL)
            Link("View Privacy Notice", destination: sync.privacyURL)
            Toggle(isOn: $recordingLawAcknowledged) {
                Text(sync.recordingLawAcknowledgement)
            }
            LabeledContent("Terms version", value: version)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let effectiveDate = sync.legalEffectiveDateText {
                LabeledContent("Effective", value: effectiveDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Link("View Terms of Service", destination: sync.termsURL)
            Link("View Privacy Notice", destination: sync.privacyURL)
            Label(
                "Connect to load the current Terms version and acknowledgements.",
                systemImage: "wifi.exclamationmark"
            )
            .foregroundStyle(.secondary)
            Button(working ? "Loading current terms…" : "Load current terms") {
                run(clearPassword: false) { await sync.loadLegalMetadata() }
            }
            .disabled(working)
        }
    }

    @ViewBuilder
    private func signedInContent(_ identity: CloudIdentity, offline: Bool) -> some View {
        Section {
            LabeledContent("Name", value: identity.name)
            LabeledContent("Email", value: identity.email)
            Button(
                sync.isRefreshing || sync.isSyncing
                    ? "Syncing…"
                    : (offline ? "Try reconnecting" : "Refresh and sync")
            ) {
                run {
                    await sync.refresh(context: context)
                    await sync.syncPending(context: context)
                    return true
                }
            }
            .disabled(working || sync.isRefreshing || sync.isSyncing)
        } header: {
            Text(offline ? "Offline account" : "Connected account")
        } footer: {
            if offline {
                Text("Showing this account's device copies. Changes remain local until Sideleaf reconnects.")
            }
        }
        if !guestPages.isEmpty {
            Section {
                Text("\(guestPages.count) page\(guestPages.count == 1 ? " is" : "s are") saved only on this device.")
                Button("Add to this account") { confirmAdoption = true }
                    .disabled(working)
            } header: {
                Text("Device-only pages")
            } footer: {
                Text("Nothing is uploaded until you confirm. Freehand PencilKit ink stays on this device.")
            }
        }
        Section {
            Button("Sign out", role: .destructive) {
                run {
                    let success = await sync.signOut()
                    if success { dismiss() }
                    return success
                }
            }
            .disabled(working)
        } footer: {
            Text("Signed-out pages stay on this device and reappear when this account signs in again.")
        }
        accountDeletionSection
    }

    private var accountDeletionSection: some View {
        Section {
            Button("Delete account…", role: .destructive) {
                confirmAccountDeletion = true
            }
            .disabled(working)
        } header: {
            Text("Delete account")
        } footer: {
            Text("Deletion is permanent. It removes cloud data and this account's cached pages, but keeps unrelated device-only drafts. Manage any existing web subscription on the Sideleaf website before retrying deletion.")
        }
    }

    private var deletedAccountPageCleanupSection: some View {
        Section {
            Button(working ? "Removing cached pages…" : "Retry cached-page removal") {
                run(clearPassword: false) {
                    let success = sync.retryDeletedAccountPageCleanup(context: context)
                    if success, sync.accountError == nil { dismiss() }
                    return success
                }
            }
            .disabled(working)
        } header: {
            Text("Finish device cleanup")
        } footer: {
            Text("This retry only removes cached pages belonging to the account the server already deleted. It does not send another account-deletion request.")
        }
    }

    private var guestPages: [LocalPage] { sync.guestPages(from: pages) }

    private var legalAcknowledgementsAreComplete: Bool {
        sync.legalMetadata != nil && acceptedTerms && recordingLawAcknowledged
    }

    private var credentialsAreValid: Bool {
        let hasEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).contains("@")
        switch mode {
        case .signIn:
            return hasEmail && !password.isEmpty
        case .create:
            return hasEmail && password.count >= 10
                && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func run(
        clearPassword: Bool = true,
        _ operation: @escaping @MainActor () async -> Bool
    ) {
        guard !working else { return }
        working = true
        Task { @MainActor in
            _ = await operation()
            if clearPassword { password = "" }
            working = false
        }
    }
}

extension NotebookSync {
    var accountActionLabel: String {
        if isVerifyingRestoredSession { return "Account and sync, verifying session" }
        switch account {
        case .restoring:
            return "Account and sync, restoring"
        case .signedOut:
            return "Sign in or create an account"
        case .termsRequired(_, offline: true):
            return "Account and sync, Terms review required while offline"
        case .termsRequired:
            return "Account and sync, Terms review required"
        case .signedIn:
            return "Account and sync, connected"
        case .signedInOffline:
            return "Account and sync, offline"
        }
    }

    var accountActionHint: String {
        requiresTermsAcceptance
            ? "Opens the required Terms review."
            : "Opens account and synchronization settings."
    }
}
