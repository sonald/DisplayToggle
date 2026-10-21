// DisplayToggle: status-bar popover that shows every display in its real
// arrangement, with a switch inside each tile to disconnect / reconnect it.
// Uses the private CoreGraphics call CGSConfigureDisplayEnabled (same
// mechanism as Lunar / BetterDisplay "disconnect"). Private API: may break
// with an OS update.
import Cocoa
import SwiftUI

// MARK: - Private API

typealias ConfigureDisplayEnabled = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
let configureDisplayEnabled: ConfigureDisplayEnabled? = {
    guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSConfigureDisplayEnabled") else { return nil }
    return unsafeBitCast(p, to: ConfigureDisplayEnabled.self)
}()

func activeDisplays() -> [CGDirectDisplayID] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16), n: UInt32 = 0
    CGGetActiveDisplayList(16, &ids, &n)
    return Array(ids.prefix(Int(n)))
}

func setDisplay(_ id: CGDirectDisplayID, enabled: Bool) -> String? {
    guard let fn = configureDisplayEnabled else { return "CGSConfigureDisplayEnabled not available on this macOS" }
    if !enabled && activeDisplays().count < 2 { return "Refusing: that is the only active display" }
    var cfg: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&cfg) == .success else { return "CGBeginDisplayConfiguration failed" }
    let err = fn(cfg, id, enabled)
    guard err == .success else { CGCancelDisplayConfiguration(cfg); return "CGSConfigureDisplayEnabled: \(err.rawValue)" }
    // .forSession: a re-login or reboot always brings displays back.
    let done = CGCompleteDisplayConfiguration(cfg, .forSession)
    return done == .success ? nil : "CGCompleteDisplayConfiguration: \(done.rawValue)"
}

// MARK: - Model

struct Display: Identifiable, Codable, Equatable {
    let id: CGDirectDisplayID
    var name: String
    var bounds: CGRect
    var builtin: Bool
    var isMain: Bool
    var isOn: Bool
    var offByApp: Bool   // we disabled it, so keep showing it as a tile
}

@MainActor final class Model: ObservableObject {
    @Published var displays: [Display] = []
    @Published var error: String?
    private let key = "knownDisplays"
    // Last known state of every display we have seen, persisted so a disabled
    // display still has a tile (and a switch to come back) after relaunch.
    private var known: [CGDirectDisplayID: Display] = [:]

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([Display].self, from: data) {
            known = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        }
        refresh()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let active = activeDisplays()
        for id in active {
            known[id] = Display(id: id, name: name(of: id), bounds: CGDisplayBounds(id),
                                builtin: CGDisplayIsBuiltin(id) != 0, isMain: CGDisplayIsMain(id) != 0,
                                isOn: true, offByApp: false)
        }
        for (id, d) in known where !active.contains(id) {
            if d.builtin || d.offByApp { known[id]!.isOn = false; known[id]!.isMain = false }
            else { known[id] = nil }  // unplugged external: forget it
        }
        if !known.values.contains(where: \.builtin) {
            // Never seen the panel on (already off at first launch): seed a tile so it can be turned on.
            // ponytail: placed under the main display at a typical 14" size; real bounds replace it once seen.
            let main = known.values.first(where: \.isMain)?.bounds ?? CGRect(x: 0, y: 0, width: 1800, height: 1169)
            let id = CGDirectDisplayID(max(UserDefaults.standard.integer(forKey: "builtinDisplayID"), 1))
            known[id] = Display(id: id, name: "Built-in Display",
                                bounds: CGRect(x: main.minX, y: main.maxY, width: 1800, height: 1169),
                                builtin: true, isMain: false, isOn: false, offByApp: false)
        }
        displays = known.values.sorted { $0.id < $1.id }
        if let data = try? JSONEncoder().encode(displays) { UserDefaults.standard.set(data, forKey: key) }
    }

    func toggle(_ d: Display) {
        error = nil
        if let err = setDisplay(d.id, enabled: !d.isOn) { error = err; return }
        if d.isOn { known[d.id]?.offByApp = true }
        // ponytail: screen-change notification usually fires; the delayed refresh covers when it doesn't.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.refresh() }
    }

    var builtinOn: Bool { displays.first(where: \.builtin)?.isOn ?? false }

    private func name(of id: CGDirectDisplayID) -> String {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id }?
            .localizedName ?? (CGDisplayIsBuiltin(id) != 0 ? "Built-in Display" : "Display \(id)")
    }
}

