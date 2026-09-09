import Foundation
import Observation
import SwiftData

enum NativeAccountState: Equatable, Sendable {
    case restoring
    case signedOut
    case signedIn(CloudIdentity)
    case signedInOffline(CloudIdentity)
}

enum NotebookPageSyncStatus: Equatable, Sendable {
    case deviceOnly
    case differentAccount
    case waiting
    case syncing
    case synced(Date?)
    case textSyncedInkLocal(Date?)
    case offline(Date?)
    case conflict
    case failed(String)

    var message: String {
        switch self {
        case .deviceOnly:
            "Saved on this device"
        case .differentAccount:
            "Saved for another account on this device"
        case .waiting:
            "Saved on this device · Waiting to sync"
        case .syncing:
            "Saved on this device · Syncing…"
        case .synced:
            "Synced"
        case .textSyncedInkLocal:
            "Text synced · Ink stays on this device"
        case .offline:
            "Saved on this device · Offline"
        case .conflict:
            "Review cloud conflict"
        case .failed(let message):
            message
        }
    }
}

@MainActor @Observable
final class NotebookSync {
    private struct DefaultNotebookRequest {
        let id: UUID
        let ownerID: String
        let task: Task<CloudNotebook, Error>
    }

    private(set) var account: NativeAccountState = .restoring
    private(set) var notebooks: [CloudNotebook] = []
    private(set) var configuration: CloudConfiguration?
    private(set) var isRefreshing = false
    private(set) var syncingPageIDs: Set<UUID> = []
    private(set) var accountError: String?
    private(set) var syncError: String?

    @ObservationIgnored private let api: any NativeAPIProviding
    @ObservationIgnored private var debounceTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var notebooksOwnerID: String?
    @ObservationIgnored private var defaultNotebookRequest: DefaultNotebookRequest?
    @ObservationIgnored private var accountOperationGeneration = 0
    @ObservationIgnored private var refreshRequestID: UUID?
    @ObservationIgnored private var refreshingOwnerID: String?
    @ObservationIgnored private var configurationTask: Task<Void, Never>?

    init(api: any NativeAPIProviding = NativeAPI()) {
        self.api = api
    }

    var identity: CloudIdentity? {
        switch account {
        case .signedIn(let identity), .signedInOffline(let identity): identity
        case .restoring, .signedOut: nil
        }
    }

    var isConnected: Bool {
        guard case .signedIn = account else { return false }
        return true
    }
    var hasAccount: Bool { identity != nil }
    var isOffline: Bool {
        guard case .signedInOffline = account else { return false }
        return true
    }
    var isSyncing: Bool { !syncingPageIDs.isEmpty }

    func restore(context: ModelContext) async {
        let operation = beginAccountOperation()
        account = .restoring
        accountError = nil
        let cachedIdentity: CloudIdentity?
        do { cachedIdentity = try await api.cachedIdentity() }
        catch NativeAPIError.staleOperation { return }
        catch { cachedIdentity = nil }
        guard operation == accountOperationGeneration else { return }

        if let cachedIdentity {
            // Keychain identity is enough to reveal this account's device copies.
            // Keep the state honestly offline until an authenticated request succeeds.
            activate(cachedIdentity, offline: true)
        }
        requestConfiguration(for: operation)

        do {
            let restored = try await api.restoreSession()
            guard operation == accountOperationGeneration else { return }
            guard let restored else {
                account = .signedOut
                notebooks = []
                notebooksOwnerID = nil
                return
            }
            activate(restored, offline: false)
            await refresh(context: context)
        } catch NativeAPIError.staleOperation {
            return
        } catch {
            guard operation == accountOperationGeneration else { return }
            if isRecoverableNetworkError(error), let cachedIdentity {
                activate(cachedIdentity, offline: true)
                accountError = "Sideleaf is offline. Showing this account's device copies; changes will wait to sync."
            } else {
                account = .signedOut
                notebooks = []
                notebooksOwnerID = nil
                accountError = message(for: error)
            }
        }
    }

