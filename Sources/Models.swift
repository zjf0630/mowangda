import SwiftUI

/// 与网页原型一致的品牌色板
enum Theme {
    static let bg = Color(red: 0.969, green: 0.965, blue: 0.953)      // F7F6F3
    static let card = Color.white
    static let ink = Color(red: 0.114, green: 0.114, blue: 0.122)     // 1D1D1F
    static let ink2 = Color(red: 0.290, green: 0.290, blue: 0.306)    // 4A4A4E
    static let muted = Color(red: 0.557, green: 0.557, blue: 0.576)   // 8E8E93
    static let faint = Color(red: 0.706, green: 0.702, blue: 0.686)   // B4B2AB
    static let line = Color(red: 0.914, green: 0.906, blue: 0.882)    // E9E7E1
    static let accent = Color(red: 0.059, green: 0.431, blue: 0.337)  // 0F6E56
    static let accentSoft = Color(red: 0.882, green: 0.961, blue: 0.933) // E1F5EE
    static let amber = Color(red: 0.729, green: 0.459, blue: 0.090)   // BA7517
    static let danger = Color(red: 0.639, green: 0.176, blue: 0.176)  // A32D2D

    /// 优先级配色：3 高=红、2 中=琥珀、1 低=墨绿、0 无=nil（走白卡）
    /// 都是低饱和的品牌色，卡片填充只取 0.10 透明度，靠"整片淡淡一层"区分，不抢文字
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

    var deadlineMark: String { deadline ? "[截止]" : "" }
    var storedNote: String { deadlineMark + note }
}

struct ParsedItem {
    var title: String
    var due: Date?
    var hasTime: Bool
    var deadline: Bool
    var listName: String = "工作"
}
