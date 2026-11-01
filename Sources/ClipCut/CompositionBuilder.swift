import AVFoundation
import CoreGraphics

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

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = size
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, frameRate.rounded())))

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

        let audioMix = volumeParams.map { params -> AVMutableAudioMix in
            let mix = AVMutableAudioMix()
            mix.inputParameters = [params]
            return mix
        }

        return Output(composition: composition, videoComposition: videoComposition, audioMix: audioMix)
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
