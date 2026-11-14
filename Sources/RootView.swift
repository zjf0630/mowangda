import SwiftUI

struct RootView: View {
    @StateObject private var store = ReminderStore()
    @State private var showCompose = false
    @State private var doneOpen = false
    @State private var selectMode = false
    @State private var selected: Set<String> = []
    @State private var detailItem: TodoItem? = nil

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                inputCard
                ScrollView {
                    listBody
                }
            }
            bottomBar
        }
        .sheet(isPresented: $showCompose) { ComposeView(store: store) }
        .sheet(item: $detailItem) { item in
            DetailView(store: store, item: item)
        }
        .task {
            await store.requestAccess()
            await store.sync()
        }
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text(dateLine).font(.system(size: 12)).foregroundColor(Theme.muted)
                Text("莫忘哒").font(.system(size: 26, weight: .semibold)).foregroundColor(Theme.ink)
            }
            Spacer()
            Button {
                withAnimation { selectMode.toggle(); selected.removeAll() }
            } label: {
                Text(selectMode ? "取消" : "选择")
                    .font(.system(size: 12))
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(Color.white)
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 12)
    }

    private var dateLine: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"
        return f.string(from: Date())
    }

    // MARK: - 输入卡

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("记一行，比如「明早9点跟张总对方案」")
                .font(.system(size: 13.5)).foregroundColor(Theme.faint)
            HStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34).background(Circle().fill(Theme.accent))
                Text("长按说话，松手成条（原型版点输入卡直接录入）")
                    .font(.system(size: 11)).foregroundColor(Theme.muted)
                Spacer()
                Image(systemName: "arrow.up").font(.system(size: 14)).foregroundColor(Theme.faint)
                    .frame(width: 30, height: 30).background(Circle().fill(Theme.bg))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.line, lineWidth: 1)))
        .padding(.horizontal, 20)
        .onTapGesture { showCompose = true }
        .opacity(selectMode ? 0.55 : 1)
        .disabled(selectMode)
    }

    // MARK: - 列表

    private var listBody: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let active = store.items.filter { !$0.done }.sorted(by: Self.cmp)
        let done = store.items.filter { $0.done }.sorted(by: Self.cmp)
        var groups: [(String, [TodoItem])] = []

        var buffer: [TodoItem] = []
        func flush(_ name: String, _ list: [TodoItem]) {
            if !list.isEmpty { groups.append((name, list)) }
        }
        flush("今天", active.filter { Self.dayDiff($0, today) <= 0 })
        flush("明天", active.filter { Self.dayDiff($0, today) == 1 })
        let rest = active.filter { Self.dayDiff($0, today) > 1 && $0.due != nil }
        flush("本周", rest.filter { Self.dayDiff($0, today) < 7 })
        flush("以后", rest.filter { Self.dayDiff($0, today) >= 7 })
        buffer = active.filter { $0.due == nil }
        flush("时间待定", buffer)

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(groups, id: \.0) { pair in
                sectionHeader(pair.0, count: pair.1.count, date: pair.1.first?.due)
                ForEach(pair.1) { item in row(item) }
            }
            if !done.isEmpty {
                Button {
                    withAnimation { doneOpen.toggle() }
                } label: {
                    HStack {
                        Text("已完成 · \(done.count) 项").font(.system(size: 11.5, weight: .medium))
                        Spacer()
                        Text(doneOpen ? "收起 ▴" : "展开 ▾").font(.system(size: 10.5))
                    }
                    .foregroundColor(Theme.muted)
                    .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 8)
                }
                .buttonStyle(.plain)
                if doneOpen {
                    ForEach(done) { item in row(item) }
                }
            }
            if store.items.isEmpty {
                VStack(spacing: 6).frame(height: 60)
                Text("还没有事项\n点下面「＋ 记一条」，说一句就行")
                    .font(.system(size: 12.5)).foregroundColor(Theme.faint)
                    .multilineTextAlignment(.center).lineSpacing(6)
            }
            Color.clear.frame(height: 110)
        }
    }

    private func sectionHeader(_ name: String, count: Int, date: Date?) -> some View {
        HStack(spacing: 8) {
            Text(sectionTitle(name, date: date)).font(.system(size: 11.5, weight: .medium))
            Rectangle().fill(Theme.line).frame(height: 1)
            Text("\(count) 项").font(.system(size: 10.5)).foregroundColor(Theme.faint)
        }
        .foregroundColor(Theme.muted)
        .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 8)
    }

    private func sectionTitle(_ name: String, date: Date?) -> String {
        guard let d = date else { return name }
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return name + " · " + f.string(from: d)
    }

    private func row(_ item: TodoItem) -> some View {
        let picked = selected.contains(item.id)
        return HStack(alignment: .top, spacing: 10) {
            Text(timeText(item))
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(item.hasTime ? Theme.muted : Theme.faint)
                .frame(width: 42, alignment: .leading).padding(.top, 13)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(item.done ? Theme.faint : Theme.ink)
                        .strikethrough(item.done)
                        .lineLimit(2)
                    Text(subText(item)).font(.system(size: 10.5)).foregroundColor(Theme.muted)
                }
                Spacer()
                if selectMode {
                    Circle()
                        .strokeBorder(picked ? Theme.accent : Color(hex: 0xD8D5CD), lineWidth: 1.5)
                        .background(Circle().fill(picked ? Theme.accent : Color.clear))
                        .frame(width: 21, height: 21)
                } else {
                    ZStack {
                        Circle().strokeBorder(item.done ? Theme.accent : Color(hex: 0xD8D5CD), lineWidth: 1.5)
                        if item.done {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                        }
                    }.frame(width: 21, height: 21)
                }
            }
            .padding(11)
            .background(RoundedRectangle(cornerRadius: 14).fill(item.done ? .clear : Color.white)
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .stroke(item.done ? .clear : Theme.line, lineWidth: 1)))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(item.done ? .clear : (item.deadline ? Theme.amber : (item.due == nil ? Color(hex: 0xDCD9D1) : Theme.accent)))
                    .frame(width: 2.5)
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if selectMode {
                if picked { selected.remove(item.id) } else { selected.insert(item.id) }
            } else {
                detailItem = item
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if selectMode {
                Button {
                    let ids = store.items.map(\.id)
                    let all = !ids.isEmpty && ids.allSatisfy { selected.contains($0) }
                    selected = all ? [] : Set(ids)
                } label: {
                    Text("全选").font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(Capsule().fill(Color.white))
                        .overlay(Capsule().stroke(Color(hex: 0xE0DDD5), lineWidth: 1))
                }
                Button {
                    let ids = selected
                    Task {
                        await store.delete(ids: ids)
                        selected.removeAll(); selectMode = false
                    }
                } label: {
                    Text("删除（\(selected.count)）").font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(Capsule().fill(selected.isEmpty ? Theme.danger.opacity(0.45) : Theme.danger))
                        .foregroundColor(.white)
                }
                .disabled(selected.isEmpty)
            } else {
                Button { showCompose = true } label: {
                    Text("＋ 记一条").font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 24).padding(.vertical, 12)
                        .background(Capsule().fill(Theme.accent)).foregroundColor(.white)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 26)
    }

    // MARK: - 工具

    private static func dayDiff(_ item: TodoItem, _ today: Date) -> Int {
        guard let d = item.due else { return 999 }
        return Calendar.current.dateComponents([.day], from: today, to: Calendar.current.startOfDay(for: d)).day ?? 999
    }

    private static func cmp(_ a: TodoItem, _ b: TodoItem) -> Bool {
        switch (a.due, b.due) {
        case (nil, nil): return false
        case (nil, _): return false      // 无时间排组尾
        case (_, nil): return true
        case (let x?, let y?): return x < y
        }
    }

    private func timeText(_ item: TodoItem) -> String {
        guard let d = item.due else { return "—" }
        if item.hasTime {
            let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
        }
        return "全天"
    }

    private func subText(_ item: TodoItem) -> String {
        if item.deadline { return item.listName + " · 截止" }
        if item.due == nil { return item.listName + " · 时间待定" }
        if !item.hasTime { return item.listName + " · 全天" }
        return item.listName + (item.remindMinutes > 0 ? " · 提前\(item.remindMinutes)分钟" : " · 不提醒")
    }
}

extension Color {
    init(hex: UInt) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
