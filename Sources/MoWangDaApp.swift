import SwiftUI

@main
struct MoWangDaApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
                .tint(Theme.accent)
        }
    }
}
