import AppKit
import GameWrapCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Phase {
        case drop, configure, building
        case done(BuildResult)
        case failed(message: String, suggestion: String)
    }

    @Published var phase: Phase = .drop
    @Published var busyMessage: String?
    @Published private(set) var info: SourceInfo?

    @Published var name = ""
    @Published var exe = "" { didSet { if exe != oldValue { refreshIcon() } } }
    @Published var customIcon: URL?
    @Published var iconPreview: NSImage?
    @Published var argsText = ""
    @Published var advertiseAVX = true
    @Published var showFPS = false
    @Published var makeDMG = false { didSet { if !destinationChosen { destination = Self.defaultDestination(dmg: makeDMG) } } }
    @Published var destination = AppModel.defaultDestination(dmg: false)
    @Published var confirmOverwrite = false

    @Published var steps: [BuildStep: StepState] = [:]
    @Published var progress: Double?
    @Published var log = ""

    @Published var runtimeInstalled: Bool
    @Published var runtimeProgress: Double?

    let gameWrap = GameWrap()
    private var destinationChosen = false
    private var buildTask: Task<Void, Never>?

    init() {
        runtimeInstalled = gameWrap.runtime.isInstalled()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self, let info = self.info { self.gameWrap.discard(info) }
            }
        }
    }

    var visibleSteps: [BuildStep] {
        BuildStep.allCases.filter { makeDMG || $0 != .package }
    }

    static func defaultDestination(dmg: Bool) -> URL {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(dmg ? "Downloads" : "Applications")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func open(_ url: URL) {
        guard busyMessage == nil else { return }
        log = "Reading \(url.lastPathComponent)\n"
        busyMessage = "Reading \(url.lastPathComponent)…"
        Task {
            defer { busyMessage = nil }
            do {
                let info = try await gameWrap.inspect(url)
                if let old = self.info { gameWrap.discard(old) }
                self.info = info
                name = info.imported.suggestedName
                customIcon = nil
                exe = info.candidates[0].relativePath
                iconPreview = info.iconPNG.flatMap(NSImage.init(data:))
                phase = .configure
            } catch {
                show(error)
            }
        }
    }

    func chooseDestination(_ url: URL) {
        destination = url
        destinationChosen = true
    }

    func setCustomIcon(_ url: URL) {
        guard let image = NSImage(contentsOf: url), image.isValid else {
            show(GameWrapError.invalidIcon)
            return
        }
        customIcon = url
        iconPreview = image
    }

    private func refreshIcon() {
        guard customIcon == nil, let info else { return }
        iconPreview = info.iconPNG(forExe: exe).flatMap(NSImage.init(data:))
    }

    func downloadRuntime() {
        runtimeProgress = 0
        Task {
            do {
                _ = try await gameWrap.runtime.ensureInstalled { value in
                    Task { @MainActor in self.runtimeProgress = value }
                }
                runtimeInstalled = true
            } catch {
                // Only take over the window from the drop screen; a running build reports its own errors.
                if case .drop = phase { show(error) } else { log += "Runtime download failed: \(error.localizedDescription)\n" }
            }
            runtimeProgress = nil
        }
    }

    func build(overwrite: Bool = false) {
        guard let info else { return }
        let config = BuildConfig(name: name.trimmingCharacters(in: .whitespaces), exe: exe,
                                 icon: customIcon.map { .custom($0) } ?? .extracted,
                                 args: ArgumentSplitter.split(argsText), advertiseAVX: advertiseAVX, showFPS: showFPS,
                                 output: makeDMG ? .appAndDMG : .app, destination: destination)
        steps = [:]
        progress = nil
        log = ""
        phase = .building
        buildTask = Task {
            do {
                for try await event in gameWrap.build(info, config, overwrite: overwrite) {
                    switch event {
                    case .step(let step, let state):
                        steps[step] = state
                        if state == .finished { progress = nil }
                    case .progress(let value):
                        progress = value
                    case .log(let line):
                        log += line + "\n"
                    case .finished(let result):
                        runtimeInstalled = true
                        phase = .done(result)
                    }
                }
                if Task.isCancelled { phase = .configure }
            } catch GameWrapError.destinationExists {
                phase = .configure
                confirmOverwrite = true
            } catch is CancellationError {
                phase = .configure
            } catch {
                show(error)
            }
        }
    }

    func cancelBuild() {
        buildTask?.cancel()
    }

    func back() {
        phase = info == nil ? .drop : .configure
    }

    func startOver() {
        if let info { gameWrap.discard(info) }
        info = nil
        name = ""
        exe = ""
        customIcon = nil
        iconPreview = nil
        argsText = ""
        advertiseAVX = true
        showFPS = false
        steps = [:]
        progress = nil
        log = ""
        confirmOverwrite = false
        phase = .drop
    }

    private func show(_ error: Error) {
        if let error = error as? GameWrapError {
            log += "\(error.message)\n\(error.suggestion)\n"
            phase = .failed(message: error.message, suggestion: error.suggestion)
        } else {
            log += "\(error.localizedDescription)\n"
            phase = .failed(message: error.localizedDescription, suggestion: "See the log for details.")
        }
    }
}
