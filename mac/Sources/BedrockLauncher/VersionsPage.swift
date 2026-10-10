import BedrockLauncherCore
import SwiftUI

struct VersionsPage: View {
    @EnvironmentObject var model: LauncherModel
    @State private var pendingDelete: GameVersion?

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
                            Button("DELETE") { pendingDelete = v }
                                .buttonStyle(ChunkyButtonStyle(kind: .red, fontSize: 10, verticalPadding: 5))
                                .disabled(model.isRunning)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Panel {
                Text("Downloading versions from Google Play comes with Google sign-in in a later version.")
                    .foregroundStyle(Theme.dimText)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
}
