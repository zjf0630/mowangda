import Foundation
import EventKit

/// 小组件侧的「直读」数据源：不经过 App，直接读系统提醒事项库。
/// 只有当本进程已有提醒事项完全访问权限时才会返回数据（小组件弹不了授权框，
/// 若未授权就返回 nil，由调用方退回 App Group 快照）。
enum LiveReminders {

    static func snapshot() async -> WidgetSnapshot? {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return nil }
        let store = EKEventStore()
        let cal = Calendar.current
        // 今天 0 点到明天 0 点：把逾期的和今天的未完成事项都捞出来
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: end, calendars: nil)

        let reminders: [EKReminder]? = await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { result in
                cont.resume(returning: result)
            }
        }
        guard let reminders else { return nil }

        let items = reminders
            .filter { $0.dueDateComponents?.date != nil }
            .sorted { ($0.dueDateComponents?.date ?? .distantPast) < ($1.dueDateComponents?.date ?? .distantPast) }
            .map { r -> WidgetItem in
                let hasTime = r.dueDateComponents?.hour != nil
                let timeText: String
                if hasTime, let d = r.dueDateComponents?.date {
                    let f = DateFormatter()
                    f.dateFormat = "HH:mm"
                    timeText = f.string(from: d)
                } else {
                    timeText = "全天"
                }
                return WidgetItem(
                    title: r.title ?? "",
                    timeText: timeText,
                    priority: Self.priority(of: r),
                    repeatName: Self.repeatName(of: r)
                )
            }

        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"
        return WidgetSnapshot(
            dateText: f.string(from: Date()),
            items: items,
            total: items.count,
            updatedAt: Date()
        )
    }

    /// 与主 App 相同的优先级映射：1-4 高、5-7 中、8-9 低
    private static func priority(of r: EKReminder) -> Int {
        switch r.priority {
        case 1...4: return 3
        case 5...7: return 2
        case 8...9: return 1
        default: return 0
        }
    }

    private static func repeatName(of r: EKReminder) -> String? {
        guard let rule = r.recurrenceRules?.first else { return nil }
        let days = rule.daysOfTheWeek?.map(\.dayOfTheWeek)
        switch rule.frequency {
        case .daily: return "每天"
        case .weekly where days == [.monday, .tuesday, .wednesday, .thursday, .friday]: return "工作日"
        default: return "重复"
        }
    }
}
