import AppKit
import SwiftUI

struct DropView: View {
    @EnvironmentObject var model: AppModel
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("Add a Windows game").font(.title2.weight(.semibold))
                Text("Drop a game folder or archive to create a Mac app.")
                    .font(.body).foregroundStyle(.secondary)
            }
            VStack(spacing: 10) {
                PixelController(highlighted: targeted).frame(width: 220, height: 70)
                if let message = model.busyMessage {
                    ProgressView(message).controlSize(.small)
                } else {
                    Button("Choose Game…", action: choose)
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .keyboardShortcut("o", modifiers: .command)
                        .disabled(locked)
                        .help("Choose a game (⌘O)")
                }
                Text("EXE, ZIP, RAR, 7Z or folder")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(targeted ? Color.accentColor.opacity(0.12) : FieldStyle.panel,
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(
                targeted ? Color.accentColor : FieldStyle.line,
                style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            Text("Game compatibility varies. Rosetta 2 is required.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(maxWidth: 600)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, !locked else { return false }
            model.startOver()
            model.open(url)
            return true
        } isTargeted: { targeted = $0 }
    }

    private var locked: Bool {
        if case .building = model.phase { return true }
        return model.busyMessage != nil
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.title = "Choose your Windows game"
        panel.prompt = "Choose game"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.startOver()
            model.open(url)
        }
    }
}

struct RuntimeStatusView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            if model.runtimeInstalled {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(FieldStyle.ink)
                Text("Windows runtime ready")
            } else if let progress = model.runtimeProgress {
                ProgressView(value: progress).frame(width: 80)
                Text("Downloading runtime…")
            } else {
                Image(systemName: "arrow.down.circle")
                Button("Get Windows runtime · 240 MB", action: model.downloadRuntime)
                    .buttonStyle(.plain).underline()
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(FieldStyle.muted)
    }
}
