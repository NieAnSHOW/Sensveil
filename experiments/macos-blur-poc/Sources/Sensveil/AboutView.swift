import AppKit
import SwiftUI

struct AboutView: View {
    @ObservedObject private var languagePreferences = LanguagePreferences.shared
    private var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (version, build) {
        case let (version?, build?): return L10n.format("版本 %@（%@）", version, build)
        case let (version?, nil): return L10n.format("版本 %@", version)
        case let (nil, build?): return L10n.format("构建 %@", build)
        case (nil, nil): return L10n.text("开发构建")
        }
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 20) {
                    appIcon
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sensveil").font(.title.bold())
                        Text(version).foregroundStyle(.secondary).textSelection(.enabled)
                        Text(L10n.text("免费的 macOS 窗口防窥应用")).font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.vertical, 12)
                Text(L10n.text("全面免费，不限应用数量。保护在本机运行。"))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section(L10n.text("项目与作者")) {
                LabeledContent(L10n.text("项目地址")) {
                    Link("NieAnSHOW / Sensveil", destination: URL(string: "https://github.com/NieAnSHOW/Sensveil")!)
                }
                LabeledContent(L10n.text("作者 GitHub")) {
                    Link("NieAnSHOW", destination: URL(string: "https://github.com/NieAnSHOW")!)
                }
            }
        }.formStyle(.grouped)
            .environment(\.locale, languagePreferences.locale)
    }

    private var appIcon: some View {
        Group {
            if let url = Bundle.main.url(forResource: "Sensveil", withExtension: "icns"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: "eye.slash.fill").resizable().foregroundStyle(.tint)
            }
        }
        .scaledToFit()
        .frame(width: 112, height: 112)
        .padding(8)
        .background(Color(red: 0.16, green: 0.21, blue: 0.25), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityHidden(true)
    }
}