    func signIn(email: String, password: String, context: ModelContext) async -> Bool {
        let operation = beginAccountOperation()
        accountError = nil
        do {
            let identity = try await api.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            guard operation == accountOperationGeneration else { return false }
            activate(identity, offline: false)
            await refresh(context: context)
            return true
        } catch NativeAPIError.staleOperation {
            return false
        } catch {
            guard operation == accountOperationGeneration else { return false }
            accountError = message(for: error)
            return false
        }
    }

    func createAccount(
        name: String,
        email: String,
        password: String,
        context: ModelContext
    ) async -> Bool {
        let operation = beginAccountOperation()
        accountError = nil
        do {
            let identity = try await api.createAccount(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            guard operation == accountOperationGeneration else { return false }
            activate(identity, offline: false)
            await refresh(context: context)
            return true
        } catch NativeAPIError.staleOperation {
            return false
        } catch {
            guard operation == accountOperationGeneration else { return false }
            accountError = message(for: error)
            return false
        }
    }

    /// Sign-out never deletes SwiftData. Account-owned pages become hidden until
    /// that same account signs in again; unowned device drafts remain visible.
    func signOut() async -> Bool {
        let operation = beginAccountOperation()
        accountError = nil
        do {
            try await api.signOut()
            guard operation == accountOperationGeneration else { return false }
            completeLocalSignOut()
            return true
        } catch NativeAPIError.sessionExpired {
            guard operation == accountOperationGeneration else { return false }
            completeLocalSignOut()
            return true
        } catch NativeAPIError.staleOperation {
            return false
        } catch {
            guard operation == accountOperationGeneration else { return false }
            accountError = message(for: error)
            return false
        }
    }

    /// Guest pages stay local until the user explicitly chooses this operation.
    func adoptGuestPages(_ pages: [LocalPage], context: ModelContext) async -> Bool {
        guard let identity else {
            accountError = NativeAPIError.notAuthenticated.localizedDescription
            return false
        }
        let guests = pages.filter { $0.ownerUserID == nil }
        guard !guests.isEmpty else { return true }
        do {
            let notebook = try await defaultNotebook(for: identity.id)
            guard self.identity?.id == identity.id else { throw CancellationError() }
            for page in guests {
                page.ownerUserID = identity.id
                page.notebookID = notebook.id
                page.serverVersion = 0
                page.cloudBlockID = page.cloudBlockID ?? page.id
                page.pendingMutationID = UUID()
                page.conflictDocumentData = nil
                page.syncError = nil
            }
            try context.save()
            await syncPending(context: context)
            return true
        } catch {
            guard self.identity?.id == identity.id else { return false }
            if case NativeAPIError.staleOperation = error { return false }
            syncError = message(for: error)
            return false
        }
    }

    /// Re-creates an account-scoped device copy whose cloud page was deleted.
    /// This is always explicit so a remote deletion is never silently reversed.
    func restoreDeviceCopyToCloud(_ page: LocalPage, context: ModelContext) async -> Bool {
        guard let identity,
              page.ownerUserID == identity.id,
              page.serverVersion == nil,
              page.notebookID == nil,
              page.pendingMutationID == nil
        else { return false }

        do {
            let notebook = try await defaultNotebook(for: identity.id)
            guard self.identity?.id == identity.id else { throw CancellationError() }
            page.notebookID = notebook.id
            page.serverVersion = 0
            page.cloudDocumentData = nil
            page.cloudBlockID = page.id
            page.conflictDocumentData = nil
            page.transcriptBlockID = page.localTranscript == nil ? nil : UUID()
            page.pendingMutationID = UUID()
            page.syncError = nil
            try context.save()
            await syncNow(page, context: context)
            return page.pendingMutationID == nil
                && page.conflictDocumentData == nil
                && page.syncError == nil
        } catch {
            guard self.identity?.id == identity.id else { return false }
            if case NativeAPIError.staleOperation = error { return false }
            page.syncError = message(for: error)
            try? context.save()
            return false
        }
    }

    /// Returns only guest drafts plus pages belonging to the current account.
    /// Cached pages for other accounts remain on disk but never appear here.
    func visiblePages(from pages: [LocalPage]) -> [LocalPage] {
        guard let identity else { return pages.filter { $0.ownerUserID == nil } }
        return pages.filter { $0.ownerUserID == nil || $0.ownerUserID == identity.id }
    }

    func guestPages(from pages: [LocalPage]) -> [LocalPage] {
        pages.filter { $0.ownerUserID == nil }
    }

    func status(for page: LocalPage) -> NotebookPageSyncStatus {
        if let owner = page.ownerUserID, owner != identity?.id { return .differentAccount }
        if page.conflictDocumentData != nil { return .conflict }
        if let error = page.syncError { return .failed(error) }
        if syncingPageIDs.contains(page.id) { return .syncing }
        if page.pendingMutationID != nil { return .waiting }
        guard page.ownerUserID != nil, page.serverVersion ?? 0 > 0 else { return .deviceOnly }
        if isOffline { return .offline(page.lastSyncedAt) }
        if !page.ink.isEmpty {
            return .textSyncedInkLocal(page.lastSyncedAt)
        }
        return .synced(page.lastSyncedAt)
    }

    /// Call after the local SwiftData edit. It persists first, marks only an
    /// account-owned page dirty, then debounces its network save.
    @discardableResult
    func pageDidChange(_ page: LocalPage, context: ModelContext) -> Bool {
        page.updatedAt = Date()
        let requiresExplicitCloudRestore = page.ownerUserID == identity?.id
            && page.serverVersion == nil
            && page.notebookID == nil
            && page.pendingMutationID == nil
            && page.syncError != nil
        if let identity,
           page.ownerUserID == identity.id,
           !requiresExplicitCloudRestore
        {
            page.pendingMutationID = UUID()
            page.syncError = nil
        }
        do {
            try context.save()
        } catch {
            page.syncError = "Could not save on this device. Keep Sideleaf open."
            syncError = page.syncError
            return false
        }
        guard page.pendingMutationID != nil else { return true }
        schedule(page, context: context)
        return true
    }

    /// Appends live text only when the resulting personal transcript block can
    /// still be synchronized. A refusal leaves both the page and live text intact.
    func appendTranscript(
        _ rawTranscript: String,
        to page: LocalPage,
        context: ModelContext
    ) -> String? {
        let transcript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return nil }

        let prior = page.localTranscript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let separator = prior.isEmpty ? "" : "\n\n"
        let combined = prior + separator + transcript
        let syncLength = combined.utf16.count + CloudDocumentBridge.transcriptMarker.utf16.count
        guard syncLength <= Self.personalBlockTextLimit else {
            let available = max(
                0,
                Self.personalBlockTextLimit
                    - CloudDocumentBridge.transcriptMarker.utf16.count
                    - prior.utf16.count
                    - separator.utf16.count
            )
            return "This page has room for only \(available) more transcript characters, but the live text needs \(transcript.utf16.count). Copy the live text and add it to a new page. Nothing was discarded."
        }

        let previousTranscript = page.localTranscript
        let previousTranscriptBlockID = page.transcriptBlockID
        let previousUpdatedAt = page.updatedAt
        let previousPendingMutationID = page.pendingMutationID
        page.localTranscript = combined
        page.transcriptBlockID = page.transcriptBlockID ?? UUID()
        guard pageDidChange(page, context: context) else {
            page.localTranscript = previousTranscript
            page.transcriptBlockID = previousTranscriptBlockID
            page.updatedAt = previousUpdatedAt
            page.pendingMutationID = previousPendingMutationID
            return "Sideleaf could not save this transcript on the device. The live text is still here; keep Sideleaf open and try again."
        }
        return nil
    }

