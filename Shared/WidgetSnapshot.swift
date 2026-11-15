import Foundation

/// App 与桌面小组件之间的共享数据。
/// 这个文件编进主 App 和小组件两个 target，只依赖 Foundation，不许引用 SwiftUI/EventKit。
/// 数据通过 App Group 的 UserDefaults 传递：主 App 写，小组件读。

struct WidgetItem: Codable, Hashable {
    var title: String
    var timeText: String    // "09:30" 或 "全天" 或 "—"
    var priority: Int       // 0 无 1 低 2 中 3 高
    var repeatName: String? // "每天" / "工作日"
}

struct WidgetSnapshot: Codable {
    var dateText: String    // "11月15日 周日"
    var items: [WidgetItem] // 当天最多 3 条
    var total: Int          // 当天总条数（含没显示出来的）
    var updatedAt: Date
}

enum WidgetKeys {
    static let appGroupId = "group.com.wuhan.mowangda"
    static let snapshotKey = "mowangda.widget.snapshot.v1"
}

/// 小组件侧读取
enum WidgetReader {
    static func read() -> WidgetSnapshot? {
        guard let d = UserDefaults(suiteName: WidgetKeys.appGroupId),
              let data = d.data(forKey: WidgetKeys.snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
