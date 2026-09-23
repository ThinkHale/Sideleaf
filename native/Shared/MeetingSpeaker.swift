import Foundation

/// Who was talking, as far as Sideleaf can tell.
///
/// Almost every useful thing a meeting produces belongs to someone. "I'll send
/// the contract" is a promise you have to keep when you said it and a promise
/// you are owed when they did, and the difference decides which list it lands
/// in. Sideleaf is honest about not always knowing.
enum MeetingSpeaker: String, Codable, CaseIterable, Sendable {
    case you
    case other
    case unknown

    /// The person on the other side of the sentence: whoever is being asked
    /// when someone makes a request.
    var counterpart: MeetingSpeaker {
        switch self {
        case .you: .other
        case .other: .you
        case .unknown: .unknown
        }
    }

    var isKnown: Bool { self != .unknown }
}

/// How an attribution was arrived at, so the interface can say so plainly and
/// the person can overrule it.
enum SpeakerSource: String, Codable, Sendable {
    /// Matched against the voice profile recorded in settings.
    case voice
    /// No voice profile, or no confident match. Sideleaf fell back to treating
    /// the speaker as you, which is what it did before it could tell.
    case assumed
    /// The person said otherwise, which always wins.
    case corrected

    var isCertain: Bool { self != .assumed }
}
