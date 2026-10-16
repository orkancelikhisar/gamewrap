import AppKit
import GameWrapCore
import SwiftUI
import UniformTypeIdentifiers

struct ConfigureView: View {
    @EnvironmentObject var model: AppModel
    @State private var advanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Mac app")
                .font(.title2.weight(.semibold))
            HStack(spacing: 16) {
                Button(action: chooseIcon) {
                    Group {
                        if let image = model.iconPreview {
                            Image(nsImage: image).resizable().interpolation(.high)
                        } else {
                            Image(systemName: "gamecontroller").resizable().scaledToFit().padding(12)
                        }
                    }.frame(width: 64, height: 64)
                }
                .buttonStyle(.plain).accessibilityLabel("Choose game icon")
                .help("Choose an icon, or drop an image here")
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    model.setCustomIcon(url)
                    return true
                }
                VStack(alignment: .leading, spacing: 6) {
                    FieldCaption(text: "App name")
                    TextField("Game name", text: $model.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 17, weight: .medium))
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                FieldCaption(text: "Windows program")
                Picker("Program", selection: $model.exe) {
                    ForEach(model.info?.candidates ?? []) { candidate in
                        Text(candidate.relativePath + (candidate.machine == .x86 ? " (32-bit)" : ""))
                            .tag(candidate.relativePath)
                    }
                }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                Text("The most likely game is selected. Choose a different program if needed.")
                    .font(.system(size: 11)).foregroundStyle(FieldStyle.muted)
            }
            VStack(alignment: .leading, spacing: 8) {
                FieldCaption(text: "Build output")
                Picker("Output", selection: $model.makeDMG) {
                    Text("Mac app").tag(false)
                    Text("Mac app + DMG").tag(true)
                }.pickerStyle(.segmented)
                Text(model.makeDMG ? "An app plus a disk image for your personal archive." : "A self-contained app. Double-click it to play.")
                    .font(.system(size: 11)).foregroundStyle(FieldStyle.muted)
            }
            VStack(alignment: .leading, spacing: 8) {
                FieldCaption(text: "Save to")
                HStack {
                    Text(model.destination.path).font(.system(size: 11, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle).help(model.destination.path)
                    Spacer(minLength: 0)
                    Button("Change…", action: chooseDestination).controlSize(.small)
                }
            }
            DisclosureGroup("Advanced settings", isExpanded: $advanced) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Launch arguments", text: $model.argsText, prompt: Text("-dx11 -windowed"))
                        .textFieldStyle(.roundedBorder)
                    Toggle("Enable AVX compatibility", isOn: $model.advertiseAVX)
                        .help("Advertise AVX instructions through Rosetta for games that require them.")
                    Toggle("Show FPS overlay", isOn: $model.showFPS)
                    if let info = model.info {
                        Text("Game folder: \(info.imported.gameRoot.path)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(FieldStyle.muted).textSelection(.enabled)
                    }
                }.padding(.top, 12)
            }.font(.system(size: 12))
            Divider().overlay(FieldStyle.line)
            Text("Compatibility varies by game. First launch may take a minute while the Windows environment is prepared.")
                .font(.system(size: 11)).foregroundStyle(FieldStyle.muted)
            HStack {
                Button("Cancel", action: model.startOver).buttonStyle(FieldButton())
                Spacer()
                Button("Build Mac App") { model.build() }
                    .buttonStyle(FieldButton(primary: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
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
