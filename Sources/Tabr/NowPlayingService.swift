import Foundation
import Combine
import MediaRemoteAdapter

struct NowPlayingInfo: Equatable {
    let title: String
    let artist: String

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

    private func handleTrackInfo(_ trackInfo: TrackInfo?) {
        guard let payload = trackInfo?.payload,
              payload.isPlaying == true,
              let title = payload.title, !title.isEmpty else {
            return
        }

        // Browser sources (e.g. YouTube Music) deliver HTML-encoded metadata, so
        // "Chance Peña" arrives as "Chance Pe&ntilde;a" — decode before display/search.
        let info = NowPlayingInfo(
            title: title.decodingHTMLEntities(),
            artist: (payload.artist ?? "").decodingHTMLEntities()
        )
        if nowPlaying != info {
            nowPlaying = info
        }
    }

    deinit {
        mediaController.stopListening()
    }
}
