import SwiftUI
import AppKit

@main
struct ClipCutApp: App {
    @StateObject private var model = EditorModel()

    init() {
        // Cần khi chạy bằng `swift run` (không có .app bundle) để có Dock icon + menu bar
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
    }

    var body: some Scene {
        WindowGroup("ClipCut") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nhập video…") { model.promptImport() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Hoàn tác") { model.undo() }
                    .keyboardShortcut("z")
                    .disabled(!model.canUndo)
                Button("Làm lại") { model.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!model.canRedo)
            }
            CommandMenu("Chỉnh sửa video") {
                Button("Cắt đôi tại playhead") { model.splitAtPlayhead() }
                    .keyboardShortcut("b")
                    .disabled(model.clips.isEmpty)
                Button("Xóa clip đang chọn") { model.removeSelected() }
                    .keyboardShortcut(.delete, modifiers: [])
                    .disabled(!model.hasTarget)
                Divider()
                Button("Xuất video…") { model.promptExport() }
                    .keyboardShortcut("e")
                    .disabled(model.clips.isEmpty || model.isExporting)
            }
        }
    }
}
