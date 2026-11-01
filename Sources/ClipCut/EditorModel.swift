import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers

enum ExportPreset: String, CaseIterable, Identifiable {
    case hevcHighest = "HEVC – chất lượng cao nhất"
    case h264Highest = "H.264 – chất lượng cao nhất"
    case h264_1080 = "H.264 – 1080p"
    case h264_720 = "H.264 – 720p"

    var id: String { rawValue }
    var avPreset: String {
        switch self {
        case .hevcHighest: AVAssetExportPresetHEVCHighestQuality
        case .h264Highest: AVAssetExportPresetHighestQuality
        case .h264_1080: AVAssetExportPreset1920x1080
        case .h264_720: AVAssetExportPreset1280x720
        }
    }
}

@MainActor
final class EditorModel: ObservableObject {
    @Published var clips: [Clip] = [] { didSet { scheduleRebuild() } }
    @Published var selection: Clip.ID?
    @Published var muted = false { didSet { scheduleRebuild() } }
    @Published var thumbnails: [Clip.ID: NSImage] = [:]
    @Published var currentTime: Double = 0
    @Published var pixelsPerSecond: Double = 40

    @Published var exportPreset: ExportPreset = .hevcHighest
    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var status: String = "Kéo thả video vào cửa sổ hoặc nhấn ⌘O để nhập."

    let player = AVPlayer()
    private var rebuildTask: Task<Void, Never>?
    private var timeObserver: Any?

