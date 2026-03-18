import SwiftUI

@main
struct TabrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var nowPlayingService = NowPlayingService()
    @StateObject private var tabService = TabSearchService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(nowPlayingService)
                .environmentObject(tabService)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 520, height: 700)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
