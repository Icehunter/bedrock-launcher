import BedrockLauncherCore
import SwiftUI

struct VersionsPage: View {
    @EnvironmentObject var model: LauncherModel
    @State private var pendingDelete: GameVersion?
    @State private var chosenCode: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(text: "Installed versions")
                    if model.versions.isEmpty {
                        Text("No game version is installed yet.").foregroundStyle(Theme.dimText)
                    }
                    ForEach(model.versions.reversed(), id: \.name) { v in
                        HStack {
                            Text(v.name).font(.system(size: 14, weight: .semibold))
                            Text("arm64-v8a").font(.system(size: 11)).foregroundStyle(Theme.dimText)
                            if v == model.versions.last {
                                Text("NEWEST").font(.system(size: 10, weight: .heavy))
                                    .padding(.horizontal, 6).padding(.vertical, 2).background(Theme.green.edge)
                            }
                            Spacer()
                            Button("EXPORT") { model.export(v) }
                                .buttonStyle(ChunkyButtonStyle(fontSize: 10, verticalPadding: 5))
                                .disabled(model.isInstalling)
                            Button("DELETE") { pendingDelete = v }
                                .buttonStyle(ChunkyButtonStyle(kind: .red, fontSize: 10, verticalPadding: 5))
                                .disabled(model.isRunning || model.isInstalling)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let progress = model.installProgress {
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(progress.title).font(.system(size: 13, weight: .semibold))
                        if let fraction = progress.fraction {
                            ProgressView(value: fraction).tint(Theme.green.face)
                        } else {
                            ProgressView().progressViewStyle(.linear).tint(Theme.green.face)
                        }
                        Button("CANCEL") { model.cancelInstall() }
                            .buttonStyle(ChunkyButtonStyle(kind: .red))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                getTheGame
            }
            Spacer()
        }
        .padding(20)
        .onAppear { model.refresh() }
        .confirmationDialog(
            "Delete Minecraft \(pendingDelete?.name ?? "")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let v = pendingDelete { model.deleteVersion(v) }
                pendingDelete = nil
            }
        } message: {
            Text("The game files are removed. Worlds and settings in your data folders stay.")
        }
    }

    private var choices: [TestedVersions.Entry] {
        model.tested.versions.sorted { $0.versionCode > $1.versionCode }
    }

    private var getTheGame: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "Get the game")
                if let first = choices.first {
                    Picker("Version", selection: Binding(get: { chosenCode ?? first.versionCode }, set: { chosenCode = $0 })) {
                        ForEach(choices, id: \.versionCode) { Text($0.name).tag($0.versionCode) }
                    }
                    .frame(maxWidth: 260)
                    Button("DOWNLOAD FROM GOOGLE PLAY") {
                        if let entry = choices.first(where: { $0.versionCode == (chosenCode ?? first.versionCode) }) {
                            model.download(entry)
                        }
                    }
                    .buttonStyle(ChunkyButtonStyle(kind: .green, fullWidth: true))
                    .disabled(model.isRunning || model.isSigningIn)
                    if model.googleEmail == nil {
                        Text("Signs in to Google first.").font(.system(size: 11)).foregroundStyle(Theme.dimText)
                    }
                }
                Divider().overlay(Theme.outline)
                Button("IMPORT FILES") { model.pickAndImport() }
                    .buttonStyle(ChunkyButtonStyle(fullWidth: true))
                    .disabled(model.isRunning)
                Text("APK files from Google Play, or a .mcversion file exported from another Mac.")
                    .font(.system(size: 11)).foregroundStyle(Theme.dimText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
