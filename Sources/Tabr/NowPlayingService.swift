import Foundation
import Combine

struct NowPlayingInfo: Equatable {
    let title: String
    let artist: String

    var searchQuery: String {
        "\(artist) \(title)"
    }
}

/// Reads macOS Now Playing info via DistributedNotificationCenter.
///
/// macOS 15.4+ blocks third-party apps from the private MediaRemote framework,
/// but Apple Music and Spotify still broadcast track-change notifications through
/// the distributed notification system. We listen for those and also do an
/// initial AppleScript poll to pick up whatever is already playing.
class NowPlayingService: ObservableObject {
    @Published var nowPlaying: NowPlayingInfo?
    @Published var isMonitoring = false

    private var observers: [NSObjectProtocol] = []

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        let dnc = DistributedNotificationCenter.default()

        // Apple Music broadcasts this when playback state or track changes.
        let musicObs = dnc.addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleMusicNotification(notification)
        }
        observers.append(musicObs)

        // Spotify broadcasts this on track changes.
        let spotifyObs = dnc.addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleSpotifyNotification(notification)
        }
        observers.append(spotifyObs)

        // Initial poll via AppleScript to grab what's already playing.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.pollViaAppleScript()
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        let dnc = DistributedNotificationCenter.default()
        for observer in observers {
            dnc.removeObserver(observer)
        }
        observers.removeAll()
    }

    // MARK: - Distributed Notification Handlers

    private func handleMusicNotification(_ notification: Notification) {
        guard let info = notification.userInfo else { return }

        // Apple Music includes "Name" (track title) and "Artist" in userInfo.
        // "Player State" can be "Playing", "Paused", "Stopped".
        let state = info["Player State"] as? String ?? ""
        guard state == "Playing" else { return }

        let title = info["Name"] as? String
        let artist = info["Artist"] as? String

        if let title, !title.isEmpty {
            let newInfo = NowPlayingInfo(title: title, artist: artist ?? "")
            if nowPlaying != newInfo {
                nowPlaying = newInfo
            }
        }
    }

    private func handleSpotifyNotification(_ notification: Notification) {
        guard let info = notification.userInfo else { return }

        let state = info["Player State"] as? String ?? ""
        guard state == "Playing" else { return }

        let title = info["Name"] as? String
        let artist = info["Artist"] as? String

        if let title, !title.isEmpty {
            let newInfo = NowPlayingInfo(title: title, artist: artist ?? "")
            if nowPlaying != newInfo {
                nowPlaying = newInfo
            }
        }
    }

    // MARK: - AppleScript Polling

    /// One-shot poll to pick up the currently playing track at launch.
    private func pollViaAppleScript() {
        // Try Apple Music first, then Spotify.
        if let info = queryAppleMusic() ?? querySpotify() {
            DispatchQueue.main.async { [weak self] in
                if self?.nowPlaying != info {
                    self?.nowPlaying = info
                }
            }
        }
    }

    private func queryAppleMusic() -> NowPlayingInfo? {
        let script = """
        tell application "System Events"
            if not (exists process "Music") then return ""
        end tell
        tell application "Music"
            if player state is playing then
                set t to name of current track
                set a to artist of current track
                return t & "\\n" & a
            end if
        end tell
        return ""
        """
        return runAppleScript(script)
    }

    private func querySpotify() -> NowPlayingInfo? {
        let script = """
        tell application "System Events"
            if not (exists process "Spotify") then return ""
        end tell
        tell application "Spotify"
            if player state is playing then
                set t to name of current track
                set a to artist of current track
                return t & "\\n" & a
            end if
        end tell
        return ""
        """
        return runAppleScript(script)
    }

    private func runAppleScript(_ source: String) -> NowPlayingInfo? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)

        if error != nil { return nil }

        let output = result.stringValue ?? ""
        let lines = output.split(separator: "\n", maxSplits: 1)
        guard lines.count == 2 else { return nil }

        let title = String(lines[0])
        let artist = String(lines[1])
        guard !title.isEmpty else { return nil }

        return NowPlayingInfo(title: title, artist: artist)
    }

    deinit {
        stopMonitoring()
    }
}
