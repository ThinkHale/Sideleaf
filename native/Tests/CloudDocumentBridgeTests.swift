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
            capture: .init(ready: true, disclosure: nil, reason: "Ready")
        )
    }

    func cachedIdentity() async throws -> CloudIdentity? { identity }
    func restoreSession() async throws -> CloudIdentity? { identity }
    func signIn(email: String, password: String) async throws -> CloudIdentity { identity }
    func createAccount(name: String, email: String, password: String) async throws -> CloudIdentity {
        identity
    }
    func signOut() async throws {}
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
