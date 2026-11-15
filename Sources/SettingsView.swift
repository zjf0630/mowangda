import SwiftUI

/// 设置页：目前只有一件事需要用户选——到期提醒用什么声音。
struct SettingsView: View {
    @ObservedObject var store: ReminderStore
    @Environment(\.dismiss) private var dismiss
    @State private var tone: AlarmTone = .system

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                navBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        sectionLabel("提醒声音")
                        toneCard
                        footnote
                        Color.clear.frame(height: 28)
                    }
                }
            }
        }
        .onAppear { tone = AlarmTone.current }
    }

    private var navBar: some View {
        HStack {
            Button("‹ 返回") { dismiss() }
            Spacer()
            Text("设置").font(.system(size: 12)).foregroundColor(Theme.muted)
            Spacer()
            Button("完成") { dismiss() }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 6)
    }

    private func sectionLabel(_ s: String) -> some View {
        HStack(spacing: 8) {
            Text(s).font(.system(size: 11.5, weight: .medium))
            Rectangle().fill(Theme.line).frame(height: 1)
        }
        .foregroundColor(Theme.muted)
        .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 8)
    }

    private var toneCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(AlarmTone.allCases.enumerated()), id: \.element.id) { pair in
                if pair.offset > 0 {
                    Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 15)
                }
                row(pair.element)
            }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1)))
        .padding(.horizontal, 20)
    }

    private func row(_ t: AlarmTone) -> some View {
        let on = tone == t
        return Button {
            tone = t
            AlarmTone.current = t
            Task { await store.refreshAlarms() }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.title)
                        .font(.system(size: 13.5, weight: on ? .semibold : .regular))
                        .foregroundColor(Theme.ink)
                    Text(t.detail)
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.muted)
                }
                Spacer()
                ZStack {
                    Circle()
                        .strokeBorder(on ? Theme.accent : Theme.tick, lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    if on {
                        Circle().fill(Theme.accent).frame(width: 11, height: 11)
                    }
                }
            }
            .padding(.horizontal, 15).padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("改完立刻生效：新记的条目、以及已存在的未完成提醒都会换成新声音。")
            Text("系统限制：振动由 iOS 决定，App 只能选声音，不能指定「振三下」；手机开了静音开关时，除「短信提示音」外通常只振动不响铃。")
        }
        .font(.system(size: 10.5))
        .lineSpacing(3)
        .foregroundColor(Theme.faint)
        .padding(.horizontal, 22).padding(.top, 12)
    }
}
