import WidgetKit
import SwiftUI

// 桌面小组件：显示当天最多 3 条提醒事项。
// 数据来自主 App 通过 App Group 写入的快照（Shared/WidgetSnapshot.swift）。
// 小组件本身不读提醒事项数据库——独立进程没有权限，也不该重复请求授权。

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: WidgetReader.read() ?? Self.sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetReader.read())
        // 半小时后让系统再要一次新数据；主 App 里的增删改也会主动触发刷新
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800))))
    }

    // 添加小组件时的预览样例
    private static let sample = WidgetSnapshot(
        dateText: "11月15日 周日",
        items: [
            WidgetItem(title: "上午项目周会", timeText: "09:30", priority: 2, repeatName: "工作日"),
            WidgetItem(title: "回复客户邮件", timeText: "11:00", priority: 0, repeatName: nil),
            WidgetItem(title: "下午 3 点评审", timeText: "15:00", priority: 3, repeatName: nil),
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
    let entry: SnapshotEntry

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
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(c.accent)
                Text(snap.dateText)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(c.muted)
                Spacer()
                Text("今天 \(snap.total) 条")
                    .font(.system(size: 10))
                    .foregroundColor(c.muted)
            }
            ForEach(snap.items.prefix(3), id: \.self) { item in
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(c.priority(item.priority))
                        .frame(width: 3, height: 26)
                    Text(item.timeText)
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundColor(c.muted)
                        .frame(width: 34, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(c.ink)
                            .lineLimit(1)
                        if let r = item.repeatName {
                            Text(r).font(.system(size: 9)).foregroundColor(c.muted)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            if snap.total > snap.items.count {
                Text("还有 \(snap.total - snap.items.count) 条，打开查看")
                    .font(.system(size: 9.5))
                    .foregroundColor(c.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    // 读到了快照但今天确实没有安排
    private func empty(_ c: MoPalette) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "checklist")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(c.accent.opacity(0.6))
            Text("今天没有安排")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(c.ink)
            Text("打开莫忘哒记一条吧")
                .font(.system(size: 9.5))
                .foregroundColor(c.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // 连快照都读不到：要么还没打开过 App，要么签名时 App Group 能力被去掉了
    private func noData(_ c: MoPalette) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(c.accent.opacity(0.6))
            Text("先打开莫忘哒")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(c.ink)
            Text("打开一次 App，这里就会显示今天的安排")
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
        .description("显示今天的提醒事项（最多 3 条）")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct MoWangDaWidgetBundle: WidgetBundle {
    var body: some Widget {
        MoWangDaWidget()
    }
}
