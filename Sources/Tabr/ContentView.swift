import SwiftUI

struct ContentView: View {
    @EnvironmentObject var nowPlayingService: NowPlayingService
    @EnvironmentObject var tabService: TabSearchService

    @State private var manualQuery = ""
    @State private var autoFetch = true

    var body: some View {
        VStack(spacing: 0) {
            if nowPlayingService.setupNeeded {
                setupBanner
            }
            nowPlayingBar
            Divider()

            if let tab = tabService.selectedTab {
                tabContentView(tab)
            } else if !tabService.results.isEmpty {
                searchResultsList
            } else if tabService.isSearching {
                loadingView("Searching for tabs...")
            } else {
                emptyStateView
            }
        }
        .frame(minWidth: 460, minHeight: 400)
        .onAppear {
            nowPlayingService.startMonitoring()
        }
        .onChange(of: nowPlayingService.nowPlaying) { _, newValue in
            if autoFetch, let info = newValue {
                tabService.search(query: info.searchQuery)
            }
        }
    }

    // MARK: - Setup Banner

    private var setupBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Install media-control for YouTube Music support")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("brew tap ungive/media-control && brew install media-control")
                    .font(.caption2)
                    .monospaced()
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Dismiss") {
                nowPlayingService.setupNeeded = false
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(.yellow.opacity(0.1))
    }

    // MARK: - Now Playing Bar

    private var nowPlayingBar: some View {
        VStack(spacing: 8) {
            if let info = nowPlayingService.nowPlaying {
                HStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(info.artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Toggle("Auto", isOn: $autoFetch)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .help("Automatically search when song changes")

                    Button {
                        tabService.search(query: info.searchQuery)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Search for this song's tabs")
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    Text("No song detected")
                        .foregroundStyle(.secondary)

                    Spacer()
                }
            }

            // Manual search
            HStack {
                TextField("Search tabs manually...", text: $manualQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if !manualQuery.isEmpty {
                            tabService.search(query: manualQuery)
                        }
                    }

                Button("Search") {
                    if !manualQuery.isEmpty {
                        tabService.search(query: manualQuery)
                    }
                }
                .disabled(manualQuery.isEmpty)
            }
        }
        .padding()
        .background(.bar)
    }

    // MARK: - Search Results List

    private var searchResultsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Results")
                    .font(.headline)
                    .padding(.leading)
                Spacer()
                Text("\(tabService.results.count) found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.trailing)
            }
            .padding(.vertical, 8)

            Divider()

            List(tabService.results) { result in
                ResultRow(result: result)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        tabService.loadTab(result)
                    }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Tab Content View

    private func tabContentView(_ tab: TabContent) -> some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button {
                    tabService.selectedTab = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Results")
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Spacer()

                VStack(alignment: .trailing) {
                    Text(tab.title)
                        .font(.headline)
                    Text("\(tab.artist) \u{2022} \(tab.type)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Tab content
            ScrollView {
                Text(tab.content)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }

    // MARK: - Helpers

    private func loadingView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(message)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "guitars")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Play a song to see tabs")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Tabr watches what's playing on your Mac and automatically finds guitar tabs.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Result Row

struct ResultRow: View {
    let result: TabResult

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(result.title)
                    .font(.body)
                    .fontWeight(.medium)
                Text(result.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                // Type badge
                Text(result.type)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeColor.opacity(0.15))
                    .foregroundStyle(badgeColor)
                    .clipShape(Capsule())

                // Rating
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text(String(format: "%.1f", result.rating))
                        .font(.caption2)
                    Text("(\(result.votes))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var badgeColor: Color {
        switch result.type {
        case "Chords": return .blue
        case "Tab": return .green
        case "Ukulele": return .orange
        default: return .gray
        }
    }
}
