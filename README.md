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
| `CompositionBuilder.swift` | Dựng `AVMutableComposition` + `AVMutableVideoComposition` (xoay, scale-to-fit) |
| `EditorModel.swift` | State, nhập file, trim/split/move, preview, export |
| `ContentView.swift` | Layout chính, preview, transport, toolbar |
| `ClipTimeline.swift` | Timeline, trim handle, kéo thả |
| `InspectorView.swift` | Panel thông tin clip đang chọn |

## Giới hạn
- Chỉ đọc định dạng AVFoundation hỗ trợ (MP4, MOV, M4V…). MKV/WebM cần convert trước:
  `ffmpeg -i in.mkv -c copy out.mp4` (hoặc `-c:v libx264` nếu codec không tương thích).
- Khung xuất lấy theo clip đầu tiên.
- Chưa có lưu project, transition, chữ overlay.