    func syncNow(_ page: LocalPage, context: ModelContext) async {
        debounceTasks[page.id]?.cancel()
        debounceTasks[page.id] = nil
        await sync(page, context: context)
    }

    func syncPending(context: ModelContext) async {
        guard identity != nil else { return }
        let pages: [LocalPage]
        do {
            pages = try context.fetch(FetchDescriptor<LocalPage>())
        } catch {
            syncError = "Sideleaf could not read device drafts for synchronization."
            return
        }
        for page in pages where page.pendingMutationID != nil && page.conflictDocumentData == nil {
            guard !Task.isCancelled else { return }
            await sync(page, context: context)
        }
    }

    func refresh(context: ModelContext) async {
        guard let identity, refreshingOwnerID != identity.id else { return }
        let requestID = UUID()
        refreshRequestID = requestID
        refreshingOwnerID = identity.id
        isRefreshing = true
        syncError = nil
        defer {
            if refreshRequestID == requestID {
                refreshRequestID = nil
                refreshingOwnerID = nil
                isRefreshing = false
            }
        }
        do {
            let localAtRequestStart = try context.fetch(FetchDescriptor<LocalPage>())
            let deletionCandidateVersions = Dictionary(
                uniqueKeysWithValues: localAtRequestStart.compactMap { page -> (UUID, Int)? in
                    guard page.ownerUserID == identity.id,
                          let version = page.serverVersion,
                          version > 0,
                          page.pendingMutationID == nil,
                          page.conflictDocumentData == nil
                    else { return nil }
                    return (page.id, version)
                }
            )
            async let notebookRequest = api.notebooks()
            async let pageRequest = api.pages()
            let (remoteNotebooks, remotePages) = try await (notebookRequest, pageRequest)
            guard self.identity?.id == identity.id else { return }
            notebooks = remoteNotebooks
            notebooksOwnerID = identity.id
            try merge(
                remotePages,
                ownerID: identity.id,
                deletionCandidateVersions: deletionCandidateVersions,
                context: context
            )
            try context.save()
            account = .signedIn(identity)
            accountError = nil
            await syncPending(context: context)
        } catch NativeAPIError.staleOperation {
            return
        } catch {
            guard self.identity?.id == identity.id else { return }
            if isRecoverableNetworkError(error) { account = .signedInOffline(identity) }
            handle(error, expectedUserID: identity.id)
        }
    }

