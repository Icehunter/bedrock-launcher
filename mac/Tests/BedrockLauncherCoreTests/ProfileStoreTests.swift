import Foundation
import Testing
@testable import BedrockLauncherCore

@Suite struct ProfileStoreTests {
    func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("profiles.json")
    }

    @Test func createsDefaultProfile() throws {
        let store = try ProfileStore(file: tempFile())
        #expect(store.profiles.count == 1)
        #expect(store.profiles[0].name == "Default")
        #expect(store.profiles[0].gameVersion == nil)
        #expect(store.selectedID == store.profiles[0].id)
    }

    @Test func savesAndReloads() throws {
        let file = tempFile()
        let store = try ProfileStore(file: file)
        var p = Profile(name: "Packs")
        p.gameVersion = "1.26.52.3"
        p.windowWidth = 1280
        p.windowHeight = 720
        store.add(p)
        store.selectedID = p.id
        try store.save()

        let again = try ProfileStore(file: file)
        #expect(again.profiles == store.profiles)
        #expect(again.selectedID == p.id)
    }

    @Test func refusesToRemoveLastProfile() throws {
        let store = try ProfileStore(file: tempFile())
        #expect(throws: ProfileStoreError.lastProfile) {
            try store.remove(id: store.profiles[0].id)
        }
    }

    @Test func removeSelectedPicksAnother() throws {
        let store = try ProfileStore(file: tempFile())
        let second = Profile(name: "Second")
        store.add(second)
        store.selectedID = second.id
        try store.remove(id: second.id)
        #expect(store.selectedID == store.profiles[0].id)
    }

    @Test func settingsRoundTripThroughDefaults() throws {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        var s = LauncherSettings.load(from: defaults)
        #expect(s == LauncherSettings())
        s.networkDebug = true
        s.hideWhilePlaying = false
        s.save(to: defaults)
        #expect(LauncherSettings.load(from: defaults) == s)
    }
}
