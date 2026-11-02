import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins

/// Thông số chỉnh màu của một clip. Mọi giá trị 0 = giữ nguyên ảnh gốc.
struct ColorAdjust: Equatable, Codable {
    /// Phơi sáng, đơn vị EV (-2...2).
    var exposure: Double = 0
    /// Các giá trị còn lại trong khoảng -1...1 (vignette 0...1).
    var contrast: Double = 0
    var saturation: Double = 0
    var vibrance: Double = 0
    var temperature: Double = 0
    var tint: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    var vignette: Double = 0

    var isIdentity: Bool { self == ColorAdjust() }

    struct Parameter: Identifiable {
        let id: String
        let title: String
        let range: ClosedRange<Double>
        let keyPath: WritableKeyPath<ColorAdjust, Double>
    }

    static let parameters: [Parameter] = [
        Parameter(id: "exposure", title: "Phơi sáng", range: -2...2, keyPath: \.exposure),
        Parameter(id: "contrast", title: "Tương phản", range: -1...1, keyPath: \.contrast),
        Parameter(id: "highlights", title: "Vùng sáng", range: -1...1, keyPath: \.highlights),
        Parameter(id: "shadows", title: "Vùng tối", range: -1...1, keyPath: \.shadows),
        Parameter(id: "saturation", title: "Bão hòa", range: -1...1, keyPath: \.saturation),
        Parameter(id: "vibrance", title: "Độ rực", range: -1...1, keyPath: \.vibrance),
        Parameter(id: "temperature", title: "Nhiệt độ", range: -1...1, keyPath: \.temperature),
        Parameter(id: "tint", title: "Tông xanh / hồng", range: -1...1, keyPath: \.tint),
        Parameter(id: "vignette", title: "Viền tối", range: 0...1, keyPath: \.vignette),
    ]

    struct Preset: Identifiable {
        let name: String
        let value: ColorAdjust
        var id: String { name }
    }

    static let presets: [Preset] = [
        Preset(name: "Gốc", value: ColorAdjust()),
        Preset(name: "Rực rỡ", value: ColorAdjust(contrast: 0.15, saturation: 0.2, vibrance: 0.4)),
        Preset(name: "Ấm", value: ColorAdjust(saturation: 0.05, temperature: 0.4, tint: 0.05)),
        Preset(name: "Lạnh", value: ColorAdjust(temperature: -0.4)),
        Preset(name: "Điện ảnh", value: ColorAdjust(contrast: 0.25, saturation: -0.2, temperature: -0.1,
                                                    highlights: -0.3, shadows: 0.1, vignette: 0.5)),
        Preset(name: "Phai màu", value: ColorAdjust(exposure: 0.1, contrast: -0.35, saturation: -0.3, shadows: 0.3)),
        Preset(name: "Đen trắng", value: ColorAdjust(contrast: 0.2, saturation: -1)),
    ]

    /// Áp các bộ lọc Core Image theo thứ tự: phơi sáng → cân bằng trắng → sáng/tối → tương phản, bão hòa
    /// → độ rực → viền tối. Kết quả cắt về đúng khung ảnh vào.
    func apply(to image: CIImage) -> CIImage {
        guard !isIdentity else { return image }
        let extent = image.extent
        var out = image

        if exposure != 0 {
            let f = CIFilter.exposureAdjust()
            f.inputImage = out
            f.ev = Float(exposure)
            out = f.outputImage ?? out
        }
        if temperature != 0 || tint != 0 {
            // đưa điểm trắng về nhiệt độ thấp hơn = ảnh ấm lên
            let f = CIFilter.temperatureAndTint()
            f.inputImage = out
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: 6500 - temperature * 3000, y: -tint * 60)
            out = f.outputImage ?? out
        }
        if highlights < 0 || shadows != 0 {
            let f = CIFilter.highlightShadowAdjust()
            f.inputImage = out
            f.highlightAmount = Float(1 + min(0, highlights) * 0.9)
            f.shadowAmount = Float(shadows)
            f.radius = Float(max(extent.width, extent.height) / 200)
            out = f.outputImage?.cropped(to: extent) ?? out
        }
        if highlights > 0 {
            // CIHighlightShadowAdjust chỉ làm tối vùng sáng được; tăng thì nâng nửa trên tone curve
            let f = CIFilter.toneCurve()
            f.inputImage = out
            f.point0 = CGPoint(x: 0, y: 0)
            f.point1 = CGPoint(x: 0.25, y: 0.25)
            f.point2 = CGPoint(x: 0.5, y: 0.5 + 0.04 * highlights)
            f.point3 = CGPoint(x: 0.75, y: 0.75 + 0.12 * highlights)
            f.point4 = CGPoint(x: 1, y: 1)
            out = f.outputImage ?? out
        }
        if contrast != 0 || saturation != 0 {
            let f = CIFilter.colorControls()
            f.inputImage = out
            f.contrast = Float(1 + contrast * 0.5)
            f.saturation = Float(1 + saturation)
            f.brightness = 0
            out = f.outputImage ?? out
        }
        if vibrance != 0 {
            let f = CIFilter.vibrance()
            f.inputImage = out
            f.amount = Float(vibrance)
            out = f.outputImage ?? out
        }
        if vignette > 0 {
            let f = CIFilter.vignetteEffect()
            f.inputImage = out
            f.center = CGPoint(x: extent.midX, y: extent.midY)
            f.radius = Float(hypot(extent.width, extent.height) / 2 * 0.95)
            f.intensity = Float(vignette)
            f.falloff = 0.6
            out = f.outputImage ?? out
        }
        return out.cropped(to: extent)
    }
}

/// Màu hiện tại của từng clip, đọc từ handler Core Image của preview (chạy ngoài main thread).
/// Sửa ở đây thì frame kế tiếp đổi màu ngay, không phải dựng lại composition.
final class ColorStore: @unchecked Sendable {
    private var values: [UUID: ColorAdjust] = [:]
    private let lock = NSLock()

    func set(_ clips: [Clip]) {
        let map = Dictionary(clips.map { ($0.id, $0.color) }, uniquingKeysWith: { a, _ in a })
        lock.lock(); values = map; lock.unlock()
    }

    func color(for id: UUID) -> ColorAdjust? {
        lock.lock(); defer { lock.unlock() }
        return values[id]
    }
}
