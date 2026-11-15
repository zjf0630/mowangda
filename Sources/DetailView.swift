import SwiftUI

/// 详情编辑：改完即回写提醒事项。
struct DetailView: View {
    @ObservedObject var store: ReminderStore
    @Environment(\.dismiss) private var dismiss

    let item: TodoItem
    @State private var title: String = ""
    @State private var due: Date = Date()
    @State private var hasTime: Bool = true
    @State private var hasDue: Bool = true
    @State private var remind: Int = 15
    @State private var listName: String = "工作"
    @State private var priority: Int = 0
    @State private var note: String = ""
    @State private var deadline: Bool = false
    @State private var repeatRule: String? = nil

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                navBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        TextField("事项标题", text: $title)
                            .font(.system(size: Theme.fs(19), weight: .semibold))
                            .padding(.horizontal, 22).padding(.vertical, 12)
                        rows
                        noteBox
                        HStack(spacing: 6) {
                            Circle().fill(Theme.accent).frame(width: 5, height: 5)
                            Text(store.authorized ? "已同步到提醒事项" : "本地保存（未授权提醒事项）")
                                .font(.system(size: Theme.fs(10.5))).foregroundColor(Theme.muted)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 16)
                        Button {
                            Task {
                                await store.delete(ids: [item.id])
                                dismiss()
                            }
                        } label: {
                            Text("删除事项").font(.system(size: Theme.fs(12.5))).foregroundColor(Theme.danger)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 22)
                    }
                }
            }
        }
        .onAppear { load() }
        .onDisappear { commit() }
    }

    private var navBar: some View {
        HStack {
            Button("‹ 返回") { dismiss() }
            Spacer()
            Text("提醒事项").font(.system(size: Theme.fs(12))).foregroundColor(Theme.muted)
            Spacer()
            Button("完成") { dismiss() }
        }
        .font(.system(size: Theme.fs(13)))
        .padding(.horizontal, 22).padding(.top, 12)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            row("时间") {
                if hasDue {
                    HStack(spacing: 8) {
                        Toggle("", isOn: $hasTime).labelsHidden().fixedSize()
                        if hasTime {
                            DatePicker("", selection: Binding(
                                get: { due },
                                set: { due = $0; hasTime = true }
                            ), displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
                                .labelsHidden().environment(\.locale, Locale(identifier: "zh_CN"))
                        } else {
                            DatePicker("", selection: Binding(
                                get: { due },
                                set: { due = $0; hasTime = false }
                            ), displayedComponents: [.date])
                                .labelsHidden().environment(\.locale, Locale(identifier: "zh_CN"))
                        }
                    }
                } else {
                    Button("设定时间") { hasDue = true }
                        .font(.system(size: Theme.fs(12.5), weight: .medium)).foregroundColor(Theme.accent)
                }
            }
            divider
            row("列表") {
                Menu {
                    Button("工作") { listName = "工作" }
                    Button("个人") { listName = "个人" }
                } label: {
                    Text(listName).font(.system(size: Theme.fs(12.5), weight: .medium))
                }
            }
            divider
            row("优先级") {
                Menu {
                    ForEach(0..<4, id: \.self) { p in
                        Button(Theme.priorityName(p)) { priority = p }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Theme.priority(priority) ?? Theme.tick)
                            .frame(width: 8, height: 8)
                        Text(Theme.priorityName(priority))
                            .font(.system(size: Theme.fs(12.5), weight: .medium))
                    }
                }
            }
            divider
            row("提醒") {
                Menu {
                    ForEach([0, 15, 30, 60], id: \.self) { m in
                        Button(m == 0 ? "不提醒" : "提前 \(m) 分钟") { remind = m }
                    }
                } label: {
                    Text(remind == 0 ? "不提醒" : "提前 \(remind) 分钟")
                        .font(.system(size: Theme.fs(12.5), weight: .medium))
                }
            }
            divider
            if hasDue {
                row("重复") {
                    Menu {
                        Button("不重复") { repeatRule = nil }
                        Button("每天") { repeatRule = "daily" }
                        Button("工作日（周一到周五）") { repeatRule = "workday" }
                    } label: {
                        HStack(spacing: 6) {
                            if let r = repeatRule, r != "custom" {
                                Image(systemName: "repeat")
                                    .font(.system(size: Theme.fs(9), weight: .semibold))
                                    .foregroundColor(Theme.accent)
                            }
                            Text(repeatName(repeatRule))
                                .font(.system(size: Theme.fs(12.5), weight: .medium))
                        }
                    }
                }
                divider
            }
            row("截止") {
                Toggle("", isOn: $deadline).labelsHidden().fixedSize()
            }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1)))
        .padding(.horizontal, 20).padding(.top, 8)
    }

    private var divider: some View { Rectangle().fill(Theme.line).frame(height: 1) }

    private func repeatName(_ r: String?) -> String {
        switch r {
        case "daily": return "每天"
        case "workday": return "工作日"
        case "custom": return "重复"
        default: return "不重复"
        }
    }

    private func row<K: View>(_ key: String, @ViewBuilder value: () -> K) -> some View {
        HStack {
            Text(key).font(.system(size: Theme.fs(12.5))).foregroundColor(Theme.muted)
            Spacer()
            value()
        }
        .padding(.horizontal, 15).padding(.vertical, 12)
    }

    private var noteBox: some View {
        TextField("备注…", text: $note, axis: .vertical)
            .font(.system(size: Theme.fs(12.5))).lineLimit(2...5)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1)))
            .padding(.horizontal, 20).padding(.top, 10)
    }

    private func load() {
        title = item.title
        due = item.due ?? Date()
        hasDue = item.due != nil
        hasTime = item.hasTime
        remind = item.remindMinutes
        listName = item.listName
        priority = item.priority
        note = item.note
        deadline = item.deadline
        repeatRule = item.repeatRule
    }

    private func commit() {
        var v = item
        v.title = title.isEmpty ? item.title : title
        v.due = hasDue ? due : nil
        v.hasTime = hasDue && hasTime
        v.remindMinutes = remind
        v.listName = listName
        v.priority = priority
        v.note = note
        v.deadline = deadline
        // 没设时间的事项谈不到重复
        v.repeatRule = hasDue ? repeatRule : nil
        if v != item {
            Task { await store.update(v) }
        }
    }
}