    /// Replaces the local editable fields with the server conflict and retains
    /// local-only ink/transcript fields. The complete server document is kept.
    func resolveConflictUsingCloud(_ page: LocalPage, context: ModelContext) -> Bool {
        guard let data = page.conflictDocumentData,
              let remote = try? JSONDecoder().decode(CloudPage.self, from: data),
              let ownerID = page.ownerUserID
        else { return false }
        do {
            try apply(remote, to: page, ownerID: ownerID)
            try context.save()
            return true
        } catch {
            page.syncError = message(for: error)
            return false
        }
    }

    /// Explicitly rebases the local edit on the conflict's server version. This
    /// can overwrite the remote editable block, so UI should prefer Keep Both.
    func resolveConflictKeepingLocal(_ page: LocalPage, context: ModelContext) {
        guard let data = page.conflictDocumentData,
              let remote = try? JSONDecoder().decode(CloudPage.self, from: data),
              let remoteDocumentData = try? CloudDocumentBridge.encode(remote.document)
        else { return }
        page.cloudDocumentData = remoteDocumentData
        page.serverVersion = remote.version
        page.notebookID = remote.notebookID
        page.conflictDocumentData = nil
        page.pendingMutationID = UUID()
        page.syncError = nil
        do {
            try context.save()
            schedule(page, context: context, delay: .zero)
        } catch {
            page.syncError = "Could not preserve the local conflict choice on this device."
        }
    }

