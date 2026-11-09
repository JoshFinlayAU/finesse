import SwiftUI

/// The Movies and TV Shows tabs: a poster grid with sort and filter.
struct LibraryRootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.jellyfinClient) private var client
    let kind: LibraryKind

    var body: some View {
        let itemKind: ItemKind = kind == .movies ? .movie : .series
        LibraryContent(
            title: kind == .movies ? "Movies" : "TV Shows",
            model: LibraryModel(
                kind: itemKind,
                client: client,
                preferences: app.session.map { LibraryPreferencesStore(account: $0.accountKey, kind: itemKind) }
            )
        )
    }
}

private struct LibraryContent: View {
    @Environment(AppModel.self) private var app
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.jellyfinClient) private var client
    let title: String
    @State var model: LibraryModel

    @State private var showsFilters = false

    private let columns = Array(repeating: GridItem(.fixed(MediaCardStyle.poster.size.width), spacing: 40), count: 6)

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 48) {
                LibraryControls(title: title, model: model, showsFilters: $showsFilters)
                    .focusSection()
                content
            }
        }
        .scrollClipDisabled()
        .fullScreenCover(isPresented: $showsFilters) {
            LibraryFilterPanel(title: title, model: model)
        }
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
                    title: emptyTitle,
                    message: emptyMessage,
                    systemImage: "film.stack"
                )
                if model.hasActiveFilter {
                    Button(onlyUnwatched ? "Show All" : "Clear Filters") {
                        Task { await model.clearFilters() }
                    }
                    .accessibilityIdentifier("emptyClearFilters")
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 600)
            .focusSection()
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

    /// Unwatched on its own finding nothing means everything has been watched, not a bad filter.
    private var onlyUnwatched: Bool {
        var rest = model.filter
        LibraryScope.all.apply(to: &rest)
        return model.scope == .unwatched && rest == ItemFilter()
    }

    private var emptyTitle: String {
        if onlyUnwatched { return "All Watched" }
        return model.hasActiveFilter ? "No Matches" : "Nothing Here Yet"
    }

    private var emptyMessage: String? {
        if onlyUnwatched { return "You've watched every one of these \(title.lowercased())." }
        return model.hasActiveFilter ? "No \(title.lowercased()) match these filters." : nil
    }

    private func card(for item: MediaItem) -> some View {
        MediaCard(
            style: .poster,
            title: item.cardTitle,
            subtitle: item.cardSubtitle,
            imageURL: client.posterURL(for: item),
            progress: item.watchedFraction,
            isWatched: item.isWatched,
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
    @Binding var showsFilters: Bool
    @FocusState private var filterHasFocus: Bool

    var body: some View {
        HStack(spacing: 32) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                if model.phase == .loaded {
                    Text(countText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("libraryCount")
                }
            }
            Spacer()
            sortMenu
            filterButton
            if model.hasActiveFilter {
                Button("Clear Filters", systemImage: "xmark.circle") {
                    // This button is about to go, and focus would otherwise drop into the grid.
                    filterHasFocus = true
                    Task { await model.clearFilters() }
                }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("libraryClearFilters")
            }
            // Last, so it stays put while Clear Filters comes and goes, and Sort stays the first
            // thing up from the grid.
            scopeSwitch
        }
    }

    /// The count, then what's narrowing it, so the grid never looks like the whole library by accident.
    private var countText: String {
        let count = "\(model.totalCount.formatted()) \(model.totalCount == 1 ? "title" : "titles")"
        let titles = model.activeFilterTitles
        guard !titles.isEmpty else { return count }
        let shown = titles.prefix(3).joined(separator: ", ")
        return "\(count) · \(shown)\(titles.count > 3 ? " +\(titles.count - 3)" : "")"
    }

    /// All or Unwatched in one press, as the filter people want most. Selecting rather than
    /// following focus, so moving across it to Sort never reloads the grid.
    private var scopeSwitch: some View {
        GlassEffectContainer {
            HStack(spacing: 12) {
                ForEach(LibraryScope.allCases, id: \.self) { scope in
                    ScopeButton(title: scope.title, isChosen: model.scope == scope) {
                        Task { await model.setScope(scope) }
                    }
                    .accessibilityIdentifier(scope == .all ? "libraryScopeAll" : "libraryScopeUnwatched")
                }
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            // First, because a new order is why anyone opens this menu while the sort is Random.
            if model.sort == .random {
                Section {
                    Button("Shuffle Again", systemImage: "shuffle") {
                        Task { await model.reshuffle() }
                    }
                }
            }
            Section("Sort By") {
                ForEach(model.sortOptions, id: \.self) { sort in
                    Button {
                        Task { await model.setSort(sort) }
                    } label: {
                        CheckedLabel(title: sort.title, isChecked: model.sort == sort)
                    }
                }
            }
            // A random order has no direction, and keeps to itself until asked for a new one.
            if model.sort != .random {
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
            }
        } label: {
            Label(model.sort.title, systemImage: "arrow.up.arrow.down")
        }
        .accessibilityIdentifier("librarySort")
        .accessibilityValue(model.sort.title)
    }

    private var filterButton: some View {
        Button {
            showsFilters = true
        } label: {
            Label(
                model.hasActiveFilter ? "Filters (\(model.activeFilterCount))" : "Filter",
                systemImage: model.hasActiveFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
            )
        }
        .focused($filterHasFocus)
        .accessibilityIdentifier("libraryFilter")
        .accessibilityValue(model.hasActiveFilter ? "Filtered" : "All")
    }
}

private struct ScopeButton: View {
    let title: String
    let isChosen: Bool
    let action: () -> Void

    var body: some View {
        if isChosen {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
        }
    }

    private var button: some View {
        Button(title, action: action)
            .accessibilityValue(isChosen ? "On" : "Off")
            .accessibilityAddTraits(isChosen ? .isSelected : [])
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
