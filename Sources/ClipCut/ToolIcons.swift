import SwiftUI

/// Icon nét mảnh cho thanh công cụ. Các icon không có trong SF Symbols (tách, xóa trái/phải,
/// marker, lật) được vẽ tay trên khung 20×20.
enum ToolIcon {
    case symbol(String)
    case split, deleteLeft, deleteRight, marker, mirror, flipVertical

    static let size: CGFloat = 20
}

struct ToolIconView: View {
    let icon: ToolIcon

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name).font(.system(size: 15, weight: .light))
        case .flipVertical:
            LineIcon(icon: .mirror).rotationEffect(.degrees(90))
        default:
            LineIcon(icon: icon)
        }
    }
}

private struct LineIcon: View {
    let icon: ToolIcon

    var body: some View {
        Canvas { ctx, size in
            let k = size.width / ToolIcon.size
            ctx.scaleBy(x: k, y: k)
            let solid = StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
            let dashed = StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [2, 2.5])
            let shading = GraphicsContext.Shading.foreground

            switch icon {
            case .split:
                // ] | [  — hai mép clip tách ra tại playhead
                ctx.stroke(bracket(x: 7, opensLeft: true), with: shading, style: solid)
                ctx.stroke(bracket(x: 13, opensLeft: false), with: shading, style: solid)
                ctx.stroke(line(10, 2, 10, 18), with: shading, style: solid)
            case .deleteLeft:
                // ⁞[  — phần bên trái (nét đứt) bị bỏ
                ctx.stroke(line(5, 3, 5, 17), with: shading, style: dashed)
                ctx.stroke(bracket(x: 11, opensLeft: false), with: shading, style: solid)
            case .deleteRight:
                // ]⁞  — phần bên phải (nét đứt) bị bỏ
                ctx.stroke(bracket(x: 9, opensLeft: true), with: shading, style: solid)
                ctx.stroke(line(15, 3, 15, 17), with: shading, style: dashed)
            case .marker:
                var p = Path()
                p.move(to: CGPoint(x: 5, y: 3))
                p.addLine(to: CGPoint(x: 15, y: 3))
                p.addLine(to: CGPoint(x: 15, y: 13))
                p.addLine(to: CGPoint(x: 10, y: 17))
                p.addLine(to: CGPoint(x: 5, y: 13))
                p.closeSubpath()
                ctx.stroke(p, with: shading, style: solid)
            case .mirror, .flipVertical:
                // ◁ ⁞ ▷  — hình và ảnh qua gương
                ctx.stroke(line(10, 2, 10, 18), with: shading, style: dashed)
                ctx.stroke(triangle(tipX: 8, baseX: 2), with: shading, style: solid)
                ctx.fill(triangle(tipX: 12, baseX: 18), with: shading)
            case .symbol:
                break
            }
        }
        .frame(width: ToolIcon.size, height: ToolIcon.size)
    }

    private func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x1, y: y1))
        p.addLine(to: CGPoint(x: x2, y: y2))
        return p
    }

    /// Ngoặc vuông cao 12pt; `opensLeft` = "]" (ngạnh chĩa sang trái), ngược lại "[".
    private func bracket(x: CGFloat, opensLeft: Bool) -> Path {
        let arm: CGFloat = opensLeft ? -4 : 4
        var p = Path()
        p.move(to: CGPoint(x: x + arm, y: 4))
        p.addLine(to: CGPoint(x: x, y: 4))
        p.addLine(to: CGPoint(x: x, y: 16))
        p.addLine(to: CGPoint(x: x + arm, y: 16))
        return p
    }

    /// Tam giác vuông: cạnh đứng tại `tipX`, đáy nằm dưới kéo tới `baseX`.
    private func triangle(tipX: CGFloat, baseX: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: tipX, y: 5))
        p.addLine(to: CGPoint(x: tipX, y: 15))
        p.addLine(to: CGPoint(x: baseX, y: 15))
        p.closeSubpath()
        return p
    }
}

// MARK: - Tooltip

/// Tooltip kiểu bong bóng tối: tên chức năng + phím tắt. Hiện sau 0.4s khi rê chuột,
/// kể cả khi nút đang bị vô hiệu hóa (khác với `.help` của hệ thống).
private struct ToolTip: ViewModifier {
    let title: String
    let shortcut: String?

    private static let bubbleHeight: CGFloat = 24

    @State private var visible = false
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                pending?.cancel()
                if inside {
                    pending = Task {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeOut(duration: 0.12)) { visible = true }
                    }
                } else {
                    visible = false
                }
            }
            .overlay(alignment: .bottom) {
                if visible {
                    // đáy bong bóng khớp đáy nút, rồi dời xuống hết chiều cao bong bóng + 6pt
                    bubble
                        .fixedSize()
                        .offset(y: Self.bubbleHeight + 6)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            // đưa nút đang hiện tooltip lên trên các nút cùng hàng, nếu không bong bóng bị nút bên phải che
            .zIndex(visible ? 1 : 0)
    }

    private var bubble: some View {
        HStack(spacing: 6) {
            Text(title)
            if let shortcut {
                Text(shortcut)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 3))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(height: Self.bubbleHeight)
        .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }
}

extension View {
    func toolTip(_ title: String, shortcut: String? = nil) -> some View {
        modifier(ToolTip(title: title, shortcut: shortcut))
    }
}

// MARK: - Phím tắt một phím

extension View {
    /// Phím tắt không kèm phím bổ trợ (I, O, Space…). Truyền `enabled: false` khi đang gõ chữ,
    /// vì phím tắt của nút được xử lý trước ô nhập và sẽ nuốt mất ký tự.
    func singleKey(_ key: KeyEquivalent, enabled: Bool) -> some View {
        keyboardShortcut(enabled ? KeyboardShortcut(key, modifiers: []) : nil)
    }
}
