import SwiftUI

struct RootView: View {
    @StateObject private var store = ReminderStore()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @State private var showCompose = false
    @State private var showSettings = false
    @State private var doneOpen = false
    @State private var selectMode = false
    @State private var selected: Set<String> = []
    @State private var detailItem: TodoItem? = nil

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                listBody
            }
            bottomBar
        }
        .sheet(isPresented: $showCompose) { ComposeView(store: store) }
        .sheet(isPresented: $showSettings) { SettingsView(store: store) }
        .sheet(item: $detailItem) { item in
            DetailView(store: store, item: item)
        }
        .task {
            await store.requestAccess()
        }
        .onChange(of: scenePhase) { _, phase in
            // 回到前台时重新读一遍，提醒事项里外部改动能立刻反映出来
            if phase == .active { Task { await store.sync() } }
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
            HStack(spacing: 8) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.ink2)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Theme.card))
                        .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("设置")

                Button {
                    withAnimation { selectMode.toggle(); selected.removeAll() }
                } label: {
                    Text(selectMode ? "取消" : "选择")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.ink2)
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(Capsule().fill(Theme.card))
                        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 12)
    }

    private var dateLine: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"
        return f.string(from: Date())
    }

    // MARK: - 列表

    /// 把分组头、条目、折叠头拍平成一维行模型。
    /// 用 List 而不是 ScrollView 的原因：swipeActions（左滑）只对 List 的直接行生效。
    private enum Row: Identifiable {
        case section(String, Int, Date?)
        case task(TodoItem)
        case doneHead(Int)
        case empty
        case tail

        var id: String {
            switch self {
            case .section(let n, _, _): return "s-" + n
            case .task(let t): return "t-" + t.id
            case .doneHead: return "done-head"
            case .empty: return "empty"
            case .tail: return "tail"
            }
        }
    }

    private var rows: [Row] {
        let today = Calendar.current.startOfDay(for: Date())
        let active = store.items.filter { !$0.done }.sorted(by: Self.cmp)
        let done = store.items.filter { $0.done }.sorted(by: Self.cmp)
        var out: [Row] = []

        func add(_ name: String, _ list: [TodoItem]) {
            guard !list.isEmpty else { return }
            out.append(.section(name, list.count, list.first?.due))
            list.forEach { out.append(.task($0)) }
        }
        add("今天", active.filter { Self.dayDiff($0, today) <= 0 })
        add("明天", active.filter { Self.dayDiff($0, today) == 1 })
        let rest = active.filter { Self.dayDiff($0, today) > 1 && $0.due != nil }
        add("本周", rest.filter { Self.dayDiff($0, today) < 7 })
        add("以后", rest.filter { Self.dayDiff($0, today) >= 7 })
        add("时间待定", active.filter { $0.due == nil })

        if !done.isEmpty {
            out.append(.doneHead(done.count))
            if doneOpen { done.forEach { out.append(.task($0)) } }
        }
        if store.items.isEmpty { out.append(.empty) }
        out.append(.tail)
        return out
    }

    private var listBody: some View {
        List {
            ForEach(rows) { r in
                switch r {
                case .section(let name, let count, let date):
                    sectionHeader(name, count: count, date: date)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                case .task(let item):
                    row(item)
                case .doneHead(let count):
                    doneHeader(count)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                case .empty:
                    emptyHint
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                case .tail:
                    Color.clear.frame(height: 104)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
    }

    private func doneHeader(_ count: Int) -> some View {
        Button {
            withAnimation { doneOpen.toggle() }
        } label: {
            HStack {
                Text("已完成 · \(count) 项").font(.system(size: 11.5, weight: .medium))
                Spacer()
                Text(doneOpen ? "收起 ▴" : "展开 ▾").font(.system(size: 10.5))
            }
            .foregroundColor(Theme.muted)
            .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 8)
        }
        .buttonStyle(.plain)
    }

    private var emptyHint: some View {
        Text("还没有事项\n点下面「＋ 记一条」，说一句就行")
            .font(.system(size: 12.5)).foregroundColor(Theme.faint)
            .multilineTextAlignment(.center).lineSpacing(6)
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
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
        // 优先级配色：整张卡片淡染一层，描边同色加深，左竖条用实色
        let dark = scheme == .dark
        let pc = Theme.priority(item.priority)
        let fillColor: Color = item.done ? .clear : Theme.priorityFill(item.priority, dark: dark)
        let strokeColor: Color = item.done ? .clear : Theme.priorityStroke(item.priority, dark: dark)
        let barColor: Color = item.done ? .clear
            : (pc ?? (item.deadline ? Theme.amber : (item.due == nil ? Theme.barNone : Theme.accent)))

        return Button { tap(item) } label: {
            HStack(alignment: .top, spacing: 10) {
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
                            .strokeBorder(picked ? Theme.accent : Theme.tick, lineWidth: 1.5)
                            .background(Circle().fill(picked ? Theme.accent : Color.clear))
                            .frame(width: 21, height: 21)
                    } else {
                        ZStack {
                            Circle()
                                .fill(item.done ? Theme.accent : Color.clear)
                                .frame(width: 21, height: 21)
                            Circle()
                                .strokeBorder(item.done ? Theme.accent : Theme.tick, lineWidth: 1.5)
                                .frame(width: 21, height: 21)
                            if item.done {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(Theme.card)
                            }
                        }
                    }
                }
                .padding(11)
                .background(RoundedRectangle(cornerRadius: 14).fill(fillColor)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(strokeColor, lineWidth: 1)))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor)
                        .frame(width: 3)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 只保留向左滑，两个按钮都在右侧；顺序按要求：完成在左、删除在最右。
        // 全滑关掉——删除是不可逆的，必须点一下，避免手滑把事项划没了。
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !selectMode {
                Button(role: .destructive) {
                    Task { await store.delete(ids: [item.id]) }
                } label: {
                    Label("删除", systemImage: "trash")
                }

                Button {
                    Task { await store.setDone(item, !item.done) }
                } label: {
                    Label(item.done ? "重开" : "完成",
                          systemImage: item.done ? "arrow.uturn.backward" : "checkmark")
                }
                .tint(Theme.accent)
            }
        }
        // 长按：同一组动作，不用记手势方向
        .contextMenu {
            Button {
                Task { await store.setDone(item, !item.done) }
            } label: {
                Label(item.done ? "标记为未完成" : "标记为已完成",
                      systemImage: item.done ? "arrow.uturn.backward.circle" : "checkmark.circle")
            }
            Button(role: .destructive) {
                Task { await store.delete(ids: [item.id]) }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func tap(_ item: TodoItem) {
        if selectMode {
            if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
        } else {
            detailItem = item
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
                        .foregroundColor(Theme.ink2)
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(Capsule().fill(Theme.card))
                        .overlay(Capsule().stroke(Theme.edge, lineWidth: 1))
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
                        .foregroundColor(Theme.bg)
                }
                .disabled(selected.isEmpty)
            } else {
                Button { showCompose = true } label: {
                    Text("＋ 记一条").font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 24).padding(.vertical, 12)
                        .background(Capsule().fill(Theme.accent)).foregroundColor(Theme.bg)
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
        var s: String
        if item.deadline { s = item.listName + " · 截止" }
        else if item.due == nil { s = item.listName + " · 时间待定" }
        else if !item.hasTime { s = item.listName + " · 全天" }
        else { s = item.listName + (item.remindMinutes > 0 ? " · 提前\(item.remindMinutes)分钟" : " · 不提醒") }
        if item.priority > 0 && !item.done { s += " · " + Theme.priorityName(item.priority) }
        return s
    }
}

extension Color {
    init(hex: UInt) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
