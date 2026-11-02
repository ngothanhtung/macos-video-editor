import Foundation
import CoreMedia

/// Một đoạn video trên timeline. `start`/`end` tính bằng giây, tương đối với file gốc.
struct Clip: Identifiable, Equatable, Codable {
    let id: UUID
    let url: URL
    let assetDuration: Double
    var start: Double
    var end: Double
    /// Hệ số tốc độ: 2 = nhanh gấp đôi (thời lượng trên timeline giảm một nửa).
    var speed: Double = 1
    /// Âm lượng 0...2 (1 = gốc).
    var volume: Double = 1
    /// Số lần xoay 90° theo chiều kim đồng hồ (0...3).
    var quarterTurns: Int = 0
    var flipH = false
    var flipV = false
    /// Clip đóng băng: một khung hình kéo dài, không có tiếng, không trim được.
    var isFreeze = false

    init(url: URL, assetDuration: Double, start: Double = 0, end: Double? = nil) {
        self.id = UUID()
        self.url = url
        self.assetDuration = assetDuration
        self.start = start
        self.end = end ?? assetDuration
    }

    /// Bản sao với id mới (giữ nguyên tốc độ, âm lượng, xoay/lật).
    func copy(start: Double? = nil, end: Double? = nil) -> Clip {
        var c = Clip(url: url, assetDuration: assetDuration, start: start ?? self.start, end: end ?? self.end)
        c.speed = speed
        c.volume = volume
        c.quarterTurns = quarterTurns
        c.flipH = flipH
        c.flipV = flipV
        c.isFreeze = isFreeze
        return c
    }

    /// Độ dài đoạn dùng trong file gốc.
    var sourceDuration: Double { max(0, end - start) }
    /// Độ dài trên timeline (đã tính tốc độ).
    var duration: Double { sourceDuration / speed }
    var name: String { url.lastPathComponent }

    /// Đổi thời gian tính từ đầu clip trên timeline sang thời gian trong file gốc.
    func sourceTime(atLocal t: Double) -> Double { start + t * speed }
}

extension Double {
    var cmTime: CMTime { CMTime(seconds: self, preferredTimescale: 600) }

    /// 75.4 -> "01:15.40"
    var timecode: String {
        let total = max(0, self)
        let m = Int(total) / 60
        let s = Int(total) % 60
        let cs = Int((total - floor(total)) * 100)
        return String(format: "%02d:%02d.%02d", m, s, cs)
    }
}
