import SwiftUI
import AppKit

/// Hộp thoại dán link YouTube, tải về bằng yt-dlp rồi thêm vào timeline.
struct DownloadSheet: View {
    @EnvironmentObject var model: EditorModel
    @ObservedObject var downloader: VideoDownloader
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var quality: VideoDownloader.Quality = .p1080
    @FocusState private var linkFocused: Bool

    private var linkValid: Bool { VideoDownloader.isYouTubeLink(link) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Tải video từ YouTube", systemImage: "arrow.down.circle").font(.headline)

            if VideoDownloader.toolPath == nil {
                missingTool
            } else {
                form
            }
        }
        .padding(20)
        .frame(width: 480)
        .interactiveDismissDisabled(downloader.isRunning)
        .onAppear {
            downloader.reset()
            // dán sẵn nếu clipboard đang có link YouTube
            if link.isEmpty, let s = NSPasteboard.general.string(forType: .string), VideoDownloader.isYouTubeLink(s) {
                link = s.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            linkFocused = true
        }
        .onChange(of: linkFocused) { _, f in model.isEditingText = f }
        .onDisappear { model.isEditingText = false }
        // thêm vào timeline do ContentView lo, kể cả khi hộp thoại đã đóng
        .onChange(of: downloader.phase) { _, phase in
            if case .finished = phase { dismiss() }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("https://www.youtube.com/watch?v=…", text: $link)
                .textFieldStyle(.roundedBorder)
                .focused($linkFocused)
                .disabled(downloader.isRunning)

            Picker("Chất lượng tối đa", selection: $quality) {
                ForEach(VideoDownloader.Quality.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(downloader.isRunning)

            statusView

            Text("Chỉ tải video bạn có quyền sử dụng. File lưu ở \(VideoDownloader.outputDirectory.path)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Mở thư mục") {
                    let dir = VideoDownloader.outputDirectory
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(dir)
                }
                Spacer()
                if downloader.isRunning {
                    Button("Hủy tải", role: .cancel) { downloader.cancel() }
                } else {
                    Button("Đóng") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Tải về", action: start)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!linkValid)
                }
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch downloader.phase {
        case .running:
            VStack(alignment: .leading, spacing: 4) {
                if let p = downloader.progress {
                    ProgressView(value: p)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                Text(downloader.detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        case .idle, .finished:
            if !link.isEmpty && !linkValid {
                Text("Link không phải YouTube (youtube.com hoặc youtu.be).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var missingTool: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cần cài công cụ yt-dlp để tải video. Mở Terminal và chạy:")
            HStack {
                Text(Self.installCommand)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                Button("Sao chép") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.installCommand, forType: .string)
                }
            }
            Text("Cài xong thì mở lại ClipCut.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Đóng") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private static let installCommand = "brew install yt-dlp ffmpeg"

    private func start() {
        guard linkValid, !downloader.isRunning else { return }
        downloader.start(link: link, quality: quality)
    }
}
