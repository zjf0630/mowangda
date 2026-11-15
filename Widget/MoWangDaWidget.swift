import WidgetKit
import SwiftUI

// 桌面小组件：按时间顺序显示「接下来」最多 3 条提醒，不限定今天。
// 数据来源优先直读系统提醒事项库（Widget/LiveReminders.swift），
// 读不到时退回主 App 通过 App Group 写入的快照（Shared/WidgetSnapshot.swift）。

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        Task {
            let snap = await Self.load()
            completion(SnapshotEntry(date: .now, snapshot: snap ?? Self.sample))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        Task {
            let snap = await Self.load()
            let entry = SnapshotEntry(date: .now, snapshot: snap)
            // 半小时后让系统再来取一次；每次取数据都会重新直读提醒事项库，
            // 所以只要权限通，数据始终是最新的，不依赖打开 App
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800))))
        }
    }

    /// 数据源优先级：① 小组件直读系统提醒事项库（不依赖打开 App）
    /// ② App Group 快照（App 最后一次运行时写的）→ 都没有才显示引导
    static func load() async -> WidgetSnapshot? {
        if let live = await LiveReminders.snapshot() { return live }
        return WidgetReader.read()
    }

    // 添加小组件时的预览样例
    private static let sample = WidgetSnapshot(
        dateText: "11月15日 周日",
        items: [
            WidgetItem(title: "上午项目周会", timeText: "09:30", priority: 2, repeatName: "工作日", dayText: "逾期"),
            WidgetItem(title: "回复客户邮件", timeText: "11:00", priority: 0, repeatName: nil, dayText: "今天"),
            WidgetItem(title: "客户现场拜访", timeText: "09:00", priority: 3, repeatName: nil, dayText: "明天"),
        ],
        total: 5,
        updatedAt: .now
    )
}

// MARK: - 配色（与主 App 一致，深浅色各一套）

private struct MoPalette {
    let bg, card, ink, muted, line, accent, amber, danger, none: Color

    static func palette(_ dark: Bool) -> MoPalette {
        dark ? MoPalette(
            bg: Color(hex: 0x171B1A), card: Color(hex: 0x212624),
            ink: Color(hex: 0xF2F3F1), muted: Color(hex: 0x9A9E9B),
            line: Color(hex: 0x2A2F2C), accent: Color(hex: 0x46C79E),
            amber: Color(hex: 0xE3A94F), danger: Color(hex: 0xE2685F), none: Color(hex: 0x4A504C))
        : MoPalette(
            bg: Color(hex: 0xF7F6F3), card: Color(hex: 0xFFFFFF),
            ink: Color(hex: 0x1D1D1F), muted: Color(hex: 0x8E8E93),
            line: Color(hex: 0xE9E7E1), accent: Color(hex: 0x0F6E56),
            amber: Color(hex: 0xBA7517), danger: Color(hex: 0xA32D2D), none: Color(hex: 0xDCD9D1))
    }

    func priority(_ p: Int) -> Color {
        switch p {
        case 3: return danger
        case 2: return amber
        case 1: return accent
        default: return none
        }
    }
}

private extension Color {
    init(hex: UInt) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - 界面

struct MoWidgetView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var small: Bool { family == .systemSmall }

    var body: some View {
        let c = MoPalette.palette(scheme == .dark)
        Group {
            if let snap = entry.snapshot {
                if snap.items.isEmpty {
                    empty(c)
                } else {
                    content(snap, c)
                }
            } else {
                noData(c)
            }
        }
        .containerBackground(for: .widget) { c.bg }
        .widgetURL(URL(string: "mowangda://open"))
    }

    private func content(_ snap: WidgetSnapshot, _ c: MoPalette) -> some View {
        let maxRows = small ? 2 : 3
        let shown = Array(snap.items.prefix(maxRows))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "checklist")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(c.accent)
                Text("接下来")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(c.ink)
                Spacer(minLength: 4)
                Text("共 \(snap.total) 条")
                    .font(.system(size: 9.5))
                    .foregroundColor(c.muted)
            }
            ForEach(shown, id: \.self) { item in
                row(item, c)
            }
            if !small && snap.total > shown.count {
                Text("还有 \(snap.total - shown.count) 条，打开查看")
                    .font(.system(size: 9.5))
                    .foregroundColor(c.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
    }

    /// 一行：优先级竖条 + 日期/时间两行小字 + 标题（重复标记跟在标题后）
    private func row(_ item: WidgetItem, _ c: MoPalette) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(c.priority(item.priority))
                .frame(width: 3, height: 24)

            VStack(alignment: .leading, spacing: 0) {
                if let d = item.dayText, !d.isEmpty {
                    Text(d)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundColor(d == "逾期" ? c.danger : c.accent)
                }
                Text(item.timeText)
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundColor(c.muted)
            }
            .frame(width: 38, alignment: .leading)

            HStack(spacing: 4) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(c.ink)
                    .lineLimit(1)
                if let r = item.repeatName {
                    Text(r)
                        .font(.system(size: 8.5))
                        .foregroundColor(c.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 28)
    }

    // 读到了数据但一条待办都没有
    private func empty(_ c: MoPalette) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "checklist")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(c.accent.opacity(0.6))
            Text("还没有安排")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(c.ink)
            Text("打开莫忘哒记一条吧")
                .font(.system(size: 9.5))
                .foregroundColor(c.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // 连数据都读不到：提醒事项权限没给到小组件，App 快照也没有
    private func noData(_ c: MoPalette) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(c.accent.opacity(0.6))
            Text("先打开莫忘哒")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(c.ink)
            Text("提醒事项权限没连上，打开一次 App 再看")
                .font(.system(size: 9.5))
                .foregroundColor(c.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MoWangDaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MoWangDaWidget", provider: Provider()) { entry in
            MoWidgetView(entry: entry)
        }
        .configurationDisplayName("莫忘哒")
        .description("按时间顺序显示接下来的 3 条提醒（不限今天）")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct MoWangDaWidgetBundle: WidgetBundle {
    var body: some Widget {
        MoWangDaWidget()
    }
}
