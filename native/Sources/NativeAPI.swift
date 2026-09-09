import Foundation

struct NativeAccountDeletionOutcome: Equatable, Sendable {
    let credentialCleanupSucceeded: Bool

    static let complete = NativeAccountDeletionOutcome(credentialCleanupSucceeded: true)
    static let credentialCleanupFailed = NativeAccountDeletionOutcome(
        credentialCleanupSucceeded: false
    )
}

protocol NativeAPIProviding: Sendable {
    func configuration() async throws -> CloudConfiguration
    func cachedIdentity() async throws -> CloudIdentity?
    func cachedAcceptedTermsVersion() async throws -> String?
    func restoreSession() async throws -> CloudIdentity?
    func signIn(email: String, password: String) async throws -> CloudIdentity
    func createAccount(name: String, email: String, password: String) async throws -> CloudIdentity
    func legalStatus() async throws -> CloudLegalStatus
    func acceptLegal(termsVersion: String) async throws -> CloudLegalStatus
    func signOut() async throws
    func deleteAccount() async throws -> NativeAccountDeletionOutcome
    func notebooks() async throws -> [CloudNotebook]
    func createNotebook(id: UUID, name: String) async throws -> CloudNotebook
    func pages() async throws -> [CloudPage]
    func savePage(id: UUID, write: CloudPageWrite) async throws -> CloudPage
}

enum NativeAPIError: Error, LocalizedError, Sendable {
    case notAuthenticated
    case sessionExpired
    case missingSessionToken
    case invalidResponse
    case responseTooLarge
    case blockedRedirect
    case staleOperation
    case termsAcceptanceRequired(CloudLegalMetadata?)
    case conflict(CloudPage?)
    case server(status: Int, message: String)
    case transport

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Sign in to connect this device to Sideleaf."
        case .sessionExpired:
            "Your session expired. Sign in again; your device drafts are still here."
        case .missingSessionToken:
            "Sideleaf could not establish a secure app session. Try again."
        case .invalidResponse:
            "Sideleaf received an invalid server response. Your device draft is unchanged."
        case .responseTooLarge:
            "The cloud page is too large for this app version. Your device draft is unchanged."
        case .blockedRedirect:
            "Sideleaf blocked a connection that left its secure server."
        case .staleOperation:
            "The account changed while this request was running."
        case .termsAcceptanceRequired:
            "Review and accept the current Terms of Service to continue."
        case .conflict:
            "Another edit is already in the cloud. Review both copies before continuing."
        case .server(_, let message):
            message
        case .transport:
            "Sideleaf could not reach the notebook server. Your draft remains on this device."
        }
    }
}

