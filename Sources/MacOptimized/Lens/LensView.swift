import SwiftUI

struct LensView: View {
    @ObservedObject var model: LensModel
    @State private var confirming = false

    var body: some View {
        ZStack {
            switch model.phase {
            case .idle: start
            case .scanning: scanning
            case .done: if let current = model.current { map(current) }
            }
            if confirming { confirmSheet }
        }
        .toast($model.toast)
        .animation(.easeOut(duration: 0.2), value: model.phase)
        .animation(.easeOut(duration: 0.2), value: confirming)
        #if DEBUG
        .onAppear {
            if let path = DebugSnapshot.env["MACOPT_LENS"], model.phase == .idle {
                model.scan(URL(fileURLWithPath: path), name: URL(fileURLWithPath: path).lastPathComponent)
            }
        }
        #endif
    }

    // MARK: Start

    private var start: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 0) {
                Text("map a location").typeface(.mono, Theme.muted).padding(.bottom, 16)
                ForEach(Array(model.locations.enumerated()), id: \.element.id) { i, loc in
                    LocationRow(location: loc, isFirst: i == 0) { model.open(loc) }
                }
                Hairline()
            }
            .frame(width: 560)
            Text("give Full Disk Access to see everything  ·  settings › privacy")
                .typeface(.monoSmall, Theme.muted)
                .padding(.top, 32)
            Spacer()
        }
        .background { Button("") { model.chooseFolder() }.keyboardShortcut("o").hidden() }
    }

    // MARK: Scanning

    private var scanning: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                BubbleShape(diameter: 300)
                VStack(spacing: 6) {
                    if let p = model.progress {
                        Text("\(Int(p * 100))%").font(Fonts.inter(64, .light)).tracking(-2.5).foregroundStyle(Theme.text).monospacedDigit()
                        Text("\(Bytes.format(model.scannedBytes)) of \(Bytes.format(model.expectedBytes))").typeface(.monoSmall, Theme.muted)
                    } else {
                        Text(Bytes.format(model.scannedBytes)).font(Fonts.inter(56, .light)).tracking(-2).foregroundStyle(Theme.text).monospacedDigit()
                        Text("scanned").typeface(.monoSmall, Theme.muted)
                    }
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.line)
                    Rectangle().fill(Theme.accent).frame(width: geo.size.width * (model.progress ?? 0))
                }
            }
            .frame(width: 300, height: 2)
            Text(model.currentPath).typeface(.mono, Theme.muted).lineLimit(1).truncationMode(.middle).frame(maxWidth: 720)
            Spacer()
            HStack {
                Text("\(model.scanTarget)  ·  skipping /Volumes, /private/var/vm").typeface(.monoSmall, Theme.muted)
                Spacer()
                TextButton(title: "stop", hint: "esc", color: Theme.muted) { model.cancelScan() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    // MARK: Map

    private func map(_ current: FileNode) -> some View {
        VStack(spacing: 0) {
            HStack {
                breadcrumb(current)
                Spacer()
                Text(Bytes.format(current.size)).typeface(.mono)
                TextButton(title: "new scan", color: Theme.muted) { model.reset() }.padding(.leading, 24)
            }
            BubbleMap(node: current, model: model)
            VStack(spacing: 16) {
                Hairline()
                HStack {
                    HStack(spacing: 12) {
                        Dot(isOn: !model.selection.isEmpty)
                        Text(model.selection.isEmpty ? "click a bubble to select it" : "\(model.selection.count) selected  ·  \(Bytes.format(model.selectedSize))")
                            .typeface(.mono, model.selection.isEmpty ? Theme.muted : Theme.text)
                    }
                    Spacer()
                    ActionLink(title: "move to trash", enabled: !model.selection.isEmpty) { confirming = true }
                }
            }
        }
        .padding(EdgeInsets(top: 16, leading: 40, bottom: 28, trailing: 40))
        .background {
            Button("") { model.goUp() }.keyboardShortcut(.cancelAction).hidden()
        }
    }

    private func breadcrumb(_ current: FileNode) -> some View {
        let chain = current.pathFromRoot
        let prefix = chain[0].url.path == "/" ? [] : chain[0].url.deletingLastPathComponent().pathComponents.filter { $0 != "/" }
        return HStack(spacing: 10) {
            Text("/").typeface(.mono, Theme.muted)
            ForEach(prefix, id: \.self) { part in
                Text(part.lowercased()).typeface(.mono, Theme.muted)
                Text("/").typeface(.mono, Theme.muted)
            }
            ForEach(Array(chain.enumerated()), id: \.offset) { i, node in
                if !(i == 0 && node.url.path == "/") {
                    Button { model.current = node } label: {
                        Text(node.name.lowercased()).typeface(.mono, node === current ? Theme.text : Theme.muted)
                    }
                    .buttonStyle(.plain)
                    if node !== current { Text("/").typeface(.mono, Theme.muted) }
                }
            }
        }
        .lineLimit(1)
    }

    // MARK: Confirm

    private var confirmSheet: some View {
        let names = model.selection.map(\.name).sorted()
        let label = names.count == 1 ? names[0] : "\(names.count) items"
        return ModalSheet {
            ModalHeader(title: "Move to Trash?")
            VStack(spacing: 0) {
                Hairline()
                FactRow(key: Bytes.format(model.selectedSize), value: "\(label) · \(model.selectedFiles.formatted()) files, you can still restore them")
                FactRow(key: "space", value: "is only reclaimed after you empty the Trash in free")
            }
            ModalActions(primary: "move to trash", onCancel: { confirming = false }) {
                confirming = false
                model.trashSelection()
            }
        }
    }
}

private struct LocationRow: View {
    let location: LensLocation
    let isFirst: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let active = hovering || isFirst
        Button(action: action) {
            VStack(spacing: 0) {
                Hairline()
                HStack {
                    Text(location.name).font(Fonts.inter(32, .light)).tracking(-1).foregroundStyle(active ? Theme.text : Theme.muted)
                    Spacer()
                    Text(location.detail).typeface(.mono, Theme.muted)
                    Image(systemName: "arrow.right").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.accent)
                        .opacity(hovering ? 1 : (isFirst ? 1 : 0))
                        .padding(.leading, 14)
                }
                .padding(.vertical, 20)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// One level at a time: the current folder's children as packed bubbles,
/// small ones merged into "others".
struct BubbleMap: View {
    let node: FileNode
    @ObservedObject var model: LensModel

    private struct Bubble: Identifiable {
        let id: Int
        let node: FileNode?
        let name: String
        let size: Int64
        let circle: CirclePacking.Circle
    }

    private var layout: (bubbles: [Bubble], bounds: CGRect) {
        let kids = node.children.filter { $0.size > 0 }
        let top = Array(kids.prefix(LensModel.maxBubbles))
        let rest = kids.dropFirst(LensModel.maxBubbles).reduce(Int64(0)) { $0 + $1.size }
        var items: [(FileNode?, String, Int64)] = top.map { ($0, $0.name, $0.size) }
        if rest > 0 { items.append((nil, "others", rest)) }
        items.sort { $0.2 > $1.2 }
        guard !items.isEmpty else { return ([], .zero) }
        // Area proportional to size.
        let circles = CirclePacking.pack(radii: items.map { CGFloat(sqrt(Double($0.2))) })
        let minX = circles.map { $0.x - $0.r }.min()!, maxX = circles.map { $0.x + $0.r }.max()!
        let minY = circles.map { $0.y - $0.r }.min()!, maxY = circles.map { $0.y + $0.r }.max()!
        let bubbles = zip(items, circles).enumerated().map { i, pair in
            Bubble(id: i, node: pair.0.0, name: pair.0.1, size: pair.0.2, circle: pair.1)
        }
        return (bubbles, CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
    }

    var body: some View {
        GeometryReader { geo in
            let (bubbles, bounds) = layout
            let scale = bounds.width > 0 ? min(geo.size.width / bounds.width, geo.size.height / bounds.height) * 0.94 : 1
            ZStack {
                Color.clear.contentShape(Rectangle()).onTapGesture(count: 2) { model.goUp() }
                ForEach(bubbles) { b in
                    let d = max(4, b.circle.r * 2 * scale - 6)
                    let selected = b.node.map { model.selection.contains($0) } ?? false
                    ZStack {
                        BubbleShape(diameter: d, selected: selected)
                        if d > 68 {
                            VStack(spacing: 4) {
                                Text(b.name).font(Fonts.inter(max(12, min(28, d / 10)), .regular))
                                    .foregroundStyle(b.node == nil ? Theme.muted : Theme.text)
                                    .lineLimit(1).truncationMode(.middle)
                                Text(Bytes.format(b.size)).typeface(.monoSmall, selected ? Theme.accent : Theme.muted)
                            }
                            .frame(width: d * 0.8)
                        }
                    }
                    .position(x: geo.size.width / 2 + (b.circle.x - bounds.midX) * scale,
                              y: geo.size.height / 2 + (b.circle.y - bounds.midY) * scale)
                    .help("\(b.name) — \(Bytes.format(b.size))")
                    .onTapGesture(count: 2) { if let n = b.node { model.enter(n) } }
                    .onTapGesture { if let n = b.node { model.toggle(n) } }
                    .contextMenu {
                        if let n = b.node {
                            Button("Open") { model.enter(n) }.disabled(!n.isDirectory || n.children.isEmpty)
                            Button(model.selection.contains(n) ? "Deselect" : "Select") { model.toggle(n) }
                            Button("Reveal in Finder") { model.reveal(n) }
                            Button("Quick Look") { model.quickLook(n) }
                        }
                    }
                }
            }
            .animation(.spring(duration: 0.35), value: node.id)
        }
        .padding(.vertical, 8)
    }
}
