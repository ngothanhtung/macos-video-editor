import SwiftUI
import AVKit

struct ContentView: View {
    @EnvironmentObject var model: EditorModel
    @State private var dropTargeted = false
    /// Panel thông tin bên phải, mặc định ẩn; bật bằng nút Info trên thanh công cụ.
    @State private var showInspector = false

    var body: some View {
        VStack(spacing: 0) {
            AnnotationBar()
                .zIndex(3) // tooltip tràn xuống preview
            Divider()
            preview
            PlaybackBar()
                .zIndex(2)
            Divider()
            EditToolbar()
                .zIndex(1) // tooltip tràn xuống timeline
            Divider()
            ClipTimeline()
                .frame(minHeight: 150, idealHeight: 180, maxHeight: 280)
            statusBar
        }
        .frame(minWidth: 680)
        .inspector(isPresented: $showInspector) {
            InspectorView()
                .inspectorColumnWidth(min: 260, ideal: 280, max: 340)
        }
        .toolbar { toolbarContent }
        .navigationTitle(model.windowTitle)
        .dropDestination(for: URL.self) { urls, _ in
            model.addFiles(urls.filter { $0.isFileURL })
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private var preview: some View {
        ZStack {
            Color.black
            if model.clips.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "film.stack").font(.system(size: 44))
                    Text("Kéo thả video vào đây").font(.title3)
                    Button("Nhập video… (⌘O)") { model.promptImport() }
                }
                .foregroundStyle(.secondary)
            } else {
                PlayerView(player: model.player)
                GeometryReader { geo in
                    let rect = videoRect(in: geo.size)
                    OverlayCanvas(size: rect.size)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            if dropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(8)
            }
        }
        .frame(minHeight: 300)
    }

    /// Vùng khung hình thực trong preview (AVPlayerView vẽ aspect-fit).
    private func videoRect(in container: CGSize) -> CGRect {
        let video = model.renderSize
        guard video.width > 0, video.height > 0 else { return CGRect(origin: .zero, size: container) }
        let scale = min(container.width / video.width, container.height / video.height)
        let w = video.width * scale, h = video.height * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }

    private var statusBar: some View {
        HStack {
            Text(model.status).lineLimit(1).foregroundStyle(.secondary)
            Spacer()
            if model.isExporting {
                ProgressView(value: model.exportProgress).frame(width: 160)
                Text("\(Int(model.exportProgress * 100))%").monospacedDigit()
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button { model.promptImport() } label: { Label("Nhập", systemImage: "plus") }
            Button { model.saveProject() } label: { Label("Lưu dự án", systemImage: "square.and.arrow.down") }
                .help("Lưu dự án (⌘S)")
            Toggle(isOn: $model.muted) { Label("Tắt tiếng", systemImage: model.muted ? "speaker.slash" : "speaker.wave.2") }
            Picker("Định dạng", selection: $model.exportPreset) {
                ForEach(ExportPreset.allCases) { Text($0.rawValue).tag($0) }
            }
            .frame(width: 220)
            Button { model.promptExport() } label: { Label("Xuất", systemImage: "square.and.arrow.up") }
                .disabled(model.clips.isEmpty || model.isExporting)
        }
        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $showInspector) { Label("Thông tin", systemImage: "info.circle") }
                .keyboardShortcut("i")
                .help("Hiện / ẩn panel thông tin (⌘I)")
        }
    }
}

/// Bọc AVPlayerView trực tiếp thay cho SwiftUI `VideoPlayer`: khi build bằng SwiftPM,
/// `VideoPlayer` crash lúc chạy vì AVKit không được link nên không tìm thấy class AVPlayerView.
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        // điều khiển phát nằm ở PlaybackBar; preview để trống cho lớp vẽ overlay
        view.controlsStyle = .none
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}