    /// Safest resolution: duplicates the local state as a new pending page, then
    /// restores the original page from the complete remote response.
    @discardableResult
    func resolveConflictKeepingBoth(
        _ page: LocalPage,
        context: ModelContext
    ) -> LocalPage? {
        guard let identity,
              page.ownerUserID == identity.id,
              let data = page.conflictDocumentData,
              let remote = try? JSONDecoder().decode(CloudPage.self, from: data)
        else { return nil }

        let copy = LocalPage(title: recoveredCopyTitle(for: page.title))
        copy.text = page.text
        copy.textRevision = page.textRevision
        copy.ink = page.ink
        copy.inkPreview = page.inkPreview
        copy.annotations = page.annotations.map { annotation in
            var annotation = annotation
            annotation.anchor.blockId = copy.id
            return annotation
        }
        copy.updatedAt = Date()
        copy.ownerUserID = identity.id
        copy.notebookID = page.notebookID ?? remote.notebookID
        copy.serverVersion = 0
        copy.pendingMutationID = UUID()
        copy.cloudDocumentData = nil
        copy.cloudBlockID = copy.id
        copy.recoveryDocumentData = page.cloudDocumentData
        copy.localTranscript = page.localTranscript
        copy.transcriptBlockID = page.localTranscript.map { _ in UUID() }
        context.insert(copy)

        do {
            try apply(remote, to: page, ownerID: identity.id)
            try context.save()
            schedule(copy, context: context, delay: .zero)
            return copy
        } catch {
            context.delete(copy)
            page.syncError = message(for: error)
            return nil
        }
    }

    private func schedule(
        _ page: LocalPage,
        context: ModelContext,
        delay: Duration = .milliseconds(700)
    ) {
        debounceTasks[page.id]?.cancel()
        debounceTasks[page.id] = Task { @MainActor [weak self, weak page] in
            do { try await Task.sleep(for: delay) }
            catch { return }
            guard let self, let page else { return }
            self.debounceTasks[page.id] = nil
            await self.sync(page, context: context)
        }
    }

    private func sync(_ page: LocalPage, context: ModelContext) async {
        guard let identity,
              page.ownerUserID == identity.id,
              page.conflictDocumentData == nil,
              let mutationID = page.pendingMutationID,
              !syncingPageIDs.contains(page.id)
        else { return }

        // Claim the page before any suspension point so a refresh, manual sync,
        // and debounce cannot start duplicate first-save requests.
        syncingPageIDs.insert(page.id)
        defer { syncingPageIDs.remove(page.id) }
        var submittedBaseVersion: Int?

        do {
            if let validationError = validationError(for: page) {
                page.syncError = validationError
                try? context.save()
                return
            }
            if page.notebookID == nil {
                page.notebookID = try await defaultNotebook(for: identity.id).id
            }
            guard self.identity?.id == identity.id,
                  let notebookID = page.notebookID
            else { return }
            let blockID = page.cloudBlockID ?? page.id
            page.cloudBlockID = blockID
            if page.localTranscript != nil, page.transcriptBlockID == nil {
                page.transcriptBlockID = UUID()
            }
            let baseDocument = try page.cloudDocumentData.map(CloudDocumentBridge.decode)
            let document = try CloudDocumentBridge.updating(
                document: baseDocument,
                blockID: blockID,
                text: page.text,
                revision: page.textRevision,
                annotations: page.annotations,
                transcriptBlockID: page.transcriptBlockID,
                localTranscript: page.localTranscript
            )
            let baseVersion = page.serverVersion ?? 0
            submittedBaseVersion = baseVersion
            let write = CloudPageWrite(
                title: normalizedTitle(page.title),
                notebookID: notebookID,
                document: document,
                baseVersion: baseVersion,
                mutationID: mutationID
            )
            try context.save()

            let saved = try await api.savePage(id: page.id, write: write)
            guard self.identity?.id == identity.id, page.ownerUserID == identity.id else { return }
            markAuthenticatedSuccess(for: identity.id)
            guard shouldApplySavedResponse(version: saved.version, to: page) else {
                scheduleNewerMutationIfNeeded(page, submittedMutationID: mutationID, context: context)
                return
            }
            page.serverVersion = saved.version
            page.notebookID = saved.notebookID
            page.cloudDocumentData = try CloudDocumentBridge.encode(saved.document)
            page.lastSyncedAt = Date()
            page.syncError = nil
            page.conflictDocumentData = nil
            if page.pendingMutationID == mutationID { page.pendingMutationID = nil }
            try context.save()
            if page.pendingMutationID != nil { schedule(page, context: context) }
        } catch NativeAPIError.conflict(let current) {
            guard self.identity?.id == identity.id, page.ownerUserID == identity.id else { return }
            markAuthenticatedSuccess(for: identity.id)
            guard let current else {
                guard page.conflictDocumentData == nil,
                      let submittedBaseVersion,
                      (page.serverVersion ?? 0) <= submittedBaseVersion
                else {
                    scheduleNewerMutationIfNeeded(
                        page,
                        submittedMutationID: mutationID,
                        context: context
                    )
                    return
                }
                makeDeviceOnly(
                    page,
                    reason: "The cloud copy could not be found. This page is safely device-only; add it to your account again when ready."
                )
                try? context.save()
                return
            }
            guard shouldApplyConflictResponse(version: current.version, to: page) else {
                scheduleNewerMutationIfNeeded(page, submittedMutationID: mutationID, context: context)
                return
            }
            page.serverVersion = current.version
            page.conflictDocumentData = try? JSONEncoder().encode(current)
            page.syncError = nil
            try? context.save()
        } catch is CancellationError {
            return
        } catch NativeAPIError.staleOperation {
            return
        } catch {
            guard self.identity?.id == identity.id else { return }
            page.syncError = message(for: error)
            try? context.save()
            if isRecoverableNetworkError(error) { account = .signedInOffline(identity) }
            handle(error, expectedUserID: identity.id)
        }
    }

