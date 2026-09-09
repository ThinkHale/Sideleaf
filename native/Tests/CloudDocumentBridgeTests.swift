import Foundation
import SwiftData
import XCTest
@testable import Sideleaf

final class CloudDocumentBridgeTests: XCTestCase {
    func testCloudJSONIntegerRejectsRoundedOutOfRangeNumber() {
        XCTAssertNil(CloudJSON.number(Double(Int.max)).integerValue)
        XCTAssertNil(CloudJSON.number(1.5).integerValue)
        XCTAssertEqual(CloudJSON.number(42).integerValue, 42)
    }

    func testUpdatingPersonalBlockPreservesOpaqueCloudContent() throws {
        let pageID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let personalBlockID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let remoteBlockID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let oldAnnotationID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let unrelatedAnnotationID = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
        let newAnnotationID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!

        let personalBlock: CloudJSON = .object([
            "id": .string(personalBlockID.uuidString.lowercased()),
            "kind": .string("paragraph"),
            "source": .string("personal"),
            "text": .string("Before"),
            "revision": .number(4),
            "futureBlockField": .object(["mode": .string("keep-me")]),
        ])
        let remoteBlock: CloudJSON = .object([
            "id": .string(remoteBlockID.uuidString.lowercased()),
            "kind": .string("transcript"),
            "source": .string("capture"),
            "text": .string("Remote transcript"),
            "revision": .number(9),
            "segments": .array([.object(["speaker": .string("A")])]),
        ])
        let webInk: CloudJSON = .array([
            .object([
                "id": .string("web-stroke"),
                "points": .array([.number(1.25), .number(8.5)]),
                "brush": .object(["color": .string("#123456")]),
            ]),
        ])
        let preparation: CloudJSON = .object([
            "type": .string("Interview"),
            "agenda": .string("Unchanged agenda"),
            "futurePreparationField": .array([.string("one"), .bool(true)]),
        ])
        let oldDesignatedAnnotation: CloudJSON = .object([
            "id": .string(oldAnnotationID.uuidString.lowercased()),
            "kind": .string("important"),
            "anchor": .object([
                "blockId": .string(personalBlockID.uuidString.lowercased()),
                "revision": .number(4),
                "start": .number(0),
                "end": .number(6),
                "quote": .string("Before"),
                "prefix": .string(""),
                "suffix": .string(""),
                "resolved": .bool(true),
            ]),
            "question": .string("Old mark"),
            "state": .string("open"),
            "createdAt": .string("2025-01-02T03:04:05Z"),
            "webOnlyAnnotationField": .string("replaced-with-designated-marks"),
        ])
        let unrelatedAnnotation: CloudJSON = .object([
            "id": .string(unrelatedAnnotationID.uuidString.lowercased()),
            "kind": .string("web-only-kind"),
            "anchor": .object([
                "blockId": .string(remoteBlockID.uuidString.lowercased()),
                "futureAnchorField": .number(42),
            ]),
            "payload": .object(["unknown": .string("preserve exactly")]),
        ])
        let document: CloudJSON = .object([
            "schemaVersion": .number(12),
            "blocks": .array([remoteBlock, personalBlock]),
            "ink": webInk,
            "annotations": .array([oldDesignatedAnnotation, unrelatedAnnotation]),
            "preparation": preparation,
            "meetingState": .string("capture"),
            "futureRootField": .object(["nested": .null]),
        ])

        let replacement = NativeAnnotation(
            id: newAnnotationID,
            kind: "action",
            anchor: NativeAnchor(
                blockId: pageID,
                revision: 5,
                start: 0,
                end: 5,
                quote: "After",
                prefix: "",
                suffix: " text",
                resolved: true
            ),
            question: "Who owns this?",
            state: "open",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let incompatible = NativeAnnotation(
            kind: "web-only-kind",
            anchor: NativeAnchor(
                blockId: pageID,
                revision: 5,
                start: 0,
                end: 5,
                quote: "After",
                prefix: "",
                suffix: "",
                resolved: true
            )
        )

        let result = try CloudDocumentBridge.updating(
            document: document,
            blockID: personalBlockID,
            text: "After text",
            revision: 5,
            annotations: [replacement, incompatible]
        )
        let root = try XCTUnwrap(result.objectValue)

        XCTAssertEqual(root["schemaVersion"], .number(12))
        XCTAssertEqual(root["ink"], webInk)
        XCTAssertEqual(root["preparation"], preparation)
        XCTAssertEqual(root["meetingState"], .string("capture"))
        XCTAssertEqual(root["futureRootField"], .object(["nested": .null]))

        let blocks = try XCTUnwrap(root["blocks"]?.arrayValue)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0], remoteBlock)
        let updatedBlock = try XCTUnwrap(blocks[1].objectValue)
        XCTAssertEqual(updatedBlock["id"], personalBlock.objectValue?["id"])
        XCTAssertEqual(updatedBlock["kind"], personalBlock.objectValue?["kind"])
        XCTAssertEqual(updatedBlock["source"], personalBlock.objectValue?["source"])
        XCTAssertEqual(updatedBlock["futureBlockField"], personalBlock.objectValue?["futureBlockField"])
        XCTAssertEqual(updatedBlock["text"], .string("After text"))
        XCTAssertEqual(updatedBlock["revision"], .number(5))

        let annotations = try XCTUnwrap(root["annotations"]?.arrayValue)
        XCTAssertEqual(annotations.count, 2)
        XCTAssertEqual(annotations[0], unrelatedAnnotation)
        let replacementJSON = try XCTUnwrap(annotations[1].objectValue)
        XCTAssertEqual(replacementJSON["id"], .string(newAnnotationID.uuidString.lowercased()))
        XCTAssertEqual(replacementJSON["kind"], .string("action"))
        XCTAssertEqual(replacementJSON["question"], .string("Who owns this?"))
        XCTAssertEqual(replacementJSON["state"], .string("open"))
        XCTAssertEqual(
            replacementJSON["anchor"]?.objectValue?["blockId"],
            .string(personalBlockID.uuidString.lowercased())
        )

