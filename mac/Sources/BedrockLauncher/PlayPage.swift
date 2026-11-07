import AppKit
import BedrockLauncherCore
import SwiftUI

struct PlayPage: View {
    @EnvironmentObject var model: LauncherModel
    @State private var editing: Profile?
    @State private var linkedCount = 0
    @State private var errorCount = 0
    @State private var showVersions = false

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
        let folder = data
        linkedCount = PackLinker.linkedPacks(dataFolder: folder).count
        Task {
            errorCount = await Task.detached(priority: .userInitiated) { () -> Int in
                guard let file = ContentLog.latestFile(dataFolder: folder),
                      let text = try? String(contentsOf: file, encoding: .utf8) else { return 0 }
                return ContentLog.parse(text).filter { $0.level.lowercased() == "error" }.count
            }.value
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
                    .buttonStyle(ChunkyButtonStyle(fullWidth: true))
                Button("OPEN WORLDS FOLDER") {
                    let worlds = data.appendingPathComponent("games/com.mojang/minecraftWorlds", isDirectory: true)
                    try? FileManager.default.createDirectory(at: worlds, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(worlds)
                }
                .buttonStyle(ChunkyButtonStyle(fullWidth: true))
                Button("LINK A PACK FOLDER…") { model.page = .content }
                    .buttonStyle(ChunkyButtonStyle(fullWidth: true))
            }
            .frame(width: 280)
        }
    }

    private func isTested(_ v: GameVersion) -> Bool {
        model.tested.versions.first { $0.name == v.name }?.tested ?? false
    }

    private var profileCard: some View {
        Panel {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("PROFILE").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.dimText)
                    Menu {
                        ForEach(model.profileList) { p in
                            Button(p.name) { model.selectProfile(p.id) }
                        }
                        Divider()
                        Button("New Profile…") { editing = Profile(name: "New Profile") }
                    } label: {
                        HStack(spacing: 6) {
                            Text(model.selectedProfile.name).font(.system(size: 16, weight: .heavy))
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(Theme.text)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                Button { editing = model.selectedProfile } label: {
                    Image(systemName: "pencil").frame(width: 14, height: 14)
                }
                .buttonStyle(ChunkyButtonStyle(horizontalPadding: 10, verticalPadding: 8))
                .help("Edit profile")
            }
        }
    }

    /// PLAY starts the selected version. The arrow beside it picks the version and saves it with the profile.
    private var playButton: some View {
        let version = model.version(for: model.selectedProfile)
        return HStack(spacing: 0) {
            Button { model.play() } label: {
                VStack(spacing: 2) {
                    Text(model.isRunning ? "PLAYING" : "PLAY")
                        .font(.system(size: 24, weight: .black))
                    Text(version.map { "MINECRAFT \($0.name)" } ?? "NO GAME INSTALLED")
                        .font(.system(size: 10, weight: .bold))
                        .opacity(0.85)
                }
                .frame(width: 260, height: 46)
            }
            .buttonStyle(ChunkyButtonStyle(kind: .green, verticalPadding: 7))
            .disabled(version == nil || model.isRunning)

            Button { showVersions.toggle() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .black))
                    .frame(width: 44, height: 46)
            }
            .buttonStyle(ChunkyButtonStyle(kind: .green, horizontalPadding: 0, verticalPadding: 7))
            .disabled(model.isRunning)
            .help("Choose the game version")
            .popover(isPresented: $showVersions, arrowEdge: .top) { versionPopover }
        }
    }

    /// The version list in the launcher's own panel style, opened from the arrow beside PLAY.
    private var versionPopover: some View {
        let chosen = model.selectedProfile.gameVersion
        // An unpinned profile plays the newest installed version.
        let current = chosen ?? model.versions.last?.name
        return Panel {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: "Game version")
                ForEach(model.versions.reversed(), id: \.name) { v in
                    versionChoice(v.name, isTested(v) ? nil : "UNTESTED", selected: current == v.name) {
                        model.selectGameVersion(v.name)
                    }
                }
                if model.versions.isEmpty {
                    Text("No game version installed yet.").font(.system(size: 13)).foregroundStyle(Theme.dimText)
                }
            }
            .frame(width: 240, alignment: .leading)
        }
    }

    private func versionChoice(_ title: String, _ note: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            showVersions = false
        } label: {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .heavy))
                    if let note {
                        Text(note).font(.system(size: 9, weight: .heavy)).opacity(0.85)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .black))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(ChunkyButtonStyle(kind: selected ? .green : .slate, horizontalPadding: 14, verticalPadding: 8, fullWidth: true))
    }
}
