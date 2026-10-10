import AppKit
import BedrockLauncherCore
import SwiftUI

struct PlayPage: View {
    @EnvironmentObject var model: LauncherModel
    @State private var editing: Profile?
    @State private var linkedCount = 0
    @State private var errorCount = 0

    private var data: URL { model.dataFolder(for: model.selectedProfile) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            titleCard
            HStack(alignment: .top, spacing: 16) {
                statusCard
                actionsCard
            }
            Spacer(minLength: 16)
            HStack(alignment: .bottom) {
                profileCard
                Spacer()
                playButton
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The scenery is drawn behind the content so it never changes the layout.
        .background { Scenery() }
        .clipped()
        .onAppear(perform: reloadCounts)
        .onChange(of: model.selectedProfileID) { _, _ in reloadCounts() }
        .onChange(of: model.isRunning) { _, running in if !running { reloadCounts() } }
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

    private func reloadCounts() {
        linkedCount = PackLinker.linkedPacks(dataFolder: data).count
        if let file = ContentLog.latestFile(dataFolder: data),
           let text = try? String(contentsOf: file, encoding: .utf8) {
            errorCount = ContentLog.parse(text).filter { $0.level.lowercased() == "error" }.count
        } else {
            errorCount = 0
        }
    }

    // MARK: Cards

    private var titleCard: some View {
        Panel {
            VStack(alignment: .leading, spacing: 4) {
                Text("BEDROCK LAUNCHER")
                    .font(.system(size: 26, weight: .black))
                    .kerning(1)
                Text("Minecraft: Bedrock Edition on Apple Silicon")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dimText)
            }
        }
    }

    private var statusCard: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Status")
                if let v = model.version(for: model.selectedProfile) {
                    row("Game", "Minecraft \(v.name), ready to play")
                } else {
                    row("Game", "No version installed", color: Theme.warningText) { model.page = .versions }
                }
                row("Packs in progress", linkedCount == 0 ? "None linked" : "\(linkedCount) linked") { model.page = .content }
                row("Pack errors", errorCount == 0 ? "None in the last run" : "\(errorCount) in the last run",
                    color: errorCount == 0 ? Theme.text : Theme.errorText) { model.page = .content }
                row("Last session", lastSessionText, color: lastSessionColor) { model.page = .log }
            }
            .frame(width: 420, alignment: .leading)
        }
    }

    private var lastSessionText: String {
        guard let s = model.lastSession else { return "Not played yet" }
        let when = RelativeDateTimeFormatter().localizedString(for: s.ended, relativeTo: Date())
        return s.exitCode == 0 ? "Ended normally \(when)" : "Stopped with code \(s.exitCode) \(when)"
    }

    private var lastSessionColor: Color {
        guard let s = model.lastSession, s.exitCode != 0 else { return Theme.text }
        return Theme.errorText
    }

    private func row(_ label: String, _ value: String, color: Color = Theme.text,
                     action: (() -> Void)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Theme.dimText)
                .frame(width: 140, alignment: .leading)
            if let action {
                Button(action: action) {
                    Text(value).underline().foregroundStyle(color)
                }
                .buttonStyle(.plain)
            } else {
                Text(value).foregroundStyle(color)
            }
        }
        .font(.system(size: 13))
    }

    private var actionsCard: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Quick actions")
                Button("INSTALL CONTENT…") { model.pickAndInstallContent() }
                    .buttonStyle(ChunkyButtonStyle())
                Button("OPEN WORLDS FOLDER") {
                    let worlds = data.appendingPathComponent("games/com.mojang/minecraftWorlds", isDirectory: true)
                    try? FileManager.default.createDirectory(at: worlds, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(worlds)
                }
                .buttonStyle(ChunkyButtonStyle())
                Button("LINK A PACK FOLDER…") { model.page = .content }
                    .buttonStyle(ChunkyButtonStyle())
            }
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
                        Text(model.selectedProfile.name).font(.system(size: 15, weight: .heavy))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Text("Profile").font(.system(size: 11)).foregroundStyle(Theme.dimText)
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
        let version = model.version(for: model.selectedProfile)
        return Button { model.play() } label: {
            VStack(spacing: 2) {
                Text(model.isRunning ? "PLAYING" : "PLAY")
                    .font(.system(size: 24, weight: .black))
                Text(version.map { "MINECRAFT \($0.name)" } ?? "NO GAME INSTALLED")
                    .font(.system(size: 10, weight: .bold))
                    .opacity(0.85)
            }
            .frame(width: 260)
        }
        .buttonStyle(ChunkyButtonStyle(kind: .green, verticalPadding: 12))
        .disabled(version == nil || model.isRunning)
    }
}
