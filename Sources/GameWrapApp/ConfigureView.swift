import AppKit
import GameWrapCore
import SwiftUI
import UniformTypeIdentifiers

struct ConfigureView: View {
    @EnvironmentObject var model: AppModel
    @State private var advanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Button(action: chooseIcon) {
                    Group {
                        if let image = model.iconPreview {
                            Image(nsImage: image).resizable().interpolation(.high)
                        } else {
                            Image(systemName: "gamecontroller").resizable().scaledToFit().padding(10)
                        }
                    }.frame(width: 48, height: 48)
                }
                .buttonStyle(.plain).accessibilityLabel("Choose game icon")
                .help("Choose an icon, or drop an image here")
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    model.setCustomIcon(url)
                    return true
                }
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Game name", text: $model.name)
                        .textFieldStyle(.plain).font(.title2.weight(.medium))
                        .accessibilityLabel("App name")
                    Text("Ready to make a Mac app.").font(.caption).foregroundStyle(.secondary)
                }
                Button("Change…", action: model.chooseGame)
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .keyboardShortcut("o", modifiers: .command)
                    .help("Choose another game (⌘O)")
            }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                GridRow {
                    Text("Program").foregroundStyle(.secondary)
                    Picker("Program", selection: $model.exe) {
                        ForEach(model.info?.candidates ?? []) { candidate in
                            Text(candidate.relativePath + (candidate.machine == .x86 ? " (32-bit)" : ""))
                                .tag(candidate.relativePath)
                        }
                    }.labelsHidden().frame(maxWidth: .infinity)
                }
                GridRow {
                    Text("Engine").foregroundStyle(.secondary)
                    Picker("Compatibility engine", selection: $model.runtimeProfile) {
                        ForEach(RuntimeProfile.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.labelsHidden().disabled(model.runtimeProgress != nil)
                }
                GridRow {
                    Text("Output").foregroundStyle(.secondary)
                    Picker("Output", selection: $model.makeDMG) {
                        Text("Mac app").tag(false)
                        Text("Mac app + disk image").tag(true)
                    }.labelsHidden()
                }
                GridRow {
                    Text("Save to").foregroundStyle(.secondary)
                    HStack {
                        Text(model.destination.lastPathComponent).lineLimit(1)
                            .truncationMode(.middle).help(model.destination.path)
                        Spacer(minLength: 8)
                        Button("Change…", action: chooseDestination).controlSize(.small)
                    }
                }
            }.font(.system(size: 13))
            if model.runtimeProfile == .unity6 {
                Text("DXMT supports Direct3D 10/11 and uses a separate save environment. First download: 491 MB.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("Advanced options", isExpanded: $advanced) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Launch arguments", text: $model.argsText, prompt: Text("-dx11 -windowed"))
                        .textFieldStyle(.roundedBorder)
                    Toggle("Enable AVX compatibility", isOn: $model.advertiseAVX)
                        .help("Advertise AVX instructions through Rosetta for games that require them.")
                    Toggle("Show FPS overlay", isOn: $model.showFPS)
                    if let info = model.info {
                        Text("Game folder: \(info.imported.gameRoot.path)")
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }.padding(.top, 12)
            }.font(.system(size: 12))
            HStack(alignment: .center) {
                Button("Cancel", action: model.startOver).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Build Mac app") { model.build() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Original game files stay untouched. Compatibility varies by game.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .alert("Replace existing output?", isPresented: $model.confirmOverwrite) {
            Button("Replace", role: .destructive) { model.build(overwrite: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Existing output for \(model.name) in the selected folder will be replaced.")
        }
    }

    private func chooseIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .icns]
        if panel.runModal() == .OK, let url = panel.url { model.setCustomIcon(url) }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = model.destination
        if panel.runModal() == .OK, let url = panel.url { model.chooseDestination(url) }
    }
}
