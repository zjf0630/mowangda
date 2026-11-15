import Foundation

/// App 与桌面小组件之间的共享数据。
/// 这个文件编进主 App 和小组件两个 target，只依赖 Foundation，不许引用 SwiftUI/EventKit。
/// 数据通过 App Group 的 UserDefaults 传递：主 App 写，小组件读。

struct WidgetItem: Codable, Hashable {
    var title: String
    var timeText: String    // "09:30" 或 "全天" 或 "—"
    var priority: Int       // 0 无 1 低 2 中 3 高
    var repeatName: String? // "每天" / "工作日"
    /// "今天" / "明天" / "逾期" / "11月18日"。可选是为了兼容旧快照（旧数据没有这个字段）
    var dayText: String? = nil
}

struct WidgetSnapshot: Codable {
    var dateText: String    // "11月15日 周日"（今天，用在标题栏）
    var items: [WidgetItem] // 接下来最多 3 条，已按时间升序
    var total: Int          // 全部待办（有时间的）条数
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

/// 日期标签：小组件里每条前面那行小字。两个 target 都要用，所以放共享文件。
enum WidgetDay {

    static func label(for date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let d0 = cal.startOfDay(for: date)
        let today = cal.startOfDay(for: now)
        if d0 < today { return "逾期" }
        if d0 == today { return "今天" }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: today), d0 == tomorrow { return "明天" }
        if let yearLater = cal.date(byAdding: .year, value: 1, to: today), d0 < yearLater {
            return "\(cal.component(.month, from: d0))月\(cal.component(.day, from: d0))日"
        }
        return "\(cal.component(.year, from: d0))年\(cal.component(.month, from: d0))月\(cal.component(.day, from: d0))日"
    }

    /// 重复条目的「下一次」。系统提醒事项里 dueDateComponents 存的是首次发生的日期，
    /// 每天 / 工作日的条目过了那天不会自己往后滚，所以小组件里得自己算下一次，
    /// 否则一条「每天 9 点」的提醒会永远显示成逾期。
    /// 只处理能算清楚的两种规则（每天、每周指定星期），其它返回 nil 交给调用方原样保留。
    static func nextOccurrence(base: Date, hasTime: Bool, weekdays: Set<Int>?, repeatsDaily: Bool, now: Date) -> Date? {
        guard repeatsDaily || weekdays != nil else { return nil }
        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: base)
        // 全天事项只要还没过完今天就算今天的，所以门槛用「今天 0 点」而不是此刻
        let floor = hasTime ? now : cal.startOfDay(for: now)
        var day = cal.startOfDay(for: max(base, now))
        for _ in 0..<400 {
            var candidate = day
            if hasTime, let h = hm.hour, let m = hm.minute {
                candidate = cal.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day
            }
            let weekdayOK = weekdays.map { $0.contains(cal.component(.weekday, from: day)) } ?? true
            if candidate >= floor && weekdayOK { return candidate }
            guard let nextDay = cal.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = nextDay
        }
        return nil
    }
}
