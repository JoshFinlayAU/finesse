import SwiftUI

/// The Movies and TV Shows tabs: a poster grid with sort and filter.
struct LibraryRootView: View {
    @Environment(\.jellyfinClient) private var client
    let kind: LibraryKind

    var body: some View {
        LibraryContent(
            title: kind == .movies ? "Movies" : "TV Shows",
            model: LibraryModel(kind: kind == .movies ? .movie : .series, client: client)
        )
    }
}

private struct LibraryContent: View {
    @Environment(AppModel.self) private var app
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.jellyfinClient) private var client
    let title: String
    @State var model: LibraryModel

    private let columns = Array(repeating: GridItem(.fixed(MediaCardStyle.poster.size.width), spacing: 40), count: 6)

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 48) {
                LibraryControls(title: title, model: model)
                    .focusSection()
                content
            }
        }
        .scrollClipDisabled()
        // Runs each time the grid reappears, so progress is current after Detail or the player.
        .task { await model.appeared() }
        .onChange(of: navigator.activePlayback == nil) { _, finished in
            if finished { Task { await model.appeared() } }
        }
        .onChange(of: model.sessionExpired) { _, expired in
            if expired { app.sessionExpired() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            LoadingStateView()
                .frame(height: 600)
        case .failed(let message):
            ErrorStateView(message: message) {
                Task { await model.reload() }
            }
            .frame(height: 600)
        case .loaded where model.items.isEmpty:
            VStack(spacing: 40) {
                EmptyStateView(
                    title: model.hasActiveFilter ? "No Matches" : "Nothing Here Yet",
                    message: model.hasActiveFilter ? "No \(title.lowercased()) match these filters." : nil,
                    systemImage: "film.stack"
                )
                if model.hasActiveFilter {
                    Button("Clear Filters") {
                        Task { await model.setFilter(ItemFilter()) }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 600)
        case .loaded:
            LazyVGrid(columns: columns, alignment: .leading, spacing: 56) {
                ForEach(model.items) { item in
                    card(for: item)
                        .onAppear {
                            Task { await model.loadMore(after: item) }
                        }
                }
            }
            footer
        }
    }

    private func card(for item: MediaItem) -> some View {
        MediaCard(
            style: .poster,
            title: item.cardTitle,
            subtitle: item.cardSubtitle,
            imageURL: client.posterURL(for: item),
            progress: item.watchedFraction,
            onPlay: item.isPlayable ? { navigator.play(item, resumeFrom: item.resumePosition) } : nil,
            action: { navigator.show(.detail(item)) },
            menu: {
                if item.isPlayable {
                    Button(item.resumePosition == nil ? "Play" : "Resume", systemImage: "play.fill") {
                        navigator.play(item, resumeFrom: item.resumePosition)
                    }
                }
                Button("Go to Details", systemImage: "info.circle") {
                    navigator.show(.detail(item))
                }
            }
        )
    }

    @ViewBuilder
    private var footer: some View {
        if model.loadMoreFailed {
            Button("Couldn't load more. Try Again") {
                Task { await model.retryLoadMore() }
            }
            .frame(maxWidth: .infinity)
        } else if model.isLoadingMore {
            ProgressView()
                .frame(maxWidth: .infinity)
        }
    }
}

private struct LibraryControls: View {
    let title: String
    let model: LibraryModel

    var body: some View {
        HStack(spacing: 32) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                if model.phase == .loaded {
                    Text("\(model.totalCount, format: .number) \(model.totalCount == 1 ? "title" : "titles")")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            sortMenu
            filterMenu
        }
    }

    private var sortMenu: some View {
        Menu {
            Section("Sort By") {
                ForEach(model.sortOptions, id: \.self) { sort in
                    Button {
                        Task { await model.setSort(sort) }
                    } label: {
                        CheckedLabel(title: sort.title, isChecked: model.sort == sort)
                    }
                }
            }
            Section("Order") {
                Button {
                    Task { await model.setDirection(.ascending) }
                } label: {
                    CheckedLabel(title: "Ascending", isChecked: model.direction == .ascending)
                }
                Button {
                    Task { await model.setDirection(.descending) }
                } label: {
                    CheckedLabel(title: "Descending", isChecked: model.direction == .descending)
                }
            }
        } label: {
            Label(model.sort.title, systemImage: "arrow.up.arrow.down")
        }
        .accessibilityIdentifier("librarySort")
    }

    private var filterMenu: some View {
        Menu {
            Section {
                filterButton("All", isChecked: model.filter.isPlayed == nil) { $0.isPlayed = nil }
                filterButton("Unwatched", isChecked: model.filter.isPlayed == false) { $0.isPlayed = false }
                filterButton("Watched", isChecked: model.filter.isPlayed == true) { $0.isPlayed = true }
            }
            Section {
                filterButton("Favourites", isChecked: model.filter.isFavorite == true) {
                    $0.isFavorite = $0.isFavorite == true ? nil : true
                }
            }
            valueMenu("Genre", values: model.options.genres, selected: model.filter.genres) { $0.genres = $1 }
            valueMenu("Year", values: model.options.years.map(String.init), selected: model.filter.years.map(String.init)) {
                $0.years = $1.compactMap(Int.init)
            }
            valueMenu("Rating", values: model.options.officialRatings, selected: model.filter.officialRatings) {
                $0.officialRatings = $1
            }
            if model.hasActiveFilter {
                Section {
                    Button("Clear Filters") {
                        Task { await model.setFilter(ItemFilter()) }
                    }
                }
            }
        } label: {
            Label(
                model.hasActiveFilter ? "Filtered" : "Filter",
                systemImage: model.hasActiveFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
            )
        }
        .accessibilityIdentifier("libraryFilter")
    }

    private func filterButton(_ title: String, isChecked: Bool, change: @escaping (inout ItemFilter) -> Void) -> some View {
        Button {
            var filter = model.filter
            change(&filter)
            Task { await model.setFilter(filter) }
        } label: {
            CheckedLabel(title: title, isChecked: isChecked)
        }
    }

    /// One value at a time, which is what the remote makes comfortable. Choosing it again clears it.
    @ViewBuilder
    private func valueMenu(
        _ title: String,
        values: [String],
        selected: [String],
        change: @escaping (inout ItemFilter, [String]) -> Void
    ) -> some View {
        if !values.isEmpty {
            Menu(title) {
                ForEach(values, id: \.self) { value in
                    filterButton(value, isChecked: selected.contains(value)) {
                        change(&$0, selected.contains(value) ? [] : [value])
                    }
                }
            }
        }
    }
}

private struct CheckedLabel: View {
    let title: String
    let isChecked: Bool

    var body: some View {
        if isChecked {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}