    init() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main
        ) { [weak self] time in
            Task { @MainActor in self?.currentTime = time.seconds.isFinite ? time.seconds : 0 }
        }
    }

    var totalDuration: Double { clips.reduce(0) { $0 + $1.duration } }
    var selectedClip: Clip? { clips.first { $0.id == selection } }

    /// Vị trí bắt đầu của clip trên timeline.
    func offset(of id: Clip.ID) -> Double {
        var t = 0.0
        for c in clips {
            if c.id == id { return t }
            t += c.duration
        }
        return t
    }

    // MARK: - Nhập file

    func promptImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { addFiles(panel.urls) }
    }

    func addFiles(_ urls: [URL]) {
        Task {
            var skipped: [String] = []
            for url in urls {
                let asset = AVURLAsset(url: url)
                do {
                    let tracks = try await asset.loadTracks(withMediaType: .video)
                    let duration = try await asset.load(.duration).seconds
                    guard !tracks.isEmpty, duration.isFinite, duration > 0 else {
                        skipped.append(url.lastPathComponent); continue
                    }
                    let clip = Clip(url: url, assetDuration: duration)
                    clips.append(clip)
                    loadThumbnail(for: clip)
                } catch {
                    skipped.append(url.lastPathComponent)
                }
            }
            status = skipped.isEmpty
                ? "\(clips.count) clip · tổng \(totalDuration.timecode)"
                : "Không mở được: \(skipped.joined(separator: ", ")) (thử convert sang MP4/MOV)"
        }
    }

    private func loadThumbnail(for clip: Clip) {
        Task {
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: clip.url))
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 240, height: 136)
            let at = min(clip.start + 0.1, max(clip.end - 0.01, clip.start)).cmTime
            if let result = try? await gen.image(at: at) {
                let cg = result.image
                thumbnails[clip.id] = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
        }
    }

    // MARK: - Lịch sử (undo / redo)

    @Published private(set) var undoStack: [[Clip]] = []
    @Published private(set) var redoStack: [[Clip]] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Lưu trạng thái hiện tại trước khi sửa. Thao tác kéo liên tục (trim, slider) chỉ gọi một lần lúc bắt đầu.
    func checkpoint() {
        undoStack.append(clips)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(clips)
        clips = prev
        if let id = selection, !clips.contains(where: { $0.id == id }) { selection = nil }
        status = "Hoàn tác"
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(clips)
        clips = next
        if let id = selection, !clips.contains(where: { $0.id == id }) { selection = nil }
        status = "Làm lại"
    }

    // MARK: - Chỉnh sửa

    /// Clip tại playhead: (index, vị trí bắt đầu trên timeline).
    private func clipAtPlayhead() -> (index: Int, offset: Double)? {
        var t = 0.0
        for (i, c) in clips.enumerated() {
            if currentTime >= t && currentTime < t + c.duration { return (i, t) }
            t += c.duration
        }
        return nil
    }

    /// Clip mà các nút chỉnh sửa tác động tới: clip đang chọn, nếu không có thì clip dưới playhead.
    private var targetIndex: Int? {
        if let id = selection, let i = clips.firstIndex(where: { $0.id == id }) { return i }
        return clipAtPlayhead()?.index
    }

    var hasTarget: Bool { targetIndex != nil }
    var targetClip: Clip? { targetIndex.map { clips[$0] } }

    func setTrim(id: Clip.ID, start: Double? = nil, end: Double? = nil) {
        guard let i = clips.firstIndex(where: { $0.id == id }), !clips[i].isFreeze else { return }
        var c = clips[i]
        let minLen = 0.1
        if let start { c.start = min(max(0, start), c.end - minLen) }
        if let end { c.end = max(min(c.assetDuration, end), c.start + minLen) }
        clips[i] = c
    }

    /// Đặt điểm đầu/cuối của clip đang chọn tại playhead (phím I / O).
    func markIn() {
        guard let c = selectedClip else { return }
        checkpoint()
        setTrim(id: c.id, start: c.sourceTime(atLocal: currentTime - offset(of: c.id)))
    }

    func markOut() {
        guard let c = selectedClip else { return }
        checkpoint()
        setTrim(id: c.id, end: c.sourceTime(atLocal: currentTime - offset(of: c.id)))
    }

    func splitAtPlayhead() {
        guard let (i, t) = clipAtPlayhead() else { return }
        let c = clips[i]
        guard !c.isFreeze else { return }
        let local = c.sourceTime(atLocal: currentTime - t)
        guard local - c.start > 0.1, c.end - local > 0.1 else { return }
        checkpoint()
        let a = c.copy(end: local)
        let b = c.copy(start: local)
        thumbnails[a.id] = thumbnails[c.id]
        clips.replaceSubrange(i...i, with: [a, b])
        loadThumbnail(for: b)
        selection = b.id
        status = "Đã cắt \(c.name) tại \(local.timecode)"
    }

    /// Xóa phần clip nằm bên trái playhead (giữ phần bên phải).
    func deleteLeftOfPlayhead() {
        guard let (i, t) = clipAtPlayhead(), !clips[i].isFreeze else { return }
        let c = clips[i]
        checkpoint()
        setTrim(id: c.id, start: c.sourceTime(atLocal: currentTime - t))
        selection = c.id
        seek(to: t)
        status = "Đã xóa phần bên trái playhead"
    }

    /// Xóa phần clip nằm bên phải playhead (giữ phần bên trái).
    func deleteRightOfPlayhead() {
        guard let (i, t) = clipAtPlayhead(), !clips[i].isFreeze else { return }
        let c = clips[i]
        checkpoint()
        setTrim(id: c.id, end: c.sourceTime(atLocal: currentTime - t))
        selection = c.id
        status = "Đã xóa phần bên phải playhead"
    }

    func removeSelected() {
        guard let i = targetIndex else { return }
        checkpoint()
        clips.remove(at: i)
        selection = nil
        seek(to: currentTime)
    }

    /// Nhân đôi clip, đặt bản sao ngay sau bản gốc.
    func duplicateTarget() {
        guard let i = targetIndex else { return }
        checkpoint()
        let dup = clips[i].copy()
        thumbnails[dup.id] = thumbnails[clips[i].id]
        clips.insert(dup, at: i + 1)
        selection = dup.id
        status = "Đã nhân đôi \(dup.name)"
    }

    /// Chèn khung hình đóng băng 2 giây tại playhead (tách clip nếu playhead nằm giữa clip).
    func freezeFrame(seconds: Double = 2) {
        guard let (i, t) = clipAtPlayhead(), !clips[i].isFreeze else { return }
        let c = clips[i]
        let local = c.sourceTime(atLocal: currentTime - t)
        let frameLen = 1.0 / 30
        let frameStart = min(local, c.end - frameLen)

        var freeze = Clip(url: c.url, assetDuration: c.assetDuration, start: frameStart, end: frameStart + frameLen)
        freeze.speed = frameLen / seconds
        freeze.volume = 0
        freeze.quarterTurns = c.quarterTurns
        freeze.flipH = c.flipH
        freeze.flipV = c.flipV
        freeze.isFreeze = true

        checkpoint()
        var replacement: [Clip] = []
        if local - c.start > 0.1 {
            let a = c.copy(end: local)
            thumbnails[a.id] = thumbnails[c.id]
            replacement.append(a)
        }
        replacement.append(freeze)
        if c.end - local > 0.1 {
            let b = c.copy(start: local)
            replacement.append(b)
            loadThumbnail(for: b)
        }
        clips.replaceSubrange(i...i, with: replacement)
        loadThumbnail(for: freeze)
        selection = freeze.id
        status = "Đã chèn khung hình đóng băng \(Int(seconds)) giây"
    }

    /// Sửa thuộc tính clip mục tiêu. `record: false` khi gọi liên tục từ slider (đã checkpoint lúc bắt đầu kéo).
    func updateTarget(record: Bool = true, _ change: (inout Clip) -> Void) {
        guard let i = targetIndex else { return }
        if record { checkpoint() }
        var c = clips[i]
        change(&c)
        clips[i] = c
    }

    func setSpeed(_ speed: Double) {
        guard targetClip?.isFreeze == false else { return }
        updateTarget { $0.speed = speed }
        status = "Tốc độ \(speed.formatted())x"
    }

    func rotateTarget() { updateTarget { $0.quarterTurns = ($0.quarterTurns + 1) % 4 } }
    func flipTargetHorizontal() { updateTarget { $0.flipH.toggle() } }
    func flipTargetVertical() { updateTarget { $0.flipV.toggle() } }

    func move(clipID: Clip.ID, before targetID: Clip.ID?) {
        guard let from = clips.firstIndex(where: { $0.id == clipID }) else { return }
        checkpoint()
        let clip = clips.remove(at: from)
        if let targetID, let to = clips.firstIndex(where: { $0.id == targetID }) {
            clips.insert(clip, at: to)
        } else {
            clips.append(clip)
        }
    }

    // MARK: - Marker

    @Published var markers: [Double] = []

    /// Thêm marker tại playhead, hoặc gỡ nếu đã có marker sát đó.
    func toggleMarker() {
        if let i = markers.firstIndex(where: { abs($0 - currentTime) < 0.05 }) {
            markers.remove(at: i)
        } else {
            markers.append(currentTime)
            markers.sort()
        }
    }

    // MARK: - Zoom

    /// Zoom để toàn bộ timeline vừa với độ rộng cho trước.
    func zoomToFit(width: Double) {
        guard totalDuration > 0 else { return }
        pixelsPerSecond = min(200, max(5, (width - 150) / totalDuration))
    }

    func seek(to seconds: Double) {
        let t = min(max(0, seconds), totalDuration)
        currentTime = t
        player.seek(to: t.cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func togglePlay() {
        if player.timeControlStatus == .playing { player.pause() } else { player.play() }
    }

    // MARK: - Dựng preview

    private func scheduleRebuild() {
        rebuildTask?.cancel()
        rebuildTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await rebuildPreview()
        }
    }

    private func rebuildPreview() async {
        let snapshot = clips
        let keepTime = currentTime
        let wasPlaying = player.timeControlStatus == .playing
        guard !snapshot.isEmpty else {
            player.replaceCurrentItem(with: nil)
            return
        }
        do {
            let out = try await CompositionBuilder.build(clips: snapshot, muted: muted)
            guard !Task.isCancelled else { return }
            let item = AVPlayerItem(asset: out.composition)
            item.videoComposition = out.videoComposition
            item.audioMix = out.audioMix
            item.audioTimePitchAlgorithm = .spectral
            player.replaceCurrentItem(with: item)
            seek(to: keepTime)
            if wasPlaying { player.play() }
        } catch {
            status = "Lỗi dựng preview: \(error.localizedDescription)"
        }
    }

    // MARK: - Xuất file

    func promptExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "ClipCut-\(Int(Date().timeIntervalSince1970)).mp4"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await export(to: url) }
    }

    private func export(to url: URL) async {
        player.pause()
        isExporting = true
        exportProgress = 0
        status = "Đang xuất…"
        defer { isExporting = false }

        do {
            let out = try await CompositionBuilder.build(clips: clips, muted: muted)
            guard let session = AVAssetExportSession(asset: out.composition, presetName: exportPreset.avPreset) else {
                status = "Preset không được hỗ trợ trên máy này."
                return
            }
            try? FileManager.default.removeItem(at: url)
            session.outputURL = url
            session.outputFileType = .mp4
            session.videoComposition = out.videoComposition
            session.audioMix = out.audioMix
            session.audioTimePitchAlgorithm = .spectral
            session.shouldOptimizeForNetworkUse = true

            let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                let p = Double(session.progress)
                Task { @MainActor in self?.exportProgress = p }
            }
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously { cont.resume() }
            }
            timer.invalidate()

            switch session.status {
            case .completed:
                exportProgress = 1
                status = "Đã xuất: \(url.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([url])
            case .cancelled:
                status = "Đã hủy xuất."
            default:
                status = "Xuất lỗi: \(session.error?.localizedDescription ?? "không rõ")"
            }
        } catch {
            status = "Xuất lỗi: \(error.localizedDescription)"
        }
    }
}
