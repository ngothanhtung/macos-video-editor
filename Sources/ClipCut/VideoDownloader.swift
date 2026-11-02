import Foundation

/// Tải video từ link YouTube công khai bằng `yt-dlp` (cài riêng: `brew install yt-dlp`).
/// Ưu tiên luồng H.264 + AAC ghép thành MP4 để AVFoundation mở được; ghép cần `ffmpeg`.
@MainActor
final class VideoDownloader: ObservableObject {
    enum Quality: String, CaseIterable, Identifiable {
        case p1080 = "1080p", p720 = "720p", p480 = "480p"
        var id: String { rawValue }
        var height: Int { Int(rawValue.dropLast())! }
    }

    enum Phase: Equatable {
        case idle
        case running
        case finished(URL)
        case failed(String)
    }

    @Published var phase: Phase = .idle
    /// Tiến độ phần đang tải (video và audio tải lần lượt nên có thể chạy lại từ 0).
    @Published var progress: Double?
    @Published var detail = ""

    private var process: Process?
    private var cancelled = false
    private var finalPath: String?
    private var startedAt = Date()
    private var errorLines: [String] = []

    static let toolPath = findExecutable("yt-dlp")
    static let ffmpegPath = findExecutable("ffmpeg")

    static var outputDirectory: URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return movies.appendingPathComponent("ClipCut Downloads", isDirectory: true)
    }

    var isRunning: Bool { phase == .running }

    /// Link có dạng youtube.com/… hoặc youtu.be/…
    static func isYouTubeLink(_ text: String) -> Bool {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased()
        else { return false }
        return host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
    }

    func start(link: String, quality: Quality) {
        guard !isRunning, let tool = Self.toolPath else { return }
        let dir = Self.outputDirectory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            phase = .failed("Không tạo được thư mục \(dir.path)")
            return
        }

        let h = quality.height
        // không có ffmpeg thì không ghép được, chỉ lấy file MP4 có sẵn cả hình lẫn tiếng
        let format = Self.ffmpegPath == nil
            ? "b[ext=mp4][height<=\(h)]/b[ext=mp4]"
            : "bv*[vcodec^=avc1][height<=\(h)]+ba[ext=m4a]/b[ext=mp4][height<=\(h)]/bv*[height<=\(h)]+ba/b"
        var args = [
            "--no-playlist", "--newline", "--no-simulate", "--progress",
            // client mặc định hay bị YouTube bắt "xác nhận không phải bot"; tv / mweb thường vẫn lấy được
            "--extractor-args", "youtube:player_client=default,tv,mweb",
            "--progress-template", "download:[clipcut] %(progress.downloaded_bytes)s %(progress.total_bytes)s %(progress.total_bytes_estimate)s",
            "--print", "after_move:filepath",
            "-f", format,
            "--merge-output-format", "mp4",
            "-o", dir.path + "/%(title).120B [%(id)s].%(ext)s",
        ]
        if let ffmpeg = Self.ffmpegPath {
            args += ["--ffmpeg-location", ffmpeg.deletingLastPathComponent().path]
        }
        args.append(link.trimmingCharacters(in: .whitespacesAndNewlines))

        let p = Process()
        p.executableURL = tool
        p.arguments = args
        // gộp stderr vào stdout để đọc theo đúng thứ tự và biết chắc khi nào hết output
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        let reader = LineReader()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty {
                // EOF: yt-dlp đã đóng output, chờ thoát rồi báo kết quả
                h.readabilityHandler = nil
                let lines = reader.flush()
                p.waitUntilExit()
                let status = p.terminationStatus
                DispatchQueue.main.async {
                    lines.forEach { self?.handle($0) }
                    self?.finish(status: status)
                }
            } else {
                let lines = reader.feed(data)
                DispatchQueue.main.async { lines.forEach { self?.handle($0) } }
            }
        }

        finalPath = nil
        errorLines = []
        startedAt = Date()
        cancelled = false
        progress = nil
        detail = "Đang lấy thông tin video…"
        phase = .running
        do {
            try p.run()
            process = p
        } catch {
            phase = .failed("Không chạy được yt-dlp: \(error.localizedDescription)")
        }
    }

    func cancel() {
        guard isRunning else { return }
        cancelled = true
        process?.terminate()
    }

    func reset() {
        guard !isRunning else { return }
        phase = .idle
        progress = nil
        detail = ""
    }

    // MARK: - Xử lý output

    private func handle(_ line: String) {
        if line.hasPrefix("[clipcut]") {
            handleProgress(line)
        } else if line.hasPrefix("ERROR:") {
            errorLines.append(line)
        } else if line.hasPrefix("/") {
            finalPath = line
        }
    }

    private func handleProgress(_ line: String) {
        let parts = line.split(separator: " ").dropFirst().map { Double($0) }
        guard let done = parts.first ?? nil else { return }
        let total = parts.dropFirst().compactMap { $0 }.first { $0 > 0 }
        if let total {
            progress = min(1, done / total)
            detail = "Đang tải \(Self.bytes(done)) / \(Self.bytes(total))"
        } else {
            progress = nil
            detail = "Đang tải \(Self.bytes(done))"
        }
    }

    private func finish(status: Int32) {
        let path = finalPath, errors = errorLines
        process = nil
        progress = nil
        if cancelled {
            removePartialFiles()
            phase = .failed("Đã hủy tải.")
        } else if status == 0, let path, FileManager.default.fileExists(atPath: path) {
            phase = .finished(URL(fileURLWithPath: path))
        } else {
            let message = errors.last.map { String($0.dropFirst("ERROR:".count)).trimmingCharacters(in: .whitespaces) }
            phase = .failed(message ?? "yt-dlp dừng với mã lỗi \(status).")
        }
    }

    /// Hủy giữa chừng yt-dlp để lại file .part / .ytdl; xóa những file tạo ra từ lúc bắt đầu tải.
    private func removePartialFiles() {
        let fm = FileManager.default
        let dir = Self.outputDirectory
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        for name in names where name.hasSuffix(".part") || name.hasSuffix(".ytdl") {
            let url = dir.appendingPathComponent(name)
            if let modified = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
               modified >= startedAt {
                try? fm.removeItem(at: url)
            }
        }
    }

    private static func bytes(_ n: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }

    /// App mở từ Finder không có PATH của shell nên tìm thêm ở các thư mục Homebrew / pip hay dùng.
    private static func findExecutable(_ name: String) -> URL? {
        let envPath = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dirs = envPath + ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "/usr/bin"]
        return dirs.lazy
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

/// Gom dữ liệu từ pipe thành từng dòng (pipe trả về từng khúc bất kỳ).
private final class LineReader: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()

    func feed(_ data: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)
        var lines: [String] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            lines.append(String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex...nl)
        }
        return Self.clean(lines)
    }

    func flush() -> [String] {
        lock.lock(); defer { lock.unlock() }
        let rest = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll()
        return Self.clean([rest])
    }

    private static func clean(_ lines: [String]) -> [String] {
        lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
