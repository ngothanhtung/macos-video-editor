import SwiftUI

struct InspectorView: View {
    @EnvironmentObject var model: EditorModel
    @FocusState private var textFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let o = model.selectedOverlay {
                    overlaySection(o)
                } else if let clip = model.selectedClip {
                    clipSection(clip)
                } else {
                    Text("Chọn một clip hoặc đối tượng để chỉnh.")
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Dự án").font(.headline)
                    row("Số clip", "\(model.clips.count)")
                    row("Tổng thời lượng", model.totalDuration.timecode)
                    row("Đối tượng", "\(model.overlays.count)")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func clipSection(_ clip: Clip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(clip.name).font(.headline).lineLimit(2)

            if let img = model.thumbnails[clip.id] {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            row("File gốc", clip.assetDuration.timecode)
            row("Đoạn dùng", clip.sourceDuration.timecode)
            row("Trên timeline", clip.duration.timecode)
            if clip.isFreeze {
                Label("Khung hình đóng băng", systemImage: "snowflake").font(.callout)
            } else {
                row("Tốc độ", "\(clip.speed.formatted())x")
            }
            row("Âm lượng", "\(Int(clip.volume * 100))%")

            VStack(alignment: .leading, spacing: 2) {
                Text("Điểm đầu: \(clip.start.timecode)").font(.caption)
                Slider(value: Binding(
                    get: { clip.start },
                    set: { model.setTrim(id: clip.id, start: $0) }
                ), in: 0...clip.assetDuration) { if $0 { model.checkpoint() } }
                .disabled(clip.isFreeze)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Điểm cuối: \(clip.end.timecode)").font(.caption)
                Slider(value: Binding(
                    get: { clip.end },
                    set: { model.setTrim(id: clip.id, end: $0) }
                ), in: 0...clip.assetDuration) { if $0 { model.checkpoint() } }
                .disabled(clip.isFreeze)
            }

            HStack {
                Button("Đầu = playhead") { model.markIn() }
                Button("Cuối = playhead") { model.markOut() }
            }
            .controlSize(.small)

            HStack {
                Button("Khôi phục") {
                    model.updateTarget {
                        if !$0.isFreeze { $0.start = 0; $0.end = $0.assetDuration; $0.speed = 1 }
                        $0.quarterTurns = 0; $0.flipH = false; $0.flipV = false
                        if !$0.isFreeze { $0.volume = 1 }
                    }
                }
                Spacer()
                Button(role: .destructive) { model.removeSelected() } label: {
                    Label("Xóa clip", systemImage: "trash")
                }
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func overlaySection(_ o: Overlay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(o.kind.title, systemImage: o.kind.symbol).font(.headline)

            if o.kind == .text {
                TextField("Nội dung chữ", text: Binding(
                    get: { o.text },
                    set: { t in model.updateOverlay(o.id) { $0.text = t } }
                ), axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .focused($textFocused)
                .onChange(of: textFocused) { _, f in
                    model.isEditingText = f
                    if f { model.checkpoint() }
                }
            }

            timeStepper("Bắt đầu", value: o.start) { v in
                model.updateOverlay(o.id, record: true) { $0.start = min(max(0, v), $0.end - 0.1) }
            }
            timeStepper("Kết thúc", value: o.end) { v in
                model.updateOverlay(o.id, record: true) { $0.end = max(v, $0.start + 0.1) }
            }
            row("Thời lượng", o.duration.timecode)

            HStack {
                Button("Đầu = playhead") {
                    model.updateOverlay(o.id, record: true) { $0.start = min(model.currentTime, $0.end - 0.1) }
                }
                Button("Cuối = playhead") {
                    model.updateOverlay(o.id, record: true) { $0.end = max(model.currentTime, $0.start + 0.1) }
                }
            }
            .controlSize(.small)

            HStack {
                Spacer()
                Button(role: .destructive) { model.removeOverlay(o.id) } label: {
                    Label("Xóa đối tượng", systemImage: "trash")
                }
            }
            .controlSize(.small)
        }
    }

    /// Hiển thị mốc thời gian, nút −/+ chỉnh từng 0.1 giây.
    private func timeStepper(_ label: String, value: Double, set: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value.timecode).monospacedDigit()
            Stepper("", value: Binding(get: { value }, set: set), step: 0.1)
                .labelsHidden()
        }
        .font(.callout)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }
}
