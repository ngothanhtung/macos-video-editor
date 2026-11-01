import SwiftUI

struct InspectorView: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let clip = model.selectedClip {
                    clipSection(clip)
                } else {
                    Text("Chọn một clip trên timeline để chỉnh.")
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Dự án").font(.headline)
                    row("Số clip", "\(model.clips.count)")
                    row("Tổng thời lượng", model.totalDuration.timecode)
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Phím tắt").font(.headline)
                    shortcut("Space", "Phát / dừng")
                    shortcut("⌘B", "Cắt tại playhead")
                    shortcut("I / O", "Đặt điểm đầu / cuối")
                    shortcut("⌫", "Xóa clip đang chọn")
                    shortcut("⌘O", "Nhập video")
                    shortcut("⌘E", "Xuất video")
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
            row("Đoạn dùng", clip.duration.timecode)

            VStack(alignment: .leading, spacing: 2) {
                Text("Điểm đầu: \(clip.start.timecode)").font(.caption)
                Slider(value: Binding(
                    get: { clip.start },
                    set: { model.setTrim(id: clip.id, start: $0) }
                ), in: 0...clip.assetDuration)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Điểm cuối: \(clip.end.timecode)").font(.caption)
                Slider(value: Binding(
                    get: { clip.end },
                    set: { model.setTrim(id: clip.id, end: $0) }
                ), in: 0...clip.assetDuration)
            }

            HStack {
                Button("Đầu = playhead") { model.markIn() }
                Button("Cuối = playhead") { model.markOut() }
            }
            .controlSize(.small)

            HStack {
                Button("Khôi phục") { model.setTrim(id: clip.id, start: 0, end: clip.assetDuration) }
                Spacer()
                Button(role: .destructive) { model.removeSelected() } label: {
                    Label("Xóa clip", systemImage: "trash")
                }
            }
            .controlSize(.small)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }

    private func shortcut(_ key: String, _ action: String) -> some View {
        HStack {
            Text(key).font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
            Text(action).font(.caption)
        }
    }
}
