import AppKit
import HostCatCore
import SwiftUI

/// 首次启动展示的隐私 & 使用方式摘要。
struct WelcomeView: View {
    let onAcknowledge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            VStack(alignment: .leading, spacing: 14) {
                point(
                    icon: "lock.shield",
                    title: L.welcomePointLocalTitle,
                    body: L.welcomePointLocalBody
                )
                point(
                    icon: "checkmark.shield",
                    title: L.welcomePointHelperTitle,
                    body: L.welcomePointHelperBody
                )
                point(
                    icon: "clock.arrow.circlepath",
                    title: L.welcomePointBackupTitle,
                    body: L.welcomePointBackupBody
                )
                point(
                    icon: "doc.text.magnifyingglass",
                    title: L.welcomePointDiagnosticsTitle,
                    body: L.welcomePointDiagnosticsBody
                )
            }

            Text(L.welcomeFootnote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(L.welcomePrivacyButton) {
                    openPrivacyPolicy()
                }

                Spacer()

                Button(L.welcomeAcknowledge) {
                    onAcknowledge()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "pawprint.circle.fill")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(L.welcomeTitle)
                    .font(.title.weight(.semibold))
                Text(L.welcomeSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func point(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 打开打包进 app bundle 的 PRIVACY.md。Markdown 默认由系统注册的编辑器（通常是 TextEdit）展示。
    private func openPrivacyPolicy() {
        guard let url = Bundle.main.url(forResource: "PRIVACY", withExtension: "md") else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(url)
    }
}
