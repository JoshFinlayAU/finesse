import SwiftUI

struct HomeView: View {
    @Environment(\.jellyfinClient) private var client

    var body: some View {
        HomeContent(model: HomeModel(client: client))
    }
}

private struct HomeContent: View {
    @Environment(AppModel.self) private var app
    @Environment(AppNavigator.self) private var navigator
    @State var model: HomeModel

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                LoadingStateView()
            case .failed(let message):
                ErrorStateView(message: message) {
                    Task { await model.load() }
                }
            case .loaded(let hubs) where hubs.isEmpty:
                EmptyStateView(
                    title: "Nothing to Show Yet",
                    message: "Your recently added and in-progress items will appear here.",
                    systemImage: "house"
                )
            case .loaded(let hubs):
                HomeLanding(model: model, hubs: hubs)
            }
        }
        // Runs each time Home reappears, so progress is current after Detail.
        .task { await model.load() }
        // The player covers Home without it disappearing, so `.task` doesn't rerun when it closes.
        // The player reports stop before clearing this, so the reload sees the final position.
        .onChange(of: navigator.activePlayback == nil) { _, playerClosed in
            if playerClosed {
                Task { await model.load() }
            }
        }
        .onChange(of: model.sessionExpired) { _, expired in
            if expired { app.sessionExpired() }
        }
    }
}

/// The billboard fills the screen behind everything. Its buttons and the rows scroll over it, and
/// the details stay put, so a row always has the item it's on described above it.
private struct HomeLanding: View {
    private enum HeroFocus: Hashable {
        case play
        case moreInfo
    }

    /// Distances from the top of the screen, because the art and the content both run under the tab bar.
    private enum Layout {
        /// Where a focused row's title settles, under the shorter details.
        static let rowsTop: CGFloat = 470
        /// Where the buttons sit, under the fuller details.
        static let buttonsTop: CGFloat = 720
        static let logoTop: CGFloat = 130
        static let rotation = Duration.seconds(14)
        /// Moving between cards reports the old one's loss first, so this tells a move from leaving the rows.
        static let focusLossDelay = Duration.milliseconds(120)
        /// How long the system gets to put focus back after Detail or the player closes.
        static let focusRestoreDelay = Duration.milliseconds(700)
    }

    private struct FocusedCard: Equatable {
        let hub: HomeHub.Kind
        let item: MediaItem
    }

    @Environment(AppNavigator.self) private var navigator
    @Environment(\.jellyfinClient) private var client
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: HomeModel
    let hubs: [HomeHub]

    @FocusState private var heroFocus: HeroFocus?
    @State private var focusedCard: FocusedCard?
    /// The focused card lost focus to Detail or the player, which doesn't mean leaving the rows.
    @State private var lostFocusWhileCovered = false
    /// More Info opened Detail, so focus coming back to it is a return and not a move from elsewhere.
    @State private var isReturningToMoreInfo = false

    private var isOnRows: Bool { focusedCard != nil }
    /// Only while nothing is being browsed, and never behind the player. Detail ends this by
    /// taking Home off screen.
    private var rotates: Bool { !isOnRows && navigator.activePlayback == nil && !reduceMotion }
    private var isCovered: Bool { navigator.activePlayback != nil || !(navigator.paths[.home] ?? []).isEmpty }

    private let topID = "home-top"

