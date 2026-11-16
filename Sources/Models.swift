import SwiftUI
import UIKit

/// 品牌色板。每一条都是「浅色 / 深色」成对的动态色，
/// 由 UIColor 的 dynamic provider 在运行时按 userInterfaceStyle 取值，
/// 所以切换系统深色模式时整站会自动换色，不需要在视图里到处判断。
enum Theme {
    static let bg          = dyn(0xF7F6F3, 0x0F1211)   // 页面底
    static let card        = dyn(0xFFFFFF, 0x1B1F1E)   // 卡片 / 输入框底
    static let ink         = dyn(0x1D1D1F, 0xF2F3F1)   // 主文字
    static let ink2        = dyn(0x4A4A4E, 0xBFC2BE)   // 次文字
    static let muted       = dyn(0x8E8E93, 0x9A9E9B)   // 弱文字
    static let faint       = dyn(0xB4B2AB, 0x6B706C)   // 更弱 / 已完成
    static let line        = dyn(0xE9E7E1, 0x2A2F2C)   // 描边、分隔线
    static let accent      = dyn(0x0F6E56, 0x46C79E)   // 品牌墨绿（深色下提亮）
    static let accentSoft  = dyn(0xE1F5EE, 0x153A2F)   // 墨绿淡底
    static let amber       = dyn(0xBA7517, 0xE3A94F)   // 琥珀 / 截止
    static let danger      = dyn(0xA32D2D, 0xE2685F)   // 红 / 删除
    static let tick        = dyn(0xD8D5CD, 0x4A504C)   // 未勾选圆圈
    static let barNone     = dyn(0xDCD9D1, 0x3A403C)   // 无优先级左竖条
    static let chip        = dyn(0xF1EFE9, 0x262B28)   // 灰色小胶囊
    static let chipWarn    = dyn(0xFAEEDA, 0x3A2E17)   // 截止胶囊底
    static let chipWarnInk = dyn(0x854F0B, 0xE3A94F)
    static let disabled    = dyn(0xD9D6CE, 0x343A36)   // 禁用按钮
    static let edge        = dyn(0xE0DDD5, 0x3A403C)

    /// 优先级配色：3 高=红、2 中=琥珀、1 低=墨绿、0 无=nil（走普通卡）
    /// 都是低饱和的品牌色，卡片填充只取一层很淡的透明度，靠"整片淡淡一层"区分，不抢文字。
    static func priority(_ p: Int) -> Color? {
        switch p {
        case 3: return danger
        case 2: return amber
        case 1: return accent
        default: return nil
        }
    }

    static func priorityName(_ p: Int) -> String {
        switch p {
        case 3: return "高"
        case 2: return "中"
        case 1: return "低"
        default: return "无"
        }
    }

    /// 整卡染色的填充/描边。深色模式下同一个颜色在深底上更"糊"，
    /// 所以透明度要比浅色模式高一档，否则看起来像没上色。
    static func priorityFill(_ p: Int, dark: Bool) -> Color {
        guard let c = priority(p) else { return card }
        return c.opacity(dark ? 0.22 : 0.11)
    }

    static func priorityStroke(_ p: Int, dark: Bool) -> Color {
        guard let c = priority(p) else { return line }
        return c.opacity(dark ? 0.45 : 0.30)
    }

    /// 字号统一从这里走：设置页选了"大 / 特大"后全站字体按倍率放大。
    /// 所有用 .system(size:) 的地方都要包一层 fs()，新写界面别直接写 size。
    static func fs(_ s: CGFloat) -> CGFloat {
        s * Prefs.fontScale
    }
}

private func dyn(_ light: UInt, _ dark: UInt) -> Color {
    Color(uiColor: UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
    })
}

extension UIColor {
    convenience init(hex: UInt) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// 数据模型。权威数据在系统「提醒事项」，本地只做缓存。
struct TodoItem: Identifiable, Codable, Equatable {
    var id: String              // EventKit calendarItemIdentifier；未授权时用本地 UUID
    var title: String
    var due: Date?              // 有时间为具体时刻，无时间为当天 0 点
    var hasTime: Bool
    var deadline: Bool          // 以备注前缀 [截止] 持久化
    var listName: String
    var remindMinutes: Int      // 0 = 不提醒
    var note: String
    var priority: Int           // 0 无 1 低 2 中 3 高
    var done: Bool
    var repeatRule: String?     // nil/"" = 不重复；"daily" = 每天；"workday" = 工作日；"custom" = 其他重复
    /// 完成时间（EventKit 的 completionDate）。已完成列表里要显示「完成于哪天」。
    /// 可选是为了兼容旧缓存：旧数据没有这个字段，解出来是 nil。
    var completedAt: Date? = nil

    var deadlineMark: String { deadline ? "[截止]" : "" }
    var storedNote: String { deadlineMark + note }

    var repeatName: String? {
        switch repeatRule {
        case "daily": return "每天"
        case "workday": return "工作日"
        case "custom": return "重复"
        default: return nil
        }
    }
}

struct ParsedItem {
    var title: String
    var due: Date?
    var hasTime: Bool
    var deadline: Bool
    var listName: String = "工作"
}
