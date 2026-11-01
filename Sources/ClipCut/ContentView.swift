import SwiftUI
import AVKit

struct ContentView: View {
    @EnvironmentObject var model: EditorModel
    @State private var dropTargeted = false

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                preview
                PlaybackBar()
                Divider()
                EditToolbar()
                Divider()
                ClipTimeline()
                    .frame(minHeight: 150, idealHeight: 170, maxHeight: 220)
                statusBar
            }
            .frame(minWidth: 680)

            InspectorView()
                .frame(minWidth: 260, idealWidth: 280, maxWidth: 340)
        }
        .toolbar { toolbarContent }
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
            }
            if dropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(8)
            }
        }
        .frame(minHeight: 300)
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
            Toggle(isOn: $model.muted) { Label("Tắt tiếng", systemImage: model.muted ? "speaker.slash" : "speaker.wave.2") }
            Picker("Định dạng", selection: $model.exportPreset) {
                ForEach(ExportPreset.allCases) { Text($0.rawValue).tag($0) }
            }
            .frame(width: 220)
            Button { model.promptExport() } label: { Label("Xuất", systemImage: "square.and.arrow.up") }
                .disabled(model.clips.isEmpty || model.isExporting)
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
        view.controlsStyle = .floating
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}
