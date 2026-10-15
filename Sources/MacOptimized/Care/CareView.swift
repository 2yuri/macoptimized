import SwiftUI

struct CareView: View {
    @ObservedObject var model: CareModel
    @State private var detailGroup: String?
    @State private var confirming = false

    var body: some View {
        ZStack {
            switch model.phase {
            case .idle: idle
            case .scanning: progressScreen(running: false)
            case .results: results(done: false)
            case .running: progressScreen(running: true)
            case .done: results(done: true)
            }

            if let id = detailGroup, let group = model.junk.first(where: { $0.id == id }) {
                CategorySheet(model: model, group: group) { detailGroup = nil }
            }
            if confirming {
                confirmSheet
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.phase)
        .animation(.easeOut(duration: 0.2), value: confirming)
        .animation(.easeOut(duration: 0.2), value: detailGroup)
        #if DEBUG
        .onAppear { if DebugSnapshot.env["MACOPT_AUTOSCAN"] != nil { model.scan() } }
        #endif
    }

    // MARK: Idle

    private var idle: some View {
        VStack(spacing: 0) {
            Spacer()
            Button { model.scan() } label: {
                ZStack {
                    Ring(start: -8, sweep: 38, headAtEnd: false)
                    VStack(spacing: 10) {
                        Text("scan").font(Fonts.inter(38, .light)).tracking(-1).foregroundStyle(Theme.text)
                        Text("↵ return").typeface(.monoSmall, Theme.muted)
                    }
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            Text("cleanup  ·  maintenance  ·  duplicates").typeface(.mono, Theme.muted).padding(.top, 48)
            Spacer()
            footer(left: lastScanText, right: "nothing is removed without review")
        }
    }

    private var lastScanText: String {
        guard let last = model.lastScan else { return "no scan yet" }
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.dateStyle = .short
        f.timeStyle = .short
        return "last scan  \(f.string(from: last.date).lowercased())  —  \(Bytes.format(last.size))"
    }

    // MARK: Scanning / running

    private func progressScreen(running: Bool) -> some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Ring(start: 0, sweep: model.progress * 360)
                VStack(spacing: 10) {
                    Text(running ? Bytes.format(model.removedSoFar) : "\(Int(model.progress * 100))%")
                        .font(Fonts.inter(56, .light)).tracking(-2).foregroundStyle(Theme.text).monospacedDigit()
                    Text(running ? "removed so far" : "scanning \(model.activeModule.title)").typeface(.monoSmall, Theme.muted)
                }
            }
            moduleSteps.padding(.top, 48)
            Spacer()
            HStack {
                Text((running ? "removing  " : "") + model.currentPath)
                    .typeface(.monoSmall, Theme.muted).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 40)
                if running {
                    Text("don't quit apps while this runs").typeface(.monoSmall, Theme.muted)
                } else {
                    GhostButton(title: "stop", hint: "esc") { model.cancelScan() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    private var moduleSteps: some View {
        HStack(spacing: 24) {
            ForEach(CareModel.Module.allCases, id: \.self) { m in
                let active = m == model.activeModule
                let passed = m.rawValue < model.activeModule.rawValue
                HStack(spacing: 8) {
                    Dot(isOn: active || passed)
                    Text(m.title).typeface(.mono, active ? Theme.text : Theme.muted)
                }
            }
        }
    }

    // MARK: Results / done

    private func results(done: Bool) -> some View {
        HStack(alignment: .top, spacing: 96) {
            VStack(alignment: .leading, spacing: 20) {
                Text(done ? "freed" : "ready to clean").typeface(.mono, Theme.muted)
                let (value, unit) = Bytes.split(done ? model.freedTotal : model.junkSelectedSize + model.duplicatesSelectedSize)
                BigNumber(value: value, unit: unit)
                Text(done ? model.summary : resultsContext).typeface(.mono, Theme.muted)
                Spacer()
                if done {
                    PrimaryButton(title: "scan again") { model.scan() }
                } else {
                    PrimaryButton(title: "run") { confirming = true }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    if done { reportList } else { reviewList }
                }
            }
            .frame(width: 500)
        }
        .padding(EdgeInsets(top: 56, leading: 80, bottom: 48, trailing: 80))
    }

    private var resultsContext: String {
        "of \(Bytes.format(model.foundTotal)) found · \(model.selectedTasks.count) tasks · \(model.duplicates.count) duplicates"
    }

    @ViewBuilder private var reviewList: some View {
        if !model.junk.isEmpty {
            VStack(spacing: 0) {
                GroupHeader(title: "cleanup")
                ForEach(model.junk) { g in
                    SelectRow(label: g.rule.title, value: Bytes.format(g.isOn ? g.selectedSize : g.size), isOn: g.isOn,
                              onToggle: { model.toggleGroup(g.id) }, onOpen: { detailGroup = g.id })
                }
            }
        }
        if !model.tasks.isEmpty {
            VStack(spacing: 0) {
                GroupHeader(title: "maintenance")
                ForEach(model.tasks) { t in
                    SelectRow(label: t.title, value: t.value, isOn: t.selected, onToggle: { model.toggleTask(t.id) })
                }
            }
        }
        VStack(spacing: 0) {
            GroupHeader(title: "duplicates")
            if model.duplicates.isEmpty {
                SelectRow(label: "no duplicates in ~/Downloads", value: "", isOn: false, showsDot: false)
            }
            ForEach(model.duplicates) { d in
                let on = Set(d.extras.map(\.url)).isSubset(of: model.selectedDuplicates)
                SelectRow(label: "\(d.copies[0].name) ×\(d.copies.count)", value: Bytes.format(d.wasted), isOn: on,
                          onToggle: { model.toggleDuplicates(d) })
            }
        }
    }

    @ViewBuilder private var reportList: some View {
        VStack(spacing: 0) {
            GroupHeader(title: "report")
            ForEach(model.report) { SelectRow(label: $0.label, value: $0.value, isOn: true) }
        }
        if !model.skipped.isEmpty {
            VStack(spacing: 0) {
                GroupHeader(title: "skipped")
                ForEach(model.skipped) { SelectRow(label: $0.label, value: $0.value, isOn: false, note: $0.note) }
            }
        }
    }

    // MARK: Confirm

    private var confirmSheet: some View {
        ModalSheet {
            ModalHeader(title: "Run care now?")
            VStack(spacing: 0) {
                Hairline()
                FactRow(key: Bytes.format(model.junkSelectedSize), value: "deleted permanently, not moved to Trash")
                ForEach(model.selectedTasks) { t in
                    switch t.kind {
                    case .flushDNS: FactRow(key: "flush dns", value: "macOS will ask for your password")
                    case .purgeable: FactRow(key: t.value, value: "purgeable space handed back to macOS")
                    }
                }
                let dups = model.selectedDuplicateItems.count
                FactRow(key: "\(dups) files", value: dups == 0 ? "duplicates stay where they are" : "duplicates moved to Trash")
            }
            ModalActions(primary: "run", onCancel: { confirming = false }) {
                confirming = false
                model.run()
            }
        }
    }

    private func footer(left: String, right: String) -> some View {
        HStack {
            Text(left).typeface(.monoSmall, Theme.muted)
            Spacer()
            Text(right).typeface(.monoSmall, Theme.muted)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }
}

/// Every item of one cleanup category, each with its own toggle.
private struct CategorySheet: View {
    @ObservedObject var model: CareModel
    let group: JunkGroup
    let onDone: () -> Void

    private static let visible = 8

    var body: some View {
        ModalSheet(width: 600) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("cleanup / \(group.rule.title)").typeface(.monoSmall, Theme.muted)
                    Text(Bytes.format(group.selectedSize)).font(Fonts.inter(56, .light)).tracking(-2.5).foregroundStyle(Theme.text)
                }
                Spacer()
                Text("\(group.selected.count) of \(group.items.count) selected").typeface(.monoSmall, Theme.muted)
            }
            VStack(spacing: 0) {
                Hairline()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(group.items) { item in
                            SelectRow(label: item.name, value: Bytes.format(item.size), isOn: group.selected.contains(item.url),
                                      note: item.note, onToggle: { model.toggleItem(item.url, in: group.id) })
                                .contextMenu {
                                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                                }
                        }
                    }
                }
                .frame(maxHeight: 46 * CGFloat(Self.visible))
            }
            HStack {
                Text("\(group.rule.detail)  ·  right-click to reveal in Finder").typeface(.monoSmall, Theme.muted)
                Spacer()
                PrimaryButton(title: "done", action: onDone).keyboardShortcut(.defaultAction)
            }
        }
        .onExitCommand(perform: onDone)
    }
}
