import Foundation

/// A Sendable JSON tree used to round-trip notebook documents without flattening
/// web-only blocks, preparation fields, ink, or future schema additions.
enum CloudJSON: Codable, Equatable, Sendable {
    case object([String: CloudJSON])
    case array([CloudJSON])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([CloudJSON].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: CloudJSON].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var objectValue: [String: CloudJSON]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var arrayValue: [CloudJSON]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var integerValue: Int? {
        guard case .number(let value) = self else { return nil }
        return Int(exactly: value)
    }
}

struct CloudIdentity: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let email: String
}

struct CloudSessionEnvelope: Codable, Sendable {
    let user: CloudIdentity
}

struct CloudAuthEnvelope: Codable, Sendable {
    let user: CloudIdentity
}

struct CloudNotebook: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let color: String
}

struct CloudPage: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let notebookID: UUID
    let title: String
    let document: CloudJSON
    let version: Int
    let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case id
        case notebookID = "notebookId"
        case title
        case document
        case version
        case updatedAt
    }
}

struct CloudPageWrite: Codable, Equatable, Sendable {
    let title: String
    let notebookID: UUID
    let document: CloudJSON
    let baseVersion: Int
    let mutationID: UUID

    private enum CodingKeys: String, CodingKey {
        case title
        case notebookID = "notebookId"
        case document
        case baseVersion
        case mutationID = "mutationId"
    }
}

struct CloudConfiguration: Codable, Equatable, Sendable {
    struct Capture: Codable, Equatable, Sendable {
        let ready: Bool
        let disclosure: String?
        let reason: String
    }

    let name: String
    let passwordAuth: Bool
    let googleAuth: Bool
    let capture: Capture
}

enum CloudDocumentError: Error, LocalizedError, Equatable {
    case invalidDocument
    case invalidEditableBlock

    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            "The cloud page has an unsupported document format. It remains unchanged."
        case .invalidEditableBlock:
            "The selected cloud text block is not editable. It remains unchanged."
        }
    }
}

struct CloudEditableContent: Equatable, Sendable {
    let blockID: UUID
    let text: String
    let revision: Int
    let annotations: [NativeAnnotation]
    let transcriptBlockID: UUID?
    let transcript: String?
}

enum CloudDocumentBridge {
    static let transcriptMarker = "[Sideleaf on-device transcript]\n"

    static func decode(_ data: Data) throws -> CloudJSON {
        try JSONDecoder().decode(CloudJSON.self, from: data)
    }

