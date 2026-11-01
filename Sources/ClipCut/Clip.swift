import Foundation
import CoreMedia

/// Một đoạn video trên timeline. Thời gian tính bằng giây, tương đối với file gốc.
struct Clip: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let assetDuration: Double
    var start: Double
    var end: Double

    init(url: URL, assetDuration: Double, start: Double = 0, end: Double? = nil) {
        self.id = UUID()
        self.url = url
        self.assetDuration = assetDuration
        self.start = start
        self.end = end ?? assetDuration
    }

    var duration: Double { max(0, end - start) }
    var name: String { url.lastPathComponent }
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