    private func merge(
        _ remotePages: [CloudPage],
        ownerID: String,
        deletionCandidateVersions: [UUID: Int],
        context: ModelContext
    ) throws {
        let local = try context.fetch(FetchDescriptor<LocalPage>())
        let localByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let remoteIDs = Set(remotePages.map(\.id))

        for remote in remotePages {
            if let page = localByID[remote.id] {
                guard page.ownerUserID == ownerID else {
                    syncError = "A cloud page identifier matches a different device draft. Both were preserved."
                    continue
                }
                // A refresh and a save can overlap. Never let an older refresh
                // snapshot roll back the version/document just acknowledged by PUT.
                guard remote.version >= (page.serverVersion ?? 0) else { continue }
                if page.conflictDocumentData != nil {
                    guard let conflictVersion = storedConflictVersion(for: page),
                          remote.version > conflictVersion
                    else { continue }
                    page.serverVersion = remote.version
                    page.conflictDocumentData = try JSONEncoder().encode(remote)
                    continue
                }
                if page.pendingMutationID != nil {
                    if remote.version > (page.serverVersion ?? 0) {
                        page.serverVersion = remote.version
                        page.conflictDocumentData = try JSONEncoder().encode(remote)
                    }
                    continue
                }
                try apply(remote, to: page, ownerID: ownerID)
            } else {
                let page = LocalPage(id: remote.id, title: remote.title)
                context.insert(page)
                try apply(remote, to: page, ownerID: ownerID)
            }
        }

        for page in local where page.ownerUserID == ownerID {
            guard let candidateVersion = deletionCandidateVersions[page.id],
                  page.serverVersion == candidateVersion,
                  page.pendingMutationID == nil,
                  page.conflictDocumentData == nil,
                  !remoteIDs.contains(page.id)
            else { continue }
            makeDeviceOnly(
                page,
                reason: "The cloud copy was deleted. This page is safely device-only; add it to your account again when ready."
            )
        }
    }

