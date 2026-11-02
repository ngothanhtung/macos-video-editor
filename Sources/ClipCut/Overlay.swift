import SwiftUI
import AppKit

/// Màu lưu được vào file dự án (sRGB).
struct RGBAColor: Codable, Hashable {
    var r: Double, g: Double, b: Double, a: Double = 1

    static let palette: [RGBAColor] = [
        RGBAColor(r: 1, g: 0.23, b: 0.19),     // đỏ
        RGBAColor(r: 1, g: 0.58, b: 0),        // cam
        RGBAColor(r: 1, g: 0.8, b: 0),         // vàng
        RGBAColor(r: 0.2, g: 0.78, b: 0.35),   // xanh lá
        RGBAColor(r: 0, g: 0.48, b: 1),        // xanh dương
        RGBAColor(r: 0.69, g: 0.32, b: 0.87),  // tím
        RGBAColor(r: 1, g: 1, b: 1),           // trắng
        RGBAColor(r: 0, g: 0, b: 0),           // đen
    ]

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .systemRed
        self.init(r: ns.redComponent, g: ns.greenComponent, b: ns.blueComponent, a: ns.alphaComponent)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var isLight: Bool { 0.299 * r + 0.587 * g + 0.114 * b > 0.6 }
    func opacity(_ k: Double) -> RGBAColor { RGBAColor(r: r, g: g, b: b, a: a * k) }
}

enum OverlayKind: String, Codable, CaseIterable, Identifiable {
    case arrow, line, rectangle, ellipse, highlight, text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .arrow: "Mũi tên"
        case .line: "Đường thẳng"
        case .rectangle: "Hình chữ nhật"
        case .ellipse: "Hình elip"
        case .highlight: "Tô sáng"
        case .text: "Chữ"
        }
    }

    var symbol: String {
        switch self {
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .highlight: "highlighter"
        case .text: "textformat"
        }
    }

    var shortcut: Character {
        switch self {
        case .arrow: "a"
        case .line: "l"
        case .rectangle: "r"
        case .ellipse: "e"
        case .highlight: "h"
        case .text: "t"
        }
    }

    /// Đối tượng có hai đầu mút (kéo từng đầu), còn lại là khung chữ nhật (kéo 4 góc).
    var isSegment: Bool { self == .arrow || self == .line }
}

/// Đối tượng vẽ đè lên video trong một khoảng thời gian trên timeline.
/// Tọa độ chuẩn hóa 0...1 theo khung hình, gốc ở góc trên-trái; nét và cỡ chữ tính theo chiều cao khung.
struct Overlay: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: OverlayKind
    var start: Double
    var end: Double
    /// Mũi tên/đường: điểm đầu → điểm cuối. Khung: hai góc đối diện. Chữ: `p1` là tâm.
    var p1: CGPoint
    var p2: CGPoint
    var color: RGBAColor
    var lineWidth: Double
    var text = ""
    var fontSize = 0.06
    var textBackground = true

    var duration: Double { max(0, end - start) }
    func isVisible(at t: Double) -> Bool { t >= start && t < end }

    var label: String {
        kind == .text ? (text.isEmpty ? kind.title : text) : kind.title
    }
}

/// Kiểu vẽ đang dùng cho đối tượng mới (và áp vào đối tượng đang chọn).
struct OverlayStyle: Equatable {
    var color = RGBAColor.palette[0]
    var lineWidth = 0.007
    var fontSize = 0.06
    var textBackground = true

    static let lineWidths: [(String, Double)] = [("Mảnh", 0.004), ("Vừa", 0.007), ("Dày", 0.012)]
}

/// Hình học dùng chung cho preview (SwiftUI) và xuất file (Core Animation) để hai bên khớp nhau.
enum OverlayGeometry {
    struct Shape {
        let path: CGPath
        let filled: Bool
        let color: RGBAColor
        let lineWidth: CGFloat
    }

