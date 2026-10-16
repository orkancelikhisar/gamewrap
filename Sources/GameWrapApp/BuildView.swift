import AppKit
import GameWrapCore
import SwiftUI

struct BuildView: View {
    @EnvironmentObject var model: AppModel
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch model.phase {
            case .done(let result): done(result)
            case .failed(let message, let suggestion): failed(message, suggestion)
            default: progressList
            }
            if !model.log.isEmpty {
                DisclosureGroup("Build details", isExpanded: $showLog) {
                    ScrollView {
                        Text(model.log).font(.system(size: 10, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }.frame(height: 130).padding(.top, 8)
                }.font(.system(size: 12))
                Button("Copy diagnostics") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.log, forType: .string)
                }.controlSize(.small)
            }
            Spacer(minLength: 0)
        }
    }

    private var progressList: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Creating your app…")
                .font(.title2.weight(.semibold))
            Text(model.name).foregroundStyle(FieldStyle.muted)
            ForEach(model.visibleSteps, id: \.self) { step in
                HStack(spacing: 12) {
                    Group {
                        switch model.steps[step] {
                        case .finished: Image(systemName: "checkmark.square.fill")
                        case .started: ProgressView().controlSize(.small)
                        case nil: Image(systemName: "square")
                        }
                    }.frame(width: 18)
                    Text(step.title).font(.system(size: 12, design: .monospaced))
                }.foregroundStyle(model.steps[step] == nil ? FieldStyle.muted : FieldStyle.ink)
            }
            if let progress = model.progress { ProgressView(value: progress) }
            Text("Large games and disk images can take several minutes. Your original files stay untouched.")
                .font(.system(size: 11)).foregroundStyle(FieldStyle.muted)
            Button("Cancel build", action: model.cancelBuild).buttonStyle(FieldButton())
        }
    }

    private func done(_ result: BuildResult) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 36)).foregroundStyle(FieldStyle.ink)
            Text("Your app is ready")
                .font(.title2.weight(.semibold))
            Text("\(model.name) is ready.").font(.system(size: 15, weight: .medium))
            Text((result.dmg ?? result.app).path).font(.system(size: 11, design: .monospaced))
                .foregroundStyle(FieldStyle.muted).textSelection(.enabled)
            Text("First launch sets up the Windows environment. Give it a minute before opening the game again.")
                .font(.system(size: 12)).foregroundStyle(FieldStyle.muted)
            HStack {
                Button("Launch game") { NSWorkspace.shared.open(result.app) }.buttonStyle(FieldButton(primary: true))
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([result.dmg ?? result.app]) }
                    .buttonStyle(FieldButton())
            }
            Button("Wrap another game", action: model.startOver).buttonStyle(.plain).underline()
        }
    }

    private func failed(_ message: String, _ suggestion: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "exclamationmark.square.fill").font(.system(size: 32)).foregroundStyle(FieldStyle.orange)
            Text("Couldn’t complete the request").font(.title2.weight(.semibold))
            Text(message).font(.system(size: 15, weight: .semibold)).textSelection(.enabled)
            Text(suggestion).font(.system(size: 12)).foregroundStyle(FieldStyle.muted).textSelection(.enabled)
            Button(model.info == nil ? "Choose a game" : "Back to settings", action: model.back)
                .buttonStyle(FieldButton(primary: true))
        }
    }
}
