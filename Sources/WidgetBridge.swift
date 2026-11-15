import Foundation
import WidgetKit

/// 主 App 侧：把当天条目写成小组件快照，并通知 WidgetKit 刷新。
/// 在 saveCache()（任何增删改）时调用。
enum WidgetBridge {

    static func publish(items: [TodoItem]) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // 当天（含逾期未完成的）未完成条目，按时间排序
        let todays = items
            .filter { !$0.done && $0.due != nil && cal.startOfDay(for: $0.due!) <= today }
            .sorted { ($0.due ?? .distantPast) < ($1.due ?? .distantPast) }

        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"

        let snap = WidgetSnapshot(
            dateText: f.string(from: Date()),
            items: todays.prefix(3).map { item in
                WidgetItem(
                    title: item.title,
                    timeText: item.due == nil ? "—"
                        : (item.hasTime ? Self.hm.string(from: item.due!) : "全天"),
                    priority: item.priority,
                    repeatName: item.repeatName
                )
            },
            total: todays.count,
            updatedAt: Date()
        )

        guard let d = UserDefaults(suiteName: WidgetKeys.appGroupId),
              let data = try? JSONEncoder().encode(snap) else { return }
        d.set(data, forKey: WidgetKeys.snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "MoWangDaWidget")
    }

    private static let hm: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
