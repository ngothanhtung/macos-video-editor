import SwiftUI

/// Lớp vẽ overlay trên preview, phủ đúng vùng khung hình (aspect-fit).
/// - Có công cụ vẽ: kéo để tạo mũi tên/đường/khung, bấm để đặt chữ.
/// - Không có công cụ: bấm chọn, kéo để di chuyển, kéo tay nắm để đổi đầu mút / góc.
/// - Bấm đúp vào chữ: sửa nội dung trên thanh chú thích.
struct OverlayCanvas: View {
    @EnvironmentObject var model: EditorModel
    let size: CGSize

    private enum Drag {
        case create(Overlay.ID)
        case move(Overlay.ID, original: Overlay, moved: Bool)
        case handle(Overlay.ID, index: Int, original: Overlay, moved: Bool)
        case idle
    }

    @State private var drag: Drag?

    private static let handleRadius: CGFloat = 5

    var body: some View {
        Canvas { ctx, size in
            for o in model.visibleOverlays { draw(o, in: &ctx, size: size) }
            if let o = model.selectedOverlay, o.isVisible(at: model.currentTime) {
                drawSelection(o, in: &ctx, size: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged(dragChanged)
                .onEnded(dragEnded)
        )
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if model.selectedOverlay?.kind == .text { model.textEditRequest += 1 }
        })
        .onContinuousHover { phase in
            if case .active = phase, model.overlayTool != nil { NSCursor.crosshair.set() }
        }
    }

    // MARK: - Vẽ

    private func draw(_ o: Overlay, in ctx: inout GraphicsContext, size: CGSize) {
        if o.kind == .text {
            let frame = OverlayGeometry.textFrame(for: o, in: size)
            let colors = OverlayGeometry.textColors(for: o)
            let text = Text(o.text)
                .font(Font(OverlayGeometry.font(for: o, in: size) as CTFont))
                .foregroundColor(colors.foreground.color)
            if let bg = colors.background {
                ctx.fill(Path(roundedRect: frame, cornerRadius: frame.height * 0.22), with: .color(bg.color))
                ctx.draw(text, at: CGPoint(x: frame.midX, y: frame.midY), anchor: .center)
            } else {
                var shadowed = ctx
                shadowed.addFilter(.shadow(color: .black.opacity(0.6), radius: 3))
                shadowed.draw(text, at: CGPoint(x: frame.midX, y: frame.midY), anchor: .center)
            }
            return
        }
        for shape in OverlayGeometry.shapes(for: o, in: size) {
            let path = Path(shape.path)
            if shape.filled {
                ctx.fill(path, with: .color(shape.color.color))
            } else {
                ctx.stroke(path, with: .color(shape.color.color),
                           style: StrokeStyle(lineWidth: shape.lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func drawSelection(_ o: Overlay, in ctx: inout GraphicsContext, size: CGSize) {
        let dash = StrokeStyle(lineWidth: 1, dash: [4, 3])
        switch o.kind {
        case .text:
            let r = OverlayGeometry.textFrame(for: o, in: size).insetBy(dx: -4, dy: -4)
            ctx.stroke(Path(r), with: .color(.white), style: dash)
        case .rectangle, .ellipse, .highlight:
            ctx.stroke(Path(OverlayGeometry.rect(o, in: size)), with: .color(.white.opacity(0.8)), style: dash)
        case .arrow, .line:
            break
        }
        for p in handles(of: o, in: size) {
            let r = CGRect(x: p.x - Self.handleRadius, y: p.y - Self.handleRadius,
                           width: Self.handleRadius * 2, height: Self.handleRadius * 2)
            ctx.fill(Path(ellipseIn: r), with: .color(.white))
            ctx.stroke(Path(ellipseIn: r), with: .color(.accentColor), lineWidth: 1.5)
        }
    }

    /// Tay nắm: hai đầu mút (mũi tên/đường) hoặc 4 góc (khung). Chữ chỉ di chuyển, đổi cỡ trên thanh chú thích.
    private func handles(of o: Overlay, in size: CGSize) -> [CGPoint] {
        let a = OverlayGeometry.point(o.p1, in: size), b = OverlayGeometry.point(o.p2, in: size)
        switch o.kind {
        case .arrow, .line: return [a, b]
        case .rectangle, .ellipse, .highlight: return [a, b, CGPoint(x: b.x, y: a.y), CGPoint(x: a.x, y: b.y)]
        case .text: return []
        }
    }

    // MARK: - Tương tác

    private func normalized(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x / size.width, 0), 1), y: min(max(p.y / size.height, 0), 1))
    }

    private func dragChanged(_ v: DragGesture.Value) {
        if drag == nil { begin(at: v.startLocation) }
        guard let drag else { return }
        let moved = hypot(v.translation.width, v.translation.height) > 1
        switch drag {
        case .create(let id):
            model.updateOverlay(id) { if $0.kind != .text { $0.p2 = normalized(v.location) } }
        case .move(let id, let original, _):
            let dx = v.translation.width / size.width, dy = v.translation.height / size.height
            model.updateOverlay(id) {
                $0.p1 = CGPoint(x: original.p1.x + dx, y: original.p1.y + dy)
                $0.p2 = CGPoint(x: original.p2.x + dx, y: original.p2.y + dy)
            }
            if moved { self.drag = .move(id, original: original, moved: true) }
        case .handle(let id, let index, let original, _):
            let q = normalized(v.location)
            model.updateOverlay(id) {
                switch index {
                case 0: $0.p1 = q
                case 1: $0.p2 = q
                case 2: $0.p2.x = q.x; $0.p1.y = q.y
                default: $0.p1.x = q.x; $0.p2.y = q.y
                }
            }
            if moved { self.drag = .handle(id, index: index, original: original, moved: true) }
        case .idle:
            break
        }
    }

    private func begin(at p: CGPoint) {
        if let tool = model.overlayTool {
            drag = .create(model.addOverlay(tool, at: normalized(p)))
            return
        }
        if let sel = model.selectedOverlay, sel.isVisible(at: model.currentTime),
           let index = handles(of: sel, in: size).firstIndex(where: { hypot($0.x - p.x, $0.y - p.y) <= Self.handleRadius + 4 }) {
            model.checkpoint()
            drag = .handle(sel.id, index: index, original: sel, moved: false)
        } else if let hit = model.visibleOverlays.last(where: { OverlayGeometry.hitTest($0, at: p, in: size) }) {
            model.selectOverlay(hit.id)
            model.checkpoint()
            drag = .move(hit.id, original: hit, moved: false)
        } else {
            model.selectOverlay(nil)
            drag = .idle
        }
    }

    private func dragEnded(_ v: DragGesture.Value) {
        defer { drag = nil }
        switch drag {
        case .create(let id):
            let tiny = hypot(v.translation.width, v.translation.height) < 4
            if tiny, model.overlayTool != .text {
                // bấm mà không kéo: bỏ hình rỗng
                model.overlays.removeAll { $0.id == id }
                model.discardLastCheckpoint()
                model.selectedOverlayID = nil
                return
            }
            model.overlayTool = nil
            if model.selectedOverlay?.kind == .text { model.textEditRequest += 1 }
        case .move(_, _, let moved), .handle(_, _, _, let moved):
            if !moved { model.discardLastCheckpoint() }
        case .idle, nil:
            break
        }
    }
}
