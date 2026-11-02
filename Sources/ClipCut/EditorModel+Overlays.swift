import Foundation
import CoreGraphics

extension EditorModel {
    var selectedOverlay: Overlay? { overlays.first { $0.id == selectedOverlayID } }

    /// Overlay hiện ở thời điểm playhead, theo thứ tự vẽ (sau cùng nằm trên cùng).
    var visibleOverlays: [Overlay] { overlays.filter { $0.isVisible(at: currentTime) } }

    /// Tạo đối tượng mới tại điểm chuẩn hóa `p`, hiện 3 giây kể từ playhead.
    @discardableResult
    func addOverlay(_ kind: OverlayKind, at p: CGPoint) -> Overlay.ID {
        checkpoint()
        let start = min(currentTime, max(0, totalDuration - 0.5))
        var o = Overlay(kind: kind, start: start, end: min(start + 3, max(totalDuration, start + 0.5)),
                        p1: p, p2: p, color: overlayStyle.color, lineWidth: overlayStyle.lineWidth)
        o.fontSize = overlayStyle.fontSize
        o.textBackground = overlayStyle.textBackground
        if kind == .text { o.text = "Nhập chữ" }
        overlays.append(o)
        selectedOverlayID = o.id
        return o.id
    }

    /// Sửa một overlay. `record: true` lưu bước hoàn tác trước khi sửa.
    func updateOverlay(_ id: Overlay.ID, record: Bool = false, _ change: (inout Overlay) -> Void) {
        guard let i = overlays.firstIndex(where: { $0.id == id }) else { return }
        var o = overlays[i]
        change(&o)
        guard o != overlays[i] else { return }
        if record { checkpoint() }
        overlays[i] = o
    }

    func removeOverlay(_ id: Overlay.ID) {
        guard overlays.contains(where: { $0.id == id }) else { return }
        checkpoint()
        overlays.removeAll { $0.id == id }
        if selectedOverlayID == id { selectedOverlayID = nil }
        status = "Đã xóa đối tượng"
    }

    /// Đổi kiểu vẽ; nếu đang chọn một đối tượng thì áp luôn vào nó.
    func applyStyle(_ change: (inout OverlayStyle) -> Void) {
        change(&overlayStyle)
        guard let id = selectedOverlayID else { return }
        let style = overlayStyle
        updateOverlay(id, record: true) {
            $0.color = style.color
            $0.lineWidth = style.lineWidth
            $0.fontSize = style.fontSize
            $0.textBackground = style.textBackground
        }
    }

    /// Chọn đối tượng và đồng bộ thanh kiểu vẽ theo nó.
    func selectOverlay(_ id: Overlay.ID?) {
        selectedOverlayID = id
        guard let o = selectedOverlay else { return }
        overlayStyle.color = o.color
        overlayStyle.lineWidth = o.lineWidth
        overlayStyle.fontSize = o.fontSize
        overlayStyle.textBackground = o.textBackground
    }

    /// Dời khoảng hiện của overlay trên timeline (giữ nguyên độ dài, không âm).
    func moveOverlayTime(_ id: Overlay.ID, start: Double, length: Double) {
        updateOverlay(id) {
            $0.start = max(0, start)
            $0.end = $0.start + length
        }
    }

    /// Xếp overlay vào các làn không chồng nhau để vẽ trên timeline.
    var overlayLanes: (lanes: [Overlay.ID: Int], count: Int) {
        var laneEnds: [Double] = []
        var result: [Overlay.ID: Int] = [:]
        for o in overlays.sorted(by: { $0.start < $1.start }) {
            if let lane = laneEnds.firstIndex(where: { $0 <= o.start + 0.001 }) {
                laneEnds[lane] = o.end
                result[o.id] = lane
            } else {
                laneEnds.append(o.end)
                result[o.id] = laneEnds.count - 1
            }
        }
        return (result, laneEnds.count)
    }
}