actor NativeAPI: NativeAPIProviding {
    static let origin = URL(string: "https://sideleaf.vercel.app")!

    private enum Authentication {
        case none
        case required
    }

    private struct Payload: Sendable {
        let data: Data
        let response: HTTPURLResponse
        let sessionToken: String?
    }

    private struct ErrorEnvelope: Decodable {
        let error: String?
        let message: String?
        let legal: CloudLegalMetadata?
    }

    private struct ErrorCodeEnvelope: Decodable {
        let code: String?
    }

    private struct ConflictEnvelope: Decodable {
        let current: CloudPage?
    }

    private struct DeletionEnvelope: Decodable {
        let deleted: Bool
    }

    private let tokenStore: KeychainSessionStore
    private let accountDeletionCredentialCleanup: @Sendable () throws -> Void
    private let sendRequest: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private var authenticationGeneration = 0

    init(tokenStore: KeychainSessionStore = KeychainSessionStore()) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let delegate = SameHostRedirectDelegate(origin: Self.origin)
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
        self.tokenStore = tokenStore
        accountDeletionCredentialCleanup = { try tokenStore.delete() }
        sendRequest = { request in try await session.data(for: request) }
    }

    init(
        tokenStore: KeychainSessionStore,
        accountDeletionCredentialCleanup: (@Sendable () throws -> Void)? = nil,
        sendRequest: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) {
        self.tokenStore = tokenStore
        self.accountDeletionCredentialCleanup = accountDeletionCredentialCleanup
            ?? { try tokenStore.delete() }
        self.sendRequest = sendRequest
    }

    func configuration() async throws -> CloudConfiguration {
        let payload = try await send(path: "config", method: "GET", authentication: .none)
        try requireSuccess(payload)
        return try decode(CloudConfiguration.self, from: payload.data)
    }

    func cachedIdentity() async throws -> CloudIdentity? {
        try tokenStore.load()?.identity
    }

    func cachedAcceptedTermsVersion() async throws -> String? {
        try tokenStore.load()?.acceptedTermsVersion
    }

    func restoreSession() async throws -> CloudIdentity? {
        guard let storedSession = try tokenStore.load() else { return nil }
        let generation = authenticationGeneration
        do {
            let payload = try await send(
                path: "auth/get-session",
                method: "GET",
                authentication: .required
            )
            try requireSuccess(payload)
            let session = try decode(CloudSessionEnvelope?.self, from: payload.data)
            guard generation == authenticationGeneration else {
                throw NativeAPIError.staleOperation
            }
            guard let identity = session?.user else {
                try tokenStore.delete()
                authenticationGeneration &+= 1
                return nil
            }
            let acceptedTermsVersion = storedSession.identity.id == identity.id
                ? storedSession.acceptedTermsVersion
                : nil
            try tokenStore.save(
                StoredNativeSession(
                    token: payload.sessionToken ?? storedSession.token,
                    identity: identity,
                    acceptedTermsVersion: acceptedTermsVersion
                )
            )
            authenticationGeneration &+= 1
            return identity
        } catch NativeAPIError.sessionExpired {
            return nil
        }
    }

    func signIn(email: String, password: String) async throws -> CloudIdentity {
        authenticationGeneration &+= 1
        let generation = authenticationGeneration
        let priorSession = try? tokenStore.load()
        let body = try encoded(["email": email, "password": password])
        let payload = try await send(
            path: "auth/sign-in/email",
            method: "POST",
            body: body,
            authentication: .none
        )
        try requireSuccess(payload, authenticationAttempt: true)
        guard let token = payload.sessionToken else { throw NativeAPIError.missingSessionToken }
        let identity = try decode(CloudAuthEnvelope.self, from: payload.data).user
        guard generation == authenticationGeneration else {
            throw NativeAPIError.staleOperation
        }
        let acceptedTermsVersion = priorSession?.identity.id == identity.id
            ? priorSession?.acceptedTermsVersion
            : nil
        do {
            try tokenStore.save(
                StoredNativeSession(
                    token: token,
                    identity: identity,
                    acceptedTermsVersion: acceptedTermsVersion
                )
            )
        }
        catch {
            try? tokenStore.delete()
            throw error
        }
        authenticationGeneration &+= 1
        return identity
    }

    func createAccount(name: String, email: String, password: String) async throws -> CloudIdentity {
        authenticationGeneration &+= 1
        let generation = authenticationGeneration
        let body = try encoded(["name": name, "email": email, "password": password])
        let payload = try await send(
            path: "auth/sign-up/email",
            method: "POST",
            body: body,
            authentication: .none
        )
        try requireSuccess(payload, authenticationAttempt: true)
        guard let token = payload.sessionToken else { throw NativeAPIError.missingSessionToken }
        let identity = try decode(CloudAuthEnvelope.self, from: payload.data).user
        guard generation == authenticationGeneration else {
            throw NativeAPIError.staleOperation
        }
        do { try tokenStore.save(StoredNativeSession(token: token, identity: identity)) }
        catch {
            try? tokenStore.delete()
            throw error
        }
        authenticationGeneration &+= 1
        return identity
    }

    func legalStatus() async throws -> CloudLegalStatus {
        let payload = try await send(
            path: "legal/status",
            method: "GET",
            authentication: .required
        )
        try requireSuccess(payload)
        let status = try decode(CloudLegalStatus.self, from: payload.data)
        try cacheLegalStatus(status, refreshedToken: payload.sessionToken)
        return status
    }

    func acceptLegal(termsVersion: String) async throws -> CloudLegalStatus {
        let acceptance = CloudLegalAcceptance(
            termsVersion: termsVersion,
            acceptedTerms: true,
            recordingLawAcknowledged: true
        )
        let payload = try await send(
            path: "legal/acceptance",
            method: "POST",
            body: try encoded(acceptance),
            authentication: .required
        )
        try requireSuccess(payload)
        let status = try decode(CloudLegalStatus.self, from: payload.data)
        try cacheLegalStatus(status, refreshedToken: payload.sessionToken)
        return status
    }

    func signOut() async throws {
        authenticationGeneration &+= 1
        let token = try? tokenStore.load()?.token
        // Remove the local credential before any network suspension. Revocation
        // is best effort so an outage cannot block a local sign-out.
        try tokenStore.delete()
        guard let token else { return }
        Task { [weak self] in
            await self?.revoke(token: token)
        }
    }

    func deleteAccount() async throws -> NativeAccountDeletionOutcome {
        let payload = try await send(
            path: "account",
            method: "DELETE",
            body: try encoded(["confirmation": "DELETE"]),
            authentication: .required
        )
        try requireSuccess(payload, allowForbiddenMessage: true)
        guard try decode(DeletionEnvelope.self, from: payload.data).deleted else {
            throw NativeAPIError.invalidResponse
        }
        authenticationGeneration &+= 1
        do {
            try accountDeletionCredentialCleanup()
            return .complete
        } catch {
            // The server has already confirmed permanent deletion. Credential
            // cleanup is a separate device issue and must not turn that success
            // into a failed remote deletion or block account-scoped data purge.
            return .credentialCleanupFailed
        }
    }

    private func revoke(token: String) async {
        _ = try? await send(
            path: "auth/sign-out",
            method: "POST",
            body: Data("{}".utf8),
            authentication: .none,
            bearerToken: token
        )
    }

    func notebooks() async throws -> [CloudNotebook] {
        let payload = try await send(
            path: "notebooks",
            method: "GET",
            authentication: .required
        )
        try requireSuccess(payload)
        return try decode([CloudNotebook].self, from: payload.data)
    }

    func createNotebook(id: UUID, name: String) async throws -> CloudNotebook {
        struct Body: Encodable {
            let id: UUID
            let name: String
        }
        let payload = try await send(
            path: "notebooks",
            method: "POST",
            body: try encoded(Body(id: id, name: name)),
            authentication: .required
        )
        try requireSuccess(payload)
        return try decode(CloudNotebook.self, from: payload.data)
    }

    func pages() async throws -> [CloudPage] {
        let payload = try await send(
            path: "pages",
            method: "GET",
            authentication: .required
        )
        try requireSuccess(payload)
        return try decode([CloudPage].self, from: payload.data)
    }

    func savePage(id: UUID, write: CloudPageWrite) async throws -> CloudPage {
        let payload = try await send(
            path: "pages/\(id.uuidString.lowercased())",
            method: "PUT",
            body: try encoded(write),
            authentication: .required
        )
        if payload.response.statusCode == 409 {
            let conflict = try? decode(ConflictEnvelope.self, from: payload.data)
            throw NativeAPIError.conflict(conflict?.current)
        }
        try requireSuccess(payload)
        return try decode(CloudPage.self, from: payload.data)
    }

    private func send(
        path: String,
        method: String,
        body: Data? = nil,
        authentication: Authentication,
        bearerToken: String? = nil
    ) async throws -> Payload {
        guard let url = endpoint(path), isAllowed(url) else { throw NativeAPIError.blockedRedirect }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if !["GET", "HEAD", "OPTIONS"].contains(method) {
            request.setValue(Self.origin.absoluteString, forHTTPHeaderField: "Origin")
        }
        let generation = authenticationGeneration
        var authenticatedSession: StoredNativeSession?
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        } else if authentication == .required {
            guard let session = try tokenStore.load() else {
                throw NativeAPIError.notAuthenticated
            }
            authenticatedSession = session
            request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await sendRequest(request)
            if authentication == .required {
                try requireCurrentAuthentication(
                    generation: generation,
                    session: authenticatedSession
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            if authentication == .required {
                try requireCurrentAuthentication(
                    generation: generation,
                    session: authenticatedSession
                )
            }
            throw NativeAPIError.transport
        }
        guard data.count <= 8 * 1_024 * 1_024 else { throw NativeAPIError.responseTooLarge }
        guard let http = response as? HTTPURLResponse,
              let finalURL = http.url,
              isAllowed(finalURL)
        else { throw NativeAPIError.invalidResponse }

        let responseToken = http.value(forHTTPHeaderField: "set-auth-token")
            .flatMap { $0.isEmpty ? nil : $0 }

        if http.statusCode == 401, authentication == .required {
            authenticationGeneration &+= 1
            try tokenStore.delete()
            throw NativeAPIError.sessionExpired
        }
        return Payload(
            data: data,
            response: http,
            sessionToken: responseToken
        )
    }

    private func requireCurrentAuthentication(
        generation: Int,
        session: StoredNativeSession?
    ) throws {
        guard generation == authenticationGeneration,
              let session,
              try tokenStore.load() == session
        else { throw NativeAPIError.staleOperation }
    }

    private func requireSuccess(
        _ payload: Payload,
        authenticationAttempt: Bool = false,
        allowForbiddenMessage: Bool = false
    ) throws {
        let status = payload.response.statusCode
        guard (200..<300).contains(status) else {
            if authenticationAttempt && status == 401 {
                throw NativeAPIError.server(
                    status: status,
                    message: "The email or password was not accepted."
                )
            }
            let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: payload.data)
            let code = (try? JSONDecoder().decode(ErrorCodeEnvelope.self, from: payload.data))?.code
            // Treat the protocol status itself as authoritative. A future server
            // may add fields that this app cannot decode yet; that must not turn
            // a legal gate into a generic error or leave stale acceptance cached.
            if status == 428 || code == "TERMS_ACCEPTANCE_REQUIRED" {
                try? cacheAcceptedTermsVersion(nil, refreshedToken: payload.sessionToken)
                throw NativeAPIError.termsAcceptanceRequired(envelope?.legal)
            }
            let candidate = envelope?.error ?? envelope?.message
            let message = safeMessage(
                candidate,
                status: status,
                code: code,
                allowForbiddenMessage: allowForbiddenMessage
            )
            throw NativeAPIError.server(status: status, message: message)
        }
    }

    private func safeMessage(
        _ candidate: String?,
        status: Int,
        code: String?,
        allowForbiddenMessage: Bool = false
    ) -> String {
        if status == 429 { return "Too many attempts. Wait a moment and try again." }
        if status == 413 { return "This page is too large to sync. Split it into smaller pages." }
        if status == 403, !allowForbiddenMessage {
            return "This request was not accepted by the Sideleaf server."
        }
        if status >= 500 { return "The notebook server is unavailable. Your device draft is unchanged." }
        guard let candidate else {
            return code == nil
                ? "The notebook server could not complete this request."
                : "The notebook server rejected this request."
        }
        let value = candidate
            .unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
            .prefix(300)
        let cleaned = String(String.UnicodeScalarView(value))
        return cleaned.isEmpty ? "The notebook server rejected this request." : cleaned
    }

    private func cacheLegalStatus(
        _ status: CloudLegalStatus,
        refreshedToken: String?
    ) throws {
        try cacheAcceptedTermsVersion(
            status.confirmsCurrentTerms ? status.legal.termsVersion : nil,
            refreshedToken: refreshedToken
        )
    }

    private func cacheAcceptedTermsVersion(
        _ version: String?,
        refreshedToken: String?
    ) throws {
        guard let session = try tokenStore.load() else {
            throw NativeAPIError.notAuthenticated
        }
        try tokenStore.save(
            StoredNativeSession(
                token: refreshedToken ?? session.token,
                identity: session.identity,
                acceptedTermsVersion: version
            )
        )
    }

    private func endpoint(_ path: String) -> URL? {
        let normalized = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalized.isEmpty,
              !normalized.contains(".."),
              !normalized.contains("://"),
              !normalized.contains("?")
        else { return nil }
        var components = URLComponents(url: Self.origin, resolvingAgainstBaseURL: false)
        components?.path = "/api/\(normalized)"
        components?.query = nil
        components?.fragment = nil
        return components?.url
    }

    private func isAllowed(_ url: URL) -> Bool {
        Self.isSameOrigin(url, Self.origin)
    }

    private static func isSameOrigin(_ left: URL, _ right: URL) -> Bool {
        left.scheme?.lowercased() == "https"
            && left.scheme?.lowercased() == right.scheme?.lowercased()
            && left.host?.lowercased() == right.host?.lowercased()
            && effectivePort(left) == effectivePort(right)
    }

    private static func effectivePort(_ url: URL) -> Int? {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : nil)
    }

    private func encoded<Value: Encodable>(_ value: Value) throws -> Data {
        do { return try JSONEncoder().encode(value) }
        catch { throw NativeAPIError.invalidResponse }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw NativeAPIError.invalidResponse }
    }
}

private final class SameHostRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let origin: URL

    init(origin: URL) {
        self.origin = origin
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let destination = request.url,
              destination.scheme?.lowercased() == "https",
              destination.host?.lowercased() == origin.host?.lowercased(),
              (destination.port ?? 443) == (origin.port ?? 443)
        else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
