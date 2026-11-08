import SwiftUI

/// Settings > Licences: every component the app ships, each opening its licence in full.
struct LicencesView: View {
    @State private var catalog: Result<LicenceCatalog, Error>?

    var body: some View {
        Group {
            switch catalog {
            case nil:
                LoadingStateView()
            case .failure(let error):
                ErrorStateView(message: error.userMessage)
            case .success(let catalog):
                list(catalog)
            }
        }
        .navigationTitle("Licences")
        .task {
            if catalog == nil {
                catalog = Result { try LicenceCatalog.load() }
            }
        }
    }

    private func list(_ catalog: LicenceCatalog) -> some View {
        List {
            Section("Source Code") {
                SourceOfferRow(offer: catalog.sourceOffer)
            }
            Section("Finesse") {
                rows(catalog.components(in: .app))
            }
            Section("Playback Libraries") {
                rows(catalog.components(in: .playback))
            }
            Section("Swift Packages") {
                rows(catalog.components(in: .swift))
            }
        }
    }

    private func rows(_ components: [LicenceCatalog.Component]) -> some View {
        ForEach(components) { component in
            NavigationLink {
                LicenceDetailView(component: component)
            } label: {
                LabeledContent {
                    Text(component.licence)
                        .lineLimit(1)
                } label: {
                    Text(component.name)
                }
            }
            .accessibilityIdentifier("licence-\(component.id)")
        }
    }
}

/// Where to get the source. A manifest without the wording shows a marked placeholder instead.
private struct SourceOfferRow: View {
    let offer: String?

    var body: some View {
        Button {} label: {
            VStack(alignment: .leading, spacing: 8) {
                if let offer {
                    Text(offer)
                } else {
                    Label("Placeholder for the owner", systemImage: "exclamationmark.triangle")
                        .fontWeight(.semibold)
                    Text("The source code offer goes here. Its wording hasn't been decided.")
                        .font(.callout)
                }
            }
        }
        .accessibilityIdentifier("sourceOffer")
    }
}

/// One component's licence in full. Each piece of text takes focus, so the remote moves through it.
struct LicenceDetailView: View {
    let component: LicenceCatalog.Component

    @State private var sections: Result<[TextSection], Error>?

    struct TextSection: Identifiable {
        let file: LicenceCatalog.File
        let chunks: [String]

        var id: String { file.id }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                header
                switch sections {
                case nil:
                    LoadingStateView()
                        .frame(height: 400)
                case .failure(let error):
                    ErrorStateView(message: error.userMessage)
                case .success(let sections):
                    ForEach(sections) { section in
                        Text(section.file.title)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .padding(.top, 40)
                            .padding(.bottom, 16)
                        ForEach(Array(section.chunks.enumerated()), id: \.offset) { _, chunk in
                            LicenceTextChunk(text: chunk)
                        }
                    }
                }
            }
        }
        .scrollClipDisabled()
        .task {
            guard sections == nil else { return }
            let files = component.files
            sections = await Task.detached {
                Result {
                    try files.map { file in
                        TextSection(file: file, chunks: LicenceText.chunks(of: try LicenceCatalog.text(of: file)))
                    }
                }
            }.value
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(component.name)
                .font(.title2)
                .fontWeight(.semibold)
            Text("Version \(component.version)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(component.licence)
                .font(.callout)
            if let note = component.note {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let credit = component.credit {
                Text(credit)
                    .font(.callout)
            }
        }
    }
}

private struct LicenceTextChunk: View {
    let text: String

    @FocusState private var isFocused: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 26, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(isFocused ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 12))
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
    }
}
