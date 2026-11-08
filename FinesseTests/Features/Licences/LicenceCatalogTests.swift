import Foundation
import Testing
@testable import FinEsse

/// Compares the manifest with what the project really depends on. The tests run in the simulator on
/// the build Mac, so they can read the checked-in files next to this one.
struct LicenceCatalogTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private var catalog: LicenceCatalog {
        get throws { try LicenceCatalog.load() }
    }

    private func pins() throws -> [String: String] {
        struct Resolved: Decodable {
            struct Pin: Decodable {
                struct State: Decodable { let version: String? }
                let identity: String
                let state: State
            }
            let pins: [Pin]
        }
        let data = try Data(contentsOf: Self.root.appending(path: "Package.resolved"))
        let resolved = try JSONDecoder().decode(Resolved.self, from: data)
        return Dictionary(uniqueKeysWithValues: resolved.pins.map { ($0.identity, $0.state.version ?? "") })
    }

    /// The `*_VERSION` and `*_TAG` values of the libraries we build, without the build tools.
    private func buildVersions() throws -> [String: String] {
        let text = try String(contentsOf: Self.root.appending(path: "tvos-deps/versions.sh"), encoding: .utf8)
        let tools: Set = ["MESON_VERSION", "NINJA_VERSION", "CMAKE_VERSION"]
        var versions: [String: String] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0].hasSuffix("_VERSION") || parts[0].hasSuffix("_TAG"), !tools.contains(parts[0])
            else { continue }
            versions[parts[0]] = parts[1]
        }
        return versions
    }

    @Test func everySwiftPackageShippedIsListedAtItsPinnedVersion() throws {
        let catalog = try catalog
        let listed = Dictionary(uniqueKeysWithValues: catalog.components.compactMap { component in
            component.package.map { ($0, component.version) }
        })
        for (identity, version) in try pins() where !catalog.developmentOnlyPackages.contains(identity) {
            #expect(listed[identity] == version, "\(identity) \(version) needs an up-to-date licences.json entry")
        }
    }

    @Test func nothingIsListedThatIsNoLongerAPackage() throws {
        let pins = try pins()
        for component in try catalog.components {
            if let package = component.package {
                #expect(pins[package] != nil, "\(component.name) is listed but no longer pinned")
            }
        }
    }

    @Test func everyLibraryWeBuildIsListedAtItsBuiltVersion() throws {
        let catalog = try catalog
        let listed = Dictionary(uniqueKeysWithValues: catalog.components.compactMap { component in
            component.versionKey.map { ($0, component.version) }
        })
        for (key, value) in try buildVersions() {
            // Tags like v1.4.2 list as 1.4.2, while vulkan-sdk-1.4.363.0 stays as it is.
            let isVersionTag = value.first == "v" && value.dropFirst().first?.isNumber == true
            let version = isVersionTag ? String(value.dropFirst()) : value
            #expect(listed[key] == version, "\(key)=\(value) needs an up-to-date licences.json entry")
        }
    }

    @Test func everyFileExistsAndHasText() throws {
        for component in try catalog.components {
            #expect(!component.files.isEmpty, "\(component.name) has no licence text")
            for file in component.files {
                let text = try LicenceCatalog.text(of: file)
                #expect(text.count > 100, "\(file.file) for \(component.name) looks empty")
            }
        }
    }

    @Test func theFullLicenceTextsAreTheRealOnes() throws {
        func text(_ id: String, containing title: String) throws -> String {
            let component = try #require(try catalog.components.first { $0.id == id })
            let file = try #require(component.files.first { $0.title.contains(title) })
            return try LicenceCatalog.text(of: file)
        }
        #expect(try text("ffmpeg", containing: "Lesser").contains("Version 3, 29 June 2007"))
        #expect(try text("ffmpeg", containing: "GNU General Public License").contains("GNU GENERAL PUBLIC LICENSE"))
        #expect(try text("mpv", containing: "Lesser").contains("Version 2.1, February 1999"))
        #expect(try text("jellyfin-sdk-swift", containing: "Mozilla").contains("Mozilla Public License Version 2.0"))
        #expect(try text("freetype", containing: "FreeType").contains("The FreeType Project LICENSE"))
    }

    @Test func freeTypeCarriesItsRequiredCredit() throws {
        let freetype = try #require(try catalog.components.first { $0.id == "freetype" })
        #expect(freetype.credit?.contains("The FreeType Project (www.freetype.org)") == true)
    }

    /// Finesse is LGPL 3, and the offer points to the public repository that also builds our LGPL libraries.
    @Test func theSourceOfferPointsToThePublicRepository() throws {
        let offer = try #require(try catalog.sourceOffer)
        #expect(offer.contains("github.com/JoshFinlayAU/finesse"))
        #expect(offer.contains("tvos-deps"))
    }

    @Test func finesseIsListedUnderItsOwnLicenceAtTheAppVersion() throws {
        let finesse = try #require(try catalog.components.first { $0.id == "finesse" })
        #expect(finesse.group == .app)
        #expect(finesse.version == Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        let lesser = try #require(finesse.files.first { $0.title.contains("Lesser") })
        #expect(try LicenceCatalog.text(of: lesser).contains("Version 3, 29 June 2007"))
    }
}

struct LicenceTextTests {
    private let sample = (1...200).map { "Line \($0) of a licence." }.joined(separator: "\n")

    @Test func noPieceIsTallerThanTheScreen() {
        let chunks = LicenceText.chunks(of: sample, maxLines: 10, maxLineLength: 96)
        #expect(chunks.count >= 20)
        #expect(chunks.allSatisfy { $0.split(separator: "\n", omittingEmptySubsequences: false).count <= 10 })
    }

    @Test func noTextIsLost() {
        let chunks = LicenceText.chunks(of: sample, maxLines: 10)
        #expect(chunks.joined(separator: "\n") == sample)
    }

    @Test func aParagraphEndBreaksOnceThePieceIsWellFilled() {
        let text = (1...8).map { "Line \($0)" }.joined(separator: "\n") + "\n\nNext paragraph"
        let chunks = LicenceText.chunks(of: text, maxLines: 10)
        #expect(chunks.count == 2)
        #expect(chunks[1] == "Next paragraph")
    }

    @Test func aVeryLongLineIsSplitRatherThanRunningOffScreen() {
        let line = String(repeating: "x", count: 5000)
        let chunks = LicenceText.chunks(of: line, maxLines: 10, maxLineLength: 100)
        #expect(chunks.allSatisfy { $0.count <= 1000 })
        #expect(chunks.joined() == line)
    }

    @Test func emptyTextHasNoPieces() {
        #expect(LicenceText.chunks(of: "\n\n").isEmpty)
    }
}