        // A decode/encode cycle must not erase opaque JSON values either.
        let roundTripped = try CloudDocumentBridge.decode(CloudDocumentBridge.encode(result))
        XCTAssertEqual(roundTripped, result)
    }

    func testNewDocumentHasStableEnvelopeAndDesignatedPersonalBlock() throws {
        let blockID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let document = try CloudDocumentBridge.updating(
            document: nil,
            blockID: blockID,
            text: "Created on iPhone",
            revision: 0,
            annotations: []
        )
        let root = try XCTUnwrap(document.objectValue)

        XCTAssertEqual(root["schemaVersion"], .number(1))
        XCTAssertEqual(root["ink"], .array([]))
        XCTAssertEqual(root["annotations"], .array([]))
        XCTAssertEqual(root["meetingState"], .string("notes"))
        XCTAssertNotNil(root["preparation"]?.objectValue)

        let blocks = try XCTUnwrap(root["blocks"]?.arrayValue)
        XCTAssertEqual(blocks.count, 1)
        let block = try XCTUnwrap(blocks.first?.objectValue)
        XCTAssertEqual(block["id"], .string(blockID.uuidString.lowercased()))
        XCTAssertEqual(block["kind"], .string("paragraph"))
        XCTAssertEqual(block["source"], .string("personal"))
        XCTAssertEqual(block["text"], .string("Created on iPhone"))
        XCTAssertEqual(block["revision"], .number(1))
        XCTAssertEqual(block["excluded"], .bool(false))
    }

    func testEditableContentUsesPreferredPersonalBlockAndMapsAnchorsToLocalPage() throws {
        let localPageID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let firstBlockID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let preferredBlockID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let annotationID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let document: CloudJSON = .object([
            "blocks": .array([
                .object([
                    "id": .string(firstBlockID.uuidString.lowercased()),
                    "kind": .string("paragraph"),
                    "source": .string("personal"),
                    "text": .string("First personal block"),
                    "revision": .number(2),
                ]),
                .object([
                    "id": .string(preferredBlockID.uuidString.uppercased()),
                    "kind": .string("paragraph"),
                    "source": .string("personal"),
                    "text": .string("Preferred personal block"),
                    "revision": .number(7),
                ]),
            ]),
            "annotations": .array([
                .object([
                    "id": .string(annotationID.uuidString.lowercased()),
                    "kind": .string("follow-up"),
                    "anchor": .object([
                        "blockId": .string(preferredBlockID.uuidString.lowercased()),
                        "revision": .number(7),
                        "start": .number(0),
                        "end": .number(9),
                        "quote": .string("Preferred"),
                        "prefix": .string(""),
                        "suffix": .string(" personal block"),
                        "resolved": .bool(true),
                    ]),
                    "question": .string("Follow up"),
                    "state": .string("later"),
                    "createdAt": .string("2025-01-02T03:04:05Z"),
                ]),
            ]),
        ])

        let content = try CloudDocumentBridge.editableContent(
            in: document,
            preferredBlockID: preferredBlockID,
            localPageID: localPageID
        )

        XCTAssertEqual(content.blockID, preferredBlockID)
        XCTAssertEqual(content.text, "Preferred personal block")
        XCTAssertEqual(content.revision, 7)
        XCTAssertEqual(content.annotations.count, 1)
        XCTAssertEqual(content.annotations[0].id, annotationID)
        XCTAssertEqual(content.annotations[0].anchor.blockId, localPageID)
        XCTAssertEqual(content.annotations[0].anchor.quote, "Preferred")
    }

    func testOnDeviceTranscriptRoundTripsAsSeparatePersonalBlock() throws {
        let pageID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let noteBlockID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let transcriptBlockID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let document = try CloudDocumentBridge.updating(
            document: nil,
            blockID: noteBlockID,
            text: "Ordinary notes",
            revision: 2,
            annotations: [],
            transcriptBlockID: transcriptBlockID,
            localTranscript: "A private on-device transcript."
        )

        let content = try CloudDocumentBridge.editableContent(
            in: document,
            preferredBlockID: noteBlockID,
            preferredTranscriptBlockID: transcriptBlockID,
            localPageID: pageID
        )
        XCTAssertEqual(content.blockID, noteBlockID)
        XCTAssertEqual(content.text, "Ordinary notes")
        XCTAssertEqual(content.transcriptBlockID, transcriptBlockID)
        XCTAssertEqual(content.transcript, "A private on-device transcript.")

        let blocks = try XCTUnwrap(document.objectValue?["blocks"]?.arrayValue)
        let transcript = try XCTUnwrap(
            blocks.first {
                $0.objectValue?["id"]?.stringValue == transcriptBlockID.uuidString.lowercased()
            }?.objectValue
        )
        XCTAssertEqual(transcript["kind"], .string("paragraph"))
        XCTAssertEqual(transcript["source"], .string("personal"))
        XCTAssertEqual(
            transcript["text"],
            .string(CloudDocumentBridge.transcriptMarker + "A private on-device transcript.")
        )
    }

    func testTranscriptAppendPreservesItsRevisionAndAnchoredAnnotations() throws {
        let noteBlockID = UUID(uuidString: "10101010-1010-1010-1010-101010101010")!
        let transcriptBlockID = UUID(uuidString: "20202020-2020-2020-2020-202020202020")!
        let annotationID = UUID(uuidString: "30303030-3030-3030-3030-303030303030")!
        let transcriptText = CloudDocumentBridge.transcriptMarker + "Existing words."
        let transcriptBlock: CloudJSON = .object([
            "id": .string(transcriptBlockID.uuidString.lowercased()),
            "kind": .string("paragraph"),
            "source": .string("personal"),
            "text": .string(transcriptText),
            "revision": .number(7),
            "excluded": .bool(false),
        ])
        let transcriptAnnotation: CloudJSON = .object([
            "id": .string(annotationID.uuidString.lowercased()),
            "kind": .string("important"),
            "anchor": .object([
                "blockId": .string(transcriptBlockID.uuidString.lowercased()),
                "revision": .number(7),
                "start": .number(Double(CloudDocumentBridge.transcriptMarker.utf16.count)),
                "end": .number(Double(CloudDocumentBridge.transcriptMarker.utf16.count + 8)),
                "quote": .string("Existing"),
                "prefix": .string(""),
                "suffix": .string(" words."),
                "resolved": .bool(true),
            ]),
            "question": .string("Keep this mark"),
            "state": .string("open"),
            "createdAt": .string("2025-01-02T03:04:05Z"),
        ])
        let document: CloudJSON = .object([
            "blocks": .array([transcriptBlock]),
            "annotations": .array([transcriptAnnotation]),
            "ink": .array([]),
        ])

        let result = try CloudDocumentBridge.updating(
            document: document,
            blockID: noteBlockID,
            text: "Notes changed without owning the transcript block.",
            revision: 42,
            annotations: [],
            transcriptBlockID: transcriptBlockID,
            localTranscript: "Existing words. Appended words."
        )
        let blocks = try XCTUnwrap(result.objectValue?["blocks"]?.arrayValue)
        let updatedTranscript = try XCTUnwrap(
            blocks.first {
                $0.objectValue?["id"]?.stringValue == transcriptBlockID.uuidString.lowercased()
            }?.objectValue
        )
        XCTAssertEqual(updatedTranscript["revision"], .number(7))
        XCTAssertEqual(updatedTranscript["text"], .string(transcriptText + " Appended words."))
        XCTAssertTrue(
            try XCTUnwrap(result.objectValue?["annotations"]?.arrayValue).contains(
                transcriptAnnotation
            )
        )
    }

    func testInvalidDocumentAndNonpersonalEditAreRejectedWithoutMutation() throws {
        let blockID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let invalidDocument: CloudJSON = .object(["future": .string("untouched")])

        XCTAssertThrowsError(
            try CloudDocumentBridge.updating(
                document: invalidDocument,
                blockID: blockID,
                text: "Must not be inserted",
                revision: 1,
                annotations: []
            )
        ) { error in
            XCTAssertEqual(error as? CloudDocumentError, .invalidDocument)
        }
        XCTAssertEqual(invalidDocument, .object(["future": .string("untouched")]))

        let nonpersonalBlock: CloudJSON = .object([
            "id": .string(blockID.uuidString.lowercased()),
            "kind": .string("transcript"),
            "source": .string("capture"),
            "text": .string("Authoritative transcript"),
            "revision": .number(3),
            "providerMetadata": .object(["immutable": .bool(true)]),
        ])
        let nonpersonalDocument: CloudJSON = .object([
            "blocks": .array([nonpersonalBlock]),
            "annotations": .array([]),
            "ink": .array([]),
        ])

        XCTAssertThrowsError(
            try CloudDocumentBridge.updating(
                document: nonpersonalDocument,
                blockID: blockID,
                text: "Overwrite attempt",
                revision: 4,
                annotations: []
            )
        ) { error in
            XCTAssertEqual(error as? CloudDocumentError, .invalidEditableBlock)
        }
        XCTAssertEqual(
            nonpersonalDocument,
            .object([
                "blocks": .array([nonpersonalBlock]),
                "annotations": .array([]),
                "ink": .array([]),
            ])
        )
    }
}

final class NativeLegalModelTests: XCTestCase {
    func testLegacyStoredSessionDecodesWithoutAcceptanceVersion() throws {
        let data = Data(
            #"{"token":"legacy-token","identity":{"id":"user-1","name":"Taylor","email":"taylor@example.com"}}"#.utf8
        )

        let session = try JSONDecoder().decode(StoredNativeSession.self, from: data)

        XCTAssertEqual(session.token, "legacy-token")
        XCTAssertEqual(session.identity.id, "user-1")
        XCTAssertNil(session.acceptedTermsVersion)
    }

    func testLegalStatusRequiresBothServerTimestamps() {
        let metadata = legalTestMetadata
        XCTAssertFalse(
            CloudLegalStatus(
                accepted: true,
                acceptedAt: "2026-09-09T00:00:00.000Z",
                recordingLawAcknowledgedAt: nil,
                legal: metadata
            ).confirmsCurrentTerms
        )
        XCTAssertTrue(acceptedLegalTestStatus.confirmsCurrentTerms)
    }
}

