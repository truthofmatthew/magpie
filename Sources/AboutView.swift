import SwiftUI

struct AboutView: View {
    private let version: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }()

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .accessibilityHidden(true)

            Text("Magpie")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .padding(.top, 6)
            Text(version)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Remembers what you copy, so you can paste it again.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            Divider().padding(.vertical, 22)

            Text("Made by")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Matthew Truth")
                .font(.title3.weight(.semibold))
                .padding(.top, 2)

            HStack(spacing: 10) {
                Link(destination: URL(string: "https://github.com/truthofmatthew/magpie")!) {
                    Label { Text("GitHub") } icon: { Image("GitHub").resizable().frame(width: 14, height: 14) }
                }
                .help("github.com/truthofmatthew/magpie")
                Link(destination: URL(string: "https://truthofmatthew.com")!) {
                    Label("truthofmatthew.com", systemImage: "globe")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.top, 16)
        }
        .padding(.horizontal, 28)
        .padding(.top, 12)  // plus the hidden title bar's height
        .padding(.bottom, 30)
        .frame(width: 430)
        .background(alignment: .top) {
            // The icon's colors, faded into the window behind it.
            LinearGradient(colors: [Color(red: 0.17, green: 0.10, blue: 0.47).opacity(0.5),
                                    Color(red: 0.12, green: 0.31, blue: 0.69).opacity(0.12), .clear],
                           startPoint: .top, endPoint: .center)
            .ignoresSafeArea()
        }
    }
}
