import SwiftUI

// MARK: - Color Palette

private extension Color {
    static let bgPrimary = Color(red: 0.07, green: 0.07, blue: 0.10)
    static let bgSecondary = Color(red: 0.10, green: 0.10, blue: 0.14)
    static let bgTertiary = Color(red: 0.13, green: 0.13, blue: 0.18)
    static let bgHover = Color.white.opacity(0.06)
    static let bgSelected = Color.white.opacity(0.10)
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

    @State private var manualQuery = ""
    @State private var autoFetch = true
    @State private var wordWrap = false

    var body: some View {
        VStack(spacing: 0) {
            nowPlayingBar
            Color.divider.frame(height: 1)

            if let tab = tabService.selectedTab {
                tabContentView(tab)
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
        .frame(minWidth: 460, minHeight: 400)
        .background(Color.bgPrimary)
        .preferredColorScheme(.dark)
        .onAppear {
            nowPlayingService.startMonitoring()
        }
        .onChange(of: nowPlayingService.nowPlaying) { _, newValue in
            if autoFetch, let info = newValue {
                tabService.search(query: info.searchQuery, artist: info.artist, title: info.title)
            }
        }
    }

    // MARK: - Now Playing Bar

    private var nowPlayingBar: some View {
        VStack(spacing: 10) {
            if let info = nowPlayingService.nowPlaying {
                HStack(spacing: 14) {
                    // Animated music icon
                    ZStack {
                        Circle()
                            .fill(Color.accent.opacity(0.15))
                            .frame(width: 40, height: 40)
                        Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.accent)
                    }

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

                    Spacer()

                    // Auto toggle - pill style
                    Button {
                        autoFetch.toggle()
                    } label: {
                        Text("AUTO")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(0.5)
                            .foregroundStyle(autoFetch ? Color.bgPrimary : Color.textTertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(autoFetch ? Color.accent : Color.bgTertiary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Auto-search when song changes")

                    Button {
                        tabService.search(query: info.searchQuery, artist: info.artist, title: info.title)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 30, height: 30)
                            .background(Color.bgTertiary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Refresh search")
                }
            } else {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.bgTertiary)
                            .frame(width: 40, height: 40)
                        Image(systemName: "music.note")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                    }

                    Text("No song playing")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.textTertiary)

                    Spacer()
                }
            }

            // Search bar
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textTertiary)

                    TextField("Search tabs...", text: $manualQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textPrimary)
                        .onSubmit {
                            if !manualQuery.isEmpty {
                                tabService.search(query: manualQuery)
                            }
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.bgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if !manualQuery.isEmpty {
                    Button {
                        tabService.search(query: manualQuery)
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.bgSecondary)
    }

    // MARK: - Search Results List

    private var searchResultsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text("RESULTS")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Color.textTertiary)

                Spacer()

                Text("\(tabService.results.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accent)
                +
                Text(" found")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
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
                            }
                    }
                }
            }
        }
    }

    // MARK: - Tab Content View

    private func tabContentView(_ tab: TabContent) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center) {
                Button {
                    tabService.selectedTab = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                        Text("Back")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accent.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(tab.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(tab.artist)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                        typeBadge(tab.type, small: true)
                    }
                }

                // Word wrap toggle
                Button {
                    wordWrap.toggle()
                } label: {
                    Image(systemName: wordWrap ? "text.justify.leading" : "arrow.left.and.right.text.below.a.magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(wordWrap ? Color.accent : Color.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(wordWrap ? Color.accent.opacity(0.12) : Color.bgTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(wordWrap ? "Word wrap: ON" : "Word wrap: OFF")
                .padding(.leading, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.bgSecondary)

            Color.divider.frame(height: 1)

            // Tab content - scrollable both ways when wrap is off
            if wordWrap {
                ScrollView(.vertical) {
                    Text(tab.content)
                        .font(.custom("SF Mono", size: 12.5, relativeTo: .body))
                        .foregroundStyle(Color(white: 0.82))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .background(Color.bgPrimary)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Text(tab.content)
                        .font(.custom("SF Mono", size: 12.5, relativeTo: .body))
                        .foregroundStyle(Color(white: 0.82))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: 0, alignment: .leading)
                        .padding(16)
                }
                .background(Color.bgPrimary)
            }
        }
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
    private func typeBadge(_ type: String, small: Bool = false) -> some View {
        let color = badgeColor(for: type)
        Text(type.uppercased())
            .font(.system(size: small ? 8 : 9, weight: .heavy))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, small ? 5 : 7)
            .padding(.vertical, small ? 2 : 3)
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
            // Left: song info
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

            // Right: badge + rating
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