    static func encode(_ document: CloudJSON) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(document)
    }

    /// Picks one stable personal block for the native single-buffer editor. All
    /// other blocks remain opaque and are preserved on the next write.
    static func editableContent(
        in document: CloudJSON,
        preferredBlockID: UUID?,
        preferredTranscriptBlockID: UUID? = nil,
        localPageID: UUID
    ) throws -> CloudEditableContent {
        guard let root = document.objectValue,
              let blocks = root["blocks"]?.arrayValue
        else { throw CloudDocumentError.invalidDocument }

        let preferred = blocks.first { block in
            guard let preferredBlockID else { return false }
            guard let object = block.objectValue else { return false }
            return object["id"]?.stringValue.flatMap(UUID.init(uuidString:)) == preferredBlockID
                && isOrdinaryPersonalBlock(object)
        }
        let personalParagraph = blocks.first { block in
            guard let object = block.objectValue else { return false }
            return isOrdinaryPersonalBlock(object)
                && object["kind"]?.stringValue == "paragraph"
        }
        let personal = blocks.first { block in
            guard let object = block.objectValue else { return false }
            return isOrdinaryPersonalBlock(object)
        }
        let transcriptBlock = blocks.first { block in
            guard let object = block.objectValue,
                  isTranscriptBlock(object),
                  let remoteID = object["id"]?.stringValue.flatMap(UUID.init(uuidString:))
            else { return false }
            return preferredTranscriptBlockID == nil || preferredTranscriptBlockID == remoteID
        } ?? blocks.first { block in
            guard let object = block.objectValue else { return false }
            return isTranscriptBlock(object)
        }
        let transcriptObject = transcriptBlock?.objectValue
        let transcriptBlockID = transcriptObject?["id"]?.stringValue.flatMap(UUID.init(uuidString:))
        let transcript = transcriptObject?["text"]?.stringValue.map(stripTranscriptMarker)

        guard let selected = preferred ?? personalParagraph ?? personal,
              let block = selected.objectValue,
              block["source"]?.stringValue == "personal",
              let remoteID = block["id"]?.stringValue.flatMap(UUID.init(uuidString:))
        else {
            return CloudEditableContent(
                blockID: preferredBlockID ?? localPageID,
                text: "",
                revision: 1,
                annotations: [],
                transcriptBlockID: transcriptBlockID,
                transcript: transcript
            )
        }

        let text = block["text"]?.stringValue ?? ""
        let revision = max(1, block["revision"]?.integerValue ?? 1)
        let annotations = compatibleAnnotations(
            in: root["annotations"]?.arrayValue ?? [],
            remoteBlockID: remoteID,
            localPageID: localPageID
        )
        return CloudEditableContent(
            blockID: remoteID,
            text: text,
            revision: revision,
            annotations: annotations,
            transcriptBlockID: transcriptBlockID,
            transcript: transcript
        )
    }

    /// Updates only the native editor's designated personal block and annotations
    /// anchored to that block. Web ink, preparation, meeting state, other blocks,
    /// other annotations, and unknown fields are retained byte-for-byte in meaning.
    static func updating(
        document: CloudJSON?,
        blockID: UUID,
        text: String,
        revision: Int,
        annotations: [NativeAnnotation],
        transcriptBlockID: UUID? = nil,
        localTranscript: String? = nil
    ) throws -> CloudJSON {
        var root: [String: CloudJSON]
        if let document {
            guard let existing = document.objectValue,
                  existing["blocks"]?.arrayValue != nil,
                  existing["annotations"]?.arrayValue != nil
            else { throw CloudDocumentError.invalidDocument }
            root = existing
        } else {
            root = newDocument()
        }

        var blocks = root["blocks"]?.arrayValue ?? []
        let blockIndex = blocks.firstIndex {
            $0.objectValue?["id"]?.stringValue.flatMap(UUID.init(uuidString:)) == blockID
        }
        if let blockIndex {
            guard var block = blocks[blockIndex].objectValue,
                  block["source"]?.stringValue == "personal"
            else { throw CloudDocumentError.invalidEditableBlock }
            block["text"] = .string(text)
            block["revision"] = .number(Double(max(1, revision)))
            blocks[blockIndex] = .object(block)
        } else {
            blocks.append(
                .object([
                    "id": .string(blockID.uuidString.lowercased()),
                    "text": .string(text),
                    "kind": .string("paragraph"),
                    "source": .string("personal"),
                    "revision": .number(Double(max(1, revision))),
                    "excluded": .bool(false),
                ])
            )
        }
        root["blocks"] = .array(blocks)

        var removedTranscriptBlockID: UUID?
        if let localTranscript, let transcriptBlockID {
            var updatedBlocks = root["blocks"]?.arrayValue ?? []
            let transcriptIndex = updatedBlocks.firstIndex {
                $0.objectValue?["id"]?.stringValue.flatMap(UUID.init(uuidString:))
                    == transcriptBlockID
            }
            if let transcriptIndex {
                guard var transcriptBlock = updatedBlocks[transcriptIndex].objectValue,
                      isTranscriptBlock(transcriptBlock)
                else { throw CloudDocumentError.invalidEditableBlock }
                if localTranscript.isEmpty {
                    updatedBlocks.remove(at: transcriptIndex)
                    removedTranscriptBlockID = transcriptBlockID
                } else {
                    let updatedText = transcriptMarker + localTranscript
                    if transcriptBlock["text"] != .string(updatedText) {
                        transcriptBlock["text"] = .string(updatedText)
                        // Native capture appends text. Keeping the transcript's
                        // revision preserves still-valid web annotations anchored
                        // to the pre-existing prefix.
                        updatedBlocks[transcriptIndex] = .object(transcriptBlock)
                    }
                }
            } else if !localTranscript.isEmpty {
                updatedBlocks.append(
                    .object([
                        "id": .string(transcriptBlockID.uuidString.lowercased()),
                        "text": .string(transcriptMarker + localTranscript),
                        "kind": .string("paragraph"),
                        "source": .string("personal"),
                        "revision": .number(Double(max(1, revision))),
                        "excluded": .bool(false),
                    ])
                )
            }
            root["blocks"] = .array(updatedBlocks)
        }

        let existingAnnotations = root["annotations"]?.arrayValue ?? []
        let replacedAnnotationBlockIDs = Set([blockID] + [removedTranscriptBlockID].compactMap { $0 })
        let retained = existingAnnotations.filter { annotation in
            guard let annotationBlockID = annotation.objectValue?["anchor"]?
                .objectValue?["blockId"]?.stringValue.flatMap(UUID.init(uuidString:))
            else { return true }
            return !replacedAnnotationBlockIDs.contains(annotationBlockID)
        }
        root["annotations"] = .array(
            retained + annotations.compactMap { compatibleJSON(for: $0, blockID: blockID) }
        )
        return .object(root)
    }

    private static func newDocument() -> [String: CloudJSON] {
        [
            "schemaVersion": .number(1),
            "blocks": .array([]),
            "ink": .array([]),
            "annotations": .array([]),
            "preparation": .object([
                "type": .string("General"),
                "participants": .string(""),
                "context": .string(""),
                "outcome": .string(""),
                "agenda": .string(""),
                "questions": .string(""),
                "concerns": .string(""),
                "background": .string(""),
                "references": .string(""),
            ]),
            "meetingState": .string("notes"),
        ]
    }

    private static func compatibleAnnotations(
        in annotations: [CloudJSON],
        remoteBlockID: UUID,
        localPageID: UUID
    ) -> [NativeAnnotation] {
        annotations.compactMap { value in
            guard let annotation = value.objectValue,
                  let id = annotation["id"]?.stringValue.flatMap(UUID.init(uuidString:)),
                  let kind = annotation["kind"]?.stringValue,
                  ["important", "follow-up", "action"].contains(kind),
                  let anchor = annotation["anchor"]?.objectValue,
                  anchor["blockId"]?.stringValue.flatMap(UUID.init(uuidString:)) == remoteBlockID,
                  let revision = anchor["revision"]?.integerValue,
                  let start = anchor["start"]?.integerValue,
                  let end = anchor["end"]?.integerValue,
                  let quote = anchor["quote"]?.stringValue,
                  let prefix = anchor["prefix"]?.stringValue,
                  let suffix = anchor["suffix"]?.stringValue,
                  let resolved = bool(anchor["resolved"]),
                  let question = annotation["question"]?.stringValue,
                  let state = annotation["state"]?.stringValue,
                  ["open", "addressed", "dismissed", "later"].contains(state),
                  let created = annotation["createdAt"]?.stringValue.flatMap(cloudDate)
            else { return nil }
            return NativeAnnotation(
                id: id,
                kind: kind,
                anchor: NativeAnchor(
                    blockId: localPageID,
                    revision: revision,
                    start: start,
                    end: end,
                    quote: quote,
                    prefix: prefix,
                    suffix: suffix,
                    resolved: resolved
                ),
                question: question,
                state: state,
                createdAt: created
            )
        }
    }

    private static func compatibleJSON(
        for annotation: NativeAnnotation,
        blockID: UUID
    ) -> CloudJSON? {
        guard ["important", "follow-up", "action"].contains(annotation.kind),
              ["open", "addressed", "dismissed", "later"].contains(annotation.state),
              annotation.anchor.end > annotation.anchor.start,
              !annotation.anchor.quote.isEmpty
        else { return nil }
        return .object([
            "id": .string(annotation.id.uuidString.lowercased()),
            "kind": .string(annotation.kind),
            "anchor": .object([
                "blockId": .string(blockID.uuidString.lowercased()),
                "revision": .number(Double(max(1, annotation.anchor.revision))),
                "start": .number(Double(max(0, annotation.anchor.start))),
                "end": .number(Double(annotation.anchor.end)),
                "quote": .string(annotation.anchor.quote),
                "prefix": .string(String(annotation.anchor.prefix.prefix(32))),
                "suffix": .string(String(annotation.anchor.suffix.prefix(32))),
                "resolved": .bool(annotation.anchor.resolved),
            ]),
            "question": .string(String(annotation.question.prefix(2_000))),
            "state": .string(annotation.state),
            "createdAt": .string(cloudDateString(annotation.createdAt)),
        ])
    }

    private static func bool(_ value: CloudJSON?) -> Bool? {
        guard case .bool(let result) = value else { return nil }
        return result
    }

    private static func isOrdinaryPersonalBlock(_ object: [String: CloudJSON]) -> Bool {
        object["source"]?.stringValue == "personal" && !isTranscriptBlock(object)
    }

    private static func isTranscriptBlock(_ object: [String: CloudJSON]) -> Bool {
        object["source"]?.stringValue == "personal"
            && object["text"]?.stringValue?.hasPrefix(transcriptMarker) == true
    }

    private static func stripTranscriptMarker(_ text: String) -> String {
        guard text.hasPrefix(transcriptMarker) else { return text }
        return String(text.dropFirst(transcriptMarker.count))
    }
}

private func cloudDateFormatter(withFractions: Bool) -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = withFractions
        ? [.withInternetDateTime, .withFractionalSeconds]
        : [.withInternetDateTime]
    return formatter
}

func cloudDate(_ value: String) -> Date? {
    cloudDateFormatter(withFractions: true).date(from: value)
        ?? cloudDateFormatter(withFractions: false).date(from: value)
}

func cloudDateString(_ value: Date) -> String {
    cloudDateFormatter(withFractions: true).string(from: value)
}
