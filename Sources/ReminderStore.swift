import Foundation
import EventKit

/// 数据层：权威数据在系统「提醒事项」（EventKit），本地 UserDefaults 缓存用于离线秒开。
@MainActor
final class ReminderStore: ObservableObject {

    @Published var items: [TodoItem] = []
    @Published var authorized = false
    @Published var lastSync: Date? = nil

    private let store = EKEventStore()
    private let listName = "工作"
    private let cacheKey = "mowangda.cache.v1"
    private let deadlineMark = "[截止]"

    init() { loadCache() }

    // MARK: - 权限与同步

    func requestAccess() async {
        do {
            authorized = try await store.requestFullAccessToReminders()
        } catch {
            authorized = false
        }
        if authorized {
            // 授权前实例化的 EKEventStore 可能持有过期状态，授权后必须 reset 才能读到内容
            store.reset()
            await sync()
        }
    }

    func sync() async {
        guard authorized else { return }
        // 读取全部提醒事项列表。
        // 早先这里只读「工作」列表（workCalendar() ?? 全部），导致「工作」一旦被创建，
        // 其它列表里原本能看到的内容就集体"消失"。现在统一读全部，写入仍进「工作」。
        let calendars = store.calendars(for: .reminder)
        guard !calendars.isEmpty else { return }
        let predicate = store.predicateForReminders(in: calendars)
        // EventKit 至今没有 async 版拉取接口，只能用 completion 包一层
        let fetched: [EKReminder]? = await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { result in
                cont.resume(returning: result)
            }
        }
        // 读失败（nil）时保留现有内容，绝不清空
        guard let reminders = fetched else { return }

