import AppKit
import BedrockLauncherCore
import SwiftUI

struct SettingsPage: View {
    @EnvironmentObject var model: LauncherModel
    @State private var tab = 0
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SubTabs(titles: ["General", "About"], selected: $tab)
            if tab == 0 { general } else { about }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 16) {
            launcher
            google
        }
    }

    private var google: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "Google account")
                if let email = model.googleEmail {
                    Text(email.isEmpty ? "Signed in" : "Signed in as \(email)")
                    Button("SIGN OUT") { model.signOutOfGoogle() }
                        .buttonStyle(ChunkyButtonStyle())
                } else {
                    Text("Signing in is only needed to download the game from Google Play.")
                        .foregroundStyle(Theme.dimText)
                    Button(model.isSigningIn ? "SIGNING IN..." : "SIGN IN TO GOOGLE") { model.signInToGoogle() }
                        .buttonStyle(ChunkyButtonStyle())
                        .disabled(model.isSigningIn)
                }
                Toggle("Keep downloaded APK files", isOn: $model.settings.keepDownloadedAPKs)
            }
            .toggleStyle(BlockToggleStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var launcher: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "Launcher")
                Toggle("Hide the launcher while the game runs", isOn: $model.settings.hideWhilePlaying)
                Toggle("Check for launcher updates when it opens", isOn: $model.settings.checkForUpdates)
                Toggle("Network debug logging", isOn: $model.settings.networkDebug)
                Divider().overlay(Theme.outline)
                Button("OPEN LAUNCHER DATA FOLDER") {
                    try? FileManager.default.createDirectory(at: model.paths.root, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(model.paths.root)
                }
                .buttonStyle(ChunkyButtonStyle())
            }
            .toggleStyle(BlockToggleStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var about: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Theme.icon("app").resizable().frame(width: 96, height: 96)
                Text("BEDROCK LAUNCHER").font(.system(size: 16, weight: .heavy))
                Text("Version \(AppInfo.version)").foregroundStyle(Theme.dimText)
                HStack(spacing: 10) {
                    Button("SOURCE") { NSWorkspace.shared.open(AppInfo.repo) }.buttonStyle(ChunkyButtonStyle())
                    Button("REPORT A PROBLEM") { NSWorkspace.shared.open(AppInfo.issues) }.buttonStyle(ChunkyButtonStyle())
                }
                Text("Runs Minecraft: Bedrock Edition on Apple Silicon Macs, built on the minecraft-linux launcher. The game comes from Google Play with your own account.")
                    .font(.system(size: 12)).foregroundStyle(Theme.dimText)
                    .frame(maxWidth: 620, alignment: .leading)
                Button("RESET LAUNCHER SETTINGS") { confirmReset = true }
                    .buttonStyle(ChunkyButtonStyle(kind: .red))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog("Reset launcher settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { model.settings = LauncherSettings() }
        } message: {
            Text("The settings on this page go back to their defaults. Profiles, game versions and worlds stay.")
        }
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }
    static let repo = URL(string: "https://github.com/Icehunter/bedrock-launcher")!
    static let issues = URL(string: "https://github.com/Icehunter/bedrock-launcher/issues")!
    static let latestRelease = URL(string: "https://api.github.com/repos/Icehunter/bedrock-launcher/releases/latest")!
}
