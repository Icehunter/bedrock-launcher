import AppKit
import SwiftUI

struct LogPage: View {
    @EnvironmentObject var model: LauncherModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Toggle("Network debug logging (next launch)", isOn: $model.settings.networkDebug)
                    .toggleStyle(BlockToggleStyle())
                    .frame(width: 380)
                Spacer()
                Button("COPY") { copy() }.buttonStyle(ChunkyButtonStyle())
                Button("SAVE…") { save() }.buttonStyle(ChunkyButtonStyle())
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(model.logLines.indices, id: \.self) { i in
                            Text(model.logLines[i])
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.text)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                    }
                    .padding(12)
                }
                .background(Theme.field)
                .overlay(Rectangle().stroke(Theme.outline, lineWidth: 2))
                .overlay {
                    if model.logLines.isEmpty {
                        Text("The log fills in when the game runs.").foregroundStyle(Theme.dimText)
                    }
                }
                .onChange(of: model.logLines.count) { _, count in
                    if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }
        }
        .padding(20)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.logLines.joined(separator: "\n"), forType: .string)
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "bedrock-game-log.txt"
        if panel.runModal() == .OK, let url = panel.url {
            try? model.logLines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
