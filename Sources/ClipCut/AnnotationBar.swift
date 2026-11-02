import SwiftUI

/// Thanh chú thích trên preview (kiểu Snappy): chọn công cụ vẽ, màu, độ dày nét, cỡ chữ
/// và sửa nội dung chữ. Kiểu vẽ áp cho đối tượng mới và cả đối tượng đang chọn.
struct AnnotationBar: View {
    @EnvironmentObject var model: EditorModel
    @FocusState private var textFocused: Bool
    @State private var textBeforeEdit: String?

    private var hasClips: Bool { !model.clips.isEmpty }
    /// Loại đối tượng đang chỉnh kiểu: đối tượng đang chọn, nếu không thì công cụ đang cầm.
    private var styleKind: OverlayKind? { model.selectedOverlay?.kind ?? model.overlayTool }

    var body: some View {
        HStack(spacing: 2) {
            toolButton(nil, symbol: "cursorarrow", title: "Chọn / di chuyển", key: "v")
            ForEach(OverlayKind.allCases) { kind in
                toolButton(kind, symbol: kind.symbol, title: kind.title, key: kind.shortcut)
            }

            separator

            ForEach(RGBAColor.palette, id: \.self) { c in swatch(c) }
            ColorPicker("", selection: Binding(
                get: { model.overlayStyle.color.color },
                set: { c in model.applyStyle { $0.color = RGBAColor(c) } }
            ), supportsOpacity: false)
            .labelsHidden()
            .frame(width: 30)
            .toolTip("Màu khác")

            separator

            if styleKind == .text {
                textControls
            } else if styleKind != .highlight {
                lineWidthControls
            }

            Spacer(minLength: 8)

            if let o = model.selectedOverlay {
                Text("\(o.start.timecode) – \(o.end.timecode)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Button { model.removeOverlay(o.id) } label: {
                    ToolIconView(icon: .symbol("trash")).frame(width: 28, height: 26)
                }
                .toolTip("Xóa đối tượng", shortcut: "⌫")
            }
        }
        .buttonStyle(ToolButtonStyle())
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .disabled(!hasClips)
        .onChange(of: model.textEditRequest) { _, _ in textFocused = true }
        .onChange(of: textFocused) { _, focused in textFocusChanged(focused) }
    }

    // MARK: - Công cụ

    private func toolButton(_ kind: OverlayKind?, symbol: String, title: String, key: Character) -> some View {
        let active = model.overlayTool == kind
        return Button {
            model.overlayTool = kind
            if kind != nil { model.selectOverlay(nil) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .light))
                .frame(width: 28, height: 26)
                .foregroundStyle(active ? Color.white : Color.primary)
                .background(RoundedRectangle(cornerRadius: 5).fill(active ? Color.accentColor : .clear))
        }
        .singleKey(KeyEquivalent(key), enabled: !model.isEditingText)
        .toolTip(title, shortcut: key.uppercased())
    }

    private func swatch(_ c: RGBAColor) -> some View {
        let selected = model.overlayStyle.color == c
        return Button { model.applyStyle { $0.color = c } } label: {
            Circle()
                .fill(c.color)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                .frame(width: 14, height: 14)
                .padding(3)
                .overlay(Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
                .frame(width: 24, height: 26)
        }
    }

    // MARK: - Kiểu nét / chữ

    private var lineWidthControls: some View {
        ForEach(OverlayStyle.lineWidths, id: \.1) { name, width in
            let active = abs(model.overlayStyle.lineWidth - width) < 0.0005
            Button { model.applyStyle { $0.lineWidth = width } } label: {
                Capsule()
                    .frame(width: 16, height: max(1.5, width * 300))
                    .frame(width: 28, height: 26)
                    .background(RoundedRectangle(cornerRadius: 5).fill(active ? Color.primary.opacity(0.15) : .clear))
            }
            .toolTip("Nét \(name.lowercased())")
        }
    }

    @ViewBuilder
    private var textControls: some View {
        Image(systemName: "textformat.size.smaller").foregroundStyle(.secondary)
        Slider(value: Binding(
            get: { model.overlayStyle.fontSize },
            set: { v in model.overlayStyle.fontSize = v; applyFontSizeLive(v) }
        ), in: 0.03...0.15) { editing in
            if editing, model.selectedOverlayID != nil { model.checkpoint() }
        }
        .controlSize(.small)
        .frame(width: 80)
        .toolTip("Cỡ chữ")
        Image(systemName: "textformat.size.larger").foregroundStyle(.secondary)

        let bg = model.overlayStyle.textBackground
        Button { model.applyStyle { $0.textBackground.toggle() } } label: {
            Image(systemName: bg ? "character.textbox" : "character")
                .font(.system(size: 15, weight: .light))
                .frame(width: 28, height: 26)
                .background(RoundedRectangle(cornerRadius: 5).fill(bg ? Color.primary.opacity(0.15) : .clear))
        }
        .toolTip(bg ? "Bỏ nền chữ" : "Thêm nền chữ")

        if let o = model.selectedOverlay, o.kind == .text {
            TextField("Nội dung chữ", text: Binding(
                get: { o.text },
                set: { t in model.updateOverlay(o.id) { $0.text = t } }
            ))
            .textFieldStyle(.roundedBorder)
            .focused($textFocused)
            .frame(minWidth: 120, maxWidth: 240)
            .onSubmit { textFocused = false }
        }
    }

    /// Kéo slider cỡ chữ: sửa trực tiếp đối tượng đang chọn (checkpoint đã ghi lúc bắt đầu kéo).
    private func applyFontSizeLive(_ v: Double) {
        guard let id = model.selectedOverlayID else { return }
        model.updateOverlay(id) { $0.fontSize = v }
    }

    /// Ghi một bước hoàn tác khi bắt đầu sửa chữ; bỏ đi nếu rời ô mà nội dung không đổi.
    private func textFocusChanged(_ focused: Bool) {
        model.isEditingText = focused
        if focused {
            textBeforeEdit = model.selectedOverlay?.text
            model.checkpoint()
        } else {
            if let before = textBeforeEdit, before == model.selectedOverlay?.text { model.discardLastCheckpoint() }
            textBeforeEdit = nil
        }
    }

    private var separator: some View {
        Divider().frame(height: 18).padding(.horizontal, 6)
    }
}
