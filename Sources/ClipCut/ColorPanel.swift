import SwiftUI

/// Bảng chỉnh màu cho clip mục tiêu: preset có sẵn và slider từng thông số.
/// Kéo slider thì preview đổi màu ngay; mỗi lần kéo là một bước hoàn tác.
struct ColorPanel: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        let color = model.targetClip?.color ?? ColorAdjust()
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Chỉnh màu").font(.headline)
                Spacer()
                Button("Đặt lại") { model.updateColor { $0 = ColorAdjust() } }
                    .disabled(color.isIdentity)
            }

            presets(current: color)

            Divider()

            VStack(spacing: 8) {
                ForEach(ColorAdjust.parameters) { p in
                    row(p, value: color[keyPath: p.keyPath])
                }
            }

            Divider()

            HStack {
                if let clip = model.targetClip {
                    Text(clip.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Áp dụng cho mọi clip") { model.applyColorToAll() }
                    .disabled(model.clips.count < 2)
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 320)
    }

    private func presets(current: ColorAdjust) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(ColorAdjust.presets) { preset in
                let active = preset.value == current
                Button { model.updateColor { $0 = preset.value } } label: {
                    Text(preset.name)
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(active ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(active ? Color.accentColor : .clear))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(_ p: ColorAdjust.Parameter, value: Double) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(p.title).font(.callout)
                Spacer()
                Text(Self.format(value, p))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(value == 0 ? .secondary : .primary)
                // nút về 0 luôn chiếm chỗ để slider không nhảy
                Button { model.updateColor { $0[keyPath: p.keyPath] = 0 } } label: {
                    Image(systemName: "arrow.uturn.backward").font(.caption2)
                }
                .buttonStyle(.borderless)
                .opacity(value == 0 ? 0 : 1)
                .disabled(value == 0)
                .help("Về mặc định")
            }
            Slider(value: Binding(
                get: { value },
                set: { v in model.updateColor(record: false) { $0[keyPath: p.keyPath] = Self.snap(v) } }
            ), in: p.range) { editing in
                if editing { model.checkpoint() }
            }
            .controlSize(.small)
        }
    }

    /// Hít về 0 khi kéo sát giữa để dễ trả về giá trị gốc.
    private static func snap(_ v: Double) -> Double {
        abs(v) < 0.02 ? 0 : (v * 100).rounded() / 100
    }

    private static func format(_ v: Double, _ p: ColorAdjust.Parameter) -> String {
        if p.id == "exposure" { return String(format: "%+.2f EV", v).replacingOccurrences(of: "+0.00", with: "0") }
        let n = Int((v * 100).rounded())
        return n > 0 && p.range.lowerBound < 0 ? "+\(n)" : "\(n)"
    }
}
