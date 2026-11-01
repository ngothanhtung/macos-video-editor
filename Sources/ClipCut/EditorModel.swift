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

    // MARK: - Chỉnh sửa

    func setTrim(id: Clip.ID, start: Double? = nil, end: Double? = nil) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        var c = clips[i]
        let minLen = 0.1
        if let start { c.start = min(max(0, start), c.end - minLen) }
        if let end { c.end = max(min(c.assetDuration, end), c.start + minLen) }
        clips[i] = c
    }

    /// Đặt điểm đầu/cuối của clip đang chọn tại playhead (phím I / O).
    func markIn() {
        guard let c = selectedClip else { return }
        let local = c.start + (currentTime - offset(of: c.id))
        setTrim(id: c.id, start: local)
    }

    func markOut() {
        guard let c = selectedClip else { return }
        let local = c.start + (currentTime - offset(of: c.id))
        setTrim(id: c.id, end: local)
    }

    func splitAtPlayhead() {
        var t = 0.0
        for (i, c) in clips.enumerated() {
            if currentTime >= t && currentTime < t + c.duration {
                let local = c.start + (currentTime - t)
                guard local - c.start > 0.1, c.end - local > 0.1 else { return }
                let a = Clip(url: c.url, assetDuration: c.assetDuration, start: c.start, end: local)
                let b = Clip(url: c.url, assetDuration: c.assetDuration, start: local, end: c.end)
                thumbnails[a.id] = thumbnails[c.id]
                clips.replaceSubrange(i...i, with: [a, b])
                loadThumbnail(for: b)
                selection = b.id
                status = "Đã cắt \(c.name) tại \(local.timecode)"
                return
            }
            t += c.duration
        }
    }

    func removeSelected() {
        guard let id = selection else { return }
        clips.removeAll { $0.id == id }
        thumbnails[id] = nil
        selection = nil
    }

    func move(clipID: Clip.ID, before targetID: Clip.ID?) {
        guard let from = clips.firstIndex(where: { $0.id == clipID }) else { return }
        let clip = clips.remove(at: from)
        if let targetID, let to = clips.firstIndex(where: { $0.id == targetID }) {
            clips.insert(clip, at: to)
        } else {
            clips.append(clip)
        }
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
