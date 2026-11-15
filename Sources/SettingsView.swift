import SwiftUI
import UIKit

/// 设置页：默认提醒提前量 + 关于铃声/振动的说明（这部分 App 改不了，原因写在卡片里）。
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var lead: Int = Prefs.leadMinutes

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                navBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        sectionLabel("默认提醒")
                        leadCard
                        sectionLabel("铃声与振动")
                        toneCard
                        Color.clear.frame(height: 28)
                    }
                }
            }
        }
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

    private var leadCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("新记的条目").font(.system(size: 13.5)).foregroundColor(Theme.ink)
                Text("到点前多久提醒你，可在详情页逐条改")
                    .font(.system(size: 10.5)).foregroundColor(Theme.muted)
            }
            Spacer()
            Menu {
                ForEach(Prefs.leadOptions, id: \.self) { m in
                    Button(Prefs.leadText(m)) {
                        lead = m
                        Prefs.leadMinutes = m
                    }
                }
            } label: {
                Text(Prefs.leadText(lead))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(Theme.accent)
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1)))
        .padding(.horizontal, 20)
    }

    private var toneCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("到点响不响、振几下，由 iPhone 决定，App 改不了。苹果只在 Mac 上开放了设置提醒声音的接口，iPhone 上没有。")
                .font(.system(size: 11.5))
                .lineSpacing(3)
                .foregroundColor(Theme.ink2)

            VStack(alignment: .leading, spacing: 7) {
                bullet("想换提示音", "打开「提醒事项」→ 点进某条 →「提醒我」那行右侧的「自定」→ 选声音")
                bullet("想让它振动", "把手机侧边的静音开关拨到静音，通知就会振动")
                bullet("没声音", "检查「设置 → 通知 → 提醒事项」里的「声音」有没有打开")
            }

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Text("打开系统设置")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(Theme.accent)
                    .padding(.top, 2)
            }
            .buttonStyle(.plain)
        }
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1)))
        .padding(.horizontal, 20)
    }

    private func bullet(_ head: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Circle().fill(Theme.accent.opacity(0.55)).frame(width: 4, height: 4).padding(.top, 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(head).font(.system(size: 11.5, weight: .medium)).foregroundColor(Theme.ink)
                Text(body).font(.system(size: 10.5)).foregroundColor(Theme.muted).lineSpacing(2)
            }
        }
    }
}
