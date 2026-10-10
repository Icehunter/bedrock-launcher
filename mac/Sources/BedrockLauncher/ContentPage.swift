import AppKit
import BedrockLauncherCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentPage: View {
    @EnvironmentObject var model: LauncherModel
    @State private var link = "minecraft://"
    @State private var linked: [LinkedPack] = []
    @State private var errors: [ContentLogEntry] = []
    @State private var logName: String?

    private var data: URL { model.dataFolder(for: model.selectedProfile) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                installSection
                folderSection
                linkedSection
                errorSection
            }
            .padding(20)
        }
        .onAppear(perform: reload)
        .onChange(of: model.selectedProfileID) { _, _ in reload() }
        .onChange(of: model.isRunning) { _, running in if !running { reload() } }
    }

    private func reload() {
        linked = PackLinker.linkedPacks(dataFolder: data)
        if let file = ContentLog.latestFile(dataFolder: data),
           let text = try? String(contentsOf: file, encoding: .utf8) {
            logName = file.lastPathComponent
            // Errors first, then warnings; the rest is noise for pack work.
            let entries = ContentLog.parse(text).filter { ["error", "warning"].contains($0.level.lowercased()) }
            errors = entries.sorted { ($0.level.lowercased() == "error" ? 0 : 1) < ($1.level.lowercased() == "error" ? 0 : 1) }
        } else {
            logName = nil
            errors = []
        }
    }

    // MARK: Install and links

    private var installSection: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "Install")
                HStack(spacing: 10) {
                    Button("INSTALL CONTENT…") { pickContent() }
                        .buttonStyle(ChunkyButtonStyle(kind: .green))
                    Text("A .mcpack, .mcaddon or .mcworld file. The game starts and imports it.")
                        .font(.system(size: 11)).foregroundStyle(Theme.dimText)
                }
                HStack(spacing: 10) {
                    TextField("minecraft://", text: $link)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 420)
                    Button("OPEN LINK") { model.play(extraArguments: ["-u", link]) }
                        .buttonStyle(ChunkyButtonStyle())
                        .disabled(!link.hasPrefix("minecraft://") || link == "minecraft://")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pickContent() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["mcpack", "mcaddon", "mcworld"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsOtherFileTypes = false
        panel.prompt = "Install"
        if panel.runModal() == .OK, let url = panel.url {
            model.play(extraArguments: ["-ifp", url.path])
        }
    }

    // MARK: Folders

    private var folderSection: some View {
        let mojang = data.appendingPathComponent("games/com.mojang", isDirectory: true)
        let folders: [(String, URL)] = [
            ("Data", data),
            ("Worlds", mojang.appendingPathComponent("minecraftWorlds")),
            ("Resource Packs", mojang.appendingPathComponent("resource_packs")),
            ("Behavior Packs", mojang.appendingPathComponent("behavior_packs")),
            ("Dev Resource Packs", mojang.appendingPathComponent("development_resource_packs")),
            ("Dev Behavior Packs", mojang.appendingPathComponent("development_behavior_packs")),
        ]
        return Panel {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "Folders")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(folders, id: \.0) { name, url in
                        Button(name.uppercased()) { open(url) }
                            .buttonStyle(ChunkyButtonStyle())
                            .help(url.path)
                    }
                }
                Text(data.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.dimText)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func open(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    // MARK: Linked packs

    private var linkedSection: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(text: "Packs in progress")
                    Spacer()
                    Button("LINK A PACK FOLDER…") { pickPackFolder() }.buttonStyle(ChunkyButtonStyle(kind: .green))
                }
                Text("A linked folder loads straight into the game: edit it anywhere, then reload the world.")
                    .font(.system(size: 11)).foregroundStyle(Theme.dimText)
                if linked.isEmpty {
                    Text("No packs linked.").foregroundStyle(Theme.dimText)
                }
                ForEach(linked, id: \.name) { pack in
                    HStack {
                        Text(pack.kind == .resource ? "RP" : "BP")
                            .font(.system(size: 10, weight: .heavy))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(pack.kind == .resource ? Theme.slateOn.face : Theme.green.edge)
                        Text(pack.name).font(.system(size: 13, weight: .semibold))
                        Text(pack.target.path).font(.system(size: 11)).foregroundStyle(Theme.dimText)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("UNLINK") { unlink(pack) }.buttonStyle(ChunkyButtonStyle(fontSize: 10, verticalPadding: 5))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pickPackFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Link"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try PackLinker.link(url, dataFolder: data)
        } catch let error as PackLinkerError {
            model.errorMessage = error.message
        } catch {
            model.errorMessage = error.localizedDescription
        }
        reload()
    }

    private func unlink(_ pack: LinkedPack) {
        do {
            try PackLinker.unlink(pack, dataFolder: data)
        } catch {
            model.errorMessage = "Could not unlink \(pack.name): \(error.localizedDescription)"
        }
        reload()
    }

    // MARK: Pack errors

    private var errorSection: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionTitle(text: "Pack errors")
                    Spacer()
                    Text(logName.map { "From \($0)" } ?? "No content log yet. It is written while the game runs.")
                        .font(.system(size: 11)).foregroundStyle(Theme.dimText)
                    Button("REFRESH") { reload() }.buttonStyle(ChunkyButtonStyle(fontSize: 10, verticalPadding: 5))
                }
                if logName != nil && errors.isEmpty {
                    Text("No errors or warnings in the last run.").foregroundStyle(Theme.dimText)
                }
                ForEach(errors.indices, id: \.self) { i in
                    let e = errors[i]
                    HStack(alignment: .top, spacing: 8) {
                        Text(e.time).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.dimText)
                        Text("[\(e.area)]").font(.system(size: 11, weight: .semibold))
                        Text(e.message).font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(e.level.lowercased() == "error" ? Theme.errorText : Theme.warningText)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