    private func apply(_ remote: CloudPage, to page: LocalPage, ownerID: String) throws {
        let documentData = try CloudDocumentBridge.encode(remote.document)
        let content = try CloudDocumentBridge.editableContent(
            in: remote.document,
            preferredBlockID: page.cloudBlockID,
            preferredTranscriptBlockID: page.transcriptBlockID,
            localPageID: page.id
        )
        page.ownerUserID = ownerID
        page.notebookID = remote.notebookID
        page.serverVersion = remote.version
        page.cloudDocumentData = documentData
        page.cloudBlockID = content.blockID
        page.title = remote.title
        page.text = content.text
        page.textRevision = content.revision
        page.annotations = content.annotations
        page.transcriptBlockID = content.transcriptBlockID
        page.localTranscript = content.transcript
        page.updatedAt = cloudDate(remote.updatedAt) ?? page.updatedAt
        page.lastSyncedAt = Date()
        page.pendingMutationID = nil
        page.conflictDocumentData = nil
        page.syncError = nil
        // PencilKit ink and its preview remain device-only.
    }

    private func defaultNotebook(for ownerID: String) async throws -> CloudNotebook {
        guard identity?.id == ownerID else { throw NativeAPIError.notAuthenticated }
        if notebooksOwnerID == ownerID, let notebook = notebooks.first { return notebook }
        if let request = defaultNotebookRequest {
            if request.ownerID == ownerID { return try await request.task.value }
            request.task.cancel()
            defaultNotebookRequest = nil
        }

        let requestID = UUID()
        let task = Task { try await api.createNotebook(id: UUID(), name: "Work") }
        defaultNotebookRequest = DefaultNotebookRequest(
            id: requestID,
            ownerID: ownerID,
            task: task
        )
        defer {
            if defaultNotebookRequest?.id == requestID { defaultNotebookRequest = nil }
        }
        do {
            let notebook = try await task.value
            guard identity?.id == ownerID else { throw CancellationError() }
            markAuthenticatedSuccess(for: ownerID)
            notebooksOwnerID = ownerID
            notebooks = [notebook]
            return notebook
        } catch let error as NativeAPIError {
            if case .server(let status, _) = error, status == 409 {
                markAuthenticatedSuccess(for: ownerID)
                let refreshed = try await api.notebooks()
                if identity?.id == ownerID, let notebook = refreshed.first {
                    markAuthenticatedSuccess(for: ownerID)
                    notebooksOwnerID = ownerID
                    notebooks = refreshed
                    return notebook
                }
            }
            throw error
        }
    }

