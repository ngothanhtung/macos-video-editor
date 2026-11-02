import SwiftUI

/// Timeline ngang: mỗi clip là một khối có độ rộng tỉ lệ với thời lượng.
/// - Bấm vào clip: chọn + tua tới vị trí bấm
/// - Kéo mép trái/phải: trim
/// - Kéo cả khối thả lên clip khác: đổi thứ tự
/// Phía trên các clip là làn overlay (chữ, mũi tên…): kéo để dời, kéo mép để đổi thời lượng.
struct ClipTimeline: View {
    @EnvironmentObject var model: EditorModel

    static let laneHeight: CGFloat = 20

    var body: some View {
        let layout = model.overlayLanes
        let overlayHeight = CGFloat(layout.count) * Self.laneHeight
        return ScrollView(.horizontal) {
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(model.clips) { clip in
                        ClipCard(clip: clip)
                    }
                    // vùng trống cuối: thả vào đây để đưa clip xuống cuối
                    Color.clear
                        .frame(width: 120)
                        .contentShape(Rectangle())
                        .dropDestination(for: String.self) { items, _ in
                            guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                            model.move(clipID: id, before: nil)
                            return true
                        }
                }
                .padding(.top, 22 + overlayHeight + (layout.count > 0 ? 4 : 0))

                ForEach(model.overlays) { o in
                    OverlayBar(overlay: o)
                        .offset(y: 22 + CGFloat(layout.lanes[o.id] ?? 0) * Self.laneHeight)
                }

                ruler
                markers
                playhead
            }
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var ruler: some View {
        let pps = model.pixelsPerSecond
        let step: Double = pps >= 80 ? 1 : pps >= 30 ? 2 : pps >= 12 ? 5 : 10
        let count = Int(model.totalDuration / step) + 1
        return ZStack(alignment: .topLeading) {
            ForEach(0..<max(count, 0), id: \.self) { i in
                let t = Double(i) * step
                VStack(alignment: .leading, spacing: 1) {
                    Rectangle().frame(width: 1, height: 6)
                    Text(t.timecode.dropLast(3)).font(.system(size: 9)).fixedSize()
                }
                .foregroundStyle(.secondary)
                .offset(x: t * pps)
            }
        }
        .frame(width: max(model.totalDuration * pps, 1), height: 20, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
            model.seek(to: v.location.x / pps)
        })
    }

    private var markers: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.markers, id: \.self) { t in
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.cyan)
                    .offset(x: t * model.pixelsPerSecond - 4, y: 9)
                    .onTapGesture { model.seek(to: t) }
                    .help("Marker \(t.timecode) — bấm để tua tới")
            }
        }
    }

    private var playhead: some View {
        Rectangle()
            .fill(Color.red)
            .frame(width: 2)
            .frame(maxHeight: .infinity)
            .offset(x: model.currentTime * model.pixelsPerSecond - 1)
            .allowsHitTesting(false)
            .opacity(model.clips.isEmpty ? 0 : 1)
    }
}

private struct ClipCard: View {
    @EnvironmentObject var model: EditorModel
    let clip: Clip

    @State private var dragBase: (start: Double, end: Double)?
    @State private var dropTargeted = false

