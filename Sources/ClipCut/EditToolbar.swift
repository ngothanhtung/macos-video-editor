import SwiftUI

/// Thanh công cụ phía trên timeline (bố cục giống CapCut): nhập, hoàn tác, tách/xóa,
/// marker, đóng băng, nhân đôi, tốc độ, âm lượng, xoay/lật và zoom.
/// Các nút tác động lên clip đang chọn, nếu chưa chọn thì lên clip dưới playhead.
struct EditToolbar: View {
    @EnvironmentObject var model: EditorModel
    @State private var showVolume = false
    @State private var timelineWidth: Double = 800

    private static let speeds: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4]

    private var hasClips: Bool { !model.clips.isEmpty }
    private var canEditTarget: Bool { hasClips && model.hasTarget }

    var body: some View {
        HStack(spacing: 2) {
            tool(.symbol("plus"), "Nhập video", shortcut: "⌘O") { model.promptImport() }

            separator

            tool(.symbol("arrow.uturn.backward"), "Hoàn tác", shortcut: "⌘Z", enabled: model.canUndo) { model.undo() }
            tool(.symbol("arrow.uturn.forward"), "Làm lại", shortcut: "⇧⌘Z", enabled: model.canRedo) { model.redo() }

            separator

            tool(.split, "Tách", shortcut: "⌘B", enabled: hasClips) { model.splitAtPlayhead() }
            tool(.deleteLeft, "Xóa bên trái", shortcut: "Q", enabled: hasClips) { model.deleteLeftOfPlayhead() }
                .keyboardShortcut("q", modifiers: [])
            tool(.deleteRight, "Xóa bên phải", shortcut: "W", enabled: hasClips) { model.deleteRightOfPlayhead() }
                .keyboardShortcut("w", modifiers: [])
            tool(.symbol("trash"), "Xóa", shortcut: "⌫", enabled: canEditTarget) { model.removeSelected() }
            tool(.marker, "Thêm / gỡ marker", shortcut: "M", enabled: hasClips) { model.toggleMarker() }
                .keyboardShortcut("m", modifiers: [])

            separator

            tool(.symbol("snowflake"), "Đóng băng khung hình (2 giây)", shortcut: "F", enabled: hasClips) {
                model.freezeFrame()
            }
            .keyboardShortcut("f", modifiers: [])
            tool(.symbol("plus.square.on.square"), "Nhân đôi", shortcut: "⌘D", enabled: canEditTarget) {
                model.duplicateTarget()
            }
            .keyboardShortcut("d")
            speedMenu
            volumeButton
            tool(.symbol("crop.rotate"), "Xoay 90°", shortcut: "⌘R", enabled: canEditTarget) { model.rotateTarget() }
                .keyboardShortcut("r")
            tool(.mirror, "Lật ngang", enabled: canEditTarget) { model.flipTargetHorizontal() }
            tool(.flipVertical, "Lật dọc", enabled: canEditTarget) { model.flipTargetVertical() }

            separator

            textTool("I", "Đặt điểm đầu tại playhead", shortcut: "I") { model.markIn() }
                .keyboardShortcut("i", modifiers: [])
            textTool("O", "Đặt điểm cuối tại playhead", shortcut: "O") { model.markOut() }
                .keyboardShortcut("o", modifiers: [])

            Spacer(minLength: 8)

            tool(.symbol("minus.magnifyingglass"), "Thu nhỏ timeline", enabled: hasClips) {
                model.pixelsPerSecond = max(5, model.pixelsPerSecond / 1.5)
            }
            .keyboardShortcut("-")
            Slider(value: $model.pixelsPerSecond, in: 5...200)
                .controlSize(.small)
                .frame(width: 80)
                .disabled(!hasClips)
            tool(.symbol("plus.magnifyingglass"), "Phóng to timeline", enabled: hasClips) {
                model.pixelsPerSecond = min(200, model.pixelsPerSecond * 1.5)
            }
            .keyboardShortcut("=")
            tool(.symbol("arrow.left.and.right.square"), "Vừa khung timeline", shortcut: "⇧Z", enabled: hasClips) {
                model.zoomToFit(width: timelineWidth)
            }
            .keyboardShortcut("z", modifiers: .shift)
        }
        .buttonStyle(ToolButtonStyle())
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(GeometryReader { geo in
            Color.clear.onAppear { timelineWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, w in timelineWidth = w }
        })
    }

    // MARK: - Tốc độ & âm lượng

    private var speedMenu: some View {
        let enabled = canEditTarget && model.targetClip?.isFreeze == false
        return Menu {
            ForEach(Self.speeds, id: \.self) { s in
                Button {
                    model.setSpeed(s)
                } label: {
                    if model.targetClip?.speed == s { Label("\(s.formatted())x", systemImage: "checkmark") }
                    else { Text("\(s.formatted())x") }
                }
            }
        } label: {
            ToolIconView(icon: .symbol("gauge.with.needle"))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 28, height: 26)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .toolTip("Tốc độ")
    }

    private var volumeButton: some View {
        tool(.symbol(model.targetClip?.volume == 0 ? "speaker.slash" : "speaker.wave.2"), "Âm lượng",
             enabled: canEditTarget) { showVolume.toggle() }
            .popover(isPresented: $showVolume, arrowEdge: .bottom) { volumePopover }
    }

    private var volumePopover: some View {
        let volume = model.targetClip?.volume ?? 1
        return VStack(alignment: .leading, spacing: 8) {
            Text("Âm lượng clip: \(Int(volume * 100))%").font(.callout)
            Slider(value: Binding(
                get: { volume },
                set: { v in model.updateTarget(record: false) { $0.volume = v } }
            ), in: 0...2) { editing in
                if editing { model.checkpoint() }
            }
            .frame(width: 200)
            HStack {
                Button("Tắt tiếng") { model.updateTarget { $0.volume = 0 } }
                Button("100%") { model.updateTarget { $0.volume = 1 } }
            }
            .controlSize(.small)
        }
        .padding(12)
    }

    // MARK: - Thành phần

    private var separator: some View {
        Divider().frame(height: 18).padding(.horizontal, 6)
    }

    /// Tooltip gắn ngoài `.disabled` để vẫn hiện khi nút bị mờ.
    private func tool(_ icon: ToolIcon, _ title: String, shortcut: String? = nil, enabled: Bool = true,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ToolIconView(icon: icon).frame(width: 28, height: 26)
        }
        .disabled(!enabled)
        .toolTip(title, shortcut: shortcut)
    }

    private func textTool(_ label: String, _ title: String, shortcut: String,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .frame(width: 24, height: 26)
        }
        .disabled(model.selectedClip == nil)
        .toolTip(title, shortcut: shortcut)
    }
}

