import AppKit
import BedrockLauncherCore
import SwiftUI

struct ProfileEditor: View {
    @EnvironmentObject var model: LauncherModel
    @State var profile: Profile
    let onSave: (Profile) -> Void
    let onDelete: (Profile) -> Void
    let onCancel: () -> Void

    @State private var width = ""
    @State private var height = ""

    init(profile: Profile, onSave: @escaping (Profile) -> Void, onDelete: @escaping (Profile) -> Void,
         onCancel: @escaping () -> Void) {
        _profile = State(initialValue: profile)
        _width = State(initialValue: profile.windowWidth.map(String.init) ?? "")
        _height = State(initialValue: profile.windowHeight.map(String.init) ?? "")
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(text: "Edit Profile")

            HStack(alignment: .top, spacing: 24) {
                field("Name") {
                    TextField("Name", text: $profile.name).textFieldStyle(.roundedBorder)
                }
                field("Version") {
                    Picker("", selection: $profile.gameVersion) {
                        Text("Newest installed").tag(String?.none)
                        ForEach(model.versions.reversed(), id: \.name) { v in
                            Text(v.name).tag(Optional(v.name))
                        }
                    }
                    .labelsHidden()
                }
            }

            field("Data folder") {
                HStack {
                    Text(model.dataFolder(for: profile).path)
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(Theme.dimText)
                    Spacer()
                    Button("Choose…") { chooseDataFolder() }
                    if profile.dataFolder != nil {
                        Button("Default") { profile.dataFolder = nil }
                    }
                }
            }

            field("Window size (empty for the game's default)") {
                HStack {
                    TextField("Width", text: $width).frame(width: 90).textFieldStyle(.roundedBorder)
                    Text("×")
                    TextField("Height", text: $height).frame(width: 90).textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                if model.profileList.contains(where: { $0.id == profile.id }) {
                    Button("Delete Profile") { onDelete(profile) }
                        .buttonStyle(ChunkyButtonStyle())
                }
                Spacer()
                Button("Cancel") { onCancel() }.buttonStyle(ChunkyButtonStyle())
                Button("Save") {
                    profile.windowWidth = Int(width)
                    profile.windowHeight = Int(height)
                    if profile.windowWidth == nil || profile.windowHeight == nil {
                        profile.windowWidth = nil
                        profile.windowHeight = nil
                    }
                    onSave(profile)
                }
                .buttonStyle(ChunkyButtonStyle(kind: .green))
                .disabled(profile.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(28)
        .frame(width: 640)
        .background(Theme.background)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13, weight: .semibold))
            content()
        }
    }

    private func chooseDataFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        if panel.runModal() == .OK, let url = panel.url {
            profile.dataFolder = url
        }
    }
}
