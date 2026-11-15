import Foundation

/// 用户偏好。都放 UserDefaults，读写走静态属性，视图里直接用。
///
/// 这里**没有**"提醒铃声 / 振动"选项，是故意的：iPhone 上的 EventKit 不给第三方 App
/// 设置提醒声音的接口（EKAlarm.soundName 只在 macOS 可用，iOS 编译直接报
/// 'soundName' is unavailable in iOS），振动次数更没有。到点怎么响由系统决定，
/// 详见设置页里的说明。
enum Prefs {

    // MARK: - 默认提前提醒

    private static let leadKey = "mowangda.leadMinutes.v1"

    /// 新记条目默认提前多少分钟提醒；0 = 不提醒
    static var leadMinutes: Int {
        get {
            let d = UserDefaults.standard
            // 没存过时默认 15 分钟
            if d.object(forKey: leadKey) == nil { return 15 }
            return d.integer(forKey: leadKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: leadKey) }
    }

    static let leadOptions = [0, 5, 15, 30, 60]

    static func leadText(_ m: Int) -> String {
        m == 0 ? "不提醒" : "提前 \(m) 分钟"
    }
}
