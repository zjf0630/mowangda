import SwiftUI

@main
struct MoWangDaApp: App {
    var body: some Scene {
        WindowGroup {
            // 不锁定外观：跟随系统的浅色 / 深色
            RootView()
                .tint(Theme.accent)
        }
    }
}