    var body: some View {
        ZStack(alignment: .topLeading) {
            HomeBackdrop(url: model.hero?.backdropURL, isDimmed: isOnRows)
            Image("FinesseLockup")
                .resizable()
                .scaledToFit()
                .frame(width: 220)
                .padding(.top, Layout.logoTop)
                .environment(\.colorScheme, .dark)
                .opacity(isOnRows ? 0 : 1)
                .accessibilityLabel("Finesse")
                .accessibilityIdentifier("homeLogo")
            HomeHeroDetails(content: model.hero, isCompact: isOnRows)
            rows
        }
        .ignoresSafeArea(edges: .top)
        .onExitCommand(perform: backAction)
        .onChange(of: focusedCard?.item.id) { _, _ in
            if let focusedCard {
                model.cardFocused(focusedCard.item)
            }
        }
        .onChange(of: heroFocus) { previous, current in
            enterButtonsOnPlay(from: previous, to: current)
        }
        .onChange(of: isCovered) { _, covered in
            if !covered { checkFocusAfterReturning() }
        }
        .task(id: rotates) {
            guard rotates else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: Layout.rotation)
                guard !Task.isCancelled else { return }
                model.rotateFeatured()
            }
        }
    }

    private var rows: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // The buttons stay outside the lazy stack, so Back can always move focus to them.
                VStack(alignment: .leading, spacing: 56) {
                    // Full width, so a move down from anywhere on the tab bar stops here first.
                    heroButtons
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Layout.buttonsTop - Layout.rowsTop)
                        .id(topID)
                        .focusSection()
                    LazyVStack(alignment: .leading, spacing: 56) {
                        ForEach(hubs) { hub in
                            HubRow(title: hub.title, items: hub.items) { item in
                                card(for: item, in: hub)
                            }
                            .id(hub.id)
                        }
                    }
                }
                .padding(.bottom, 120)
            }
            .contentMargins(.top, Layout.rowsTop, for: .scrollContent)
            .scrollClipDisabled()
            .scrollIndicators(.hidden)
            .mask { rowsMask }
            .onChange(of: focusedCard?.hub) { _, hub in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                    if let hub {
                        proxy.scrollTo(hub, anchor: .top)
                    } else {
                        proxy.scrollTo(topID, anchor: .top)
                    }
                }
            }
        }
    }

    /// Rows that have moved up fade out rather than sliding under the details.
    private var rowsMask: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Layout.rowsTop - 50)
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: 50)
            Color.black
        }
        .ignoresSafeArea()
    }

    private var heroButtons: some View {
        HStack(spacing: 24) {
            if let target = model.featuredHero?.playTarget {
                Button {
                    navigator.play(target, resumeFrom: target.resumePosition)
                } label: {
                    Label(model.featuredHero?.playTitle ?? "Play", systemImage: "play.fill")
                }
                .buttonStyle(.glassProminent)
                .focused($heroFocus, equals: .play)
                .accessibilityIdentifier("heroPlay")
            }
            Button {
                if let item = model.featuredHero?.item {
                    isReturningToMoreInfo = true
                    navigator.show(.detail(item))
                }
            } label: {
                Label("More Info", systemImage: "info.circle")
            }
            .buttonStyle(.glass)
            .focused($heroFocus, equals: .moreInfo)
            .accessibilityIdentifier("heroMoreInfo")
        }
        // Keeps the rows from jumping up when the billboard moves to something it can't play.
        .frame(minHeight: 80)
    }

    private func card(for item: MediaItem, in hub: HomeHub) -> some View {
        MediaCard(
            style: hub.usesLandscapeCards ? .landscape : .posterCompact,
            title: item.cardTitle,
            subtitle: item.cardSubtitle,
            imageURL: hub.usesLandscapeCards ? client.landscapeURL(for: item) : client.posterURL(for: item),
            progress: item.watchedFraction,
            isWatched: item.isWatched,
            onPlay: item.isPlayable ? { navigator.play(item, resumeFrom: item.resumePosition) } : nil,
            onFocusChange: { isFocused in
                if isFocused {
                    lostFocusWhileCovered = false
                    focusedCard = FocusedCard(hub: hub.kind, item: item)
                } else {
                    cardLostFocus(item, in: hub)
                }
            },
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

    private func cardLostFocus(_ item: MediaItem, in hub: HomeHub) {
        Task {
            try? await Task.sleep(for: Layout.focusLossDelay)
            guard focusedCard?.item.id == item.id, focusedCard?.hub == hub.kind else { return }
            if isCovered {
                lostFocusWhileCovered = true
                return
            }
            focusedCard = nil
            model.cardFocusEnded(item)
        }
    }

    /// The system puts focus back on the card it came from. If that card has gone, such as a film
    /// watched to the end leaving Continue Watching, focus goes to the buttons instead.
    private func checkFocusAfterReturning() {
        Task {
            try? await Task.sleep(for: Layout.focusRestoreDelay)
            guard !isCovered, lostFocusWhileCovered, let card = focusedCard else { return }
            lostFocusWhileCovered = false
            focusedCard = nil
            model.cardFocusEnded(card.item)
            heroFocus = preferredHeroFocus
        }
    }

    /// Focus goes to whichever button is nearest, and Home on the tab bar is over More Info. Coming
    /// in from anywhere else should land on Play, the main thing this screen offers.
    private func enterButtonsOnPlay(from previous: HeroFocus?, to current: HeroFocus?) {
        if previous == nil, current == .moreInfo, !isReturningToMoreInfo {
            heroFocus = preferredHeroFocus
        }
        if current != nil {
            isReturningToMoreInfo = false
        }
    }

    private var preferredHeroFocus: HeroFocus {
        model.featuredHero?.playTarget == nil ? .moreInfo : .play
    }

    /// Back steps out of the rows first. From the buttons it's left to the system, which goes to
    /// the tab bar and then out of the app.
    private var backAction: (() -> Void)? {
        guard isOnRows else { return nil }
        return { heroFocus = preferredHeroFocus }
    }
}
