import SwiftUI

/// Every filter the library really offers. It's a full screen of pages rather than a menu, because a
/// menu closes after each choice and can't hold thousands of tags. Back goes up one page at a time,
/// and the card beside the pages keeps the count and Clear Filters one press right from anywhere.
struct LibraryFilterPanel: View {
    let title: String
    let model: LibraryModel

    var body: some View {
        HStack(alignment: .top, spacing: 60) {
            NavigationStack {
                List {
                    if model.choicesPhase == .loaded {
                        choiceSection("Show", [.unwatched, .watched, .inProgress, .favourites])
                        nameRow
                        choiceSection("Resolution", [.fourK, .hd, .sd, .threeD])
                        choiceSection("Status", ItemSeriesStatus.allCases.map(FilterChoice.seriesStatus))
                        choiceSection("Includes", [.subtitles, .trailer, .specialFeature, .themeSong, .themeVideo])
                        choiceSection("Video Type", ItemVideoType.allCases.map(FilterChoice.videoType))
                        ratingRow
                        listRows
                    } else if case .failed(let message) = model.choicesPhase {
                        Text(message)
                        Button("Try Again") {
                            Task { await model.loadFilterChoices() }
                        }
                    } else {
                        // All the rows arrive together, so focus starts on the first of them.
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
                .navigationTitle("Filter \(title)")
                .navigationDestination(for: LibraryFilterPage.self) { page in
                    switch page {
                    case .list(let list): FilterValuesPage(list: list, model: model)
                    case .letters(let list, let letter): FilterLetterPage(list: list, letter: letter, model: model)
                    case .name: FilterNamePage(model: model)
                    case .rating: FilterRatingPage(model: model)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            LibraryFilterSummary(model: model)
                .frame(width: 520)
                .padding(.top, 60)
                .focusSection()
        }
        // A full screen cover is see-through by default, and the grid behind would show through the rows.
        .background(.ultraThickMaterial, ignoresSafeAreaEdges: .all)
        .task { await model.loadFilterChoices() }
    }

    @ViewBuilder
    private func choiceSection(_ title: String, _ choices: [FilterChoice]) -> some View {
        let shown = choices.filter(model.offers)
        if !shown.isEmpty {
            Section(title) {
                ForEach(shown, id: \.self) { choice in
                    Button {
                        Task { await model.toggle(choice) }
                    } label: {
                        FilterCheckedRow(title: choice.title, isChecked: choice.isOn(in: model.filter))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var nameRow: some View {
        if model.choicesPhase == .loaded || model.filter.name != nil {
            NavigationLink(value: LibraryFilterPage.name) {
                LabeledContent("Starts With", value: model.nameTitle)
            }
            .accessibilityIdentifier("filterRow-name")
        }
    }

    @ViewBuilder
    private var ratingRow: some View {
        if FilterChoice.ratings.map(FilterChoice.minimumRating).contains(where: model.offers) {
            NavigationLink(value: LibraryFilterPage.rating) {
                LabeledContent("Community Rating", value: model.filter.minCommunityRating.map { "\($0) or Higher" } ?? "Any")
            }
            .accessibilityIdentifier("filterRow-rating")
        }
    }

    @ViewBuilder
    private var listRows: some View {
        let shown = FilterList.allCases.filter(model.offers)
        if !shown.isEmpty {
            Section("Choose From a List") {
                ForEach(shown, id: \.self) { list in
                    NavigationLink(value: LibraryFilterPage.list(list)) {
                        LabeledContent(list.title, value: model.selectionSummary(list))
                    }
                    .accessibilityIdentifier("filterRow-\(list.rawValue)")
                }
            }
        }
    }
}

/// What's narrowing the library right now.
private struct LibraryFilterSummary: View {
    let model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("\(model.totalCount.formatted()) \(model.totalCount == 1 ? "title" : "titles")")
                .font(.title3)
                .fontWeight(.semibold)
                .contentTransition(.numericText())
                .accessibilityIdentifier("panelSummary")
            if model.hasActiveFilter {
                VStack(alignment: .leading, spacing: 8) {
                    let titles = model.activeFilterTitles
                    Text("\(titles.count) \(titles.count == 1 ? "filter" : "filters") on")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    ForEach(titles.prefix(Self.maximumShown), id: \.self) { title in
                        Text(title)
                            .lineLimit(1)
                    }
                    if titles.count > Self.maximumShown {
                        Text("and \(titles.count - Self.maximumShown) more")
                            .foregroundStyle(.secondary)
                    }
                }
                // Not until the rows are there, or it would take the first focus while they load.
                if model.choicesPhase != .loading {
                    Button("Clear Filters", systemImage: "xmark.circle") {
                        Task { await model.clearFilters() }
                    }
                    .accessibilityIdentifier("panelClearFilters")
                }
            } else {
                Text("No filters on")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 32))
    }

    private static let maximumShown = 8
}

enum LibraryFilterPage: Hashable {
    case list(FilterList)
    case letters(FilterList, String)
    case name
    case rating
}

/// A checkmark on the trailing edge, so rows don't shift when one is chosen.
private struct FilterCheckedRow: View {
    let title: String
    let isChecked: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if isChecked {
                Image(systemName: "checkmark")
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isChecked ? "On" : "Off")
    }
}

/// One server list. Short ones are listed outright. Long ones open by letter, with search, because
/// nobody can scroll through thousands of rows with a remote.
private struct FilterValuesPage: View {
    let list: FilterList
    let model: LibraryModel
    @State private var search = ""

    /// More rows than this are too slow to walk through one press at a time.
    private let longList = 60
    private let maximumResults = 200

    private var values: [FilterValue] {
        model.values(for: list)
    }

    var body: some View {
        List {
            selectedSection
            if values.count <= longList {
                Section("Matches any you choose") {
                    FilterValueRows(list: list, values: values, model: model)
                }
            } else if search.isEmpty {
                Section("\(values.count.formatted()) to choose from") {
                    ForEach(FilterLetters.groups(of: values), id: \.letter) { group in
                        NavigationLink(value: LibraryFilterPage.letters(list, group.letter)) {
                            LabeledContent(group.letter, value: group.values.count.formatted())
                        }
                        .accessibilityIdentifier("letterRow-\(group.letter)")
                    }
                }
            } else {
                let found = values.filter { $0.name.localizedCaseInsensitiveContains(search) }
                Section(found.count > maximumResults ? "First \(maximumResults) of \(found.count.formatted())" : "\(found.count.formatted()) found") {
                    FilterValueRows(list: list, values: Array(found.prefix(maximumResults)), model: model)
                }
            }
        }
        .navigationTitle(list.title)
        .modifier(SearchableWhenLong(isLong: values.count > longList, search: $search))
    }

    @ViewBuilder
    private var selectedSection: some View {
        let selected = list.selected(in: model.filter)
        if !selected.isEmpty {
            Section("Selected") {
                FilterValueRows(list: list, values: selected, model: model)
            }
        }
    }
}

private struct SearchableWhenLong: ViewModifier {
    let isLong: Bool
    @Binding var search: String

    func body(content: Content) -> some View {
        if isLong {
            content.searchable(text: $search, prompt: "Search")
        } else {
            content
        }
    }
}

/// One letter of a long list.
private struct FilterLetterPage: View {
    let list: FilterList
    let letter: String
    let model: LibraryModel

    var body: some View {
        List {
            Section("Matches any you choose") {
                FilterValueRows(
                    list: list,
                    values: FilterLetters.groups(of: model.values(for: list)).first { $0.letter == letter }?.values ?? [],
                    model: model
                )
            }
        }
        .navigationTitle("\(list.title): \(letter)")
    }
}

private struct FilterValueRows: View {
    let list: FilterList
    let values: [FilterValue]
    let model: LibraryModel

    var body: some View {
        ForEach(values) { value in
            Button {
                Task { await model.toggle(value, in: list) }
            } label: {
                FilterCheckedRow(
                    title: value.name,
                    isChecked: list.selected(in: model.filter).contains { $0.id == value.id }
                )
            }
        }
    }
}

/// A grid of letters, which takes far fewer presses than a list of 27 rows.
private struct FilterNamePage: View {
    let model: LibraryModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 24), count: 7)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 32) {
                ForEach(model.availableNameFilters, id: \.self) { name in
                    Button {
                        Task { await model.toggle(name) }
                    } label: {
                        Text(LibraryModel.title(of: name))
                            .frame(maxWidth: .infinity)
                    }
                    .tint(model.filter.name == name ? .accentColor : nil)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("name-\(LibraryModel.title(of: name))")
                    .accessibilityValue(model.filter.name == name ? "On" : "Off")
                }
            }
            .padding(40)
        }
        .navigationTitle("Starts With")
        .task { await model.loadNameFilters() }
    }
}

private struct FilterRatingPage: View {
    let model: LibraryModel

    var body: some View {
        List {
            Section("Community Rating") {
                ForEach(FilterChoice.ratings.map(FilterChoice.minimumRating).filter(model.offers), id: \.self) { choice in
                    Button {
                        Task { await model.toggle(choice) }
                    } label: {
                        FilterCheckedRow(title: choice.title, isChecked: choice.isOn(in: model.filter))
                    }
                }
            }
        }
        .navigationTitle("Community Rating")
    }
}

enum FilterLetters {
    struct Group {
        let letter: String
        let values: [FilterValue]
    }

    /// By first letter, with anything else under #. In the server's order within each letter.
    static func groups(of values: [FilterValue]) -> [Group] {
        var byLetter: [String: [FilterValue]] = [:]
        for value in values {
            let first = value.name.first.map { String($0).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).uppercased() } ?? "#"
            let letter = first.count == 1 && first >= "A" && first <= "Z" ? first : "#"
            byLetter[letter, default: []].append(value)
        }
        return byLetter.keys.sorted { lhs, rhs in
            lhs == "#" ? rhs != "#" : rhs == "#" ? false : lhs < rhs
        }.map { Group(letter: $0, values: byLetter[$0] ?? []) }
    }
}
