import Foundation
import Combine

struct NowPlayingInfo: Equatable {
    let title: String
    let artist: String

    var searchQuery: String {
        "\(artist) \(title)"
    }
}

/// Reads macOS Now Playing info via the private MediaRemote framework.
/// This is the same data shown in the menu bar / Control Center.
class NowPlayingService: ObservableObject {
    @Published var nowPlaying: NowPlayingInfo?
    @Published var isMonitoring = false

    private var timer: Timer?

    // MediaRemote function types
    // The callback MUST be @convention(block) — MediaRemote expects an ObjC block,
    // not a C function pointer. Using the wrong convention causes the dictionary
    // bridging to silently fail (empty dict).
    private typealias MRMediaRemoteGetNowPlayingInfoFunction = @convention(c) (
        DispatchQueue, @convention(block) ([String: Any]) -> Void
    ) -> Void
    private typealias MRMediaRemoteRegisterForNowPlayingNotificationsFunction = @convention(c) (
        DispatchQueue
    ) -> Void

    private var getNowPlayingInfo: MRMediaRemoteGetNowPlayingInfoFunction?
    private var registerForNotifications: MRMediaRemoteRegisterForNowPlayingNotificationsFunction?
    private var mediaRemoteHandle: UnsafeMutableRawPointer?

    // Known MediaRemote keys
    private let kMRMediaRemoteNowPlayingInfoTitle = "kMRMediaRemoteNowPlayingInfoTitle"
    private let kMRMediaRemoteNowPlayingInfoArtist = "kMRMediaRemoteNowPlayingInfoArtist"

    init() {
        loadMediaRemote()
    }

    private func loadMediaRemote() {
        let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(frameworkPath, RTLD_NOW) else {
            print("[Tabr] ⚠ Could not load MediaRemote: \(String(cString: dlerror()))")
            return
        }
        mediaRemoteHandle = handle
        print("[Tabr] ✓ MediaRemote loaded")

        guard let infoSymbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else {
            print("[Tabr] ⚠ MRMediaRemoteGetNowPlayingInfo not found")
            return
        }
        getNowPlayingInfo = unsafeBitCast(infoSymbol, to: MRMediaRemoteGetNowPlayingInfoFunction.self)

        if let regSymbol = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            registerForNotifications = unsafeBitCast(
                regSymbol,
                to: MRMediaRemoteRegisterForNowPlayingNotificationsFunction.self
            )
        }
    }

    func startMonitoring() {
        isMonitoring = true

        // Register for notifications first — required on newer macOS before info is returned
        registerForNotifications?(DispatchQueue.main)

        // Delay first poll slightly to let registration settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.poll()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
    }

    func poll() {
        guard let getNowPlayingInfo else {
            print("[Tabr] ⚠ poll: getNowPlayingInfo is nil")
            return
        }

        getNowPlayingInfo(DispatchQueue.main) { [weak self] info in
            guard let self else { return }

            // Debug: show what we got
            if info.isEmpty {
                print("[Tabr] poll: empty dictionary (no now-playing data)")
            } else {
                print("[Tabr] poll: got \(info.count) keys: \(info.keys.sorted())")
            }

            let title = info[self.kMRMediaRemoteNowPlayingInfoTitle] as? String
            let artist = info[self.kMRMediaRemoteNowPlayingInfoArtist] as? String

            if let title, !title.isEmpty {
                print("[Tabr] → title=\"\(title)\" artist=\"\(artist ?? "(nil)")\"")
                let effectiveArtist = artist ?? ""
                let newInfo = NowPlayingInfo(title: title, artist: effectiveArtist)
                if self.nowPlaying != newInfo {
                    self.nowPlaying = newInfo
                }
            }
        }
    }

    deinit {
        timer?.invalidate()
        if let handle = mediaRemoteHandle {
            dlclose(handle)
        }
    }
}
