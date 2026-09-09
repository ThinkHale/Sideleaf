import SwiftUI
import SwiftData
import UIKit

@main
struct SideleafApp: App {
    @State private var sync = NotebookSync()

    var body: some Scene {
        WindowGroup { NotebookLibrary().environment(sync) }
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

    init(id: UUID = UUID(), title: String = "Untitled page") {
        self.id = id; self.title = title; text = ""; textRevision = 1
        ink = Data(); annotationData = Data(); updatedAt = Date()
        ownerUserID = nil; notebookID = nil; serverVersion = nil
        pendingMutationID = nil; lastSyncedAt = nil; syncError = nil
        cloudDocumentData = nil; cloudBlockID = nil; conflictDocumentData = nil
        recoveryDocumentData = nil
        transcriptBlockID = nil; localTranscript = nil
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
    @State private var selected: UUID?
    @State private var search = ""
    @State private var preferredCompactColumn = NavigationSplitViewColumn.sidebar
    @State private var showAccount = false

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
                        showAccount = true
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityHint(sync.accountActionHint)
                    Button("New page", systemImage: "plus") {
                        let page = LocalPage()
                        if let identity = sync.identity {
                            page.ownerUserID = identity.id
                            page.cloudBlockID = page.id
                            page.pendingMutationID = UUID()
                        }
                        context.insert(page)
                        sync.pageDidChange(page, context: context)
                        selected = page.id
                        preferredCompactColumn = .detail
                    }
                    .labelStyle(.iconOnly)
                }
            }
        } detail: {
            if let page = visiblePages.first(where: { $0.id == selected }) {
                NativeNotebookPage(page: page) { showAccount = true }
                    .id(page.id)
            }
            else { SideleafEmptyPage() }
        }
        .tint(Color(red: 0.41, green: 0.45, blue: 0.33))
        .task { await sync.restore(context: context) }
        .sheet(isPresented: $showAccount) {
            NativeAccountSheet(pages: pages)
        }
        .onChange(of: selected) { _, pageID in
            if pageID != nil { preferredCompactColumn = .detail }
        }
        .onChange(of: sync.identity?.id) {
            if let selected, !visiblePages.contains(where: { $0.id == selected }) {
                self.selected = nil
                preferredCompactColumn = .sidebar
            }
        }
        .onChange(of: sync.shouldPresentTermsAcceptance) { _, required in
            if required { showAccount = true }
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
    @State private var tool: NotebookTool = .type
    @State private var transcription = LiveTranscription()
    @State private var showTranscription = false
    @State private var undoSignal = 0
    @State private var redoSignal = 0
    let openAccount: () -> Void

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
                                sync.pageDidChange(page, context: context)
                            }
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                        }
                    }
                }
            }
            .padding(horizontalSizeClass == .compact ? 16 : 30)
            .background(Color(red: 1, green: 0.99, blue: 0.97))
        }
        .safeAreaInset(edge: .bottom) {
            if prefersCompactControls { compactEditorControls }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(
                    transcriptionToolbarLabel,
                    systemImage: transcription.isListening
                        ? "mic.fill"
                        : (sync.canUseLiveTranscription ? "mic" : "mic.slash")
                ) {
                    if sync.canUseLiveTranscription {
                        showTranscription = true
                    } else {
                        openAccount()
                    }
                }
                .tint(
                    transcription.isListening
                        ? .red
                        : (sync.canUseLiveTranscription ? .olive : .secondary)
                )
                .labelStyle(.iconOnly)
                .accessibilityHint(transcriptionToolbarHint)
                Button(sync.accountActionLabel, systemImage: "person.crop.circle") { openAccount() }
                .labelStyle(.iconOnly)
                .accessibilityHint(sync.accountActionHint)
            }
        }
        .sheet(isPresented: $showTranscription) {
            LiveTranscriptionSheet(page: page, transcription: transcription)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            Task { await transcription.stop() }
        }
        .onDisappear {
            Task { await transcription.stop() }
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

    private var transcriptionToolbarLabel: String {
        if !sync.canUseLiveTranscription {
            return "Review terms to use live transcription"
        }
        switch transcription.state {
        case .preparing, .downloadingAssets, .requestingPermission, .finalizing:
            return "Live transcription: \(transcription.status)"
        case .listening:
            return "Live transcription, microphone active"
        case .interrupted, .unavailable, .failed:
            return "Live transcription: \(transcription.status)"
        case .idle, .stopped:
            return "Live transcription"
        }
    }

    private var transcriptionToolbarHint: String {
        if !sync.canUseLiveTranscription {
            return "Opens account settings for the required Terms review."
        }
        if transcription.isListening {
            return "Opens transcription controls. The microphone is active."
        }
        return "Opens on-device live transcription."
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

private enum NativeAccountMode: String, CaseIterable, Identifiable {
    case signIn = "Sign in"
    case create = "Create account"
    var id: Self { self }
}

private struct NativeAccountSheet: View {
    let pages: [LocalPage]
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

private struct LiveTranscriptionSheet: View {
    private struct AppendIssue: Identifiable {
        let id = UUID()
        let message: String
        let transcript: String
    }

    @Bindable var page: LocalPage
    @Bindable var transcription: LiveTranscription
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(NotebookSync.self) private var sync
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var confirmDiscard = false
    @State private var appendIssue: AppendIssue?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("On-device live transcription", systemImage: "waveform")
                        .font(.title2)
                        .fontDesign(.serif)
                    Text("Sideleaf uses this device's microphone and Apple's on-device speech model. Audio is held briefly in memory, never saved as a recording, and never uploaded. Choose Add to page to save transcript text with the page and sync it as personal notes.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("You are responsible for following applicable recording and interception laws, informing participants, and obtaining any permission required for this conversation.")
                                .font(.callout)
                            Link("View Terms of Service", destination: sync.termsURL)
                                .font(.callout.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("Recording responsibility", systemImage: "person.2.badge.gearshape")
                    }
                    if let errorMessage = transcription.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Live transcription error")
                            .accessibilityValue(errorMessage)
                    } else {
                        Label(
                            transcription.status,
                            systemImage: transcription.isListening ? "mic.fill" : "info.circle"
                        )
                        .foregroundStyle(transcription.isListening ? .red : .secondary)
                        .accessibilityLabel("Live transcription status")
                        .accessibilityValue(transcription.status)
                    }
                    if transcription.isBusy && !transcription.isListening {
                        if let progress = transcription.assetDownloadProgress {
                            ProgressView(progress)
                                .accessibilityLabel("Downloading on-device language assets")
                        } else {
                            ProgressView("Preparing live transcription")
                                .accessibilityValue(transcription.status)
                        }
                    }
                    GroupBox("Live text") {
                        Text(transcription.transcript.isEmpty ? "Your transcript will appear here." : transcription.transcript)
                            .foregroundStyle(transcription.transcript.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                            .textSelection(.enabled)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { transcriptionActions }
                        VStack(alignment: .leading, spacing: 12) { transcriptionActions }
                    }
                    if transcription.shouldOfferMicrophoneSettings {
                        Link("Open Sideleaf Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding()
            }
            .navigationTitle("Live Transcription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task { await requestDismissal() }
                    }
                }
            }
        }
        .confirmationDialog(
            "Save this transcript?",
            isPresented: $confirmDiscard,
            titleVisibility: .visible
        ) {
            Button("Add to page") { addTranscriptToPage() }
            Button("Discard transcript", role: .destructive) {
                transcription.resetTranscript()
                dismiss()
            }
            Button("Keep it here", role: .cancel) {}
        } message: {
            Text("Add the live text to this page or explicitly discard it before closing.")
        }
        .alert(item: $appendIssue) { issue in
            Alert(
                title: Text("Transcript was not added"),
                message: Text(issue.message),
                primaryButton: .default(Text("Copy live text")) {
                    UIPasteboard.general.string = issue.transcript
                },
                secondaryButton: .cancel(Text("Keep it here"))
            )
        }
        .interactiveDismissDisabled(
            transcription.isListening
                || transcription.state == .finalizing
                || hasUncommittedTranscript
        )
        .onChange(of: sync.canUseLiveTranscription) { _, permitted in
            if !permitted { Task { await transcription.stop() } }
        }
        .onChange(of: transcription.status) { oldStatus, newStatus in
            guard oldStatus != newStatus else { return }
            AccessibilityNotification.Announcement(newStatus).post()
        }
        .onDisappear { Task { await transcription.stop() } }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
    }

    @ViewBuilder
    private var transcriptionActions: some View {
        if transcription.isListening {
            Button("Stop", systemImage: "stop.fill") {
                Task { await transcription.stop() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        } else {
            Button("Start", systemImage: "mic.fill") {
                Task {
                    await transcription.start(
                        clearTranscript: transcription.transcript.isEmpty
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!sync.canUseLiveTranscription || transcription.isBusy)
        }
        if !transcription.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !transcription.isBusy
        {
            Button("Add to page", systemImage: "text.badge.plus") {
                addTranscriptToPage()
            }
            .buttonStyle(.bordered)
        }
    }

    private var hasUncommittedTranscript: Bool {
        !transcription.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func requestDismissal() async {
        await transcription.stop()
        if hasUncommittedTranscript {
            confirmDiscard = true
        } else {
            dismiss()
        }
    }

    private func addTranscriptToPage() {
        let value = transcription.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if let message = sync.appendTranscript(value, to: page, context: context) {
            appendIssue = AppendIssue(message: message, transcript: value)
            return
        }
        transcription.resetTranscript()
        dismiss()
    }
}

private extension NotebookSync {
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

private extension Color { static let olive = Color(red: 0.41, green: 0.45, blue: 0.33) }
