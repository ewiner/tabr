import Foundation
import Combine

struct NowPlayingInfo: Equatable {
    let title: String
    let artist: String

    var searchQuery: String {
        "\(artist) \(title)"
    }
}

/// Reads macOS Now Playing info using a layered approach:
///
/// 1. **`media-control stream`** (works with everything including Chrome PWAs / YouTube Music).
///    Uses the `mediaremote-adapter` project which routes through `/usr/bin/perl`
///    (an Apple-signed binary with MediaRemote entitlements).
///    Install: `brew tap ungive/media-control && brew install media-control`
///
/// 2. **DistributedNotificationCenter** fallback for Apple Music & Spotify
///    (works without `media-control` but only for those two players).
///
/// 3. **AppleScript** one-shot poll at launch for Apple Music / Spotify.
class NowPlayingService: ObservableObject {
    @Published var nowPlaying: NowPlayingInfo?
    @Published var isMonitoring = false
    @Published var mediaControlAvailable = false
    @Published var setupNeeded = false

    private var streamProcess: Process?
    private var observers: [NSObjectProtocol] = []

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        if let path = findMediaControl() {
            mediaControlAvailable = true
            startMediaControlStream(at: path)
        } else {
            // media-control not found — fall back to distributed notifications.
            // This won't work for Chrome PWAs (YouTube Music), so flag setup needed.
            setupNeeded = true
            startDistributedNotifications()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.pollViaAppleScript()
            }
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        streamProcess?.terminate()
        streamProcess = nil
        let dnc = DistributedNotificationCenter.default()
        for observer in observers {
            dnc.removeObserver(observer)
        }
        observers.removeAll()
    }

    // MARK: - media-control stream

    private func findMediaControl() -> String? {
        let candidates = [
            "/opt/homebrew/bin/media-control",  // Apple Silicon Homebrew
            "/usr/local/bin/media-control",     // Intel Homebrew
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // Also check PATH via `which`
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["media-control"]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = FileHandle.nullDevice
        try? which.run()
        which.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return result.isEmpty ? nil : result
    }

    private func startMediaControlStream(at path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["stream", "--no-diff"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            // media-control stream outputs one JSON object per line.
            if let line = String(data: data, encoding: .utf8) {
                for jsonLine in line.components(separatedBy: "\n") where !jsonLine.isEmpty {
                    self?.parseMediaControlJSON(jsonLine)
                }
            }
        }

        process.terminationHandler = { [weak self] proc in
            guard let self, self.isMonitoring else { return }
            // Restart if it exits unexpectedly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self, self.isMonitoring else { return }
                if let path = self.findMediaControl() {
                    self.startMediaControlStream(at: path)
                }
            }
        }

        do {
            try process.run()
            streamProcess = process

            // Also do a one-shot `get` for the current track.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.mediaControlGet(at: path)
            }
        } catch {
            print("[Tabr] Failed to start media-control stream: \(error)")
            // Fall back to distributed notifications.
            setupNeeded = false
            startDistributedNotifications()
        }
    }

    private func mediaControlGet(at path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["get"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !line.isEmpty {
            parseMediaControlJSON(line)
        }
    }

    private func parseMediaControlJSON(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // `stream` wraps in {"type":"data","payload":{...}}; `get` returns payload directly.
        let payload: [String: Any]
        if let p = json["payload"] as? [String: Any] {
            payload = p
        } else if json["title"] != nil {
            payload = json
        } else {
            return
        }

        let playing = payload["playing"] as? Bool ?? true
        guard playing else { return }

        guard let title = payload["title"] as? String, !title.isEmpty else { return }
        let artist = payload["artist"] as? String ?? ""

        let info = NowPlayingInfo(title: title, artist: artist)
        DispatchQueue.main.async { [weak self] in
            if self?.nowPlaying != info {
                self?.nowPlaying = info
            }
        }
    }

    // MARK: - Distributed Notification Fallback

    private func startDistributedNotifications() {
        let dnc = DistributedNotificationCenter.default()

        let musicObs = dnc.addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handlePlayerNotification(notification)
        }
        observers.append(musicObs)

        let spotifyObs = dnc.addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handlePlayerNotification(notification)
        }
        observers.append(spotifyObs)
    }

    private func handlePlayerNotification(_ notification: Notification) {
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

    private func pollViaAppleScript() {
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
