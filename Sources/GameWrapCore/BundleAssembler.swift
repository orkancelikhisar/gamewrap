import Foundation

public struct BundleAssembler: Sendable {
    let runner: ProcessRunner

    public init(runner: ProcessRunner) {
        self.runner = runner
    }

    /// Builds `<dir>/<Name>.app` from the game, runtime and icon, and returns its URL.
    public func assemble(manifest: GameManifest, gameRoot: URL, wine: URL, icns: URL, in dir: URL) async throws -> URL {
        let fm = FileManager.default
        let app = dir.appendingPathComponent(Self.bundleFileName(manifest.name) + ".app")
        let contents = app.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        let resources = contents.appendingPathComponent("Resources")
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)

        let plist = try PropertyListSerialization.data(fromPropertyList: Self.infoPlist(for: manifest), format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))

        let launcher = macOS.appendingPathComponent("launcher")
        try Data(LauncherTemplate.script.utf8).write(to: launcher)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)

        try manifest.encoded().write(to: resources.appendingPathComponent("gamewrap.json"))
        try fm.copyItem(at: icns, to: resources.appendingPathComponent("AppIcon.icns"))

        let wineDestination = resources.appendingPathComponent("wine")
        try await runner.run(Tool.ditto, [wine.path, wineDestination.path])
        try Data(Self.wineNotice.utf8).write(to: wineDestination.appendingPathComponent("LICENSE-NOTICE.txt"))
        try await runner.run(Tool.ditto, [gameRoot.path, resources.appendingPathComponent("game").path])
        return app
    }

    /// ASCII-only identifier part for the bundle ID, e.g. "baldur-s-gate-3".
    public static func slug(_ name: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        let parts = name.lowercased().components(separatedBy: allowed.inverted).filter { !$0.isEmpty }
        return parts.isEmpty ? "game" : parts.joined(separator: "-")
    }

    /// A file name safe for Finder: no slashes or colons.
    public static func bundleFileName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Game" : trimmed.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    static func infoPlist(for manifest: GameManifest) -> [String: Any] {
        [
            "CFBundleName": manifest.name,
            "CFBundleDisplayName": manifest.name,
            "CFBundleIdentifier": "local.gamewrap.\(slug(manifest.name))",
            "CFBundleExecutable": "launcher",
            "CFBundleIconFile": "AppIcon",
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1",
            "CFBundleShortVersionString": "1.0",
            "LSMinimumSystemVersion": "14.0",
            "LSApplicationCategoryType": "public.app-category.games",
            "NSHighResolutionCapable": true,
        ]
    }

    static let wineNotice = """
    This folder contains Wine from Apple's Game Porting Toolkit, as packaged by Gcenx:
    https://github.com/Gcenx/game-porting-toolkit
    Wine is licensed under the GNU LGPL 2.1; its source is available from the link above.
    lib/external/D3DMetal.framework is Apple software under Apple's license.
    Built with GameWrap for personal use. Do not redistribute this app publicly.

    """
}