        items = reminders.map { r in
            let dc = r.dueDateComponents
            let hasTime = dc?.hour != nil
            let note = r.notes ?? ""
            var remind = 0
            if let a = r.alarms?.first, a.relativeOffset != 0 { remind = Int(-a.relativeOffset / 60) }
            let pri: Int
            switch r.priority {
            case 1...4: pri = 3
            case 5...7: pri = 2
            case 8...9: pri = 1
            default: pri = 0
            }
            // 重复规则：识别「每天」「工作日」，其它重复一律显示为「重复」
            let rep: String?
            if let rule = r.recurrenceRules?.first {
                let days = rule.daysOfTheWeek?.map(\.dayOfTheWeek)
                switch rule.frequency {
                case .daily: rep = "daily"
                case .weekly where days == Self.workdays: rep = "workday"
                default: rep = "custom"
                }
            } else {
                rep = nil
            }
            return TodoItem(
                id: r.calendarItemIdentifier,
                title: r.title ?? "",
                due: dc?.date,
                hasTime: hasTime,
                deadline: note.contains(deadlineMark),
                listName: r.calendar?.title ?? listName,
                remindMinutes: remind,
                note: note.replacingOccurrences(of: deadlineMark, with: ""),
                priority: pri,
                done: r.isCompleted,
                repeatRule: rep,
                completedAt: r.completionDate
            )
        }
        lastSync = Date()
        saveCache()
        // 读完之后检查有没有过了截止时间还挂着的条目（只在 App 活着的时候能做，
        // iOS 不允许第三方 App 在后台定时跑代码）
        await autoCompleteExpiredDeadlines()
    }

    // MARK: - 增删改

    func add(_ p: ParsedItem) async {
        var item = TodoItem(id: UUID().uuidString, title: p.title, due: p.due, hasTime: p.hasTime,
                            deadline: p.deadline, listName: p.listName,
                            remindMinutes: p.hasTime ? Prefs.leadMinutes : 0, note: p.note, priority: 0, done: false,
                            repeatRule: nil)
        if authorized, let cal = ensureCalendar() {
            let r = EKReminder(eventStore: store)
            r.title = item.title
            r.calendar = cal
            r.notes = item.storedNote.isEmpty ? nil : item.storedNote
            if let due = item.due {
                var dc = Calendar.current.dateComponents([.year, .month, .day], from: due)
                if item.hasTime {
                    let hm = Calendar.current.dateComponents([.hour, .minute], from: due)
                    dc.hour = hm.hour; dc.minute = hm.minute
                }
                r.dueDateComponents = dc
                if item.remindMinutes > 0 {
                    r.alarms = [makeAlarm(item.remindMinutes)]
                }
            }
            try? store.save(r, commit: true)
            item.id = r.calendarItemIdentifier
        }
        items.insert(item, at: 0)
        saveCache()
    }

    func update(_ item: TodoItem) async {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item }
        saveCache()
        guard authorized, let r = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        r.title = item.title
        r.notes = item.storedNote.isEmpty ? nil : item.storedNote
        if let due = item.due {
            var dc = Calendar.current.dateComponents([.year, .month, .day], from: due)
            if item.hasTime {
                let hm = Calendar.current.dateComponents([.hour, .minute], from: due)
                dc.hour = hm.hour; dc.minute = hm.minute
            }
            r.dueDateComponents = dc
            r.alarms = item.remindMinutes > 0 ? [makeAlarm(item.remindMinutes)] : nil
        } else {
            r.dueDateComponents = nil
            r.alarms = nil
        }
        r.priority = [0, 9, 5, 1][min(3, max(0, item.priority))]
        // 重复规则（每天 / 工作日）。EKWeekday 枚举：.monday ... .friday。
        switch item.repeatRule {
        case "daily":
            r.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)]
        case "workday":
            r.recurrenceRules = [EKRecurrenceRule(
                recurrenceWith: .weekly, interval: 1,
                daysOfTheWeek: Self.workdays.map { EKRecurrenceDayOfWeek($0) },
                daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil,
                daysOfTheYear: nil, setPositions: nil, end: nil)]
        default:
            r.recurrenceRules = nil
        }
        try? store.save(r, commit: true)
    }

    /// 工作日 = 周一到周五
    private static let workdays: [EKWeekday] = [.monday, .tuesday, .wednesday, .thursday, .friday]

    func setDone(_ item: TodoItem, _ done: Bool) async {
        var v = item
        v.done = done
        v.completedAt = done ? (item.completedAt ?? Date()) : nil
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = v }
        saveCache()
        guard authorized, let r = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        // completionDate 要自己写：只把 isCompleted 置 true 时，系统不保证给出完成时间，
        // 那样已完成列表里就没有「完成于」可显示。
        r.completionDate = v.completedAt
        r.isCompleted = done
        try? store.save(r, commit: true)
    }

    // MARK: - 截止过期自动完成

    private let autoDoneKey = "mowangda.autoDone.v1"

    /// 过了截止时间还没完成的条目，自动转到已完成。
    /// 三条边界：
    ///   ① 只认「截止」类（详情页勾了截止），普通带时间的条目过期不自动完成；
    ///   ② 重复条目跳过——完成一条重复提醒会打断重复链，交给用户自己点；
    ///   ③ 用户手动「重开」过的条目不再自动完成，否则会被立刻又划掉（记在 autoDoneKey）。
    func autoCompleteExpiredDeadlines() async {
        guard authorized else { return }
        let now = Date()
        var already = Set(UserDefaults.standard.stringArray(forKey: autoDoneKey) ?? [])
        let expired = items.filter { item in
            guard !item.done, item.deadline, item.repeatRule == nil, let due = item.due else { return false }
            guard !already.contains(item.id) else { return false }
            return Self.deadlineMoment(item, due: due) < now
        }
        guard !expired.isEmpty else { return }
        for item in expired {
            already.insert(item.id)
            await setDone(item, true)
        }
        UserDefaults.standard.set(Array(already), forKey: autoDoneKey)
    }

    /// 截止时刻：有时间就用那个具体时刻；全天事项算到当天 23:59:59，
    /// 否则它会在当天 0 点就被判成过期、刚记下就自己划掉了。
    private static func deadlineMoment(_ item: TodoItem, due: Date) -> Date {
        if item.hasTime { return due }
        let cal = Calendar.current
        let start = cal.startOfDay(for: due)
        return cal.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? start
    }

    func delete(ids: Set<String>) async {
        items.removeAll { ids.contains($0.id) }
        saveCache()
        guard authorized else { return }
        for id in ids {
            if let r = store.calendarItem(withIdentifier: id) as? EKReminder {
                try? store.remove(r, commit: true)
            }
        }
    }

    // MARK: - 提醒

    /// 提前 N 分钟的提醒。
    /// 注意：不要给 EKAlarm 设 soundName —— 那个属性只有 macOS 有，
    /// iOS 上编译直接报 'soundName' is unavailable in iOS。
    /// 到点用什么声音、振几下，由系统「提醒事项」自己决定。
    private func makeAlarm(_ minutes: Int) -> EKAlarm {
        EKAlarm(relativeOffset: TimeInterval(-minutes * 60))
    }

    // MARK: - 列表

    private func workCalendar() -> EKCalendar? {
        store.calendars(for: .reminder).first { $0.title == listName }
    }

    private func ensureCalendar() -> EKCalendar? {
        if let c = workCalendar() { return c }
        guard let source = store.defaultCalendarForNewReminders()?.source else { return nil }
        let c = EKCalendar(for: .reminder, eventStore: store)
        c.title = listName
        c.source = source
        do { try store.saveCalendar(c, commit: true); return c } catch { return nil }
    }

    // MARK: - 本地缓存

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let arr = try? JSONDecoder().decode([TodoItem].self, from: data) else { return }
        items = arr
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        // 数据一变就同步一份快照给桌面小组件
        WidgetBridge.publish(items: items)
    }
}