final class NativeAPILegalGateTests: XCTestCase {
    func testHTTP428ReturnsDecodedLegalMetadataAndClearsCachedAcceptance() async throws {
        let store = makeTemporaryStore()
        defer { try? store.delete() }
        try seedAcceptedSession(in: store)
        let responseData = Data(
            #"{"code":"TERMS_ACCEPTANCE_REQUIRED","error":"Review terms.","legal":{"termsVersion":"2026-09-10.1","effectiveAt":"2026-09-10T00:00:00.000Z","termsUrl":"https://sideleaf.vercel.app/terms","privacyUrl":"https://sideleaf.vercel.app/privacy","recordingLawAcknowledgement":"I understand the updated recording-law responsibilities."}}"#.utf8
        )
        let api = NativeAPI(tokenStore: store) { request in
            (responseData, try Self.response(for: request, status: 428))
        }

        do {
            _ = try await api.notebooks()
            XCTFail("Expected HTTP 428 to require terms acceptance")
        } catch NativeAPIError.termsAcceptanceRequired(let metadata) {
            XCTAssertEqual(metadata, updatedLegalTestMetadata)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertNil(try store.load()?.acceptedTermsVersion)
    }

    func testHTTP428WithFutureLegalShapeClearsCachedAcceptance() async throws {
        let store = makeTemporaryStore()
        defer { try? store.delete() }
        try seedAcceptedSession(in: store)
        let api = NativeAPI(tokenStore: store) { request in
            // The deliberately incompatible legal object makes ErrorEnvelope
            // decoding fail, and there is no code field to fall back to.
            return (
                Data(#"{"legal":{"termsVersion":42,"future":true}}"#.utf8),
                try Self.response(for: request, status: 428)
            )
        }

        do {
            _ = try await api.pages()
            XCTFail("Expected HTTP 428 to require terms acceptance")
        } catch NativeAPIError.termsAcceptanceRequired(let metadata) {
            XCTAssertNil(metadata)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertNil(try store.load()?.acceptedTermsVersion)
    }

    func testLegacyTermsCodeWithoutMetadataStillGatesAndClearsCache() async throws {
        let store = makeTemporaryStore()
        defer { try? store.delete() }
        try seedAcceptedSession(in: store)
        let api = NativeAPI(tokenStore: store) { request in
            (
                Data(#"{"code":"TERMS_ACCEPTANCE_REQUIRED"}"#.utf8),
                try Self.response(for: request, status: 409)
            )
        }

        do {
            _ = try await api.pages()
            XCTFail("Expected the legacy error code to require terms acceptance")
        } catch NativeAPIError.termsAcceptanceRequired(let metadata) {
            XCTAssertNil(metadata)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertNil(try store.load()?.acceptedTermsVersion)
    }

    func testRestoreDoesNotCarryAcceptanceAcrossChangedServerIdentity() async throws {
        let store = makeTemporaryStore()
        defer { try? store.delete() }
        let priorIdentity = CloudIdentity(id: "user-1", name: "Taylor", email: "taylor@example.com")
        let restoredIdentity = CloudIdentity(id: "user-2", name: "Morgan", email: "morgan@example.com")
        try store.save(
            StoredNativeSession(
                token: "test-token",
                identity: priorIdentity,
                acceptedTermsVersion: legalTestMetadata.termsVersion
            )
        )
        let responseData = try JSONEncoder().encode(CloudSessionEnvelope(user: restoredIdentity))
        let api = NativeAPI(tokenStore: store) { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  )
            else { throw NativeAPIError.invalidResponse }
            return (responseData, response)
        }

        let restored = try await api.restoreSession()

        XCTAssertEqual(restored, restoredIdentity)
        XCTAssertEqual(try store.load()?.identity, restoredIdentity)
        XCTAssertNil(try store.load()?.acceptedTermsVersion)
    }

    private func makeTemporaryStore() -> KeychainSessionStore {
        KeychainSessionStore(
            service: "com.thinkhale.sideleaf.tests.\(UUID().uuidString)",
            account: "native-api-legal-gate"
        )
    }

    private func seedAcceptedSession(in store: KeychainSessionStore) throws {
        try store.save(
            StoredNativeSession(
                token: "test-token",
                identity: CloudIdentity(
                    id: "user-1",
                    name: "Taylor",
                    email: "taylor@example.com"
                ),
                acceptedTermsVersion: legalTestMetadata.termsVersion
            )
        )
    }

    private static func response(for request: URLRequest, status: Int) throws -> HTTPURLResponse {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
              )
        else { throw NativeAPIError.invalidResponse }
        return response
    }
}

final class NativeAPIAccountDeletionTests: XCTestCase {
    func testDeleteAccountSendsConfirmationAndClearsSession() async throws {
        let store = makeTemporaryStore()
        defer { try? store.delete() }
        try seedSession(in: store)
        let api = NativeAPI(tokenStore: store) { request in
            guard request.httpMethod == "DELETE",
                  request.url?.path == "/api/account",
                  let body = request.httpBody,
                  let object = try JSONSerialization.jsonObject(with: body) as? [String: String],
                  object == ["confirmation": "DELETE"]
            else { throw NativeAPIError.invalidResponse }
            return (
                Data(#"{"deleted":true}"#.utf8),
                try Self.response(for: request, status: 200)
            )
        }

        _ = try await api.deleteAccount()

        XCTAssertNil(try store.load())
    }

    func testConfirmedDeletionReportsCredentialCleanupFailureWithoutThrowing() async throws {
        let store = makeTemporaryStore()
        defer { try? store.delete() }
        try seedSession(in: store)
        let api = NativeAPI(
            tokenStore: store,
            accountDeletionCredentialCleanup: {
                throw KeychainSessionStore.StoreError.keychain(-34_018)
            }
        ) { request in
            (
                Data(#"{"deleted":true}"#.utf8),
                try Self.response(for: request, status: 200)
            )
        }

        let outcome = try await api.deleteAccount()

        XCTAssertEqual(outcome, .credentialCleanupFailed)
        XCTAssertNotNil(try store.load(), "The injected Keychain failure should leave the credential")
    }

    func testDeleteAccountSurfacesRecentSignInRequirement() async throws {
        let store = makeTemporaryStore()
        defer { try? store.delete() }
        try seedSession(in: store)
        let message = "Sign out and sign in again before deleting your account."
        let api = NativeAPI(tokenStore: store) { request in
            (
                Data(#"{"error":"Sign out and sign in again before deleting your account."}"#.utf8),
                try Self.response(for: request, status: 403)
            )
        }

        do {
            _ = try await api.deleteAccount()
            XCTFail("Expected recent sign-in requirement")
        } catch NativeAPIError.server(let status, let receivedMessage) {
            XCTAssertEqual(status, 403)
            XCTAssertEqual(receivedMessage, message)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertNotNil(try store.load())
    }

    func testDeleteAccountSurfacesActiveSubscriptionRequirement() async throws {
        let store = makeTemporaryStore()
        defer { try? store.delete() }
        try seedSession(in: store)
        let message = "End your subscription before deleting the account so future billing can be stopped."
        let api = NativeAPI(tokenStore: store) { request in
            (
                Data(#"{"error":"End your subscription before deleting the account so future billing can be stopped."}"#.utf8),
                try Self.response(for: request, status: 409)
            )
        }

        do {
            _ = try await api.deleteAccount()
            XCTFail("Expected active subscription requirement")
        } catch NativeAPIError.server(let status, let receivedMessage) {
            XCTAssertEqual(status, 409)
            XCTAssertEqual(receivedMessage, message)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertNotNil(try store.load())
    }

    private func makeTemporaryStore() -> KeychainSessionStore {
        KeychainSessionStore(
            service: "com.thinkhale.sideleaf.tests.\(UUID().uuidString)",
            account: "native-api-account-deletion"
        )
    }

    private func seedSession(in store: KeychainSessionStore) throws {
        try store.save(
            StoredNativeSession(
                token: "test-token",
                identity: CloudIdentity(
                    id: "delete-user",
                    name: "Taylor",
                    email: "taylor@example.com"
                ),
                acceptedTermsVersion: legalTestMetadata.termsVersion
            )
        )
    }

    private static func response(for request: URLRequest, status: Int) throws -> HTTPURLResponse {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
              )
        else { throw NativeAPIError.invalidResponse }
        return response
    }
}

private let legalTestMetadata = CloudLegalMetadata(
    termsVersion: "2026-09-09.1",
    effectiveAt: "2026-09-09T00:00:00.000Z",
    termsUrl: "https://sideleaf.vercel.app/terms",
    privacyUrl: "https://sideleaf.vercel.app/privacy",
    recordingLawAcknowledgement: "I understand my recording-law responsibilities."
)

private let acceptedLegalTestStatus = CloudLegalStatus(
    accepted: true,
    acceptedAt: "2026-09-09T00:00:00.000Z",
    recordingLawAcknowledgedAt: "2026-09-09T00:00:00.000Z",
    legal: legalTestMetadata
)

private let requiredLegalTestStatus = CloudLegalStatus(
    accepted: false,
    acceptedAt: nil,
    recordingLawAcknowledgedAt: nil,
    legal: legalTestMetadata
)

private let updatedLegalTestMetadata = CloudLegalMetadata(
    termsVersion: "2026-09-10.1",
    effectiveAt: "2026-09-10T00:00:00.000Z",
    termsUrl: "https://sideleaf.vercel.app/terms",
    privacyUrl: "https://sideleaf.vercel.app/privacy",
    recordingLawAcknowledgement: "I understand the updated recording-law responsibilities."
)

private let updatedAcceptedLegalTestStatus = CloudLegalStatus(
    accepted: true,
    acceptedAt: "2026-09-10T00:00:00.000Z",
    recordingLawAcknowledgedAt: "2026-09-10T00:00:00.000Z",
    legal: updatedLegalTestMetadata
)

private actor AsyncTestGate {
    private var armed = false
    private var blocked = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var blockedContinuation: CheckedContinuation<Void, Never>?

    func arm() { armed = true }

    func waitIfArmed() async {
        guard armed else { return }
        armed = false
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
            blocked = true
            blockedContinuation?.resume()
            blockedContinuation = nil
        }
        blocked = false
    }

    func waitUntilBlocked() async {
        guard !blocked else { return }
        await withCheckedContinuation { continuation in
            blockedContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor LegalRaceAPI: NativeAPIProviding {
    let identity: CloudIdentity
    private let refreshGate = AsyncTestGate()
    private let saveGate = AsyncTestGate()
    private var useUpdatedTerms = false
    private var refreshThrowsTerms = false
    private var dualRefreshFailure = false
    private var completionOrderTermsFailure = false
    private var notebookRequestCount = 0
    private var saveRequestCount = 0
    private var saveCountWaiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(identity: CloudIdentity) { self.identity = identity }

    func configuration() async throws -> CloudConfiguration {
        CloudConfiguration(
            name: "Sideleaf test",
            passwordAuth: true,
            googleAuth: false,
            capture: .init(ready: true, disclosure: nil, reason: "Ready"),
            legal: useUpdatedTerms ? updatedLegalTestMetadata : legalTestMetadata
        )
    }

    func cachedIdentity() async throws -> CloudIdentity? { identity }
    func cachedAcceptedTermsVersion() async throws -> String? { legalTestMetadata.termsVersion }
    func restoreSession() async throws -> CloudIdentity? { identity }
    func signIn(email: String, password: String) async throws -> CloudIdentity { identity }
    func createAccount(name: String, email: String, password: String) async throws -> CloudIdentity {
        identity
    }
    func legalStatus() async throws -> CloudLegalStatus {
        useUpdatedTerms ? updatedAcceptedLegalTestStatus : acceptedLegalTestStatus
    }
    func acceptLegal(termsVersion: String) async throws -> CloudLegalStatus {
        useUpdatedTerms ? updatedAcceptedLegalTestStatus : acceptedLegalTestStatus
    }
    func signOut() async throws {}
    func deleteAccount() async throws -> NativeAccountDeletionOutcome { .complete }
    func notebooks() async throws -> [CloudNotebook] {
        notebookRequestCount += 1
        if dualRefreshFailure { throw NativeAPIError.transport }
        let shouldThrowTerms = refreshThrowsTerms
        if shouldThrowTerms { refreshThrowsTerms = false }
        await refreshGate.waitIfArmed()
        if shouldThrowTerms {
            throw NativeAPIError.termsAcceptanceRequired(legalTestMetadata)
        }
        return []
    }
    func createNotebook(id: UUID, name: String) async throws -> CloudNotebook {
        CloudNotebook(id: id, name: name, color: "#687354")
    }
    func pages() async throws -> [CloudPage] {
        if completionOrderTermsFailure {
            throw NativeAPIError.termsAcceptanceRequired(updatedLegalTestMetadata)
        }
        if dualRefreshFailure {
            throw NativeAPIError.termsAcceptanceRequired(updatedLegalTestMetadata)
        }
        return []
    }
    func savePage(id: UUID, write: CloudPageWrite) async throws -> CloudPage {
        saveRequestCount += 1
        let completedWaiters = saveCountWaiters.filter { saveRequestCount >= $0.target }
        saveCountWaiters.removeAll { saveRequestCount >= $0.target }
        completedWaiters.forEach { $0.continuation.resume() }
        await saveGate.waitIfArmed()
        return CloudPage(
            id: id,
            notebookID: write.notebookID,
            title: write.title,
            document: write.document,
            version: write.baseVersion + 1,
            updatedAt: "2026-09-09T00:00:00.000Z"
        )
    }

    func armRefresh() async { await refreshGate.arm() }
    func armRefreshTermsError() async {
        refreshThrowsTerms = true
        await refreshGate.arm()
    }
    func waitForRefresh() async { await refreshGate.waitUntilBlocked() }
    func releaseRefresh() async { await refreshGate.release() }
    func armSave() async { await saveGate.arm() }
    func waitForSave() async { await saveGate.waitUntilBlocked() }
    func releaseSave() async { await saveGate.release() }
    func updateTerms() { useUpdatedTerms = true }
    func enableDualRefreshFailure() { dualRefreshFailure = true }
    func armCompletionOrderTermsFailure() async {
        completionOrderTermsFailure = true
        await refreshGate.arm()
    }
    func notebookRequests() -> Int { notebookRequestCount }
    func waitForSaveRequestCount(_ target: Int) async {
        guard saveRequestCount < target else { return }
        await withCheckedContinuation { continuation in
            saveCountWaiters.append((target, continuation))
        }
    }
}

private actor RestoreVersionRaceAPI: NativeAPIProviding {
    enum RestoreOutcome: Sendable {
        case identity
        case transportFailure
    }

    let identity: CloudIdentity
    let cachedIdentityValue: CloudIdentity
    let restoreOutcome: RestoreOutcome
    let cachedTermsVersion: String?
    let configuredLegal: CloudLegalMetadata
    let restoredLegalStatus: CloudLegalStatus
    let legalStatusError: NativeAPIError?
    private let restoreGate = AsyncTestGate()

    init(
        identity: CloudIdentity,
        restoreOutcome: RestoreOutcome,
        cachedIdentity: CloudIdentity? = nil,
        cachedTermsVersion: String? = legalTestMetadata.termsVersion,
        configuredLegal: CloudLegalMetadata = updatedLegalTestMetadata,
        restoredLegalStatus: CloudLegalStatus = acceptedLegalTestStatus,
        legalStatusError: NativeAPIError? = nil
    ) {
        self.identity = identity
        cachedIdentityValue = cachedIdentity ?? identity
        self.restoreOutcome = restoreOutcome
        self.cachedTermsVersion = cachedTermsVersion
        self.configuredLegal = configuredLegal
        self.restoredLegalStatus = restoredLegalStatus
        self.legalStatusError = legalStatusError
    }

    func configuration() async throws -> CloudConfiguration {
        CloudConfiguration(
            name: "Sideleaf test",
            passwordAuth: true,
            googleAuth: false,
            capture: .init(ready: true, disclosure: nil, reason: "Ready"),
            legal: configuredLegal
        )
    }

    func cachedIdentity() async throws -> CloudIdentity? { cachedIdentityValue }
    func cachedAcceptedTermsVersion() async throws -> String? { cachedTermsVersion }
    func restoreSession() async throws -> CloudIdentity? {
        await restoreGate.waitIfArmed()
        switch restoreOutcome {
        case .identity: return identity
        case .transportFailure: throw NativeAPIError.transport
        }
    }
    func signIn(email: String, password: String) async throws -> CloudIdentity { identity }
    func createAccount(name: String, email: String, password: String) async throws -> CloudIdentity {
        identity
    }
    func legalStatus() async throws -> CloudLegalStatus {
        if let legalStatusError { throw legalStatusError }
        return restoredLegalStatus
    }
    func acceptLegal(termsVersion: String) async throws -> CloudLegalStatus {
        updatedAcceptedLegalTestStatus
    }
    func signOut() async throws {}
    func deleteAccount() async throws -> NativeAccountDeletionOutcome { .complete }
    func notebooks() async throws -> [CloudNotebook] { [] }
    func createNotebook(id: UUID, name: String) async throws -> CloudNotebook {
        CloudNotebook(id: id, name: name, color: "#687354")
    }
    func pages() async throws -> [CloudPage] { [] }
    func savePage(id: UUID, write: CloudPageWrite) async throws -> CloudPage {
        throw NativeAPIError.transport
    }

    func armRestore() async { await restoreGate.arm() }
    func waitForRestore() async { await restoreGate.waitUntilBlocked() }
    func releaseRestore() async { await restoreGate.release() }
}

private actor LegalFlowAPI: NativeAPIProviding {
    let identity: CloudIdentity
    let acceptanceFails: Bool
    private(set) var createAccountCalls = 0

    init(identity: CloudIdentity, acceptanceFails: Bool = false) {
        self.identity = identity
        self.acceptanceFails = acceptanceFails
    }

    func configuration() async throws -> CloudConfiguration {
        CloudConfiguration(
            name: "Sideleaf test",
            passwordAuth: true,
            googleAuth: false,
            capture: .init(ready: true, disclosure: nil, reason: "Ready"),
            legal: legalTestMetadata
        )
    }

    func cachedIdentity() async throws -> CloudIdentity? { identity }
    func cachedAcceptedTermsVersion() async throws -> String? { nil }
    func restoreSession() async throws -> CloudIdentity? { identity }
    func signIn(email: String, password: String) async throws -> CloudIdentity { identity }
    func createAccount(name: String, email: String, password: String) async throws -> CloudIdentity {
        createAccountCalls += 1
        return identity
    }
    func legalStatus() async throws -> CloudLegalStatus { requiredLegalTestStatus }
    func acceptLegal(termsVersion: String) async throws -> CloudLegalStatus {
        if acceptanceFails { throw NativeAPIError.transport }
        return acceptedLegalTestStatus
    }
    func signOut() async throws {}
    func deleteAccount() async throws -> NativeAccountDeletionOutcome { .complete }
    func notebooks() async throws -> [CloudNotebook] { [] }
    func createNotebook(id: UUID, name: String) async throws -> CloudNotebook {
        CloudNotebook(id: id, name: name, color: "#687354")
    }
    func pages() async throws -> [CloudPage] { [] }
    func savePage(id: UUID, write: CloudPageWrite) async throws -> CloudPage {
        throw NativeAPIError.transport
    }
    func createAccountCallCount() -> Int { createAccountCalls }
}

private actor AccountDeletionAPI: NativeAPIProviding {
    let identity: CloudIdentity
    let legalStatusValue: CloudLegalStatus
    let deletionError: NativeAPIError?
    let deletionOutcome: NativeAccountDeletionOutcome
    private(set) var deletionCalls = 0

    init(
        identity: CloudIdentity,
        legalStatus: CloudLegalStatus = acceptedLegalTestStatus,
        deletionError: NativeAPIError? = nil,
        deletionOutcome: NativeAccountDeletionOutcome = .complete
    ) {
        self.identity = identity
        legalStatusValue = legalStatus
        self.deletionError = deletionError
        self.deletionOutcome = deletionOutcome
    }

    func configuration() async throws -> CloudConfiguration {
        CloudConfiguration(
            name: "Sideleaf test",
            passwordAuth: true,
            googleAuth: false,
            capture: .init(ready: true, disclosure: nil, reason: "Ready"),
            legal: legalTestMetadata
        )
    }
    func cachedIdentity() async throws -> CloudIdentity? { identity }
    func cachedAcceptedTermsVersion() async throws -> String? { legalTestMetadata.termsVersion }
    func restoreSession() async throws -> CloudIdentity? { identity }
    func signIn(email: String, password: String) async throws -> CloudIdentity { identity }
    func createAccount(name: String, email: String, password: String) async throws -> CloudIdentity {
        identity
    }
    func legalStatus() async throws -> CloudLegalStatus { legalStatusValue }
    func acceptLegal(termsVersion: String) async throws -> CloudLegalStatus { acceptedLegalTestStatus }
    func signOut() async throws {}
    func deleteAccount() async throws -> NativeAccountDeletionOutcome {
        deletionCalls += 1
        if let deletionError { throw deletionError }
        return deletionOutcome
    }
    func notebooks() async throws -> [CloudNotebook] { [] }
    func createNotebook(id: UUID, name: String) async throws -> CloudNotebook {
        CloudNotebook(id: id, name: name, color: "#687354")
    }
    func pages() async throws -> [CloudPage] { [] }
    func savePage(id: UUID, write: CloudPageWrite) async throws -> CloudPage {
        throw NativeAPIError.transport
    }
    func deletionCallCount() -> Int { deletionCalls }
}

@MainActor
final class NotebookSyncLegalTests: XCTestCase {
    func testRestoreRequiresTermsWithoutHidingAccountDeviceCopies() async throws {
        let identity = CloudIdentity(id: "legal-user", name: "Taylor", email: "taylor@example.com")
        let api = LegalFlowAPI(identity: identity)
        let (context, page) = try makeContext(ownerID: identity.id)
        let sync = NotebookSync(api: api)

        await sync.restore(context: context)

        XCTAssertEqual(sync.account, .termsRequired(identity, offline: false))
        XCTAssertEqual(sync.visiblePages(from: [page]).map(\.id), [page.id])
        XCTAssertFalse(sync.isConnected)
        XCTAssertFalse(sync.canUseLiveTranscription)
    }

    func testAcceptanceFailureRetainsAuthenticatedTermsGate() async throws {
        let identity = CloudIdentity(id: "legal-user", name: "Taylor", email: "taylor@example.com")
        let api = LegalFlowAPI(identity: identity, acceptanceFails: true)
        let (context, _) = try makeContext(ownerID: identity.id)
        let sync = NotebookSync(api: api)
        await sync.restore(context: context)

        let accepted = await sync.acceptTerms(
            acceptedTerms: true,
            recordingLawAcknowledged: true,
            context: context
        )

        XCTAssertFalse(accepted)
        XCTAssertEqual(sync.account, .termsRequired(identity, offline: false))
        XCTAssertEqual(sync.identity, identity)
        XCTAssertFalse(sync.canUseLiveTranscription)
        XCTAssertEqual(
            sync.accountError,
            "Sideleaf could not reach the notebook server. Your draft remains on this device."
        )
    }

    func testAcceptanceEnablesSyncAndLiveTranscription() async throws {
        let identity = CloudIdentity(id: "legal-user", name: "Taylor", email: "taylor@example.com")
        let api = LegalFlowAPI(identity: identity)
        let (context, _) = try makeContext(ownerID: identity.id)
        let sync = NotebookSync(api: api)
        await sync.restore(context: context)

        let accepted = await sync.acceptTerms(
            acceptedTerms: true,
            recordingLawAcknowledged: true,
            context: context
        )

        XCTAssertTrue(accepted)
        XCTAssertEqual(sync.account, .signedIn(identity))
        XCTAssertEqual(sync.acceptedTermsVersion, legalTestMetadata.termsVersion)
        XCTAssertTrue(sync.canUseLiveTranscription)
    }

    func testSignInChecksExistingUsersTermsBeforeSync() async throws {
        let identity = CloudIdentity(id: "legal-user", name: "Taylor", email: "taylor@example.com")
        let api = LegalFlowAPI(identity: identity)
        let (context, _) = try makeContext(ownerID: identity.id)
        let sync = NotebookSync(api: api)

        let signedIn = await sync.signIn(
            email: identity.email,
            password: "long-password",
            context: context
        )

        XCTAssertTrue(signedIn)
        XCTAssertEqual(sync.account, .termsRequired(identity, offline: false))
        XCTAssertFalse(sync.isConnected)
    }

    func testCreateAccountKeepsSessionWhenAcceptanceRequestFails() async throws {
        let identity = CloudIdentity(id: "legal-user", name: "Taylor", email: "taylor@example.com")
        let api = LegalFlowAPI(identity: identity, acceptanceFails: true)
        let (context, _) = try makeContext(ownerID: nil)
        let sync = NotebookSync(api: api)

        let created = await sync.createAccount(
            name: identity.name,
            email: identity.email,
            password: "long-password",
            acceptedTerms: true,
            recordingLawAcknowledged: true,
            context: context
        )

        XCTAssertFalse(created)
        XCTAssertEqual(sync.identity, identity)
        XCTAssertEqual(sync.account, .termsRequired(identity, offline: false))
    }

    func testCreateAccountRejectsMissingAcknowledgementBeforeCallingAPI() async throws {
        let identity = CloudIdentity(id: "legal-user", name: "Taylor", email: "taylor@example.com")
        let api = LegalFlowAPI(identity: identity)
        let (context, _) = try makeContext(ownerID: nil)
        let sync = NotebookSync(api: api)

        let created = await sync.createAccount(
            name: "Taylor",
            email: "taylor@example.com",
            password: "long-password",
            acceptedTerms: true,
            recordingLawAcknowledged: false,
            context: context
        )

        XCTAssertFalse(created)
        let createAccountCalls = await api.createAccountCallCount()
        XCTAssertEqual(createAccountCalls, 0)
    }

    private func makeContext(ownerID: String?) throws -> (ModelContext, LocalPage) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: LocalPage.self, configurations: configuration)
        let context = container.mainContext
        let page = LocalPage(title: "Device copy")
        page.ownerUserID = ownerID
        context.insert(page)
        try context.save()
        return (context, page)
    }
}

@MainActor
final class NotebookSyncAccountDeletionTests: XCTestCase {
    func testDeletionFromTermsGateRemovesOnlyDeletedAccountsCachedPages() async throws {
        let identity = CloudIdentity(id: "delete-user", name: "Taylor", email: "taylor@example.com")
        let api = AccountDeletionAPI(identity: identity, legalStatus: requiredLegalTestStatus)
        let container = try ModelContainer(
            for: LocalPage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let accountPage = LocalPage(title: "Delete me")
        accountPage.ownerUserID = identity.id
        let guestPage = LocalPage(title: "Keep guest")
        let otherAccountPage = LocalPage(title: "Keep other account")
        otherAccountPage.ownerUserID = "another-user"
        [accountPage, guestPage, otherAccountPage].forEach(context.insert)
        try context.save()
        let sync = NotebookSync(api: api)
        await sync.restore(context: context)
        XCTAssertTrue(sync.requiresTermsAcceptance)

        let deleted = await sync.deleteAccount(context: context)

        XCTAssertTrue(deleted)
        XCTAssertEqual(sync.account, .signedOut)
        let remainingIDs = Set(try context.fetch(FetchDescriptor<LocalPage>()).map(\.id))
        XCTAssertFalse(remainingIDs.contains(accountPage.id))
        XCTAssertTrue(remainingIDs.contains(guestPage.id))
        XCTAssertTrue(remainingIDs.contains(otherAccountPage.id))
        let deletionCalls = await api.deletionCallCount()
        XCTAssertEqual(deletionCalls, 1)
    }

    func testCredentialCleanupFailureStillSignsOutAndPurgesAccountPages() async throws {
        let identity = CloudIdentity(id: "delete-user", name: "Taylor", email: "taylor@example.com")
        let api = AccountDeletionAPI(
            identity: identity,
            deletionOutcome: .credentialCleanupFailed
        )
        let container = try ModelContainer(
            for: LocalPage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let accountPage = LocalPage(title: "Delete despite Keychain failure")
        accountPage.ownerUserID = identity.id
        let guestPage = LocalPage(title: "Keep guest")
        [accountPage, guestPage].forEach(context.insert)
        try context.save()
        let sync = NotebookSync(api: api)
        await sync.restore(context: context)

        let deleted = await sync.deleteAccount(context: context)

        XCTAssertTrue(deleted, "Confirmed remote deletion remains successful")
        XCTAssertEqual(sync.account, .signedOut)
        let remainingIDs = Set(try context.fetch(FetchDescriptor<LocalPage>()).map(\.id))
        XCTAssertFalse(remainingIDs.contains(accountPage.id))
        XCTAssertTrue(remainingIDs.contains(guestPage.id))
        XCTAssertTrue(sync.accountError?.contains("account and its cached pages were deleted") == true)
    }

    func testFailedCachedPageCleanupCanRetryWithoutRepeatingRemoteDeletion() async throws {
        let identity = CloudIdentity(id: "delete-user", name: "Taylor", email: "taylor@example.com")
        let api = AccountDeletionAPI(identity: identity)
        let container = try ModelContainer(
            for: LocalPage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let accountPage = LocalPage(title: "Remove on retry")
        accountPage.ownerUserID = identity.id
        let guestPage = LocalPage(title: "Keep guest")
        [accountPage, guestPage].forEach(context.insert)
        try context.save()
        var cleanupSaveAttempts = 0
        let sync = NotebookSync(
            api: api,
            saveDeletedAccountPageChanges: { context in
                cleanupSaveAttempts += 1
                if cleanupSaveAttempts == 1 { throw NativeAPIError.transport }
                try context.save()
            }
        )
        await sync.restore(context: context)

        let initialCleanup = await sync.deleteAccount(context: context)

        XCTAssertFalse(initialCleanup)
        XCTAssertEqual(sync.account, .signedOut)
        XCTAssertTrue(sync.hasPendingDeletedAccountPageCleanup)
        XCTAssertTrue(sync.accountError?.contains("Retry removing the cached pages") == true)

        let retryCleanup = sync.retryDeletedAccountPageCleanup(context: context)

        XCTAssertTrue(retryCleanup)
        XCTAssertFalse(sync.hasPendingDeletedAccountPageCleanup)
        XCTAssertNil(sync.accountError)
        let remainingIDs = Set(try context.fetch(FetchDescriptor<LocalPage>()).map(\.id))
        XCTAssertFalse(remainingIDs.contains(accountPage.id))
        XCTAssertTrue(remainingIDs.contains(guestPage.id))
        XCTAssertEqual(cleanupSaveAttempts, 2)
        let deletionCalls = await api.deletionCallCount()
        XCTAssertEqual(deletionCalls, 1, "A local cleanup retry must not delete the account again")
    }

    func testDeletionFailurePreservesSessionPagesAndServerMessage() async throws {
        let identity = CloudIdentity(id: "delete-user", name: "Taylor", email: "taylor@example.com")
        let message = "End your subscription before deleting the account so future billing can be stopped."
        let api = AccountDeletionAPI(
            identity: identity,
            deletionError: .server(status: 409, message: message)
        )
        let container = try ModelContainer(
            for: LocalPage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let accountPage = LocalPage(title: "Keep on failure")
        accountPage.ownerUserID = identity.id
        context.insert(accountPage)
        try context.save()
        let sync = NotebookSync(api: api)
        await sync.restore(context: context)

        let deleted = await sync.deleteAccount(context: context)

        XCTAssertFalse(deleted)
        XCTAssertEqual(sync.account, .signedIn(identity))
        XCTAssertEqual(sync.accountError, message)
        XCTAssertNotNil(
            try context.fetch(FetchDescriptor<LocalPage>()).first { $0.id == accountPage.id }
        )
    }
}

@MainActor
final class NotebookSyncLegalRaceTests: XCTestCase {
    func testRestoredDifferentIdentityCannotReuseCachedAcceptanceWhenLegalCheckFails() async throws {
        let cachedIdentity = CloudIdentity(
            id: "cached-user",
            name: "Taylor",
            email: "taylor@example.com"
        )
        let restoredIdentity = CloudIdentity(
            id: "restored-user",
            name: "Morgan",
            email: "morgan@example.com"
        )
        let api = RestoreVersionRaceAPI(
            identity: restoredIdentity,
            restoreOutcome: .identity,
            cachedIdentity: cachedIdentity,
            configuredLegal: legalTestMetadata,
            legalStatusError: .transport
        )
        let context = try makeContext()
        let sync = NotebookSync(api: api)

        await sync.restore(context: context)

        XCTAssertEqual(sync.identity, restoredIdentity)
        XCTAssertEqual(sync.account, .termsRequired(restoredIdentity, offline: true))
        XCTAssertNil(sync.acceptedTermsVersion)
        XCTAssertFalse(sync.canUseLiveTranscription)
    }

    func testCompletedTermsFailureGatesBeforeSlowerRefreshSiblingFinishes() async throws {
        let identity = CloudIdentity(id: "race-user", name: "Taylor", email: "taylor@example.com")
        let api = LegalRaceAPI(identity: identity)
        let context = try makeContext()
        let sync = NotebookSync(api: api)
        await sync.restore(context: context)
        XCTAssertTrue(sync.canUseLiveTranscription)

        await api.armCompletionOrderTermsFailure()
        let refresh = Task { @MainActor in await sync.refresh(context: context) }
        await api.waitForRefresh()
        for _ in 0..<100 where !sync.requiresTermsAcceptance {
            await Task.yield()
        }
        let gatedBeforeSlowRequestFinished = sync.requiresTermsAcceptance
            && !sync.canUseLiveTranscription

        await api.releaseRefresh()
        await refresh.value

        XCTAssertTrue(gatedBeforeSlowRequestFinished)
        XCTAssertEqual(sync.account, .termsRequired(identity, offline: false))
        XCTAssertEqual(sync.legalMetadata, updatedLegalTestMetadata)
    }

    func testLegacyAcceptanceDoesNotAutoPresentWhileServerVerificationIsPending() async throws {
        let identity = CloudIdentity(id: "race-user", name: "Taylor", email: "taylor@example.com")
        let api = RestoreVersionRaceAPI(
            identity: identity,
            restoreOutcome: .identity,
            cachedTermsVersion: nil,
            configuredLegal: legalTestMetadata,
            restoredLegalStatus: acceptedLegalTestStatus
        )
        await api.armRestore()
        let context = try makeContext()
        let sync = NotebookSync(api: api)

        let restore = Task { @MainActor in await sync.restore(context: context) }
        await api.waitForRestore()

        XCTAssertTrue(sync.isVerifyingRestoredSession)
        XCTAssertTrue(sync.requiresTermsAcceptance)
        XCTAssertFalse(sync.shouldPresentTermsAcceptance)
        XCTAssertEqual(sync.identity, identity)
        XCTAssertFalse(sync.canUseLiveTranscription)

        await api.releaseRestore()
        await restore.value

        XCTAssertFalse(sync.isVerifyingRestoredSession)
        XCTAssertFalse(sync.shouldPresentTermsAcceptance)
        XCTAssertEqual(sync.account, .signedIn(identity))
    }

    func testRefreshPrioritizesTermsGateWhenParallelRequestAlsoFailsTransport() async throws {
        let identity = CloudIdentity(id: "race-user", name: "Taylor", email: "taylor@example.com")
        let api = LegalRaceAPI(identity: identity)
        let context = try makeContext()
        let sync = NotebookSync(api: api)
        await sync.restore(context: context)
        XCTAssertTrue(sync.canUseLiveTranscription)

        await api.enableDualRefreshFailure()
        await sync.refresh(context: context)

        XCTAssertEqual(sync.account, .termsRequired(identity, offline: false))
        XCTAssertEqual(sync.legalMetadata, updatedLegalTestMetadata)
        XCTAssertNil(sync.acceptedTermsVersion)
        XCTAssertFalse(sync.canUseLiveTranscription)
    }

    func testStaleRefreshCompletionCannotEscapeTermsGate() async throws {
        let identity = CloudIdentity(id: "race-user", name: "Taylor", email: "taylor@example.com")
        let api = LegalRaceAPI(identity: identity)
        let context = try makeContext()
        let sync = NotebookSync(api: api)
        await sync.restore(context: context)
        XCTAssertEqual(sync.account, .signedIn(identity))

        await api.armRefresh()
        let refresh = Task { @MainActor in await sync.refresh(context: context) }
        await api.waitForRefresh()
        await api.updateTerms()
        let loadedLegalMetadata = await sync.loadLegalMetadata()
        XCTAssertTrue(loadedLegalMetadata)
        XCTAssertEqual(sync.account, .termsRequired(identity, offline: false))

        await api.releaseRefresh()
        await refresh.value

        XCTAssertEqual(sync.account, .termsRequired(identity, offline: false))
        XCTAssertNil(sync.acceptedTermsVersion)
        XCTAssertFalse(sync.canUseLiveTranscription)
    }

    func testStaleTermsErrorCannotRevokeNewAcceptanceAndFreshRefreshStarts() async throws {
        let identity = CloudIdentity(id: "race-user", name: "Taylor", email: "taylor@example.com")
        let api = LegalRaceAPI(identity: identity)
        let context = try makeContext()
        let sync = NotebookSync(api: api)
        await sync.restore(context: context)

        await api.armRefreshTermsError()
        let staleRefresh = Task { @MainActor in await sync.refresh(context: context) }
        await api.waitForRefresh()
        await api.updateTerms()
        let loadedLegalMetadata = await sync.loadLegalMetadata()
        XCTAssertTrue(loadedLegalMetadata)
        XCTAssertEqual(sync.account, .termsRequired(identity, offline: false))

        let accepted = await sync.acceptTerms(
            acceptedTerms: true,
            recordingLawAcknowledged: true,
            context: context
        )
        XCTAssertTrue(accepted)
        XCTAssertEqual(sync.account, .signedIn(identity))
        XCTAssertEqual(sync.acceptedTermsVersion, updatedLegalTestMetadata.termsVersion)
        let notebookRequests = await api.notebookRequests()
        XCTAssertGreaterThanOrEqual(notebookRequests, 3)

        await api.releaseRefresh()
        await staleRefresh.value

        XCTAssertEqual(sync.account, .signedIn(identity))
        XCTAssertEqual(sync.acceptedTermsVersion, updatedLegalTestMetadata.termsVersion)
        XCTAssertTrue(sync.canUseLiveTranscription)
    }

    func testStaleSaveCompletionCannotEscapeTermsGateOrClearMutation() async throws {
        let identity = CloudIdentity(id: "race-user", name: "Taylor", email: "taylor@example.com")
        let api = LegalRaceAPI(identity: identity)
        let context = try makeContext()
        let sync = NotebookSync(api: api)
        await sync.restore(context: context)

        let page = LocalPage(title: "Pending page")
        page.ownerUserID = identity.id
        page.notebookID = UUID()
        page.serverVersion = 1
        page.cloudBlockID = page.id
        let pendingMutationID = UUID()
        page.pendingMutationID = pendingMutationID
        context.insert(page)
        try context.save()

        await api.armSave()
        let save = Task { @MainActor in await sync.syncNow(page, context: context) }
        await api.waitForSave()
        await api.updateTerms()
        let loadedLegalMetadata = await sync.loadLegalMetadata()
        XCTAssertTrue(loadedLegalMetadata)
        XCTAssertEqual(sync.account, .termsRequired(identity, offline: false))

        await api.releaseSave()
        await save.value

        XCTAssertEqual(sync.account, .termsRequired(identity, offline: false))
        XCTAssertEqual(page.pendingMutationID, pendingMutationID)
        XCTAssertEqual(page.serverVersion, 1)
    }

    func testStaleSaveIsRetriedAfterAcceptingUpdatedTerms() async throws {
        let identity = CloudIdentity(id: "race-user", name: "Taylor", email: "taylor@example.com")
        let api = LegalRaceAPI(identity: identity)
        let context = try makeContext()
        let sync = NotebookSync(api: api)
        await sync.restore(context: context)

        let page = LocalPage(title: "Pending page")
        page.ownerUserID = identity.id
        page.notebookID = UUID()
        page.serverVersion = 1
        page.cloudBlockID = page.id
        page.pendingMutationID = UUID()
        context.insert(page)
        try context.save()

        await api.armSave()
        let staleSave = Task { @MainActor in await sync.syncNow(page, context: context) }
        await api.waitForSave()
        await api.updateTerms()
        let loadedLegalMetadata = await sync.loadLegalMetadata()
        XCTAssertTrue(loadedLegalMetadata)
        let accepted = await sync.acceptTerms(
            acceptedTerms: true,
            recordingLawAcknowledged: true,
            context: context
        )
        XCTAssertTrue(accepted)

        await api.releaseSave()
        await staleSave.value
        await api.waitForSaveRequestCount(2)
        for _ in 0..<100 where page.pendingMutationID != nil {
            await Task.yield()
        }

        XCTAssertEqual(sync.account, .signedIn(identity))
        XCTAssertNil(page.pendingMutationID)
        XCTAssertEqual(page.serverVersion, 2)
    }

    func testConfiguredTermsVersionWinsOverDelayedOlderLegalStatus() async throws {
        let identity = CloudIdentity(id: "race-user", name: "Taylor", email: "taylor@example.com")
        let api = RestoreVersionRaceAPI(identity: identity, restoreOutcome: .identity)
        await api.armRestore()
        let context = try makeContext()
        let sync = NotebookSync(api: api)

        let restore = Task { @MainActor in await sync.restore(context: context) }
        await api.waitForRestore()
        for _ in 0..<100 where sync.legalMetadata != updatedLegalTestMetadata {
            await Task.yield()
        }
        XCTAssertEqual(sync.legalMetadata, updatedLegalTestMetadata)
        await api.releaseRestore()
        await restore.value

        XCTAssertEqual(sync.account, .termsRequired(identity, offline: false))
        XCTAssertEqual(sync.legalMetadata, updatedLegalTestMetadata)
        XCTAssertNil(sync.acceptedTermsVersion)
        XCTAssertFalse(sync.canUseLiveTranscription)
    }

    func testRestoreTransportFallbackCannotReactivateCachedOlderTerms() async throws {
        let identity = CloudIdentity(id: "race-user", name: "Taylor", email: "taylor@example.com")
        let api = RestoreVersionRaceAPI(identity: identity, restoreOutcome: .transportFailure)
        await api.armRestore()
        let context = try makeContext()
        let sync = NotebookSync(api: api)

        let restore = Task { @MainActor in await sync.restore(context: context) }
        await api.waitForRestore()
        for _ in 0..<100 where sync.legalMetadata != updatedLegalTestMetadata {
            await Task.yield()
        }
        XCTAssertEqual(sync.legalMetadata, updatedLegalTestMetadata)
        await api.releaseRestore()
        await restore.value

        XCTAssertEqual(sync.account, .termsRequired(identity, offline: true))
        XCTAssertNil(sync.acceptedTermsVersion)
        XCTAssertFalse(sync.canUseLiveTranscription)
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: LocalPage.self, configurations: configuration)
        return container.mainContext
    }
}

private actor StaleRefreshAPI: NativeAPIProviding {
    let identity: CloudIdentity
    let notebook: CloudNotebook
    let remotePages: [CloudPage]

    init(identity: CloudIdentity, notebook: CloudNotebook, remotePages: [CloudPage]) {
        self.identity = identity
        self.notebook = notebook
        self.remotePages = remotePages
    }

    func configuration() async throws -> CloudConfiguration {
        CloudConfiguration(
            name: "Sideleaf test",
            passwordAuth: true,
            googleAuth: false,
            capture: .init(ready: true, disclosure: nil, reason: "Ready"),
            legal: legalTestMetadata
        )
    }

    func cachedIdentity() async throws -> CloudIdentity? { identity }
    func cachedAcceptedTermsVersion() async throws -> String? { legalTestMetadata.termsVersion }
    func restoreSession() async throws -> CloudIdentity? { identity }
    func signIn(email: String, password: String) async throws -> CloudIdentity { identity }
    func createAccount(name: String, email: String, password: String) async throws -> CloudIdentity {
        identity
    }
    func legalStatus() async throws -> CloudLegalStatus { acceptedLegalTestStatus }
    func acceptLegal(termsVersion: String) async throws -> CloudLegalStatus {
        acceptedLegalTestStatus
    }
    func signOut() async throws {}
    func deleteAccount() async throws -> NativeAccountDeletionOutcome { .complete }
    func notebooks() async throws -> [CloudNotebook] { [notebook] }
    func createNotebook(id: UUID, name: String) async throws -> CloudNotebook { notebook }
    func pages() async throws -> [CloudPage] { remotePages }
    func savePage(id: UUID, write: CloudPageWrite) async throws -> CloudPage {
        throw NativeAPIError.transport
    }

}

@MainActor
final class NotebookSyncRefreshTests: XCTestCase {
    func testRefreshNeverRegressesVersionAndFreshCloudClearsMissingTranscript() async throws {
        let identity = CloudIdentity(id: "native-test-user", name: "Tester", email: "test@example.com")
        let notebook = CloudNotebook(id: UUID(), name: "Work", color: "#687354")
        let stalePageID = UUID()
        let staleBlockID = UUID()
        let freshPageID = UUID()
        let freshBlockID = UUID()

        let staleRemoteDocument = try CloudDocumentBridge.updating(
            document: nil,
            blockID: staleBlockID,
            text: "Older cloud text",
            revision: 1,
            annotations: []
        )
        let latestLocalDocument = try CloudDocumentBridge.updating(
            document: nil,
            blockID: staleBlockID,
            text: "Latest device text",
            revision: 2,
            annotations: []
        )
        let freshRemoteDocument = try CloudDocumentBridge.updating(
            document: nil,
            blockID: freshBlockID,
            text: "Fresh cloud text",
            revision: 2,
            annotations: []
        )
        let api = StaleRefreshAPI(
            identity: identity,
            notebook: notebook,
            remotePages: [
                CloudPage(
                    id: stalePageID,
                    notebookID: notebook.id,
                    title: "Older cloud title",
                    document: staleRemoteDocument,
                    version: 1,
                    updatedAt: "2025-01-02T03:04:05Z"
                ),
                CloudPage(
                    id: freshPageID,
                    notebookID: notebook.id,
                    title: "Fresh cloud title",
                    document: freshRemoteDocument,
                    version: 2,
                    updatedAt: "2025-01-02T03:04:05Z"
                ),
            ]
        )

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: LocalPage.self, configurations: configuration)
        let context = container.mainContext

        let latestLocal = LocalPage(id: stalePageID, title: "Latest device title")
        latestLocal.text = "Latest device text"
        latestLocal.textRevision = 2
        latestLocal.ownerUserID = identity.id
        latestLocal.notebookID = notebook.id
        latestLocal.serverVersion = 2
        latestLocal.cloudBlockID = staleBlockID
        latestLocal.cloudDocumentData = try CloudDocumentBridge.encode(latestLocalDocument)
        context.insert(latestLocal)

        let transcriptToClear = LocalPage(id: freshPageID, title: "Older local title")
        transcriptToClear.text = "Older local text"
        transcriptToClear.ownerUserID = identity.id
        transcriptToClear.notebookID = notebook.id
        transcriptToClear.serverVersion = 1
        transcriptToClear.cloudBlockID = freshBlockID
        transcriptToClear.localTranscript = "No longer in the cloud"
        transcriptToClear.transcriptBlockID = UUID()
        context.insert(transcriptToClear)
        try context.save()

        let sync = NotebookSync(api: api)
        await sync.restore(context: context)

        XCTAssertEqual(latestLocal.serverVersion, 2)
        XCTAssertEqual(latestLocal.title, "Latest device title")
        XCTAssertEqual(latestLocal.text, "Latest device text")
        XCTAssertEqual(latestLocal.cloudDocumentData, try CloudDocumentBridge.encode(latestLocalDocument))
        XCTAssertEqual(transcriptToClear.serverVersion, 2)
        XCTAssertEqual(transcriptToClear.title, "Fresh cloud title")
        XCTAssertEqual(transcriptToClear.localTranscript, nil)
        XCTAssertEqual(transcriptToClear.transcriptBlockID, nil)
    }
}
