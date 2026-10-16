import AppKit
import SwiftUI

@main
struct GameWrapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("GameWrap", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 640, idealWidth: 720, minHeight: 600, idealHeight: 640)
        }
        .defaultSize(width: 720, height: 640)
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.phase {
                case .drop: DropView()
                case .configure:
                    ScrollView { ConfigureView().padding(24).frame(maxWidth: 600) }
                case .building, .done, .failed:
                    ScrollView { BuildView().padding(24).frame(maxWidth: 600) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: panelID)
            Divider()
            HStack {
                RuntimeStatusView()
                Spacer()
                Text("Apple silicon · macOS 14+").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.vertical, 12)
                .background(.bar)
        }
        .foregroundStyle(FieldStyle.ink)
        .background(FieldStyle.paper)
    }

    private var panelID: String {
        switch model.phase {
        case .drop: return "choose"
        case .configure: return "configure"
        case .building: return "building"
        case .done: return "done"
        case .failed: return "failed"
        }
    }
}
