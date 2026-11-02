import AppKit
import UniformTypeIdentifiers

/// Nội dung file dự án `.clipcut` (JSON). Video không được nhúng, chỉ lưu đường dẫn tới file gốc.
struct ProjectFile: Codable {
    var version = 1
    var clips: [Clip]
    var overlays: [Overlay]
    var markers: [Double]
    var muted: Bool
}

extension EditorModel {
    static let projectExtension = "clipcut"
    static var projectType: UTType { UTType(filenameExtension: projectExtension, conformingTo: .json) ?? .json }

    var projectName: String {
        projectURL?.deletingPathExtension().lastPathComponent ?? "Dự án chưa đặt tên"
    }

    var windowTitle: String {
        projectName + (hasUnsavedChanges && !(clips.isEmpty && overlays.isEmpty && projectURL == nil) ? " — Đã sửa" : "")
    }

    // MARK: - Lưu

    /// ⌘S: lưu vào file hiện tại, chưa có thì hỏi chỗ lưu. ⇧⌘S (`saveAs`) luôn hỏi.
    @discardableResult
    func saveProject(saveAs: Bool = false) -> Bool {
        guard !saveAs, let url = projectURL else { return promptSaveProject() }
        return writeProject(to: url)
    }

    private func promptSaveProject() -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.projectType]
        panel.nameFieldStringValue = projectURL?.lastPathComponent ?? "Dự án.\(Self.projectExtension)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return writeProject(to: url)
    }

    private func writeProject(to url: URL) -> Bool {
        let file = ProjectFile(clips: clips, overlays: overlays, markers: markers, muted: muted)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(file).write(to: url, options: .atomic)
            projectURL = url
            hasUnsavedChanges = false
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            status = "Đã lưu dự án: \(url.lastPathComponent)"
            return true
        } catch {
            status = "Lưu dự án lỗi: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Mở / tạo mới

    func promptOpenProject() {
        guard confirmDiscardChanges() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.projectType]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadProject(at: url)
    }

    func openProject(at url: URL) {
        guard confirmDiscardChanges() else { return }
        loadProject(at: url)
    }

    func newProject() {
        guard confirmDiscardChanges() else { return }
        replaceProject(with: ProjectFile(clips: [], overlays: [], markers: [], muted: false), url: nil)
        status = "Dự án mới"
    }

    private func loadProject(at url: URL) {
        do {
            var file = try JSONDecoder().decode(ProjectFile.self, from: Data(contentsOf: url))
            let missing = file.clips.filter { !FileManager.default.fileExists(atPath: $0.url.path) }
            file.clips.removeAll { c in missing.contains { $0.id == c.id } }
            replaceProject(with: file, url: url)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            status = missing.isEmpty
                ? "Đã mở dự án: \(url.lastPathComponent)"
                : "Không tìm thấy file gốc: \(Set(missing.map(\.name)).sorted().joined(separator: ", "))"
        } catch {
            status = "Mở dự án lỗi: \(error.localizedDescription)"
        }
    }

    private func replaceProject(with file: ProjectFile, url: URL?) {
        player.pause()
        selection = nil
        selectedOverlayID = nil
        overlayTool = nil
        clips = file.clips
        overlays = file.overlays
        markers = file.markers
        muted = file.muted
        thumbnails = [:]
        for clip in clips { loadThumbnail(for: clip) }
        clearHistory()
        projectURL = url
        seek(to: 0)
        hasUnsavedChanges = false
    }

    /// Hỏi lưu khi có thay đổi chưa lưu. Trả về false nếu người dùng bấm Hủy.
    func confirmDiscardChanges() -> Bool {
        guard hasUnsavedChanges, !(clips.isEmpty && overlays.isEmpty) else { return true }
        let alert = NSAlert()
        alert.messageText = "Lưu thay đổi của \"\(projectName)\"?"
        alert.informativeText = "Các thay đổi chưa lưu sẽ bị mất."
        alert.addButton(withTitle: "Lưu")
        alert.addButton(withTitle: "Không lưu")
        alert.addButton(withTitle: "Hủy")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveProject()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }
}
