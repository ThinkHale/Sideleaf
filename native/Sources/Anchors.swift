import Foundation
import CoreGraphics

// Codable counterparts use the web contract's UTF-16 offset convention.
struct NativeAnchor: Codable, Equatable, Sendable {
    var blockId: UUID
    var revision: Int
    var start: Int
    var end: Int
    var quote: String
    var prefix: String
    var suffix: String
    var resolved: Bool

    static func make(blockId: UUID, revision: Int, text: String, range: NSRange) -> NativeAnchor {
        let source = text as NSString
        let before = max(0, range.location - 32)
        return NativeAnchor(blockId: blockId, revision: revision, start: range.location, end: NSMaxRange(range), quote: source.substring(with: range), prefix: source.substring(with: NSRange(location: before, length: range.location - before)), suffix: source.substring(with: NSRange(location: NSMaxRange(range), length: min(32, source.length - NSMaxRange(range)))), resolved: true)
    }

    func remapped(to text: String, revision: Int) -> NativeAnchor {
        var result = self
        let source = text as NSString
        var matches: [Int] = []
        var cursor = 0
        while cursor < source.length {
            let found = source.range(of: quote, options: [], range: NSRange(location: cursor, length: source.length - cursor))
            if found.location == NSNotFound { break }
            let prefixLength = (prefix as NSString).length
            let suffixLength = (suffix as NSString).length
            let before = source.substring(with: NSRange(location: max(0, found.location - prefixLength), length: min(found.location, prefixLength)))
            let after = source.substring(with: NSRange(location: NSMaxRange(found), length: min(suffixLength, source.length - NSMaxRange(found))))
            if before == prefix && after == suffix { matches.append(found.location) }
            cursor = found.location + 1
        }
        guard matches.count == 1 else { result.resolved = false; return result }
        result.start = matches[0]; result.end = result.start + (quote as NSString).length
        result.revision = revision; result.resolved = true
        return result
    }
}

struct NativeAnnotation: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var kind = "important"
    var anchor: NativeAnchor
    var question = ""
    var state = "open"
    var createdAt = Date()
}

enum LassoGeometry {
    static func contains(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > point.y) != (b.y > point.y), point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }
}
