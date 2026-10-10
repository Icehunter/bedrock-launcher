import BedrockLauncherCore
import SwiftUI

struct PlayPage: View {
    @EnvironmentObject var model: LauncherModel
    @State private var editing: Profile?

    var body: some View {
        ZStack(alignment: .bottom) {
            Scenery()
            HStack(alignment: .bottom) {
                profileCard
                Spacer()
                playButton
            }
            .padding(22)
        }
        .clipped()
        .sheet(item: $editing) { profile in
            ProfileEditor(profile: profile) { saved in
                model.saveProfile(saved)
                editing = nil
            } onDelete: { deleted in
                model.deleteProfile(deleted)
                editing = nil
            } onCancel: {
                editing = nil
            }
            .environmentObject(model)
        }
    }

    private var profileCard: some View {
        Panel {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Menu {
                        ForEach(model.profileList) { p in
                            Button(p.name) { model.selectProfile(p.id) }
                        }
                        Divider()
                        Button("New Profile…") { editing = Profile(name: "New Profile") }
                    } label: {
                        Text(model.selectedProfile.name)
                            .font(.system(size: 15, weight: .heavy))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Text(model.version(for: model.selectedProfile).map { "Minecraft \($0.name)" } ?? "No game installed")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dimText)
                }
                Button { editing = model.selectedProfile } label: {
                    Image(systemName: "pencil").frame(width: 14, height: 14)
                }
                .buttonStyle(ChunkyButtonStyle(horizontalPadding: 10, verticalPadding: 8))
                .help("Edit profile")
            }
        }
    }

    private var playButton: some View {
        Button { model.play() } label: {
            Text(model.isRunning ? "PLAYING" : "PLAY")
                .frame(width: 240)
        }
        .buttonStyle(ChunkyButtonStyle(kind: .green, fontSize: 22, verticalPadding: 16))
        .disabled(model.version(for: model.selectedProfile) == nil || model.isRunning)
    }
}
