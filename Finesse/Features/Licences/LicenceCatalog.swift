import Foundation

/// Every component the app ships, read from `Licences/licences.json` in the app bundle. The manifest
/// is the single source for the screen, and `LicenceCatalogTests` fails if it falls behind
/// `Package.resolved` or `tvos-deps/versions.sh`.
struct LicenceCatalog: Decodable, Equatable {
    struct File: Decodable, Equatable, Hashable, Identifiable {
        let title: String
        let file: String

        var id: String { title + file }
    }

    struct Component: Decodable, Equatable, Hashable, Identifiable {
        enum Group: String, Decodable {
            case app
            case playback
            case swift
        }

        let id: String
        let name: String
        let version: String
        let group: Group
        let licence: String
        let files: [File]
        var versionKey: String?
        var package: String?
        var note: String?
        var credit: String?
    }

    /// Where the source code is, for Finesse and for the LGPL libraries we build.
    let sourceOffer: String?
    /// Packages pinned only for development, which don't ship and so aren't listed.
    let developmentOnlyPackages: [String]
    let components: [Component]

    func components(in group: Component.Group) -> [Component] {
        components
            .filter { $0.group == group }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func load(from bundle: Bundle = .main) throws -> LicenceCatalog {
        let url = try require(bundle.url(forResource: "licences", withExtension: "json"))
        return try JSONDecoder().decode(LicenceCatalog.self, from: Data(contentsOf: url))
    }

    static func text(of file: File, in bundle: Bundle = .main) throws -> String {
        let name = (file.file as NSString).deletingPathExtension
        return try String(contentsOf: require(bundle.url(forResource: name, withExtension: "txt")), encoding: .utf8)
    }

    private static func require(_ url: URL?) throws -> URL {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        return url
    }
}

/// Splits licence text into pieces short enough to fit on screen. tvOS scrolls by moving focus, so a
/// piece taller than the screen could never be read in full.
enum LicenceText {
    static func chunks(of text: String, maxLines: Int = 18, maxLineLength: Int = 96) -> [String] {
        var chunks: [String] = []
        var current: [Substring] = []
        var used = 0

        func flush() {
            let joined = current.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !joined.isEmpty {
                chunks.append(joined)
            }
            current = []
            used = 0
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            for piece in pieces(of: line, length: maxLineLength * maxLines) {
                let height = max(1, (piece.count + maxLineLength - 1) / maxLineLength)
                // Break at a paragraph once the piece is well filled, so text reads naturally.
                if used + height > maxLines || (piece.isEmpty && used >= maxLines * 2 / 3) {
                    flush()
                }
                current.append(piece)
                used += height
            }
        }
        flush()
        return chunks
    }

    private static func pieces(of line: Substring, length: Int) -> [Substring] {
        guard line.count > length else { return [line] }
        var pieces: [Substring] = []
        var rest = line
        while !rest.isEmpty {
            pieces.append(rest.prefix(length))
            rest = rest.dropFirst(length)
        }
        return pieces
    }
}
