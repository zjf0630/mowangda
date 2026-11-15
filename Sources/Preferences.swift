import Foundation
import EventKit

/// 提醒声音偏好。
///
/// EventKit 对"提醒"能控制的只有一件事：到期提醒用哪个系统声音（EKAlarm.soundName）。
/// - nil          → 跟随系统默认（静音开关打开时只振动，非静音时放默认提示音）
/// - ""           → 静音，只弹通知不出声
/// - 系统声音名   → 指定铃声，例如短信的三全音 "sms-received1.caf"
///
/// 做不到的：振动次数。iOS 不给第三方 App 控制振动的接口，
/// 提醒到期的振动一次还是三次，完全由系统「提醒事项」的通知设置决定。
enum AlarmTone: String, CaseIterable, Identifiable {
    case system
    case none
    case sms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "默认（振动）"
        case .none:   return "静音"
        case .sms:    return "短信提示音"
        }
    }

    var detail: String {
        switch self {
        case .system: return "系统默认提示音，静音模式下只振动"
        case .none:   return "到期只弹通知，不响铃不振动"
        case .sms:    return "三全音，跟来短信一样"
        }
    }

    /// 传给 EKAlarm.soundName 的值
    var soundName: String? {
        switch self {
        case .system: return nil
        case .none:   return ""
        case .sms:    return "sms-received1.caf"
        }
    }

    private static let key = "mowangda.alarmTone.v1"

    static var current: AlarmTone {
        get { AlarmTone(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}