/// Nút trong suốt, nền bo tròn nhạt khi rê chuột / nhấn, mờ đi khi bị vô hiệu hóa.
struct ToolButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.18 : hovering && isEnabled ? 0.09 : 0))
                )
                .opacity(isEnabled ? 1 : 0.35)
                .onHover { hovering = $0 }
        }
    }
}

/// Thanh phát ngay dưới preview: về đầu, phát/dừng, timecode.
struct PlaybackBar: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        HStack(spacing: 10) {
            Text(model.currentTime.timecode)
                .foregroundStyle(.primary)
            Text("/").foregroundStyle(.tertiary)
            Text(model.totalDuration.timecode)
                .foregroundStyle(.secondary)
            Spacer()
            Button { model.seek(to: 0) } label: {
                Image(systemName: "backward.end.fill").frame(width: 28, height: 24)
            }
            .toolTip("Về đầu")
            Button { model.togglePlay() } label: {
                Image(systemName: "playpause.fill").font(.system(size: 16)).frame(width: 32, height: 24)
            }
            .keyboardShortcut(.space, modifiers: [])
            .toolTip("Phát / dừng", shortcut: "Space")
            Spacer()
            // giữ nút phát ở giữa
            Text("00:00.00 / 00:00.00").hidden()
        }
        .font(.system(.callout, design: .monospaced))
        .buttonStyle(ToolButtonStyle())
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .disabled(model.clips.isEmpty)
    }
}
