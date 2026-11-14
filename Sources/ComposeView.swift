import SwiftUI

/// 录入页：一句话实时拆条，逐卡可改时间，确认后写入提醒事项。
struct ComposeView: View {
    @ObservedObject var store: ReminderStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var speech = SpeechController()
    @State private var text = ""
    @State private var parsed: [ParsedItem] = []
    @State private var saved = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                navBar
                inputBox
                parseArea
                Spacer(minLength: 0)
                writeButton
            }
        }
        .onAppear { parsed = [] }
    }

    private var navBar: some View {
        HStack {
            Button("取消") { speech.stop(); dismiss() }
            Spacer()
            Text(speech.transcribing ? "正在听…" : "说一句，或打一行")
                .font(.system(size: 12)).foregroundColor(Theme.muted)
            Spacer()
            Button("清空") { text = ""; parsed = [] }.foregroundColor(Theme.muted)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 22).padding(.top, 12)
    }

    private var inputBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("明天下午3点跟张总碰方案，周三前把预算表发财务", text: $text, axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(1...4)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                .onChange(of: text) { _, v in reparse(v) }
            HStack(spacing: 10) {
                Button {
                    if speech.transcribing { speech.stop() }
                    else {
                        speech.start(onText: { t in text = t },
                                     onError: { _ in speech.transcribing = false })
                    }
                } label: {
                    Image(systemName: speech.transcribing ? "stop.fill" : "mic.fill")
                        .font(.system(size: 14)).foregroundColor(.white)
                        .frame(width: 34, height: 34).background(Circle().fill(speech.transcribing ? Theme.danger : Theme.accent))
                }
                Text(speech.transcribing ? "说完自动停" : "点麦克风说话，本机识别")
                    .font(.system(size: 11)).foregroundColor(Theme.muted)
                Spacer()
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.line, lineWidth: 1)))
        .padding(.horizontal, 20).padding(.top, 6)
    }

    private var parseArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !parsed.isEmpty {
                    HStack(spacing: 8) {
                        Text("识别到 \(parsed.count) 项").font(.system(size: 11.5, weight: .medium))
                        Rectangle().fill(Theme.line).frame(height: 1)
                        Text("可逐条改").font(.system(size: 10.5)).foregroundColor(Theme.faint)
                    }
                    .foregroundColor(Theme.muted)
                    .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8)
                }
                ForEach(parsed.indices, id: \.self) { i in
                    card(i)
                }
            }
        }
    }

    private func card(_ i: Int) -> some View {
        let p = parsed[i]
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                Text(p.title).font(.system(size: 13.5, weight: .medium)).lineLimit(2)
                Spacer()
                Button { parsed.remove(at: i); reparse(text) } label: {
                    Text("×").font(.system(size: 15)).foregroundColor(Theme.faint)
                }
            }
            HStack(spacing: 5) {
                Text(whenText(p))
                    .font(.system(size: 10.5, weight: .medium))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(p.deadline ? Color(hex: 0xFAEEDA) : (p.due != nil ? Theme.accentSoft : Theme.bg)))
                    .foregroundColor(p.deadline ? Color(hex: 0x854F0B) : (p.due != nil ? Theme.accent : Theme.muted))
                Text(p.listName)
                    .font(.system(size: 10.5))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Color(hex: 0xF1EFE9)))
                    .foregroundColor(Theme.muted)
                Spacer()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1)))
        .padding(.horizontal, 20).padding(.bottom, 8)
    }

    private var writeButton: some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    for p in parsed { await store.add(p) }
                    saved = true
                    speech.stop()
                    dismiss()
                }
            } label: {
                Text(parsed.isEmpty ? "写入提醒事项" : "写入提醒事项 · \(parsed.count) 项")
                    .font(.system(size: 13.5, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 16)
                        .fill(parsed.isEmpty ? Color(hex: 0xD9D6CE) : Theme.accent))
                    .foregroundColor(.white)
            }
            .disabled(parsed.isEmpty)
            Text(summary).font(.system(size: 10.5)).foregroundColor(Theme.muted)
        }
        .padding(.horizontal, 20).padding(.bottom, 18)
    }

    // MARK: - 工具

    private func reparse(_ v: String) {
        parsed = TimeParser.parseAll(v)
    }

    private func whenText(_ p: ParsedItem) -> String {
        guard let d = p.due else { return "未定时间" }
        let cal = Calendar.current
        let dayDiff = cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                         to: cal.startOfDay(for: d)).day ?? 0
        let f = DateFormatter()
        let day: String
        if dayDiff == 0 { day = "今天" }
        else if dayDiff == 1 { day = "明天" }
        else { f.dateFormat = "M月d日"; day = f.string(from: d) }
        if p.hasTime {
            f.dateFormat = " HH:mm"
            return day + f.string(from: d)
        }
        return day + " 全天"
    }

    private var summary: String {
        if parsed.isEmpty { return "写在下面这块，识别结果会即时出现" }
        return "将排入 " + parsed.map { whenText($0) }.joined(separator: "　·　")
    }
}
