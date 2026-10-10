import Foundation
import Testing
@testable import BedrockLauncherCore

@Suite struct TestedVersionsTests {
    let list = TestedVersions(versions: [
        .init(name: "1.26.52.3", versionCode: 972605203),
        .init(name: "1.26.40.1", versionCode: 972604001),
    ])

    @Test func newestHasTheHighestCode() {
        #expect(list.newest?.name == "1.26.52.3")
        #expect(TestedVersions(versions: list.versions.reversed()).newest?.name == "1.26.52.3")
    }

    @Test func findsEntryByCode() {
        #expect(list.entry(code: 972604001)?.name == "1.26.40.1")
        #expect(list.entry(code: 1) == nil)
    }

    @Test func newerThanTested() {
        #expect(list.isNewerThanTested(972605204))
        #expect(!list.isNewerThanTested(972605203))
        #expect(!TestedVersions(versions: []).isNewerThanTested(972605204))
    }

    @Test func loadPrefersRemote() throws {
        let remote = try JSONEncoder().encode(list)
        let bundled = try JSONEncoder().encode(TestedVersions(versions: [list.versions[1]]))
        #expect(TestedVersions.load(remote: remote, bundled: bundled) == list)
    }

    @Test func loadFallsBackToBundled() throws {
        let bundled = try JSONEncoder().encode(list)
        #expect(TestedVersions.load(remote: nil, bundled: bundled) == list)
        #expect(TestedVersions.load(remote: Data("{oops".utf8), bundled: bundled) == list)
    }

    @Test func repoFileDecodes() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tested-versions.json")
        let tested = try TestedVersions.decode(Data(contentsOf: file))
        #expect(tested.newest == .init(name: "1.26.52.3", versionCode: 972605203))
    }

    @Test func remoteIsTheMainBranchFile() {
        #expect(TestedVersions.remote.absoluteString == "https://raw.githubusercontent.com/Icehunter/bedrock-launcher/main/tested-versions.json")
    }
}
