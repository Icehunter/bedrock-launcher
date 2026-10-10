import AppKit
import BedrockLauncherCore
import SwiftUI
import UniformTypeIdentifiers

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
    /// The signed-in Google account, or nil. Signing in is only needed to download.
    @Published private(set) var googleEmail: String?
    @Published private(set) var isSigningIn = false
    let googlePlay: GooglePlay
    /// Game versions the launcher is known to run; Download offers only these.
    @Published private(set) var tested = TestedVersions(versions: [])
    /// Shown while a download, import or export runs. A nil fraction means
    /// the size is not known yet.
    @Published private(set) var installProgress: (title: String, fraction: Double?)?
    /// Something worth knowing that is not a failure.
    @Published var noticeMessage: String?
    private var installTask: Task<Void, Never>?
    /// Google Play's current version code, when it is newer than every tested one.
    @Published private(set) var playHasNewer: Int?
    private var playLatestCode: Int?
    /// When the last game session ended and how; kept between launches.
    @Published private(set) var lastSession: (ended: Date, exitCode: Int32)?

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
        googlePlay = GooglePlay(helper: bundleContents.appendingPathComponent("MacOS/bedrock-gplay"), state: paths.google)
        googleEmail = googlePlay.isSignedIn ? UserDefaults.standard.string(forKey: "googleEmail") ?? "" : nil
        let bundled = (try? Data(contentsOf: bundleContents.appendingPathComponent("Resources/tested-versions.json"))) ?? Data()
        tested = TestedVersions.load(remote: nil, bundled: bundled)
        Task { [weak self] in
            let remote = try? await URLSession.shared.data(from: TestedVersions.remote)
            guard let self, (remote?.1 as? HTTPURLResponse)?.statusCode == 200 else { return }
            self.tested = TestedVersions.load(remote: remote?.0, bundled: bundled)
            self.updatePlayBanner()
        }
        checkGooglePlayVersion()
        refresh()
        if let ended = UserDefaults.standard.object(forKey: "lastSessionEnded") as? Date {
            lastSession = (ended, Int32(UserDefaults.standard.integer(forKey: "lastSessionExitCode")))
        }
        if settings.checkForUpdates {
            Task { [weak self] in
                let release = await UpdateCheck.newerRelease(than: AppInfo.version)
                self?.updateNotice = release
            }
        }
    }

    /// Asks for a .mcpack, .mcaddon or .mcworld and starts the game to import it.
    func pickAndInstallContent() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["mcpack", "mcaddon", "mcworld"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsOtherFileTypes = false
        panel.prompt = "Install"
        if panel.runModal() == .OK, let url = panel.url {
            play(extraArguments: ["-ifp", url.path])
        }
    }

    /// Opens Google's sign-in page and saves the account with the helper.
    /// `then` runs after a successful sign-in.
    func signInToGoogle(then: (() -> Void)? = nil) {
        guard !isSigningIn else { return }
        isSigningIn = true
        GoogleSignInWindow.present { [weak self] token in
            guard let self else { return }
            guard let token else {
                self.isSigningIn = false
                return
            }
            Task {
                defer { self.isSigningIn = false }
                do {
                    let email = try await self.googlePlay.signIn(oauthToken: token)
                    UserDefaults.standard.set(email, forKey: "googleEmail")
                    self.googleEmail = email
                    self.checkGooglePlayVersion()
                    then?()
                } catch {
                    self.errorMessage = "Google sign-in failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func signOutOfGoogle() {
        do {
            try googlePlay.signOut()
        } catch {
            errorMessage = "Could not sign out of Google: \(error.localizedDescription)"
            return
        }
        UserDefaults.standard.removeObject(forKey: "googleEmail")
        googleEmail = nil
        playLatestCode = nil
        updatePlayBanner()
    }

    var isInstalling: Bool { installProgress != nil }

    /// Downloads a tested version from Google Play and installs it. Signs in
    /// to Google first when needed.
    func download(_ entry: TestedVersions.Entry) {
        guard !isInstalling else { return }
        guard googleEmail != nil else {
            signInToGoogle { [weak self] in self?.download(entry) }
            return
        }
        let folder = paths.apks.appendingPathComponent(String(entry.versionCode), isDirectory: true)
        let keep = settings.keepDownloadedAPKs
        runInstall(title: "Downloading Minecraft \(entry.name)") { [googlePlay, versionsFolder = paths.versions] progress in
            try? FileManager.default.removeItem(at: folder)
            let apks = try await googlePlay.download(versionCode: entry.versionCode, to: folder) { done, total in
                progress(total > 0 ? Double(done) / Double(total) : nil)
            }
            try Task.checkCancellation()
            progress(nil)
            defer { if !keep { try? FileManager.default.removeItem(at: folder) } }
            return try await Self.offMain { try VersionInstaller.install(apks: apks, versionsFolder: versionsFolder) }
        }
    }

    /// Installs a version from APK files or from a .mcversion export.
    func pickAndImport() {
        guard !isInstalling else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["apk", ReleaseArchive.fileExtension].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        panel.prompt = "Import"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        let exports = urls.filter { $0.pathExtension == ReleaseArchive.fileExtension }
        let versionsFolder = paths.versions
        if exports.count == 1 && urls.count == 1 {
            runInstall(title: "Importing \(exports[0].lastPathComponent)") { _ in
                try await Self.offMain { try ReleaseArchive.importFile(exports[0], versionsFolder: versionsFolder) }
            }
        } else if exports.isEmpty {
            runInstall(title: "Installing from APK files") { _ in
                try await Self.offMain { try VersionInstaller.install(apks: urls, versionsFolder: versionsFolder) }
            }
        } else {
            errorMessage = "Pick either one .mcversion file or a set of .apk files."
        }
    }

    /// Saves a version as a .mcversion file for another Mac.
    func export(_ version: GameVersion) {
        guard !isInstalling else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ReleaseArchive.fileName(for: version)
        if let type = UTType(filenameExtension: ReleaseArchive.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let file = panel.url else { return }
        installProgress = ("Exporting Minecraft \(version.name)", nil)
        installTask = Task {
            do {
                try await Self.offMain { try ReleaseArchive.export(version, to: file) }
                noticeMessage = "Saved \(file.lastPathComponent). Import it on another Mac from its Versions page."
            } catch {
                errorMessage = "Could not export \(version.name): \(error.localizedDescription)"
            }
            installProgress = nil
            installTask = nil
        }
    }

    func cancelInstall() {
        installTask?.cancel()
    }

    /// Runs one install with the progress bar showing, then checks the result
    /// against the tested list.
    private func runInstall(title: String,
                            _ work: @escaping @MainActor (@escaping @Sendable (Double?) -> Void) async throws -> GameVersion) {
        installProgress = (title, nil)
        installTask = Task {
            do {
                let version = try await work { fraction in
                    Task { @MainActor in
                        if self.installProgress != nil { self.installProgress = (title, fraction) }
                    }
                }
                refresh()
                let code = try? AndroidManifest.read(file: version.folder.appendingPathComponent("AndroidManifest.xml")).versionCode
                if let code, tested.entry(code: code) == nil {
                    noticeMessage = "Minecraft \(version.name) is not on the tested list. It may not run."
                }
            } catch is CancellationError {
            } catch GooglePlayError.signInNeeded {
                signOutOfGoogle()
                errorMessage = "Google asked to sign in again. Sign in on the Settings page, then download again."
            } catch {
                errorMessage = error.localizedDescription
            }
            installProgress = nil
            installTask = nil
        }
    }

    /// Runs file work away from the main thread.
    nonisolated static func offMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated) { try work() }.value
    }

    /// Asks Google Play for its current version. Failures only mean no banner.
    func checkGooglePlayVersion() {
        guard googleEmail != nil else { return }
        Task {
            playLatestCode = try? await googlePlay.latestVersionCode()
            updatePlayBanner()
        }
    }

    private func updatePlayBanner() {
        if let code = playLatestCode, tested.isNewerThanTested(code) {
            playHasNewer = code
        } else {
            playHasNewer = nil
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
        runner.onExit = { [weak self] code in
            Task { @MainActor in self?.gameExited(code: code) }
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

    private func gameExited(code: Int32) {
        logLines = runner?.log.lines ?? logLines
        isRunning = false
        lastSession = (Date(), code)
        UserDefaults.standard.set(Date(), forKey: "lastSessionEnded")
        UserDefaults.standard.set(Int(code), forKey: "lastSessionExitCode")
        if settings.hideWhilePlaying {
            NSApp.unhide(nil)
            NSApp.activate()
        }
    }
}
