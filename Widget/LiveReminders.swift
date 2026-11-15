import Foundation
import EventKit

/// 小组件侧的「直读」数据源：不经过 App，直接读系统提醒事项库。
/// 只有当本进程已有提醒事项完全访问权限时才会返回数据（小组件弹不了授权框，
/// 若未授权就返回 nil，由调用方退回 App Group 快照）。
///
/// 取数口径：不再只看「今天」，而是把全部未完成、且有时间的事项按时间升序排，
/// 取接下来的 3 条。逾期未完成的排在最前面（它们最该被看见）。
enum LiveReminders {

    static func snapshot() async -> WidgetSnapshot? {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return nil }
        let store = EKEventStore()
        let now = Date()
        let cal = Calendar.current
        // 下界传 nil → 逾期的也一并捞出来；上界给一年，够覆盖"接下来三条"
        let end = cal.date(byAdding: .day, value: 365, to: now)!
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: end, calendars: nil)

        let reminders: [EKReminder]? = await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { result in
                cont.resume(returning: result)
            }
        }
        guard let reminders else { return nil }

        var rows: [(when: Date, item: WidgetItem)] = []
        for r in reminders {
            // 没有日期的事项（时间待定）不进小组件——它要按时间排序，没有时间就没位置
            guard let dc = r.dueDateComponents, let raw = dc.date else { continue }
            let hasTime = dc.hour != nil
            let rule = r.recurrenceRules?.first
            var weekdays: Set<Int>? = nil
            if let days = rule?.daysOfTheWeek, !days.isEmpty {
                // EKWeekday 的编号与 Calendar 的 weekday 一致：1 = 周日 … 7 = 周六
                weekdays = Set(days.map { $0.dayOfTheWeek.rawValue })
            }
            // 重复条目要自己算下一次，否则「每天 9 点」过了那天会永远显示逾期
            let when = WidgetDay.nextOccurrence(
                base: raw, hasTime: hasTime, weekdays: weekdays,
                repeatsDaily: rule?.frequency == .daily, now: now) ?? raw

            rows.append((when: when, item: WidgetItem(
                title: r.title ?? "",
                timeText: hasTime ? Self.hm.string(from: when) : "全天",
                priority: Self.priority(of: r),
                repeatName: Self.repeatName(of: r),
                dayText: WidgetDay.label(for: when, now: now)
            )))
        }
        rows.sort { $0.when < $1.when }

        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"
        return WidgetSnapshot(
            dateText: f.string(from: now),
            items: rows.prefix(3).map { $0.item },
            total: rows.count,
            updatedAt: now
        )
    }

    private static let hm: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

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
