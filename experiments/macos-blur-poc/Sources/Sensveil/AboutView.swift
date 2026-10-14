import AppKit
import SwiftUI

struct AboutView: View {
    private var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (version, build) {
        case let (version?, build?): return "版本 \(version)（\(build)）"
        case let (version?, nil): return "版本 \(version)"
        case let (nil, build?): return "构建 \(build)"
        case (nil, nil): return "开发构建"
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
                        Text("免费的 macOS 窗口防窥应用").font(.callout)
                    }
                }.padding(.vertical, 12)
                Text("全面免费，不限应用数量。保护在本机运行。")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("项目与作者") {
                LabeledContent("项目地址") {
                    Link("NieAnSHOW / Sensveil", destination: URL(string: "https://github.com/NieAnSHOW/Sensveil")!)
                }
                LabeledContent("作者 GitHub") {
                    Link("NieAnSHOW", destination: URL(string: "https://github.com/NieAnSHOW")!)
                }
            }
        }.formStyle(.grouped)
    }

    private var appIcon: some View {
        Group {
            if let url = Bundle.main.url(forResource: "Sensveil", withExtension: "icns"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: "eye.slash.fill").resizable().foregroundStyle(.tint)
            }
        }.scaledToFit().frame(width: 72, height: 72).accessibilityHidden(true)
    }
}
