import Foundation
import Testing
@testable import BedrockLauncherCore

@Suite struct AppPathsTests {
    let paths = AppPaths(root: URL(fileURLWithPath: "/tmp/x"))

    @Test func foldersSitUnderRoot() {
        #expect(paths.versions.path == "/tmp/x/versions")
        #expect(paths.logs.path == "/tmp/x/logs")
        #expect(paths.profilesFile.path == "/tmp/x/profiles.json")
    }

    @Test func gameFolderIsNamedAfterVersion() {
        #expect(paths.gameFolder(version: "1.26.52.3").path == "/tmp/x/versions/1.26.52.3")
    }

    @Test func defaultDataFolderUsesProfileID() {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        #expect(paths.defaultDataFolder(profileID: id).path == "/tmp/x/data/11111111-2222-3333-4444-555555555555")
    }

    @Test func standardRootIsApplicationSupport() {
        #expect(AppPaths.standard.root.path.hasSuffix("/Library/Application Support/BedrockLauncher"))
    }
}