    static func point(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: p.x * size.width, y: p.y * size.height)
    }

    static func rect(_ o: Overlay, in size: CGSize) -> CGRect {
        let a = point(o.p1, in: size), b = point(o.p2, in: size)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    static func shapes(for o: Overlay, in size: CGSize) -> [Shape] {
        let w = max(1, o.lineWidth * size.height)
        switch o.kind {
        case .arrow:
            let a = point(o.p1, in: size), b = point(o.p2, in: size)
            let len = hypot(b.x - a.x, b.y - a.y)
            guard len > 1 else { return [] }
            let angle = atan2(b.y - a.y, b.x - a.x)
            let head = min(max(w * 4.5, size.height * 0.02), len * 0.7)
            let spread = CGFloat.pi / 7
            func back(_ d: CGFloat, _ da: CGFloat) -> CGPoint {
                CGPoint(x: b.x - d * cos(angle + da), y: b.y - d * sin(angle + da))
            }
            let shaft = CGMutablePath()
            shaft.move(to: a)
            shaft.addLine(to: back(head * 0.75, 0))
            let tip = CGMutablePath()
            tip.move(to: b)
            tip.addLine(to: back(head, -spread))
            tip.addLine(to: back(head, spread))
            tip.closeSubpath()
            return [Shape(path: shaft, filled: false, color: o.color, lineWidth: w),
                    Shape(path: tip, filled: true, color: o.color, lineWidth: w)]
        case .line:
            let p = CGMutablePath()
            p.move(to: point(o.p1, in: size))
            p.addLine(to: point(o.p2, in: size))
            return [Shape(path: p, filled: false, color: o.color, lineWidth: w)]
        case .rectangle:
            let r = rect(o, in: size)
            let corner = min(w * 1.5, r.width / 2, r.height / 2)
            return [Shape(path: CGPath(roundedRect: r, cornerWidth: corner, cornerHeight: corner, transform: nil),
                          filled: false, color: o.color, lineWidth: w)]
        case .ellipse:
            return [Shape(path: CGPath(ellipseIn: rect(o, in: size), transform: nil),
                          filled: false, color: o.color, lineWidth: w)]
        case .highlight:
            let r = rect(o, in: size)
            let corner = min(size.height * 0.006, r.width / 2, r.height / 2)
            return [Shape(path: CGPath(roundedRect: r, cornerWidth: corner, cornerHeight: corner, transform: nil),
                          filled: true, color: o.color.opacity(0.35), lineWidth: 0)]
        case .text:
            return []
        }
    }

    // MARK: Chữ

    static func font(for o: Overlay, in size: CGSize) -> NSFont {
        .systemFont(ofSize: max(4, o.fontSize * size.height), weight: .bold)
    }

    static func textPadding(for o: Overlay, in size: CGSize) -> CGFloat {
        o.textBackground ? o.fontSize * size.height * 0.35 : 0
    }

    /// Khung chữ (gồm cả phần đệm nền) căn giữa tại `p1`.
    static func textFrame(for o: Overlay, in size: CGSize) -> CGRect {
        let text = o.text.isEmpty ? " " : o.text
        let measured = (text as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font(for: o, in: size)]).size
        let pad = textPadding(for: o, in: size)
        let w = ceil(measured.width) + pad * 2, h = ceil(measured.height) + pad * 0.8
        let c = point(o.p1, in: size)
        return CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
    }

    /// Có nền: chữ trắng/đen trên nền màu. Không nền: chữ màu, có bóng đổ.
    static func textColors(for o: Overlay) -> (foreground: RGBAColor, background: RGBAColor?) {
        guard o.textBackground else { return (o.color, nil) }
        let fg = o.color.isLight ? RGBAColor(r: 0, g: 0, b: 0) : RGBAColor(r: 1, g: 1, b: 1)
        return (fg, o.color)
    }

    /// Vùng bấm chọn (tọa độ view), nới thêm `slop` để dễ trúng nét mảnh.
    static func hitTest(_ o: Overlay, at p: CGPoint, in size: CGSize, slop: CGFloat = 6) -> Bool {
        switch o.kind {
        case .arrow, .line:
            let a = point(o.p1, in: size), b = point(o.p2, in: size)
            let tolerance = max(slop + 2, o.lineWidth * size.height / 2 + slop)
            return distance(from: p, toSegment: a, b) <= tolerance
        case .rectangle, .ellipse, .highlight:
            return rect(o, in: size).insetBy(dx: -slop, dy: -slop).contains(p)
        case .text:
            return textFrame(for: o, in: size).insetBy(dx: -slop, dy: -slop).contains(p)
        }
    }

    private static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}
