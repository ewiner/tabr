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
        guard let handle = dlopen(frameworkPath, RTLD_NOW) else { return }
        mediaRemoteHandle = handle

        guard let infoSymbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else { return }
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
        guard let getNowPlayingInfo else { return }

        getNowPlayingInfo(DispatchQueue.main) { [weak self] info in
            guard let self else { return }
            let title = info[self.kMRMediaRemoteNowPlayingInfoTitle] as? String
            let artist = info[self.kMRMediaRemoteNowPlayingInfoArtist] as? String
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
