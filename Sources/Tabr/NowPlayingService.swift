import Foundation
import Combine
import MediaRemoteAdapter
import HTMLEntities

struct NowPlayingInfo: Equatable {
    let title: String
    let artist: String
    let appName: String?
    let appBundleID: String?
    let durationSeconds: Double?

    var searchQuery: String {
        "\(artist) \(title)"
    }
}

/// Reads macOS Now Playing info via the mediaremote-adapter Swift package.
///
/// macOS 15.4+ blocks direct access to the private MediaRemote framework.
/// The mediaremote-adapter works around this by routing through `/usr/bin/perl`
/// (an Apple-signed binary with `com.apple.perl5` bundle ID that has
/// MediaRemote entitlements). This works with any media source that registers
/// with macOS Now Playing, including Chrome PWAs like YouTube Music.
class NowPlayingService: ObservableObject {
    @Published var nowPlaying: NowPlayingInfo?
    @Published var isMonitoring = false

    private let mediaController = MediaController()

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        mediaController.onTrackInfoReceived = { [weak self] trackInfo in
            self?.handleTrackInfo(trackInfo)
        }

        // If the underlying listener process dies unexpectedly, restart it so we
        // don't silently stop receiving Now Playing updates. Guarded by
        // isMonitoring so an intentional stopMonitoring() doesn't trigger a restart.
        mediaController.onListenerTerminated = { [weak self] in
            guard let self, self.isMonitoring else { return }
            self.mediaController.startListening()
        }

        mediaController.startListening()

        // One-shot get to pick up whatever is already playing.
        mediaController.getTrackInfo { [weak self] trackInfo in
            self?.handleTrackInfo(trackInfo)
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        mediaController.stopListening()
    }

    /// Minimum duration in seconds for media to be considered a song.
    /// Filters out ads (~15-30s) and short video clips.
    private static let minimumDurationSeconds: Double = 60

    /// Bundle ID prefixes for known music apps. Prefix matching handles
    /// variants (e.g. com.spotify.client vs com.spotify.client.helper).
    private static let musicAppBundlePrefixes: [String] = [
        "com.spotify.",
        "com.apple.Music",
        "com.apple.iTunes",
        "com.tidal.",
        "com.amazon.music",
        "com.pandora.",
        "com.deezer.",
        "org.videolan.vlc",
        "com.plexapp.",
        "com.clementine-player.",
        "com.coppertino.Vox",
        "io.foobar2000.",
        "com.roon.",
        "com.qobuz.",
    ]

    /// App names to match when bundleIdentifier is unavailable (e.g. Chrome PWAs
    /// like YouTube Music report the PWA name but no bundle ID distinct from Chrome).
    private static let musicAppNames: Set<String> = [
        "YouTube Music",
        "Tidal",
        "SoundCloud",
    ]

    private func isMusicApp(bundleID: String?, appName: String?) -> Bool {
        if let bundleID {
            for prefix in Self.musicAppBundlePrefixes {
                if bundleID.hasPrefix(prefix) { return true }
            }
        }
        if let appName {
            if Self.musicAppNames.contains(appName) { return true }
        }
        return false
    }

    private func handleTrackInfo(_ trackInfo: TrackInfo?) {
        guard let payload = trackInfo?.payload,
              payload.isPlaying == true,
              let title = payload.title, !title.isEmpty else {
            return
        }

        // Filter out non-music media (browser videos, ads, etc.)
        guard isMusicApp(bundleID: payload.bundleIdentifier, appName: payload.applicationName) else {
            return
        }

        // Filter out short media (ads, jingles, sound effects)
        if let durationMicros = payload.durationMicros {
            let durationSeconds = durationMicros / 1_000_000
            if durationSeconds < Self.minimumDurationSeconds {
                return
            }
        }

        let durationSeconds = payload.durationMicros.map { $0 / 1_000_000 }
        // Browser sources (e.g. YouTube Music) deliver HTML-encoded metadata, so
        // "Chance Peña" arrives as "Chance Pe&ntilde;a" — decode before display/search.
        let info = NowPlayingInfo(
            title: title.htmlUnescape(),
            artist: (payload.artist ?? "").htmlUnescape(),
            appName: payload.applicationName,
            appBundleID: payload.bundleIdentifier,
            durationSeconds: durationSeconds
        )
        if nowPlaying != info {
            nowPlaying = info
        }
    }

    deinit {
        mediaController.stopListening()
    }
}
