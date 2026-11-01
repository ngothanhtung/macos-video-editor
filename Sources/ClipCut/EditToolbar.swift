import SwiftUI

/// Thanh công cụ phía trên timeline: hoàn tác, cắt/xóa, nhân đôi, đóng băng, marker,
/// tốc độ, âm lượng, xoay/lật và zoom.
/// Các nút tác động lên clip đang chọn, nếu chưa chọn thì lên clip dưới playhead.
struct EditToolbar: View {
    @EnvironmentObject var model: EditorModel
    @State private var showVolume = false
    @State private var timelineWidth: Double = 800

    private static let speeds: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4]

    var body: some View {
        HStack(spacing: 2) {
            tool("arrow.uturn.backward", "Hoàn tác (⌘Z)", enabled: model.canUndo) { model.undo() }
            tool("arrow.uturn.forward", "Làm lại (⇧⌘Z)", enabled: model.canRedo) { model.redo() }

            separator

            tool("scissors", "Tách clip tại playhead (⌘B)") { model.splitAtPlayhead() }
            tool("rectangle.lefthalf.inset.filled.arrow.left", "Xóa phần bên trái playhead (Q)") {
                model.deleteLeftOfPlayhead()
            }
            .keyboardShortcut("q", modifiers: [])
            tool("rectangle.righthalf.inset.filled.arrow.right", "Xóa phần bên phải playhead (W)") {
                model.deleteRightOfPlayhead()
            }
            .keyboardShortcut("w", modifiers: [])
            tool("trash", "Xóa clip (⌫)", enabled: model.hasTarget) { model.removeSelected() }

            separator

            tool("plus.square.on.square", "Nhân đôi clip (⌘D)", enabled: model.hasTarget) { model.duplicateTarget() }
                .keyboardShortcut("d")
            tool("snowflake", "Đóng băng khung hình 2 giây tại playhead (F)") { model.freezeFrame() }
                .keyboardShortcut("f", modifiers: [])
            tool(model.markers.isEmpty ? "bookmark" : "bookmark.fill", "Thêm / gỡ marker tại playhead (M)") {
                model.toggleMarker()
            }
            .keyboardShortcut("m", modifiers: [])

            separator

            speedMenu
            volumeButton
            tool("rotate.right", "Xoay 90° (⌘R)", enabled: model.hasTarget) { model.rotateTarget() }
                .keyboardShortcut("r")
            tool("arrow.left.and.right.righttriangle.left.righttriangle.right", "Lật ngang",
                 enabled: model.hasTarget) { model.flipTargetHorizontal() }
            tool("arrow.up.and.down.righttriangle.up.righttriangle.down", "Lật dọc",
                 enabled: model.hasTarget) { model.flipTargetVertical() }

            separator

            textTool("I", "Đặt điểm đầu clip đang chọn tại playhead (I)") { model.markIn() }
                .keyboardShortcut("i", modifiers: [])
            textTool("O", "Đặt điểm cuối clip đang chọn tại playhead (O)") { model.markOut() }
                .keyboardShortcut("o", modifiers: [])

            Spacer(minLength: 8)

            Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
            Slider(value: $model.pixelsPerSecond, in: 5...200).frame(width: 90)
            Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
            tool("arrow.left.and.right.square", "Vừa khung timeline") { model.zoomToFit(width: timelineWidth) }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .disabled(model.clips.isEmpty)
        .background(GeometryReader { geo in
            Color.clear.onAppear { timelineWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, w in timelineWidth = w }
        })
    }

    // MARK: - Tốc độ & âm lượng

    private var speedMenu: some View {
        Menu {
            ForEach(Self.speeds, id: \.self) { s in
                Button {
                    model.setSpeed(s)
                } label: {
                    if model.targetClip?.speed == s { Label("\(s.formatted())x", systemImage: "checkmark") }
                    else { Text("\(s.formatted())x") }
                }
            }
        } label: {
            Image(systemName: "gauge.with.dots.needle.67percent")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .padding(.horizontal, 4)
        .help("Tốc độ clip")
        .disabled(model.targetClip == nil || model.targetClip?.isFreeze == true)
    }

    private var volumeButton: some View {
        tool(model.targetClip?.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2", "Âm lượng clip",
             enabled: model.hasTarget) { showVolume.toggle() }
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

    private func tool(_ symbol: String, _ help: String, enabled: Bool = true,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .help(help)
        .disabled(!enabled)
    }

    private func textTool(_ label: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .help(help)
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
            Button { model.seek(to: 0) } label: { Image(systemName: "backward.end.fill") }
                .help("Về đầu")
            Button { model.togglePlay() } label: { Image(systemName: "playpause.fill").font(.system(size: 16)) }
                .keyboardShortcut(.space, modifiers: [])
                .help("Phát / dừng (Space)")
            Spacer()
            // giữ nút phát ở giữa
            Text("00:00.00 / 00:00.00").hidden()
        }
        .font(.system(.callout, design: .monospaced))
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .disabled(model.clips.isEmpty)
    }
}
