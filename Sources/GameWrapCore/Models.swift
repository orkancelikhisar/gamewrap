import Foundation

/// Settings stored in every built game at Contents/Resources/gamewrap.json and read by the launcher.
public struct GameManifest: Codable, Equatable, Sendable {
    public var schema: Int
    public var name: String
    public var exe: String
    public var args: [String]
    public var redists: [String]
    public var env: [String: String]
    public var showFPS: Bool
    public var runtime: String

    public init(name: String, exe: String, args: [String] = [], redists: [String] = [],
                env: [String: String] = [:], showFPS: Bool = false, runtime: String) {
        self.schema = 1
        self.name = name
        self.exe = exe
        self.args = args
        self.redists = redists
        self.env = env
        self.showFPS = showFPS
        self.runtime = runtime
    }

    public init(config: BuildConfig, redists: [String], runtimeID: String) {
        var env = ["WINEMSYNC": "1"]
        if config.advertiseAVX { env["ROSETTA_ADVERTISE_AVX"] = "1" }
        self.init(name: config.name, exe: config.exe, args: config.args, redists: redists,
                  env: env, showFPS: config.showFPS, runtime: runtimeID)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

public enum IconChoice: Equatable, Sendable {
    case extracted
    case custom(URL)
}

public enum OutputKind: Equatable, Sendable {
    case app
    case appAndDMG
}

public struct BuildConfig: Equatable, Sendable {
    public var name: String
    /// Path of the game's .exe, relative to the game root.
    public var exe: String
    public var icon: IconChoice
    public var args: [String]
    public var advertiseAVX: Bool
    public var showFPS: Bool
    public var output: OutputKind
    public var destination: URL

    public init(name: String, exe: String, icon: IconChoice = .extracted, args: [String] = [],
                advertiseAVX: Bool = true, showFPS: Bool = false, output: OutputKind = .app, destination: URL) {
        self.name = name
        self.exe = exe
        self.icon = icon
        self.args = args
        self.advertiseAVX = advertiseAVX
        self.showFPS = showFPS
        self.output = output
        self.destination = destination
    }
}
