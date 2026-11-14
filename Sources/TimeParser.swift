import Foundation

/// 中文自然语言时间解析。规则与网页原型（JS 版）一致，11 条回归用例同源。
enum TimeParser {

    private static let weekMap: [String: Int] = ["一": 1, "二": 2, "三": 3, "四": 4,
                                                 "五": 5, "六": 6, "日": 0, "天": 0, "七": 0]
    private static let cnDigits: [String: Int] = ["零": 0, "一": 1, "二": 2, "两": 2, "三": 3,
                                                  "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]

    struct Raw {
        var title: String
        var due: Date?
        var hasTime: Bool
        var deadline: Bool
        var inferred: Bool = false
    }

    // MARK: - 对外入口

    static func parseAll(_ text: String, base: Date = Date()) -> [ParsedItem] {
        let prepared = text
            .replacingOccurrences(of: "然后", with: "，")
            .replacingOccurrences(of: "接着", with: "，")
            .replacingOccurrences(of: "还有", with: "，")
        let parts = prepared
            .split(whereSeparator: { "，,。；;\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var out: [ParsedItem] = []
        var lastDue: Date? = nil
        var lastPeriod: Int? = nil

        for p in parts {
            let r = parseOne(p, base: base, inheritPeriod: lastPeriod)
            var due = r.due
            if r.inferred, let ld = lastDue { due = ld }
            if let d = due, !r.inferred { lastDue = d }
            if let pe = r.period { lastPeriod = pe }
            out.append(ParsedItem(title: r.title, due: due, hasTime: r.hasTime,
                                  deadline: r.deadline, listName: "工作"))
        }
        return out
    }

    // MARK: - 单句解析

    private static func parseOne(_ raw: String, base: Date, inheritPeriod: Int?)
        -> (title: String, due: Date?, hasTime: Bool, deadline: Bool, inferred: Bool, period: Int?) {

        let cal = Calendar.current
        let today = cal.startOfDay(for: base)
        var s = " " + raw.trimmingCharacters(in: .whitespaces) + " "
        var due: Date? = nil
        var period: Int? = nil          // 0 早 1 午 2 傍晚 3 晚
        var explicitPeriod = false
        var hour: Int? = nil
        var minute = 0
        var deadline = false
        var consumed: [String] = []

        func cut(_ m: String) {
            consumed.append(m)
            s = s.replacingOccurrences(of: m, with: " ")
        }

        // 期限：截止 / 之前 / 紧跟时间词后的「前」
        if s.contains("截止") || s.contains("之前") || s.contains("以前")
            || firstMatch("(?:[日号点周天末底午晨晚]|[一二三四五六七八九十]|\\d)\\s*之?前", in: s) != nil {
            deadline = true
        }

        // 11月20号
        if let g = firstMatch("(\\d{1,2})\\s*月\\s*(\\d{1,2})\\s*[日号]", in: s) {
            let y = cal.component(.year, from: today)
            var cand = cal.date(from: DateComponents(year: y, month: Int(g[1]) ?? 1, day: Int(g[2]) ?? 1)) ?? today
            if cand < today, let n = cal.date(byAdding: .year, value: 1, to: cand) { cand = n }
            due = cand; cut(g[0])
        }

        // 下周一 / 下下周五
        if due == nil, let g = firstMatch("下(下)?(?:个)?(?:周|星期|礼拜)\\s*([一二三四五六日天七])", in: s) {
            let target = weekMap[g[2]] ?? 1
            let cur = cal.component(.weekday, from: today)          // 1=周日
            let curMonday = cal.date(byAdding: .day, value: -((cur + 5) % 7), to: today)!
            let baseMonday = cal.date(byAdding: .day, value: g[1] == "下" ? 14 : 7, to: curMonday)!
            let off = target == 0 ? 6 : target - 1
            due = cal.date(byAdding: .day, value: off, to: baseMonday)
            cut(g[0])
        }

        // 周三
        if due == nil, !s.contains("周末"),
           let g = firstMatch("(?:本)?(?:周|星期|礼拜)\\s*([一二三四五六日天七])", in: s) {
            let target = weekMap[g[1]] ?? 1
            let cur0 = cal.component(.weekday, from: today) % 7     // 周一=1 … 周日=0
            var diff = (target - cur0 + 7) % 7
            if diff == 0 { diff = 7 }
            due = cal.date(byAdding: .day, value: diff, to: today)
            cut(g[0])
        }

        // 周末
        if due == nil, s.contains("周末") {
            let cur0 = cal.component(.weekday, from: today) % 7
            let d = (6 - cur0 + 7) % 7
            due = cal.date(byAdding: .day, value: d == 0 ? 6 : d, to: today)
            consumed.append("周末")
            s = s.replacingOccurrences(of: "周末", with: " ")
        }

        // 月底
        if due == nil, s.contains("月底") || s.contains("月末") {
            let w = s.contains("月底") ? "月底" : "月末"
            let interval = cal.dateInterval(of: .month, for: today)
            due = interval.map { cal.startOfDay(for: $0.end.addingTimeInterval(-1)) }
            consumed.append(w)
            s = s.replacingOccurrences(of: w, with: " ")
        }

        // 三天后
        if due == nil, let g = firstMatch("(\\d{1,3}|[一二两三四五六七八九十]{1,3})\\s*天\\s*(?:以)?后", in: s) {
            due = cal.date(byAdding: .day, value: cnNum(g[1]) ?? 1, to: today)
            cut(g[0])
        }

        // 明天 / 后天 / 大后天 / 今晚 / 明早 …
        if due == nil {
            let rel: [(String, Int, Int?)] = [("大后天", 3, nil), ("后天", 2, nil), ("明天", 1, nil),
                                              ("明日", 1, nil), ("明早", 1, 0), ("明晚", 1, 3),
                                              ("今天", 0, nil), ("今日", 0, nil), ("今早", 0, 0), ("今晚", 0, 3)]
            for (k, off, pe) in rel where s.contains(k) {
                due = cal.date(byAdding: .day, value: off, to: today)
                if let pe { period = pe; explicitPeriod = true }
                consumed.append(k)
                s = s.replacingOccurrences(of: k, with: " ")
                break
            }
        }

        // 20号
        if due == nil, let g = firstMatch("(\\d{1,2})\\s*[日号]", in: s) {
            let y = cal.component(.year, from: today)
            let m = cal.component(.month, from: today)
            var cand = cal.date(from: DateComponents(year: y, month: m, day: Int(g[1]) ?? 1)) ?? today
            if cand < today, let n = cal.date(byAdding: .month, value: 1, to: cand) { cand = n }
            due = cand; cut(g[0])
        }

        // 时段
        if let g = firstMatch("(凌晨|清晨|早上|早晨|上午|中午|下午|傍晚|晚上|夜里|晚间)", in: s) {
            switch g[1] {
            case "凌晨", "清晨", "早上", "早晨", "上午": period = 0
            case "中午": period = 1
            case "傍晚": period = 2
            default: period = 3
            }
            explicitPeriod = true
            cut(g[0])
        }

        // 时刻
        if let g = firstMatch("(\\d{1,2})\\s*:\\s*(\\d{2})", in: s) {
            hour = Int(g[1]); minute = Int(g[2]) ?? 0; cut(g[0])
        }
        if hour == nil,
           let g = firstMatch("(\\d{1,2}|[一二两三四五六七八九十]{1,3})\\s*[点時时](?:\\s*(\\d{1,2}|[一二三四五六七八九十]{1,3})\\s*分?|(半))?", in: s) {
            hour = cnNum(g[1])
            if g[3] == "半" { minute = 30 }
            else if !g[2].isEmpty { minute = cnNum(g[2]) ?? 0 }
            cut(g[0])
        }
        if let h = hour {
            if !explicitPeriod, let ip = inheritPeriod, h <= 12 { period = ip }
            switch period {
            case 1, 2, 3: hour = h < 12 ? h + 12 : h
            case 0: hour = h == 12 ? 0 : h
            default: break
            }
        }

        // 标题
        var title = raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        for c in consumed where !c.isEmpty {
            title = title.replacingOccurrences(of: c, with: "")
        }
        title = title
            .replacingOccurrences(of: "^(然后|另外|再|顺便|记得|帮我)\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "^之?前(?![台面边后])", with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "，,、。；;：: "))
            .replacingOccurrences(of: "之?前$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        if title.isEmpty { title = raw.trimmingCharacters(in: .whitespaces) }

        // 时间落位
        var timeHM: (Int, Int)? = nil
        if let h = hour { timeHM = (h, minute) }
        else if deadline { timeHM = (18, 0) }
        else if let p = period { timeHM = (p == 0 ? 9 : (p == 1 ? 12 : 14), 0) }

        var hasTime = false
        var finalDue: Date? = nil
        var inferred = false
        if let d = due {
            if let (h, m) = timeHM {
                hasTime = true
                finalDue = cal.date(bySettingHour: h, minute: m, second: 0, of: d)
            } else {
                finalDue = cal.startOfDay(for: d)
            }
        } else if let (h, m) = timeHM {
            hasTime = true
            var fd = cal.date(bySettingHour: h, minute: m, second: 0, of: today)!
            if fd < base, let tm = cal.date(byAdding: .day, value: 1, to: fd) { fd = tm }
            finalDue = fd
            inferred = true
        }
        return (title, finalDue, hasTime, deadline, inferred, explicitPeriod ? period : nil)
    }

    // MARK: - 工具

    private static func cnNum(_ s: String) -> Int? {
        if let v = Int(s) { return v }
        if s == "十" { return 10 }
        let chars = Array(s)
        if chars.count == 1 { return cnDigits[s] }
        if let idx = chars.firstIndex(of: "十") {
            let l = String(chars[..<idx]), r = String(chars[chars.index(after: idx)...])
            let lv = l.isEmpty ? 1 : (cnDigits[l] ?? 0)
            let rv = r.isEmpty ? 0 : (cnDigits[r] ?? 0)
            return lv * 10 + rv
        }
        return cnDigits[s]
    }

    private static func firstMatch(_ pattern: String, in s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var groups: [String] = []
        for i in 0..<m.numberOfRanges {
            let r = m.range(at: i)
            groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
        }
        return groups
    }
}
