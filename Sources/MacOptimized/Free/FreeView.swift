import SwiftUI

@MainActor
final class FreeModel: ObservableObject {
    enum Job { case ram, purgeable, trash }

    @Published var memory: MemoryStats?
    @Published var volume: PurgeableSpace.Volume?
    @Published var bins: [TrashBins.Bin] = []
    @Published var job: Job?
    @Published var ramProgress: Double = 0
    @Published var secondsLeft = 0
    @Published var toast: Toast?

    private var timer: Timer?
    private var cleaner: RAMCleaner?

    var trashSize: Int64 { bins.reduce(0) { $0 + $1.size } }

    func start() {
        refresh()
        scanTrash()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        memory = MemoryStats.current()
        volume = PurgeableSpace.volume()
        if job == .ram { secondsLeft = max(0, secondsLeft - 2) }
    }

    func scanTrash() {
        Task.detached {
            let bins = TrashBins.scan()
            await MainActor.run { self.bins = bins }
        }
    }

    func freeRAM() {
        let cleaner = RAMCleaner()
        self.cleaner = cleaner
        job = .ram
        ramProgress = 0
        secondsLeft = Int(RAMCleaner.timeout)
        Task {
            let freed = await cleaner.run { p in Task { @MainActor in self.ramProgress = p } }
            job = nil
            refresh()
            toast = Toast(text: freed > 0 ? "freed \(Bytes.format(freed, binary: true)) of memory" : "memory was already in good shape")
        }
    }

    func cancelRAM() { cleaner?.cancel() }

    func freePurgeable() {
        job = .purgeable
        Task {
            let freed = await PurgeableSpace.freeUp()
            job = nil
            refresh()
            toast = Toast(text: freed > 0 ? "freed \(Bytes.format(freed)) of purgeable space" : "macOS kept its purgeable space for now")
        }
    }

    func emptyTrash() {
        job = .trash
        let bins = self.bins
        Task.detached {
            let freed = TrashBins.empty(bins)
            await MainActor.run {
                self.job = nil
                self.toast = Toast(text: "emptied \(Bytes.format(freed)) from the Trash")
                self.refresh()
                self.scanTrash()
            }
        }
    }
}

struct FreeView: View {
    @ObservedObject var model: FreeModel
    @State private var confirmingTrash = false

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                memoryColumn.dimmed(model.job != nil && model.job != .ram)
                VerticalHairline()
                purgeableColumn.dimmed(model.job != nil && model.job != .purgeable)
                VerticalHairline()
                trashColumn.dimmed(model.job != nil && model.job != .trash)
            }
            .padding(.vertical, 72)

            if confirmingTrash { trashSheet }
        }
        .toast($model.toast)
        .animation(.easeOut(duration: 0.2), value: confirmingTrash)
        .onAppear { model.start() }
    }

    // MARK: Columns

    private var memoryColumn: some View {
        let m = model.memory
        let (value, unit) = Bytes.split(Int64(m?.available ?? 0), binary: true)
        let freeing = model.job == .ram
        return FreeColumn(
            label: "memory", value: value, unit: unit,
            sub: freeing ? "freeing · \(model.secondsLeft) s left" : "available of \(Bytes.memory(m?.total ?? 0))",
            subIsActive: freeing,
            meter: freeing ? model.ramProgress : (m?.usedFraction ?? 0),
            stats: [
                "apps  \(Bytes.memory(m?.appMemory ?? 0))",
                "compressed  \(Bytes.memory(m?.compressed ?? 0))",
                "pressure  \(m?.pressure.rawValue.lowercased() ?? "—")",
            ]
        ) {
            if freeing {
                TextButton(title: "stop", hint: "esc") { model.cancelRAM() }.keyboardShortcut(.cancelAction)
            } else {
                ActionLink(title: "free up ram", enabled: model.job == nil) { model.freeRAM() }
            }
        }
    }

    private var purgeableColumn: some View {
        let v = model.volume
        let (value, unit) = Bytes.split(v?.purgeable ?? 0)
        let working = model.job == .purgeable
        let used = v.map { Double($0.total - $0.available) / Double(max($0.total, 1)) } ?? 0
        return FreeColumn(
            label: "purgeable", value: value, unit: unit,
            sub: working ? "asking macOS to purge…" : "reclaimable on \(Volumes.rootName)",
            subIsActive: working,
            meter: used,
            stats: [
                "free  \(Bytes.format(v?.available ?? 0))",
                "total  \(Bytes.format(v?.total ?? 0))",
                "via CacheDelete",
            ]
        ) {
            ActionLink(title: "free up space", enabled: model.job == nil && PurgeableSpace.isSupported && (v?.purgeable ?? 0) > 0) {
                model.freePurgeable()
            }
        }
    }

    private var trashColumn: some View {
        let (value, unit) = Bytes.split(model.trashSize)
        // Visual scale only: a full bar means 10 GB or more in the Trash.
        let meter = min(1, Double(model.trashSize) / 10e9)
        let stats = model.bins.prefix(3).map { "\($0.label)  \(Bytes.format($0.size))" }
        return FreeColumn(
            label: "trash", value: value, unit: unit,
            sub: model.bins.isEmpty ? "empty, or needs Full Disk Access" : "across \(model.bins.count) \(model.bins.count == 1 ? "bin" : "bins")",
            subIsActive: model.job == .trash,
            meter: meter,
            stats: stats.isEmpty ? ["~/.Trash  0 B"] : stats
        ) {
            ActionLink(title: "empty trash", enabled: model.job == nil && !model.bins.isEmpty) { confirmingTrash = true }
        }
    }

    private var trashSheet: some View {
        ModalSheet {
            ModalHeader(title: "Empty \(model.bins.count) trash \(model.bins.count == 1 ? "bin" : "bins")?")
            VStack(spacing: 0) {
                Hairline()
                FactRow(key: Bytes.format(model.trashSize), value: "deleted permanently, this can't be undone")
                ForEach(model.bins.prefix(3)) { bin in
                    FactRow(key: bin.label, value: bin.label.hasPrefix("iCloud")
                        ? "\(Bytes.format(bin.size)) · removed on all your devices" : Bytes.format(bin.size))
                }
            }
            ModalActions(primary: "empty trash", onCancel: { confirmingTrash = false }) {
                confirmingTrash = false
                model.emptyTrash()
            }
        }
    }
}

/// One of the three columns: label, big number, line, meter, stats and an action at the bottom.
private struct FreeColumn<Action: View>: View {
    let label: String
    let value: String
    let unit: String
    let sub: String
    var subIsActive = false
    let meter: Double
    let stats: [String]
    @ViewBuilder var action: Action

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(label).typeface(.mono, Theme.muted)
            BigNumber(value: value, unit: unit, size: 96, unitSize: 14, unitIsMono: true)
            Text(sub).typeface(.body, subIsActive ? Theme.accent : Theme.muted)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.line)
                    Rectangle().fill(Theme.accent).frame(width: geo.size.width * min(1, max(0, meter)))
                }
            }
            .frame(height: 2)
            .animation(.easeInOut(duration: 0.4), value: meter)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(stats, id: \.self) { Text($0).typeface(.monoSmall, Theme.muted) }
            }
            .padding(.top, 8)
            Spacer()
            action
        }
        .padding(.horizontal, 56)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    func dimmed(_ on: Bool) -> some View { opacity(on ? 0.35 : 1).allowsHitTesting(!on) }
}
