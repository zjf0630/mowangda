import SwiftUI

/// 录入页：一句话实时拆条，逐卡可改时间，确认后写入提醒事项。
/// 布局：顶部导航 → 中间输入框 + 识别卡片 → 底部固定操作条（麦克风在上，写入按钮在下）
struct ComposeView: View {
    @ObservedObject var store: ReminderStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var speech = SpeechController()
    @State private var text = ""
    @State private var parsed: [ParsedItem] = []
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                navBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        inputBox
                        parseSection
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                bottomBar
            }
        }
        .onAppear { parsed = [] }
    }

    // MARK: - 顶部

    private var navBar: some View {
        HStack {
            Button("取消") { speech.stop(); dismiss() }
            Spacer()
            Text(speech.transcribing ? "正在听…" : "说一句，或打一行")
                .font(.system(size: Theme.fs(12))).foregroundColor(Theme.muted)
            Spacer()
            Button("清空") { text = ""; parsed = [] }.foregroundColor(Theme.muted)
        }
        .font(.system(size: Theme.fs(13)))
        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 4)
    }

    // MARK: - 输入框

    private var inputBox: some View {
        TextField("明天下午3点跟张总碰方案，周三前把预算表发财务", text: $text, axis: .vertical)
            .font(.system(size: Theme.fs(15)))
            .lineLimit(2...6)
            .focused($focused)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line, lineWidth: 1)))
            .onChange(of: text) { _, v in reparse(v) }
            .padding(.horizontal, 20).padding(.top, 8)
    }

    // MARK: - 识别结果

    private var parseSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !parsed.isEmpty {
                HStack(spacing: 8) {
                    Text("识别到 \(parsed.count) 项").font(.system(size: Theme.fs(11.5), weight: .medium))
                    Rectangle().fill(Theme.line).frame(height: 1)
                    Text("可逐条改").font(.system(size: Theme.fs(10.5))).foregroundColor(Theme.faint)
                }
                .foregroundColor(Theme.muted)
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8)
            }
            ForEach(parsed.indices, id: \.self) { i in
                card(i)
            }
            if parsed.isEmpty {
                Text("说完或打完，这里会即时拆成带时间的一条条")
                    .font(.system(size: Theme.fs(12))).foregroundColor(Theme.faint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 44)
            }
            Color.clear.frame(height: 12)
        }
    }

    private func card(_ i: Int) -> some View {
        let p = parsed[i]
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                Text(p.title).font(.system(size: Theme.fs(13.5), weight: .medium)).lineLimit(2)
                Spacer()
                Button { parsed.remove(at: i); reparse(text) } label: {
                    Text("×").font(.system(size: Theme.fs(15))).foregroundColor(Theme.faint)
                }
            }
            HStack(spacing: 5) {
                Text(whenText(p))
                    .font(.system(size: Theme.fs(10.5), weight: .medium))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(p.deadline ? Theme.chipWarn : (p.due != nil ? Theme.accentSoft : Theme.chip)))
                    .foregroundColor(p.deadline ? Theme.chipWarnInk : (p.due != nil ? Theme.accent : Theme.muted))
                Text(p.listName)
                    .font(.system(size: Theme.fs(10.5)))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.chip))
                    .foregroundColor(Theme.muted)
                Spacer()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1)))
        .padding(.horizontal, 20).padding(.bottom, 8)
    }

    // MARK: - 底部固定操作条（麦克风在写入按钮上方）

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Button { toggleSpeech() } label: {
                ZStack {
                    Circle().fill(speech.transcribing ? Theme.danger : Theme.accent)
                        .frame(width: 54, height: 54)
                    Image(systemName: speech.transcribing ? "stop.fill" : "mic.fill")
                        .font(.system(size: Theme.fs(19), weight: .medium))
                        .foregroundColor(Theme.bg)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(speech.transcribing ? "停止听写" : "语音输入")

            Button { write() } label: {
                Text(parsed.isEmpty ? "写入提醒事项" : "写入提醒事项 · \(parsed.count) 项")
                    .font(.system(size: Theme.fs(13.5), weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 16)
                        .fill(parsed.isEmpty ? Theme.disabled : Theme.accent))
                    .foregroundColor(Theme.bg)
            }
            .disabled(parsed.isEmpty)

            Text(hint).font(.system(size: Theme.fs(10.5))).foregroundColor(Theme.muted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(
            Theme.bg.ignoresSafeArea(edges: .bottom)
                .overlay(Rectangle().fill(Theme.line).frame(height: 0.5), alignment: .top)
        )
    }

    private var hint: String {
        if speech.transcribing { return "正在听… 说完点一下方块停止" }
        if parsed.isEmpty { return "按麦克风说话，或直接在上面打字" }
        return "将排入 " + parsed.map { whenText($0) }.joined(separator: "　·　")
    }

    // MARK: - 动作

    private func toggleSpeech() {
        if speech.transcribing {
            speech.stop()
            return
        }
        focused = false
        speech.start(onText: { t in text = t },
                     onError: { _ in speech.transcribing = false })
    }

    private func write() {
        let list = parsed
        Task {
            for p in list { await store.add(p) }
            speech.stop()
            await store.sync()      // 回读一次，让列表拿到 EventKit 的真实 id
            dismiss()
        }
    }

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
}
