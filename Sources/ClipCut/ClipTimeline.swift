import SwiftUI

/// Timeline ngang: mỗi clip là một khối có độ rộng tỉ lệ với thời lượng.
/// - Bấm vào clip: chọn + tua tới vị trí bấm
/// - Kéo mép trái/phải: trim
/// - Kéo cả khối thả lên clip khác: đổi thứ tự
struct ClipTimeline: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        ScrollView(.horizontal) {
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
                .padding(.top, 22)

                ruler
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
        .overlay(alignment: .leading) { trimHandle(leading: true) }
        .overlay(alignment: .trailing) { trimHandle(leading: false) }
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
                        if dragBase == nil { dragBase = (clip.start, clip.end); model.selection = clip.id }
                        guard let base = dragBase else { return }
                        let delta = Double(v.translation.width) / model.pixelsPerSecond
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
