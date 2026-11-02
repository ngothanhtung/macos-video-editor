import AppKit
import CoreImage

/// Vẽ overlay thành ảnh trong suốt cỡ khung hình để ghép lên từng frame khi xuất.
/// Preview vẽ bằng SwiftUI; cả hai lấy hình học từ `OverlayGeometry` nên khớp nhau.
final class OverlayRasterizer: @unchecked Sendable {
    private let overlays: [Overlay]
    private let size: CGSize
    private let lock = NSLock()
    /// Ảnh theo tập overlay đang hiện (đối tượng không đổi theo thời gian nên dùng lại được).
    private var cache: [[Overlay.ID]: CIImage] = [:]

    init(overlays: [Overlay], size: CGSize) {
        self.overlays = overlays
        self.size = size
    }

    /// Ảnh overlay tại thời điểm `t` trên timeline, nil nếu không có gì hiện.
    func image(at t: Double) -> CIImage? {
        let visible = overlays.filter { $0.isVisible(at: t) }
        guard !visible.isEmpty else { return nil }
        let key = visible.map(\.id)
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        guard let cg = Self.render(visible, size: size) else { return nil }
        let image = CIImage(cgImage: cg)
        cache[key] = image
        return image
    }

    static func render(_ overlays: [Overlay], size: CGSize) -> CGImage? {
        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // gốc trên-trái như preview
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }

        for o in overlays {
            if o.kind == .text {
                drawText(o, in: ctx, size: size)
                continue
            }
            for shape in OverlayGeometry.shapes(for: o, in: size) {
                ctx.addPath(shape.path)
                if shape.filled {
                    ctx.setFillColor(shape.color.cgColor)
                    ctx.fillPath()
                } else {
                    ctx.setStrokeColor(shape.color.cgColor)
                    ctx.setLineWidth(shape.lineWidth)
                    ctx.strokePath()
                }
            }
        }
        return ctx.makeImage()
    }

    private static func drawText(_ o: Overlay, in ctx: CGContext, size: CGSize) {
        let frame = OverlayGeometry.textFrame(for: o, in: size)
        let colors = OverlayGeometry.textColors(for: o)
        if let bg = colors.background {
            ctx.addPath(CGPath(roundedRect: frame, cornerWidth: frame.height * 0.22,
                               cornerHeight: frame.height * 0.22, transform: nil))
            ctx.setFillColor(bg.cgColor)
            ctx.fillPath()
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        var attrs: [NSAttributedString.Key: Any] = [
            .font: OverlayGeometry.font(for: o, in: size),
            .foregroundColor: colors.foreground.nsColor,
            .paragraphStyle: paragraph,
        ]
        if colors.background == nil {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
            shadow.shadowBlurRadius = 3
            attrs[.shadow] = shadow
        }
        let pad = OverlayGeometry.textPadding(for: o, in: size)
        (o.text as NSString).draw(with: frame.insetBy(dx: pad, dy: pad * 0.4),
                                  options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
    }
}
