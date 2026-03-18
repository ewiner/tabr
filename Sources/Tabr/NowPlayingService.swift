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
    private typealias MRMediaRemoteGetNowPlayingInfoFunction = @convention(c) (
        DispatchQueue, @escaping ([String: Any]) -> Void
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
            print("⚠ Could not load MediaRemote framework: \(String(cString: dlerror()))")
            return
        }
        mediaRemoteHandle = handle
        print("✓ MediaRemote framework loaded")

        guard let infoSymbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else {
            print("⚠ Could not find MRMediaRemoteGetNowPlayingInfo")
            return
        }
        getNowPlayingInfo = unsafeBitCast(infoSymbol, to: MRMediaRemoteGetNowPlayingInfoFunction.self)
        print("✓ MRMediaRemoteGetNowPlayingInfo resolved")

        if let regSymbol = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            registerForNotifications = unsafeBitCast(
                regSymbol,
                to: MRMediaRemoteRegisterForNowPlayingNotificationsFunction.self
            )
            print("✓ MRMediaRemoteRegisterForNowPlayingNotifications resolved")
        } else {
            print("⚠ MRMediaRemoteRegisterForNowPlayingNotifications not found (non-fatal)")
        }
    }

    func startMonitoring() {
        isMonitoring = true

        // Register for notifications first — required on newer macOS before info is returned
        registerForNotifications?(DispatchQueue.main)

        poll() // Immediate first poll
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
            print("⚠ poll() called but getNowPlayingInfo is nil")
            return
        }

        getNowPlayingInfo(DispatchQueue.main) { [weak self] info in
            guard let self else { return }

            print("📻 Now Playing raw keys: \(info.keys.sorted())")

            let title = info[self.kMRMediaRemoteNowPlayingInfoTitle] as? String
            let artist = info[self.kMRMediaRemoteNowPlayingInfoArtist] as? String

            print("   title=\(title ?? "(nil)") artist=\(artist ?? "(nil)")")

            if let title, let artist, !title.isEmpty, !artist.isEmpty {
                let newInfo = NowPlayingInfo(title: title, artist: artist)
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
