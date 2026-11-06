import Foundation

/// A Jellyfin time value. The API counts in ticks, 10,000,000 per second.
struct Ticks: RawRepresentable, Hashable, Comparable, Sendable, Codable {
    static let perSecond: Int64 = 10_000_000
    static let zero = Ticks(rawValue: 0)

    var rawValue: Int64

    init(rawValue: Int64) {
        self.rawValue = rawValue
    }

    init(seconds: TimeInterval) {
        guard seconds.isFinite else {
            self.rawValue = 0
            return
        }
        self.rawValue = Int64((seconds * Double(Self.perSecond)).rounded())
    }

    var seconds: TimeInterval {
        Double(rawValue) / Double(Self.perSecond)
    }

    static func < (lhs: Ticks, rhs: Ticks) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
