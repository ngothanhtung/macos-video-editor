import AVFoundation
import CoreGraphics

/// Dựng AVMutableComposition + AVMutableVideoComposition từ danh sách clip.
/// Composition chỉ tham chiếu tới file gốc nên dựng lại rất nhanh.
enum CompositionBuilder {
    struct Output {
        let composition: AVMutableComposition
        let videoComposition: AVMutableVideoComposition?
    }

    enum BuildError: LocalizedError {
        case cannotCreateTrack
        var errorDescription: String? { "Không tạo được track trong composition." }
    }

    private struct Segment {
        let range: CMTimeRange          // vị trí trên timeline
        let transform: CGAffineTransform // preferredTransform của track gốc
        let naturalSize: CGSize
    }

    static func build(clips: [Clip], muted: Bool) async throws -> Output {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw BuildError.cannotCreateTrack }

        let audioTrack: AVMutableCompositionTrack? = muted ? nil :
            composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        var cursor = CMTime.zero
        var segments: [Segment] = []
        var renderSize: CGSize?
        var frameRate: Float = 30

        for clip in clips where clip.duration > 0.01 {
            let asset = AVURLAsset(url: clip.url)
            guard let srcVideo = try await asset.loadTracks(withMediaType: .video).first else { continue }

            let sourceRange = CMTimeRange(start: clip.start.cmTime, end: clip.end.cmTime)
            let (natural, transform, fps) = try await srcVideo.load(.naturalSize, .preferredTransform, .nominalFrameRate)

            try videoTrack.insertTimeRange(sourceRange, of: srcVideo, at: cursor)

            if let audioTrack,
               let srcAudio = try await asset.loadTracks(withMediaType: .audio).first {
                try? audioTrack.insertTimeRange(sourceRange, of: srcAudio, at: cursor)
            }

            let oriented = orientedSize(natural, transform)
            if renderSize == nil {
                renderSize = oriented
                if fps > 0 { frameRate = fps }
            }

            segments.append(Segment(
                range: CMTimeRange(start: cursor, duration: sourceRange.duration),
                transform: transform,
                naturalSize: natural))
            cursor = cursor + sourceRange.duration
        }

        guard let baseSize = renderSize, !segments.isEmpty else {
            return Output(composition: composition, videoComposition: nil)
        }

        // Kích thước khung xuất = kích thước (đã xoay) của clip đầu tiên, làm tròn chẵn cho encoder.
        let size = CGSize(width: (baseSize.width / 2).rounded() * 2,
                          height: (baseSize.height / 2).rounded() * 2)

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = size
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, frameRate.rounded())))

        videoComposition.instructions = segments.map { seg in
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = seg.range
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            layer.setTransform(fitTransform(natural: seg.naturalSize, preferred: seg.transform, into: size),
                               at: seg.range.start)
            instruction.layerInstructions = [layer]
            return instruction
        }

        return Output(composition: composition, videoComposition: videoComposition)
    }

    private static func orientedSize(_ natural: CGSize, _ t: CGAffineTransform) -> CGSize {
        let rect = CGRect(origin: .zero, size: natural).applying(t)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    /// Xoay đúng chiều (video dọc từ điện thoại), rồi scale-to-fit và căn giữa vào khung xuất.
    private static func fitTransform(natural: CGSize, preferred: CGAffineTransform, into target: CGSize) -> CGAffineTransform {
        let rect = CGRect(origin: .zero, size: natural).applying(preferred)
        let normalized = preferred.concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        let w = abs(rect.width), h = abs(rect.height)
        guard w > 0, h > 0 else { return preferred }
        let scale = min(target.width / w, target.height / h)
        let dx = (target.width - w * scale) / 2
        let dy = (target.height - h * scale) / 2
        return normalized
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: dx, y: dy))
    }
}
