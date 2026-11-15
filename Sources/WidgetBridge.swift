import Foundation
import WidgetKit

/// 主 App 侧：把「接下来 3 条」写成小组件快照，并通知 WidgetKit 刷新。
/// 在 saveCache()（任何增删改）时调用。
/// 这只是兜底数据源——小组件能直读提醒事项库时用不到它。
enum WidgetBridge {

    static func publish(items: [TodoItem]) {
        let now = Date()
        let cal = Calendar.current

        // 未完成 + 有时间的事项。不再限定今天：按「下一次发生时间」升序排，取前三条。
        let rows: [(when: Date, item: TodoItem)] = items.compactMap { item in
            guard !item.done, let due = item.due else { return nil }
            return (when: nextOccurrence(of: item, due: due, now: now), item: item)
        }
        .sorted { $0.when < $1.when }

        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"

        let snap = WidgetSnapshot(
            dateText: f.string(from: now),
            items: rows.prefix(3).map { row in
                WidgetItem(
                    title: row.item.title,
                    timeText: row.item.hasTime ? Self.hm.string(from: row.when) : "全天",
                    priority: row.item.priority,
                    repeatName: row.item.repeatName,
                    dayText: WidgetDay.label(for: row.when, now: now)
                )
            },
            total: rows.count,
            updatedAt: now
        )

        guard let d = UserDefaults(suiteName: WidgetKeys.appGroupId),
              let data = try? JSONEncoder().encode(snap) else { return }
        d.set(data, forKey: WidgetKeys.snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "MoWangDaWidget")
    }

    /// 重复条目（每天 / 工作日）的 due 存的是第一次发生的日期，不会自己往后滚，
    /// 这里按规则算出下一次；算不出来（自定义重复）就原样用 due。
    private static func nextOccurrence(of item: TodoItem, due: Date, now: Date) -> Date {
        let cal = Calendar.current
        switch item.repeatRule {
        case "daily":
            return WidgetDay.nextOccurrence(base: due, hasTime: item.hasTime, weekdays: nil,
                                            repeatsDaily: true, now: now) ?? due
        case "workday":
            // Calendar 的 weekday：1 = 周日，周一到周五是 2...6
            return WidgetDay.nextOccurrence(base: due, hasTime: item.hasTime,
                                            weekdays: [2, 3, 4, 5, 6],
                                            repeatsDaily: false, now: now) ?? due
        default:
            return due
        }
    }

    private static let hm: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