    private func normalizedTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled page" : trimmed
    }

    private func recoveredCopyTitle(for title: String) -> String {
        let suffix = " (recovered copy)"
        let maximumBaseLength = Self.titleLimit - suffix.utf16.count
        var base = ""
        var remaining = maximumBaseLength
        for character in normalizedTitle(title) {
            let units = String(character).utf16.count
            guard units <= remaining else { break }
            base.append(character)
            remaining -= units
        }
        return base + suffix
    }

    private func validationError(for page: LocalPage) -> String? {
        if normalizedTitle(page.title).utf16.count > Self.titleLimit {
            return "The page title exceeds the 200-character sync limit. Shorten the title; the full draft remains on this device."
        }
        if page.text.utf16.count > Self.personalBlockTextLimit {
            return "Typed notes exceed the 30,000-character sync limit. Shorten or split this page; the full draft remains on this device."
        }
        if let transcript = page.localTranscript,
           transcript.utf16.count + CloudDocumentBridge.transcriptMarker.utf16.count
               > Self.personalBlockTextLimit
        {
            return "The on-device transcript exceeds the 30,000-character sync limit. Shorten or split it; the full transcript remains on this device."
        }
        return nil
    }

    private func shouldApplySavedResponse(version: Int, to page: LocalPage) -> Bool {
        guard version >= (page.serverVersion ?? 0) else { return false }
        guard page.conflictDocumentData != nil else { return true }
        guard let conflictVersion = storedConflictVersion(for: page) else { return false }
        return version > conflictVersion
    }

    private func shouldApplyConflictResponse(version: Int, to page: LocalPage) -> Bool {
        guard version >= (page.serverVersion ?? 0) else { return false }
        guard page.conflictDocumentData != nil else { return true }
        guard let conflictVersion = storedConflictVersion(for: page) else { return false }
        return version >= conflictVersion
    }

    private func storedConflictVersion(for page: LocalPage) -> Int? {
        guard let data = page.conflictDocumentData else { return nil }
        return try? JSONDecoder().decode(CloudPage.self, from: data).version
    }

    private func scheduleNewerMutationIfNeeded(
        _ page: LocalPage,
        submittedMutationID: UUID,
        context: ModelContext
    ) {
        guard page.conflictDocumentData == nil,
              let pendingMutationID = page.pendingMutationID,
              pendingMutationID != submittedMutationID
        else { return }
        schedule(page, context: context)
    }

    private func makeDeviceOnly(_ page: LocalPage, reason: String) {
        debounceTasks[page.id]?.cancel()
        debounceTasks[page.id] = nil
        page.recoveryDocumentData = page.cloudDocumentData ?? page.recoveryDocumentData
        page.notebookID = nil
        page.serverVersion = nil
        page.pendingMutationID = nil
        page.lastSyncedAt = nil
        page.cloudDocumentData = nil
        page.cloudBlockID = nil
        page.conflictDocumentData = nil
        page.transcriptBlockID = nil
        page.syncError = reason
    }

    private func beginAccountOperation() -> Int {
        configurationTask?.cancel()
        configurationTask = nil
        accountOperationGeneration &+= 1
        return accountOperationGeneration
    }

    private func requestConfiguration(for operation: Int) {
        let api = self.api
        configurationTask = Task { @MainActor [weak self] in
            guard let configuration = try? await api.configuration(),
                  !Task.isCancelled,
                  let self,
                  operation == self.accountOperationGeneration
            else { return }
            self.configuration = configuration
        }
    }

    private func markAuthenticatedSuccess(for ownerID: String) {
        guard let identity, identity.id == ownerID else { return }
        account = .signedIn(identity)
        accountError = nil
    }

    private func activate(_ identity: CloudIdentity, offline: Bool) {
        if let refreshingOwnerID, refreshingOwnerID != identity.id {
            refreshRequestID = nil
            self.refreshingOwnerID = nil
            isRefreshing = false
        }
        if notebooksOwnerID != identity.id {
            notebooks = []
            notebooksOwnerID = nil
        }
        if let request = defaultNotebookRequest, request.ownerID != identity.id {
            request.task.cancel()
            defaultNotebookRequest = nil
        }
        account = offline ? .signedInOffline(identity) : .signedIn(identity)
    }

    private func completeLocalSignOut() {
        cancelDebounces()
        account = .signedOut
        notebooks = []
        notebooksOwnerID = nil
        syncingPageIDs = []
        refreshRequestID = nil
        refreshingOwnerID = nil
        isRefreshing = false
    }

    private func handle(_ error: Error, expectedUserID: String? = nil) {
        if case NativeAPIError.staleOperation = error { return }
        if let expectedUserID, identity?.id != expectedUserID { return }
        if case NativeAPIError.sessionExpired = error {
            completeLocalSignOut()
            accountError = NativeAPIError.sessionExpired.localizedDescription
        } else {
            syncError = message(for: error)
        }
    }

    private func isRecoverableNetworkError(_ error: Error) -> Bool {
        switch error {
        case NativeAPIError.transport:
            true
        case NativeAPIError.server(let status, _):
            status >= 500
        default:
            false
        }
    }

    private func message(for error: Error) -> String {
        if let error = error as? LocalizedError, let description = error.errorDescription {
            return description
        }
        return "The operation could not be completed. Device drafts remain available."
    }

    private func cancelDebounces() {
        debounceTasks.values.forEach { $0.cancel() }
        debounceTasks = [:]
        defaultNotebookRequest?.task.cancel()
        defaultNotebookRequest = nil
    }

    private static let titleLimit = 200
    private static let personalBlockTextLimit = 30_000
}
