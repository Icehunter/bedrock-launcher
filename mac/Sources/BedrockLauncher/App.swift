import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct BedrockLauncherApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

@MainActor
final class LauncherModel: ObservableObject {
    @Published var log: [String] = []
    @Published var installed = GameStore.isInstalled
    @Published var gamertag: String?
    @Published var prompt: DeviceCodePrompt?
    @Published var clientID: String = UserDefaults.standard.string(forKey: "clientID") ?? "" {
        didSet { UserDefaults.standard.set(clientID, forKey: "clientID") }
    }

    func say(_ s: String) { log.append(s) }

    func pickAndImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["apk", "ipa"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        say("Importing \(url.lastPathComponent)...")
        Task.detached {
            do {
                let msg = try GameImporter.run(url)
                await MainActor.run {
                    self.say(msg)
                    self.installed = GameStore.isInstalled
                }
            } catch {
                await MainActor.run { self.say("Import failed: \(error.localizedDescription)") }
            }
        }
    }

    func signIn() {
        let id = clientID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { say("Enter an Azure client ID first."); return }
        Task {
            do {
                let auth = MSAuth(clientID: id)
                let p = try await auth.requestDeviceCode()
                prompt = p
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(p.userCode, forType: .string)
                NSWorkspace.shared.open(p.verificationURI)
                say("Code \(p.userCode) copied. Finish sign-in in the browser.")
                let result = try await auth.completeSignIn(p)
                gamertag = result.gamertag
                prompt = nil
                Keychain.save("refresh", result.refreshToken)
                say("Signed in as \(result.gamertag)")
            } catch {
                prompt = nil
                say("Sign-in failed: \(error.localizedDescription)")
            }
        }
    }

    func play() {
        do {
            let r = try ELFInspector.inspect(GameStore.mainLib)
            say("libminecraftpe.so: aarch64, \(r.loadSegments) load segments, \(r.memorySpan / 1_048_576) MiB image")
            say("Needs: " + r.needed.joined(separator: ", "))
            say("Milestone 1 only: the loader does not execute the game yet.")
        } catch {
            say("Inspect failed: \(error.localizedDescription)")
        }
    }
}

struct ContentView: View {
    @StateObject private var m = LauncherModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Bedrock Launcher").font(.title.bold())

            GroupBox("1. Game files") {
                HStack {
                    Text(m.installed ? "Imported" : "Not imported")
                    Spacer()
                    Button("Import APK or IPA...") { m.pickAndImport() }
                }
                .padding(4)
            }

            GroupBox("2. Microsoft account") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Azure app client ID", text: $m.clientID)
                    HStack {
                        Text(m.gamertag ?? "Signed out")
                        Spacer()
                        Button("Sign in") { m.signIn() }
                    }
                    if let p = m.prompt {
                        Text("Enter \(p.userCode) at \(p.verificationURI.absoluteString)")
                            .textSelection(.enabled)
                    }
                }
                .padding(4)
            }

            Button("Play") { m.play() }
                .disabled(!m.installed)
                .keyboardShortcut(.defaultAction)

            ScrollView {
                Text(m.log.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 120)
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 440)
    }
}
