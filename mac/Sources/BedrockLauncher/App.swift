import AppKit
import SwiftUI

@main
struct BedrockLauncherApp: App {
    @StateObject private var model = LauncherModel()

    init() {
        // Used by scripts/assemble-app.sh to check the built app finds its images.
        if CommandLine.arguments.contains("--check-resources") {
            print(AppResources.loads ? "resources: ok" : "resources: missing")
            exit(AppResources.loads ? 0 : 1)
        }
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Bedrock Launcher") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1100, minHeight: 720)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentMinSize)
    }
}

struct RootView: View {
    @EnvironmentObject var model: LauncherModel

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            if let release = model.updateNotice {
                Button {
                    NSWorkspace.shared.open(release.html_url)
                } label: {
                    Text("Bedrock Launcher \(release.tag_name) is out. Click to open the download page.")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(Theme.green.edge)
                }
                .buttonStyle(.plain)
            }
            if model.playHasNewer != nil {
                Button {
                    let name = model.tested.newest?.name ?? "the newest tested one"
                    model.noticeMessage = "Downloads stay on the newest tested version (\(name)) until the launcher is updated to support the new one. Your installed game keeps working."
                } label: {
                    Text("Google Play has a newer Minecraft than this launcher has tested.")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(Theme.red.face)
                }
                .buttonStyle(.plain)
            }
            ZStack {
                Theme.background
                switch model.page {
                case .play: PlayPage()
                case .content: ContentPage()
                case .versions: VersionsPage()
                case .mods: ModsPage()
                case .log: LogPage()
                case .settings: SettingsPage()
                }
            }
        }
        .background(Theme.background)
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("Note", isPresented: Binding(
            get: { model.noticeMessage != nil },
            set: { if !$0 { model.noticeMessage = nil } }
        )) {
            Button("OK") { model.noticeMessage = nil }
        } message: {
            Text(model.noticeMessage ?? "")
        }
    }
}

/// Chunky tabs across the top; the active page's tab is the lighter one.
struct TopBar: View {
    @EnvironmentObject var model: LauncherModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Page.allCases, id: \.self) { page in
                Button {
                    model.page = page
                } label: {
                    HStack(spacing: 8) {
                        Theme.icon(page.icon).resizable().frame(width: 18, height: 18)
                        Text(page.title.uppercased())
                    }
                }
                .buttonStyle(ChunkyButtonStyle(kind: model.page == page ? .selected : .slate))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Theme.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.outline).frame(height: 3) }
    }
}

/// Mods arrive in a later version; the page says so.
struct ModsPage: View {
    var body: some View {
        VStack(alignment: .leading) {
            Panel {
                Text("Browsing and installing launcher mods comes in a later version. The updates mod the game needs is already built in.")
                    .foregroundStyle(Theme.dimText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