// MARK: - Views

struct DisplayTile: View {
    let d: Display
    let onToggle: () -> Void
    @State private var hover = false

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(d.isOn
                      ? LinearGradient(colors: [Color.accentColor.opacity(0.85), Color.accentColor.opacity(0.55)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                      : LinearGradient(colors: [Color.primary.opacity(0.12), Color.primary.opacity(0.06)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(d.isOn ? Color.white.opacity(0.35) : Color.primary.opacity(0.25),
                              style: StrokeStyle(lineWidth: 1, dash: d.isOn ? [] : [4, 3]))
            if d.isMain {  // menu-bar strip marks the main display
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.3)).frame(height: 7).padding(1)
                    .mask(Rectangle().frame(height: 6).frame(maxHeight: .infinity, alignment: .top))
            }
            VStack(spacing: 4) {
                Spacer(minLength: 0)
                Image(systemName: d.builtin ? "laptopcomputer" : "display")
                    .font(.system(size: 18, weight: .light))
                Text(d.name).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(verbatim: "\(Int(d.bounds.width)) × \(Int(d.bounds.height))")
                    .font(.system(size: 9, design: .monospaced)).opacity(0.75)
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(get: { d.isOn }, set: { _ in onToggle() }))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                    .tint(.green)
                    .padding(.bottom, 6)
            }
            .foregroundStyle(d.isOn ? Color.white : Color.primary.opacity(0.7))
            .padding(.horizontal, 6)
        }
        .scaleEffect(hover ? 1.03 : 1)
        .shadow(color: .black.opacity(hover ? 0.25 : 0.1), radius: hover ? 8 : 3, y: 2)
        .onHover { hover = $0 }
        .animation(.spring(duration: 0.25), value: hover)
        .help(d.isOn ? "Turn off \(d.name)" : "Turn on \(d.name)")
    }
}

struct LayoutView: View {
    @ObservedObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Displays").font(.headline)
                Spacer()
                Text("\(model.displays.filter(\.isOn).count) of \(model.displays.count) on")
                    .font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                let union = model.displays.map(\.bounds).reduce(CGRect.null) { $0.union($1) }
                let scale = min(geo.size.width / max(union.width, 1), geo.size.height / max(union.height, 1))
                let ox = (geo.size.width - union.width * scale) / 2
                let oy = (geo.size.height - union.height * scale) / 2
                ForEach(model.displays) { d in
                    DisplayTile(d: d) { model.toggle(d) }
                        .frame(width: max(d.bounds.width * scale - 6, 40), height: max(d.bounds.height * scale - 6, 40))
                        .offset(x: (d.bounds.minX - union.minX) * scale + ox + 3,
                                y: (d.bounds.minY - union.minY) * scale + oy + 3)
                }
            }
            .frame(height: 230)
            .animation(.spring(duration: 0.4), value: model.displays)
            if let e = model.error {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red).lineLimit(2)
            }
            HStack {
                Text("Off displays reconnect on sleep/wake or re-login.")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 440)
    }
}

// MARK: - App

@MainActor final class App: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let popover = NSPopover()
    var model: Model!

    func applicationDidFinishLaunching(_: Notification) {
        model = Model()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: LayoutView(model: model))
        item.button?.action = #selector(togglePopover)
        item.button?.target = self
        refreshIcon()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.refreshIcon() }
    }

    func refreshIcon() {
        DispatchQueue.main.async {
            self.item.button?.image = NSImage(systemSymbolName: self.model.builtinOn ? "laptopcomputer" : "laptopcomputer.slash",
                                              accessibilityDescription: "Built-in display")
        }
    }

    @objc func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        model.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = App()
    app.delegate = delegate
    app.run()
}
