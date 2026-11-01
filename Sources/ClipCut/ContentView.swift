import SwiftUI
import AVKit

struct ContentView: View {
    @EnvironmentObject var model: EditorModel
    @State private var dropTargeted = false

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                preview
                Divider()
                transportBar
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
                VideoPlayer(player: model.player)
            }
            if dropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(8)
            }
        }
        .frame(minHeight: 300)
    }

    private var transportBar: some View {
        HStack(spacing: 12) {
            Button { model.seek(to: 0) } label: { Image(systemName: "backward.end.fill") }
            Button { model.togglePlay() } label: { Image(systemName: "playpause.fill") }
                .keyboardShortcut(.space, modifiers: [])
            Button { model.splitAtPlayhead() } label: { Label("Cắt", systemImage: "scissors") }
                .help("Cắt đôi clip tại playhead (⌘B)")
            Button { model.markIn() } label: { Text("I") }
                .keyboardShortcut("i", modifiers: [])
                .help("Đặt điểm đầu clip đang chọn tại playhead")
            Button { model.markOut() } label: { Text("O") }
                .keyboardShortcut("o", modifiers: [])
                .help("Đặt điểm cuối clip đang chọn tại playhead")

            Spacer()

            Text("\(model.currentTime.timecode) / \(model.totalDuration.timecode)")
                .font(.system(.body, design: .monospaced))

            Spacer()

            Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
            Slider(value: $model.pixelsPerSecond, in: 5...200).frame(width: 120)
            Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .disabled(model.clips.isEmpty)
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
