import SwiftUI

struct CountdownCard: View {
    let event: CountdownEvent
    var detail = CountdownDetail()
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onDuplicate: () -> Void
    var onFeature: () -> Void
    var onMove: (Int) -> Void
    var onResize: (Double?, Double?) -> Void
    @State private var hovering = false
    @State private var liveSize: CGSize?
    @State private var dragStart: CGSize?

    private var baseSize: CGSize {
        CGSize(width: event.cardWidth ?? CardSize.defaultWidth, height: event.cardHeight ?? CardSize.defaultHeight)
    }
    private var size: CGSize { liveSize ?? baseSize }
    /// Big number scales with card height so enlarged cards actually use the space.
    private var numberFont: CGFloat { (size.height * 0.2).clamped(to: 24...72) }

    var body: some View {
        LiveCountdown(target: event.targetDate, showsSeconds: false) { b, _ in
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: event.iconName)
                        .foregroundStyle(event.colorToken.color)
                        .frame(width: 32, height: 32)
                        .background(event.colorToken.color.opacity(0.18), in: Circle())
                    Text(event.title).font(.headline).lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text(CountdownFormatter.compact(b, detail: detail))
                    .font(.system(size: numberFont, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(b.isExpired ? .secondary : .primary)
                HStack {
                    Text(event.targetDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if b.isExpired { Text("Ended").font(.caption2.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.white.opacity(0.14), in: Capsule()) }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(event.title), \(CountdownFormatter.spoken(b)) \(b.isExpired ? "" : "remaining")")
        }
        .padding(18)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background { cardImage }
        .glassSurface(cornerRadius: 26, tint: event.colorToken.color.opacity(0.08), interactive: true)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 4) {
                Button(action: onEdit) { Image(systemName: "pencil") }.help("Edit").accessibilityLabel("Edit")
                Button(action: onDelete) { Image(systemName: "trash") }.help("Delete").accessibilityLabel("Delete")
            }
            .buttonStyle(.plain).padding(8)
            .opacity(hovering ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: hovering)
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .rotationEffect(.degrees(90))
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(10)
                .contentShape(Rectangle())
                .opacity(hovering || liveSize != nil ? 1 : 0.35)
                .help("Drag to resize")
                .accessibilityLabel("Resize card")
                .accessibilityHint("Use the Card Size actions to resize without dragging")
                .onHover { inside in if inside { NSCursor.crosshair.push() } else { NSCursor.pop() } }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .global)
                        .onChanged { g in
                            let start = dragStart ?? baseSize
                            dragStart = start
                            liveSize = CGSize(width: (start.width + g.translation.width).clamped(to: CardSize.widthRange),
                                              height: (start.height + g.translation.height).clamped(to: CardSize.heightRange))
                        }
                        .onEnded { _ in
                            if let s = liveSize { onResize(s.width, s.height) }
                            liveSize = nil; dragStart = nil
                        })
        }
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onEdit)
        .draggable(event.id.uuidString)
        .contextMenu {
            Button("Edit…", systemImage: "pencil", action: onEdit)
            Button("Make Featured", systemImage: "star", action: onFeature)
            Button("Duplicate", systemImage: "plus.square.on.square", action: onDuplicate)
            Divider()
            Button("Move Up", systemImage: "arrow.up") { onMove(-1) }
            Button("Move Down", systemImage: "arrow.down") { onMove(1) }
            Menu("Card Size", systemImage: "arrow.up.left.and.arrow.down.right") {
                Button("Small") { onResize(220, 130) }
                Button("Medium") { onResize(280, 150) }
                Button("Large") { onResize(420, 230) }
                Button("Extra Large") { onResize(540, 300) }
                Divider()
                Button("Reset Size") { onResize(nil, nil) }
            }
            Divider()
            Button("Delete…", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .accessibilityAction(named: "Edit", onEdit)
        .accessibilityAction(named: "Make Featured", onFeature)
        .accessibilityAction(named: "Delete", onDelete)
        .accessibilityAction(named: "Larger") { onResize((size.width + 60), (size.height + 40)) }
        .accessibilityAction(named: "Smaller") { onResize((size.width - 60), (size.height - 40)) }
        .accessibilityIdentifier("card-\(event.title)")
    }

    @ViewBuilder
    private var cardImage: some View {
        if let name = event.backgroundImageFileName {
            CachedImage(fileName: name, maxPixel: 640) { img in
                if let img {
                    ZStack {
                        Image(nsImage: img).resizable().scaledToFill()
                        LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                }
            }
        }
    }
}
