import Foundation

/// A dotted version number such as 1.2.0, compared part by part (1.10 is newer than 1.9).
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let parts: [Int]

    /// Accepts "1.2.3" and tags like "v1.2.3"; returns nil for anything else.
    public init?(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespaces)
        if s.first == "v" || s.first == "V" { s.removeFirst() }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        self.parts = parts.map { $0! }
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    public static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }
}

/// The parts of a GitHub release (from /repos/<owner>/<repo>/releases/latest) the updater uses.
public struct Release: Decodable, Equatable, Sendable {
    public struct Asset: Decodable, Equatable, Sendable {
        public let name: String
        public let downloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
        }
    }

    public let tag: String
    public let notes: String?
    public let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tag = "tag_name"
        case notes = "body"
        case assets
    }

    /// The archive the updater installs: the same DoubleTake.zip install.sh downloads.
    public static let archiveName = "DoubleTake.zip"

    public var version: AppVersion? { AppVersion(tag) }
    public var archive: Asset? { assets.first { $0.name == Self.archiveName } }
}
