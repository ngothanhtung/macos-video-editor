# ClipCut

Trình edit video tối giản cho macOS, viết bằng Swift + SwiftUI + AVFoundation. Dùng cá nhân.

## Tính năng
- Nhập nhiều video (⌘O hoặc kéo thả vào cửa sổ)
- Timeline có thumbnail, zoom, ruler; bấm/kéo ruler để tua
- Trim bằng cách kéo mép clip, slider trong Inspector, hoặc phím I / O tại playhead
- Cắt đôi clip tại playhead (⌘B), xóa clip (⌫), kéo thả để đổi thứ tự
- Preview real-time bằng AVPlayer, tự dựng lại khi sửa
- Tự xoay đúng video quay dọc; clip khác tỉ lệ được scale-to-fit (viền đen)
- Tắt tiếng toàn bộ
- Xuất MP4: HEVC hoặc H.264 (cao nhất / 1080p / 720p), dùng mã hóa phần cứng
- Đối tượng vẽ đè (overlay): mũi tên, đường thẳng, hình chữ nhật, elip, tô sáng, chữ.
  Vẽ trực tiếp trên preview, chỉnh màu / nét / cỡ chữ, kéo trên timeline để đổi thời điểm hiện
- Lưu / mở dự án `.clipcut` (⌘S, ⇧⌘S, ⇧⌘O); file JSON chỉ lưu đường dẫn tới video gốc

## Yêu cầu
macOS 14+, Xcode 15+ (hoặc Command Line Tools có Swift 5.9+).

## Chạy
```bash
cd ClipCut
swift run                 # chạy thử bản debug
./build-app.sh            # đóng gói build/ClipCut.app
```
Hoặc mở bằng Xcode: `open Package.swift`, chọn scheme ClipCut, ⌘R.

## Cấu trúc
| File | Vai trò |
|---|---|
| `ClipCutApp.swift` | Entry point, menu & phím tắt |
| `Clip.swift` | Model clip + tiện ích thời gian |
| `CompositionBuilder.swift` | Dựng `AVMutableComposition` + `AVMutableVideoComposition` (xoay, scale-to-fit, tốc độ, ghép overlay khi xuất) |
| `EditorModel.swift` | State, nhập file, trim/split/move, undo, preview, export |
| `EditorModel+Overlays.swift` | Thêm / sửa / xóa overlay, kiểu vẽ, xếp làn trên timeline |
| `EditorModel+Project.swift` | Lưu / mở / tạo mới dự án `.clipcut` |
| `Overlay.swift` | Model overlay + hình học dùng chung cho preview và xuất |
| `OverlayCanvas.swift` | Lớp vẽ overlay trên preview: tạo, chọn, kéo, đổi kích thước |
| `OverlayExport.swift` | Vẽ overlay thành ảnh để ghép vào từng frame khi xuất |
| `AnnotationBar.swift` | Thanh công cụ vẽ: loại đối tượng, màu, nét, chữ |
| `EditToolbar.swift` | Thanh công cụ timeline (tách, xóa, tốc độ, âm lượng…) và thanh phát |
| `ToolIcons.swift` | Icon vẽ tay, tooltip, phím tắt một phím |
| `ContentView.swift` | Layout chính, preview, toolbar cửa sổ |
| `ClipTimeline.swift` | Timeline, trim handle, kéo thả, làn overlay |
| `InspectorView.swift` | Panel thông tin clip / đối tượng đang chọn |

## Giới hạn
- Chỉ đọc định dạng AVFoundation hỗ trợ (MP4, MOV, M4V…). MKV/WebM cần convert trước:
  `ffmpeg -i in.mkv -c copy out.mp4` (hoặc `-c:v libx264` nếu codec không tương thích).
- Khung xuất lấy theo clip đầu tiên.
- Chưa có transition. Overlay không có hiệu ứng xuất hiện / biến mất.
