import SwiftUI

// MARK: - Color Palette

private extension Color {
    static let bgPrimary = Color(red: 0.07, green: 0.07, blue: 0.10)
    static let bgSecondary = Color(red: 0.10, green: 0.10, blue: 0.14)
    static let bgTertiary = Color(red: 0.13, green: 0.13, blue: 0.18)
    static let bgHover = Color.white.opacity(0.06)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.30)
    static let accent = Color(red: 1.0, green: 0.45, blue: 0.30)       // warm coral
    static let accentBlue = Color(red: 0.35, green: 0.60, blue: 1.0)   // electric blue
    static let accentGreen = Color(red: 0.30, green: 0.85, blue: 0.55) // mint green
    static let accentPurple = Color(red: 0.70, green: 0.45, blue: 1.0) // lavender
    static let starYellow = Color(red: 1.0, green: 0.82, blue: 0.28)
    static let divider = Color.white.opacity(0.08)
}

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var nowPlayingService: NowPlayingService
    @EnvironmentObject var tabService: TabSearchService

    @State private var autoFetch = true
    @State private var wordWrap = false
    @State private var fontSize: CGFloat = 14
    @State private var showingResults = false
    @State private var showingSearch = false
    @State private var searchText = ""
    @State private var contentHovered = false
    @FocusState private var searchFieldFocused: Bool

    private let fontSizeRange: ClosedRange<CGFloat> = 10...24

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Color.divider.frame(height: 1)
            contentArea
        }
        .frame(minWidth: 460, minHeight: 400)
        .background(Color.bgPrimary)
        .preferredColorScheme(.dark)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                tabrLogo
            }
        }
        .onAppear {
            nowPlayingService.startMonitoring()
        }
        .onChange(of: nowPlayingService.nowPlaying) { _, newValue in
            if autoFetch, let info = newValue {
                showingResults = false
                showingSearch = false
                tabService.search(query: info.searchQuery, artist: info.artist, title: info.title, autoSelect: true)
            }
        }
        .onChange(of: autoFetch) { _, isOn in
            if isOn, let info = nowPlayingService.nowPlaying {
                showingResults = false
                showingSearch = false
                tabService.search(query: info.searchQuery, artist: info.artist, title: info.title, autoSelect: true)
            }
        }
        .onChange(of: tabService.selectedTab) { _, newValue in
            if newValue != nil && !showingResults {
                showingSearch = false
            }
        }
    }

    // MARK: - TABR Logo (in window title bar)

    private var tabrLogo: some View {
        Text("T A B R")
            .font(.system(size: 11, weight: .black))
            .tracking(4)
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.accent, Color.accent.opacity(0.7)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }

    // MARK: - Top Bar (in content area, below title bar)

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                songInfoSection

                Spacer()

                headerActionButtons
            }
            .padding(.top, 8)

            if showingSearch {
                searchField
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Song Info

    @ViewBuilder
    private var songInfoSection: some View {
        if let tab = tabService.selectedTab {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(tab.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    typeBadge(tab.type)
                }
                Text(tab.artist)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
        } else if tabService.isLoadingTab {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.accent)
                Text("Loading...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }
        } else if let info = nowPlayingService.nowPlaying {
            VStack(alignment: .leading, spacing: 2) {
                Text(info.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(info.artist)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                Text("No song playing")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    // MARK: - Header Action Buttons

    private var headerActionButtons: some View {
        HStack(spacing: 6) {
            if !tabService.results.isEmpty {
                Button {
                    showingResults.toggle()
                } label: {
                    Image(systemName: showingResults ? "music.note.list" : "list.bullet")
                }
                .help(showingResults ? "Back to tab" : "Other tabs")
            }

            Toggle(isOn: $autoFetch) {
                Text("Auto")
            }
            .toggleStyle(.button)
            .tint(Color.accent)
            .help(autoFetch ? "Auto-sync ON" : "Auto-sync OFF")

            Button {
                showingSearch.toggle()
                if showingSearch {
                    searchFieldFocused = true
                }
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Search")
        }
        .controlSize(.regular)
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textTertiary)

                TextField("Search artist or song...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textPrimary)
                    .focused($searchFieldFocused)
                    .onSubmit {
                        submitSearch()
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.bgTertiary)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if !searchText.isEmpty {
                Button("Search") {
                    submitSearch()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accent)
                .controlSize(.small)
            }
        }
    }

    private func submitSearch() {
        guard !searchText.isEmpty else { return }
        autoFetch = false
        showingResults = true
        tabService.search(query: searchText, autoSelect: false)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if showingResults && !tabService.results.isEmpty {
            searchResultsList
        } else if let tab = tabService.selectedTab {
            tabContentArea(tab)
        } else if tabService.isLoadingTab {
            loadingView("Loading tab...")
        } else if !tabService.results.isEmpty {
            searchResultsList
        } else if tabService.isSearching {
            loadingView("Searching...")
        } else {
            emptyStateView
        }
    }

    // MARK: - Tab Content with Floating Controls

    private func tabContentArea(_ tab: TabContent) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if wordWrap {
                    ScrollView(.vertical) {
                        tabText(tab.content)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        tabText(tab.content)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(16)
                    }
                }
            }

            // Floating text controls — visible on hover
            floatingTextControls
                .padding(12)
                .opacity(contentHovered ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: contentHovered)
        }
        .background(Color.bgPrimary)
        .onHover { hovering in
            contentHovered = hovering
        }
    }

    private func tabText(_ content: String) -> some View {
        Text(content)
            .font(.system(size: fontSize, design: .monospaced))
            .foregroundStyle(Color(white: 0.82))
            .textSelection(.enabled)
    }

    // MARK: - Floating Text Controls

    private var floatingTextControls: some View {
        GlassEffectContainer {
            HStack(spacing: 4) {
                ControlGroup {
                    Button {
                        fontSize = max(fontSizeRange.lowerBound, fontSize - 1)
                    } label: {
                        Image(systemName: "textformat.size.smaller")
                    }
                    .help("Smaller text")

                    Button {
                        fontSize = min(fontSizeRange.upperBound, fontSize + 1)
                    } label: {
                        Image(systemName: "textformat.size.larger")
                    }
                    .help("Larger text")
                }

                Toggle(isOn: $wordWrap) {
                    Label("Wrap", systemImage: "text.justify.leading")
                }
                .toggleStyle(.button)
                .help(wordWrap ? "Wrap: ON" : "Wrap: OFF")
            }
            .controlSize(.regular)
        }
    }

    // MARK: - Search Results List

    private var searchResultsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text("OTHER TABS")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Color.textTertiary)

                Spacer()

                HStack(spacing: 0) {
                    Text("\(tabService.results.count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accent)
                    Text(" found")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Color.divider.frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(tabService.results) { result in
                        ResultRow(result: result)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                tabService.loadTab(result)
                                showingResults = false
                            }
                    }
                }
            }
        }
        .background(Color.bgPrimary)
    }

    // MARK: - Helpers

    private func loadingView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(Color.accent)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.bgPrimary)
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.accent.opacity(0.15), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "guitars")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.accent.opacity(0.6))
            }

            VStack(spacing: 8) {
                Text("Play a song to see tabs")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.textPrimary)

                Text("Tabr watches what's playing and\nautomatically finds guitar tabs")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.bgPrimary)
    }

    @ViewBuilder
    private func typeBadge(_ type: String) -> some View {
        let color = badgeColor(for: type)
        Text(type.uppercased())
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func badgeColor(for type: String) -> Color {
        switch type {
        case "Chords": return .accentBlue
        case "Tab": return .accentGreen
        case "Ukulele": return .accentPurple
        default: return .textTertiary
        }
    }
}

// MARK: - Result Row

struct ResultRow: View {
    let result: TabResult
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(result.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(result.artist)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                badgeView

                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.starYellow)
                    Text(String(format: "%.1f", result.rating))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.textPrimary)
                    Text("(\(result.votes))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isHovered ? Color.bgHover : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var badgeView: some View {
        let color = badgeColor
        return Text(result.type.uppercased())
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var badgeColor: Color {
        switch result.type {
        case "Chords": return .accentBlue
        case "Tab": return .accentGreen
        case "Ukulele": return .accentPurple
        default: return .textTertiary
        }
    }
}
