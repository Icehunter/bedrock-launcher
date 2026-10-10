import AppKit
import BedrockLauncherCore
import SwiftUI

enum Page: CaseIterable {
    case play, content, versions, mods, log, settings

    var title: String {
        switch self {
        case .play: "Play"
        case .content: "Content"
        case .versions: "Versions"
        case .mods: "Mods"
        case .log: "Game Log"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .play: "play"
        case .content: "content"
        case .versions: "versions"
        case .mods: "mods"
        case .log: "log"
        case .settings: "settings"
        }
    }
}

/// Launcher state shared by every page.
@MainActor
final class LauncherModel: ObservableObject {
    let paths: AppPaths
    let profiles: ProfileStore
    /// The client bundle's Contents folder: the app's own, or
    /// BEDROCK_BUNDLE_CONTENTS while developing with `swift run`.
    let bundleContents: URL

    @Published var page: Page = .play
    @Published var settings: LauncherSettings {
        didSet { settings.save() }
    }
    @Published private(set) var versions: [GameVersion] = []
    @Published private(set) var logLines: [String] = []
    @Published private(set) var isRunning = false
    @Published var errorMessage: String?
    @Published private(set) var profileList: [Profile] = []
    @Published var selectedProfileID: UUID
    @Published var updateNotice: UpdateCheck.Release?

    private var runner: GameRunner?
    private var logRefreshPending = false

    init(paths: AppPaths = .standard) {
        self.paths = paths
        let store: ProfileStore
        do {
            store = try ProfileStore(file: paths.profilesFile)
        } catch {
            // A damaged profiles.json is kept aside and a fresh one started.
            let aside = paths.profilesFile.appendingPathExtension("damaged")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: paths.profilesFile, to: aside)
            store = (try? ProfileStore(file: paths.profilesFile))!
        }
        profiles = store
        selectedProfileID = store.selectedID
        settings = LauncherSettings.load()
        if let override = ProcessInfo.processInfo.environment["BEDROCK_BUNDLE_CONTENTS"] {
            bundleContents = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            bundleContents = Bundle.main.bundleURL.appendingPathComponent("Contents", isDirectory: true)
        }
        refresh()
        if settings.checkForUpdates {
            Task { [weak self] in
                let release = await UpdateCheck.newerRelease(than: AppInfo.version)
                self?.updateNotice = release
            }
        }
    }

    func deleteVersion(_ version: GameVersion) {
        do {
            try InstalledVersions.delete(version)
        } catch {
            errorMessage = "Could not delete \(version.name): \(error.localizedDescription)"
        }
        refresh()
    }

    var selectedProfile: Profile {
        profiles.profiles.first { $0.id == selectedProfileID } ?? profiles.selected
    }

    func refresh() {
        versions = InstalledVersions.list(versionsFolder: paths.versions)
        profileList = profiles.profiles
    }

    func dataFolder(for profile: Profile) -> URL {
        profile.dataFolder ?? paths.defaultDataFolder(profileID: profile.id)
    }

    /// The version a profile starts: its chosen one if still installed, else the newest.
    func version(for profile: Profile) -> GameVersion? {
        if let name = profile.gameVersion, let v = versions.first(where: { $0.name == name }) {
            return v
        }
        return versions.last
    }

    func selectProfile(_ id: UUID) {
        selectedProfileID = id
        profiles.selectedID = id
        saveProfiles()
    }

    func saveProfile(_ profile: Profile) {
        if profiles.profiles.contains(where: { $0.id == profile.id }) {
            profiles.update(profile)
        } else {
            profiles.add(profile)
        }
        selectProfile(profile.id)
    }

    func deleteProfile(_ profile: Profile) {
        do {
            try profiles.remove(id: profile.id)
            selectedProfileID = profiles.selectedID
            saveProfiles()
        } catch {
            errorMessage = "The last profile cannot be deleted."
        }
    }

    private func saveProfiles() {
        do {
            try profiles.save()
        } catch {
            errorMessage = "Could not save profiles: \(error.localizedDescription)"
        }
        profileList = profiles.profiles
    }

    func play(extraArguments: [String] = []) {
        guard !isRunning else { return }
        let profile = selectedProfile
        guard let version = version(for: profile) else {
            errorMessage = "No game version is installed."
            return
        }
        let data = dataFolder(for: profile)
        do {
            try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
            // The Content page reads this log, so it must be on.
            try GameOptions.set("content_log_file", to: "1", dataFolder: data)
        } catch {
            errorMessage = "Could not prepare the data folder: \(error.localizedDescription)"
            return
        }

        var size: (width: Int, height: Int)?
        if let w = profile.windowWidth, let h = profile.windowHeight {
            size = (w, h)
        }
        let plan = LaunchPlan.make(
            contents: bundleContents,
            gameFolder: version.folder,
            dataFolder: data,
            windowSize: size,
            extraArguments: extraArguments,
            networkDebug: settings.networkDebug,
            baseEnvironment: ProcessInfo.processInfo.environment
        )

        let log = GameLog(file: paths.logs.appendingPathComponent("last-run.log"))
        log.onChange = { [weak self] in
            Task { @MainActor in self?.scheduleLogRefresh() }
        }
        let runner = GameRunner(log: log)
        runner.onExit = { [weak self] _ in
            Task { @MainActor in self?.gameExited() }
        }
        logLines = []
        do {
            try runner.start(plan)
        } catch {
            errorMessage = "Could not start the game: \(error.localizedDescription)"
            return
        }
        self.runner = runner
        isRunning = true
        if settings.hideWhilePlaying {
            NSApp.hide(nil)
        }
    }

    private func scheduleLogRefresh() {
        guard !logRefreshPending else { return }
        logRefreshPending = true
        // Collect bursts of output into one update.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.logRefreshPending = false
                self.logLines = self.runner?.log.lines ?? self.logLines
            }
        }
    }

    private func gameExited() {
        logLines = runner?.log.lines ?? logLines
        isRunning = false
        if settings.hideWhilePlaying {
            NSApp.unhide(nil)
            NSApp.activate()
        }
    }
}
