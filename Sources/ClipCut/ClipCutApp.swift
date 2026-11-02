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
                Button("Dự án mới") { model.newProject() }
                    .keyboardShortcut("n")
                Button("Mở dự án…") { model.promptOpenProject() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button("Nhập video…") { model.promptImport() }
                    .keyboardShortcut("o")
                Button("Tải video từ YouTube…") { model.showDownloader = true }
                    .keyboardShortcut("y", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .saveItem) {
                Button("Lưu dự án") { model.saveProject() }
                    .keyboardShortcut("s")
                Button("Lưu dự án thành…") { model.saveProject(saveAs: true) }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            // Khi đang gõ chữ, nhường ⌘Z và ⌫ cho ô nhập.
            CommandGroup(replacing: .undoRedo) {
                Button("Hoàn tác") { model.undo() }
                    .keyboardShortcut(model.isEditingText ? nil : KeyboardShortcut("z"))
                    .disabled(!model.canUndo)
                Button("Làm lại") { model.redo() }
                    .keyboardShortcut(model.isEditingText ? nil : KeyboardShortcut("z", modifiers: [.command, .shift]))
                    .disabled(!model.canRedo)
            }
            CommandMenu("Chỉnh sửa video") {
                Button("Cắt đôi tại playhead") { model.splitAtPlayhead() }
                    .keyboardShortcut("b")
                    .disabled(model.clips.isEmpty)
                Button(model.selectedOverlayID != nil ? "Xóa đối tượng đang chọn" : "Xóa clip đang chọn") {
                    model.removeSelected()
                }
                .keyboardShortcut(model.isEditingText ? nil : KeyboardShortcut(.delete, modifiers: []))
                .disabled(!model.canDelete)
                Divider()
                Button("Xuất video…") { model.promptExport() }
                    .keyboardShortcut("e")
                    .disabled(model.clips.isEmpty || model.isExporting)
            }
        }
    }
}