    private var isSelected: Bool { model.selection == clip.id }
    private var width: CGFloat { max(8, clip.duration * model.pixelsPerSecond) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            thumbnailStrip
            Text(clip.name)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 3))
                .foregroundStyle(.white)
                .padding(4)
            badges
            Text(clip.duration.timecode)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white)
                .padding(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: width, height: 90)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(isSelected ? Color.yellow : Color.white.opacity(0.25),
                              lineWidth: isSelected ? 2 : 1)
        )
        .overlay(alignment: .leading) { if dropTargeted { Rectangle().fill(Color.accentColor).frame(width: 3) } }
        .overlay(alignment: .leading) { if !clip.isFreeze { trimHandle(leading: true) } }
        .overlay(alignment: .trailing) { if !clip.isFreeze { trimHandle(leading: false) } }
        .padding(.horizontal, 1)
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { loc in
            model.selection = clip.id
            model.seek(to: model.offset(of: clip.id) + Double(loc.x) / model.pixelsPerSecond)
        }
        .draggable(clip.id.uuidString) {
            Text(clip.name).padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(UUID.init(uuidString:)), id != clip.id else { return false }
            model.move(clipID: id, before: clip.id)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    /// Biểu tượng nhỏ cho thuộc tính đã chỉnh: tốc độ, đóng băng, âm lượng, xoay/lật.
    private var badges: some View {
        HStack(spacing: 3) {
            if clip.isFreeze { Image(systemName: "snowflake") }
            if clip.speed != 1 && !clip.isFreeze { Text("\(clip.speed.formatted())x") }
            if clip.volume == 0 && !clip.isFreeze { Image(systemName: "speaker.slash.fill") }
            if clip.quarterTurns != 0 { Image(systemName: "rotate.right") }
            if clip.flipH || clip.flipV { Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.white)
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private var thumbnailStrip: some View {
        GeometryReader { geo in
            if let img = model.thumbnails[clip.id] {
                let tileW = max(1, 90 * img.size.width / max(img.size.height, 1))
                let count = max(1, Int(ceil(geo.size.width / tileW)))
                HStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { _ in
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: tileW, height: geo.size.height).clipped()
                    }
                }
            } else {
                Color.gray.opacity(0.4)
            }
        }
    }

    private func trimHandle(leading: Bool) -> some View {
        Rectangle()
            .fill(isSelected ? Color.yellow : Color.white.opacity(0.35))
            .frame(width: 6)
            .contentShape(Rectangle().inset(by: -3))
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { v in
                        if dragBase == nil {
                            dragBase = (clip.start, clip.end)
                            model.selection = clip.id
                            model.checkpoint()
                        }
                        guard let base = dragBase else { return }
                        // kéo theo thời gian timeline -> đổi sang thời gian file gốc
                        let delta = Double(v.translation.width) / model.pixelsPerSecond * clip.speed
                        if leading {
                            model.setTrim(id: clip.id, start: base.start + delta)
                        } else {
                            model.setTrim(id: clip.id, end: base.end + delta)
                        }
                    }
                    .onEnded { _ in dragBase = nil }
            )
    }
}

/// Một overlay trên timeline: bấm để chọn, kéo thân để dời thời điểm, kéo mép để đổi thời lượng.
private struct OverlayBar: View {
    @EnvironmentObject var model: EditorModel
    let overlay: Overlay

    @State private var dragBase: (start: Double, end: Double)?

    private var isSelected: Bool { model.selectedOverlayID == overlay.id }
    private var pps: Double { model.pixelsPerSecond }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: overlay.kind.symbol)
            Text(overlay.label).lineLimit(1)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(overlay.color.isLight ? Color.black : Color.white)
        .padding(.horizontal, 6)
        .frame(width: max(10, overlay.duration * pps), height: ClipTimeline.laneHeight - 3, alignment: .leading)
        .background(overlay.color.opacity(0.85).color, in: RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(isSelected ? Color.yellow : Color.black.opacity(0.25), lineWidth: isSelected ? 2 : 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(alignment: .leading) { edgeHandle(leading: true) }
        .overlay(alignment: .trailing) { edgeHandle(leading: false) }
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectOverlay(overlay.id)
            if !overlay.isVisible(at: model.currentTime) { model.seek(to: overlay.start) }
        }
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { v in
                    let base = begin()
                    let delta = Double(v.translation.width) / pps
                    model.moveOverlayTime(overlay.id, start: base.start + delta, length: base.end - base.start)
                }
                .onEnded { _ in dragBase = nil }
        )
        .offset(x: overlay.start * pps)
        .help("\(overlay.label): \(overlay.start.timecode) – \(overlay.end.timecode)")
    }

    /// Lần đầu kéo: chọn overlay, ghi bước hoàn tác và nhớ vị trí gốc.
    private func begin() -> (start: Double, end: Double) {
        if let dragBase { return dragBase }
        model.selectOverlay(overlay.id)
        model.checkpoint()
        let base = (overlay.start, overlay.end)
        dragBase = base
        return base
    }

    private func edgeHandle(leading: Bool) -> some View {
        Color.clear
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { v in
                        let base = begin()
                        let delta = Double(v.translation.width) / pps
                        let minLen = 0.2
                        model.updateOverlay(overlay.id) {
                            if leading {
                                $0.start = min(max(0, base.start + delta), base.end - minLen)
                            } else {
                                $0.end = max(base.end + delta, base.start + minLen)
                            }
                        }
                    }
                    .onEnded { _ in dragBase = nil }
            )
    }
}
