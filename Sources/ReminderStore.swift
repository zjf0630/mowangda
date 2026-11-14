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
        if authorized { await sync() }
    }

    func sync() async {
        guard authorized else { return }
        let calendars = workCalendar().map { [$0] } ?? store.calendars(for: .reminder)
        let predicate = store.predicateForReminders(in: calendars)
        // EventKit 至今没有 async 版拉取接口，只能用 completion 包一层
        let reminders: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { result in
                cont.resume(returning: result ?? [])
            }
        }

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
                done: r.isCompleted
            )
        }
        lastSync = Date()
        saveCache()
    }

    // MARK: - 增删改

    func add(_ p: ParsedItem) async {
        var item = TodoItem(id: UUID().uuidString, title: p.title, due: p.due, hasTime: p.hasTime,
                            deadline: p.deadline, listName: p.listName,
                            remindMinutes: p.hasTime ? 15 : 0, note: "", priority: 0, done: false)
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
                    r.alarms = [EKAlarm(relativeOffset: TimeInterval(-item.remindMinutes * 60))]
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
            r.alarms = item.remindMinutes > 0 ? [EKAlarm(relativeOffset: TimeInterval(-item.remindMinutes * 60))] : nil
        } else {
            r.dueDateComponents = nil
            r.alarms = nil
        }
        r.priority = [0, 9, 5, 1][min(3, max(0, item.priority))]
        try? store.save(r, commit: true)
    }

    func setDone(_ item: TodoItem, _ done: Bool) async {
        var v = item
        v.done = done
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].done = done }
        saveCache()
        guard authorized, let r = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        r.isCompleted = done
        try? store.save(r, commit: true)
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
    }
}
