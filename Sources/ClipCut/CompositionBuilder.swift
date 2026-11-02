import AVFoundation
import CoreGraphics
import CoreImage

/// Dựng AVMutableComposition + AVMutableVideoComposition từ danh sách clip.
/// Composition chỉ tham chiếu tới file gốc nên dựng lại rất nhanh.
enum CompositionBuilder {
    struct Output {
        let composition: AVMutableComposition
        let videoComposition: AVMutableVideoComposition?
        let audioMix: AVMutableAudioMix?
    }

    enum BuildError: LocalizedError {
        case cannotCreateTrack
        var errorDescription: String? { "Không tạo được track trong composition." }
    }

    private struct Segment {
        let range: CMTimeRange          // vị trí trên timeline
        let transform: CGAffineTransform // preferredTransform của track gốc
        let naturalSize: CGSize
        let clip: Clip
    }

    /// `overlays` chỉ truyền khi xuất: khi đó khung hình được ghép bằng Core Image để vẽ overlay lên.
    static func build(clips: [Clip], muted: Bool, overlays: [Overlay] = []) async throws -> Output {
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
        let volumeParams = audioTrack.map { AVMutableAudioMixInputParameters(track: $0) }

        for clip in clips where clip.duration > 0.01 {
            let asset = AVURLAsset(url: clip.url)
            guard let srcVideo = try await asset.loadTracks(withMediaType: .video).first else { continue }

            let sourceRange = CMTimeRange(start: clip.start.cmTime, end: clip.end.cmTime)
            let (natural, transform, fps) = try await srcVideo.load(.naturalSize, .preferredTransform, .nominalFrameRate)

            try videoTrack.insertTimeRange(sourceRange, of: srcVideo, at: cursor)

            var hasAudio = false
            if let audioTrack, !clip.isFreeze,
               let srcAudio = try await asset.loadTracks(withMediaType: .audio).first {
                hasAudio = (try? audioTrack.insertTimeRange(sourceRange, of: srcAudio, at: cursor)) != nil
            }

            // Đổi tốc độ: co/giãn đoạn vừa chèn (clip đóng băng = 1 khung hình giãn ra vài giây).
            let placed = CMTimeRange(start: cursor, duration: sourceRange.duration)
            let target = clip.duration.cmTime
            if clip.speed != 1 {
                videoTrack.scaleTimeRange(placed, toDuration: target)
                if hasAudio { audioTrack?.scaleTimeRange(placed, toDuration: target) }
            }
            volumeParams?.setVolume(Float(clip.volume), at: cursor)

            let oriented = orientedSize(natural, transform)
            if renderSize == nil {
                renderSize = oriented
                if fps > 0 { frameRate = fps }
            }

            segments.append(Segment(
                range: CMTimeRange(start: cursor, duration: target),
                transform: transform,
                naturalSize: natural,
                clip: clip))
            cursor = cursor + target
        }

        guard let baseSize = renderSize, !segments.isEmpty else {
            return Output(composition: composition, videoComposition: nil, audioMix: nil)
        }

        // Kích thước khung xuất = kích thước (đã xoay) của clip đầu tiên, làm tròn chẵn cho encoder.
        let size = CGSize(width: (baseSize.width / 2).rounded() * 2,
                          height: (baseSize.height / 2).rounded() * 2)

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, frameRate.rounded())))
        let audioMix = volumeParams.map { params -> AVMutableAudioMix in
            let mix = AVMutableAudioMix()
            mix.inputParameters = [params]
            return mix
        }

        if !overlays.isEmpty {
            let vc = overlayComposition(composition, segments: segments, overlays: overlays, size: size)
            vc.frameDuration = frameDuration
            return Output(composition: composition, videoComposition: vc, audioMix: audioMix)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = size
        videoComposition.frameDuration = frameDuration

        videoComposition.instructions = segments.map { seg in
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = seg.range
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            layer.setTransform(fitTransform(natural: seg.naturalSize, preferred: seg.transform,
                                            clip: seg.clip, into: size),
                               at: seg.range.start)
            instruction.layerInstructions = [layer]
            return instruction
        }

        return Output(composition: composition, videoComposition: videoComposition, audioMix: audioMix)
    }

    /// Ghép từng frame bằng Core Image: đặt frame nguồn theo transform của clip (giống layer instruction),
    /// nền đen, rồi phủ ảnh overlay đang hiện ở thời điểm đó.
    private static func overlayComposition(_ composition: AVComposition, segments: [Segment],
                                           overlays: [Overlay], size: CGSize) -> AVMutableVideoComposition {
        let canvas = CGRect(origin: .zero, size: size)
        // Transform của AVFoundation dùng trục y hướng xuống, Core Image hướng lên: lật trước và sau.
        let flipDst = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
        let placements: [(start: CMTime, transform: CGAffineTransform)] = segments.map { seg in
            let flipSrc = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: seg.naturalSize.height)
            let fit = fitTransform(natural: seg.naturalSize, preferred: seg.transform, clip: seg.clip, into: size)
            return (seg.range.start, flipSrc.concatenating(fit).concatenating(flipDst))
        }
        let raster = OverlayRasterizer(overlays: overlays, size: size)
        let black = CIImage(color: .black).cropped(to: canvas)

        let vc = AVMutableVideoComposition(asset: composition) { request in
            let t = request.compositionTime
            let transform = (placements.last { $0.start <= t } ?? placements[0]).transform
            var frame = request.sourceImage.transformed(by: transform).composited(over: black)
            if let overlay = raster.image(at: t.seconds) { frame = overlay.composited(over: frame) }
            request.finish(with: frame.cropped(to: canvas), context: nil)
        }
        vc.renderSize = size
        return vc
    }

    private static func orientedSize(_ natural: CGSize, _ t: CGAffineTransform) -> CGSize {
        let rect = CGRect(origin: .zero, size: natural).applying(t)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    /// Xoay đúng chiều (video dọc từ điện thoại), áp xoay/lật của người dùng,
    /// rồi scale-to-fit và căn giữa vào khung xuất.
    private static func fitTransform(natural: CGSize, preferred: CGAffineTransform,
                                     clip: Clip, into target: CGSize) -> CGAffineTransform {
        let rect = CGRect(origin: .zero, size: natural).applying(preferred)
        let normalized = preferred.concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        var w = abs(rect.width), h = abs(rect.height)
        guard w > 0, h > 0 else { return preferred }

        // Xoay/lật quanh tâm khung hình, sau đó đưa gốc tọa độ về (0, 0).
        let turns = ((clip.quarterTurns % 4) + 4) % 4
        let user = CGAffineTransform(translationX: -w / 2, y: -h / 2)
            .concatenating(CGAffineTransform(scaleX: clip.flipH ? -1 : 1, y: clip.flipV ? -1 : 1))
            .concatenating(CGAffineTransform(rotationAngle: CGFloat(turns) * .pi / 2))
        if turns % 2 == 1 { swap(&w, &h) }
        let oriented = normalized
            .concatenating(user)
            .concatenating(CGAffineTransform(translationX: w / 2, y: h / 2))

        let scale = min(target.width / w, target.height / h)
        let dx = (target.width - w * scale) / 2
        let dy = (target.height - h * scale) / 2
        return oriented
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: dx, y: dy))
    }
}
