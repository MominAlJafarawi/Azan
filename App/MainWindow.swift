import AppKit
import SwiftUI

// MARK: - navigation inside the one main window

enum MainTab: String, CaseIterable {
    case home, adhkar, quran, settings
    var title: String { switch self { case .home: return "الرئيسية"; case .adhkar: return "الأذكار"; case .quran: return "المصحف"; case .settings: return "الإعدادات" } }
    var symbol: String { switch self { case .home: return "moon.stars.fill"; case .adhkar: return "hands.sparkles.fill"; case .quran: return "book.fill"; case .settings: return "gearshape.fill" } }
}

struct NavState: Equatable {
    var tab: MainTab = .home
    var adhkar: AdhkarKind = .morning
    var quranPage = 1
    var settingsTab = 0
}

/// Where the window is, plus the places visited before (for the back button).
final class Nav: ObservableObject {
    @Published var state = NavState()
    @Published private(set) var history: [NavState] = []

    /// move somewhere and remember where we were
    func go(_ change: (inout NavState) -> Void) {
        var s = state
        change(&s)
        guard s != state else { return }
        history.append(state)
        if history.count > 50 { history.removeFirst() }
        state = s
    }
    func show(_ tab: MainTab) { go { $0.tab = tab } }
    var canGoBack: Bool { !history.isEmpty }
    func back() { if let s = history.popLast() { state = s } }
}

// MARK: - window content

struct MainWindowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var nav: Nav
    var quit: () -> Void

    var body: some View {
        let look = model.sky
        VStack(spacing: 0) {
            header(look)
            tabs(look)
            Rectangle().fill(look.gold.opacity(0.2)).frame(height: 1)
            content(look)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background {
            ZStack {
                // calm, star-free background while reading the Quran
                if nav.state.tab == .quran {
                    LinearGradient(colors: [look.top, look.bottom], startPoint: .topTrailing, endPoint: .bottomLeading)
                } else {
                    SkyBackground(look: look)
                }
                Veil(look: look)
            }
            .ignoresSafeArea()
        }
        .foregroundStyle(look.text)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Fmt.locale(latin: model.latin))
        .preferredColorScheme(.dark)
        .focusEffectDisabled()
        .frame(minWidth: 600, minHeight: 640)
    }

    private func header(_ look: SkyLook) -> some View {
        HStack(spacing: 12) {
            Button { nav.back() } label: {
                HStack(spacing: 6) { Image(systemName: "arrow.right"); Text("رجوع") }.font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(look.text.opacity(0.08)))
                    .overlay(Capsule().strokeBorder(look.gold.opacity(0.45), lineWidth: 0.8))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!nav.canGoBack).opacity(nav.canGoBack ? 1 : 0.4)
            .keyboardShortcut("[", modifiers: .command)
            Text("أذان").font(AppFont.naskh(26, bold: true)).foregroundStyle(look.gold)
            Spacer()
            if let (p, t) = model.nextPrayer {
                Text("\(p == .maghrib && model.ramadan ? "الإفطار" : p.arabic) بعد \(Fmt.countdown(t.timeIntervalSince(model.now), latin: model.latin))")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(look.secondary)
            }
        }
        .padding(.horizontal, UI.pad)
        .padding(.top, 30)        // room for the window buttons
        .padding(.bottom, 8)
    }

    private func tabs(_ look: SkyLook) -> some View {
        let sel = Binding<MainTab>(get: { nav.state.tab }, set: { t in nav.show(t) })
        return HStack {
            GoldTabs(look: look, items: MainTab.allCases.map { ($0, $0.title, $0.symbol) }, selection: sel)
            Spacer()
        }
        .padding(.horizontal, UI.pad).padding(.bottom, 14)
    }

    @ViewBuilder private func content(_ look: SkyLook) -> some View {
        switch nav.state.tab {
        case .home:
            ScrollView(showsIndicators: false) {
                MainView(model: model, openSettings: { nav.show(.settings) },
                         openAdhkar: { k in nav.go { $0.tab = .adhkar; $0.adhkar = k } },
                         quit: quit,
                         openQuran: { p in nav.go { $0.tab = .quran; $0.quranPage = p } },
                         inWindow: true)
                    .padding(.vertical, UI.pad)
                    .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.top)
        case .adhkar:
            AdhkarView(model: model, kind: Binding(get: { nav.state.adhkar }, set: { nav.state.adhkar = $0 }), embedded: true,
                       openQuran: { p in nav.go { $0.tab = .quran; $0.quranPage = p } })
        case .quran:
            MushafView(model: model, nav: nav)
                .padding(.horizontal, UI.pad).padding(.vertical, 16)
        case .settings:
            SettingsView(model: model, tab: Binding(get: { nav.state.settingsTab }, set: { nav.state.settingsTab = $0 }), embedded: true)
        }
    }
}

// MARK: - the window itself (only ever one)

final class MainWindowController {
    let model: AppModel
    let nav = Nav()
    var quit: () -> Void = { NSApp.terminate(nil) }
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
        nav.state.quranPage = min(Quran.pages, max(1, model.settings.quranPage))
    }

    /// bring the window up at a place (pushes the current place on the back history if it was open)
    func open(_ change: (inout NavState) -> Void) {
        if let w = window, w.isVisible {
            nav.go(change)
        } else {
            var s = nav.state
            change(&s)
            nav.state = s
        }
        let w = window ?? make()
        window = w
        if !w.isVisible { w.center() }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func make() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 800),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "أذان"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 600, height: 640)
        let host = NSHostingController(rootView: MainWindowView(model: model, nav: nav, quit: { [weak self] in self?.quit() }))
        host.sizingOptions = []
        w.contentViewController = host
        if !w.setFrameUsingName("AzanMain") { w.setContentSize(NSSize(width: 680, height: 800)) }
        w.setFrameAutosaveName("AzanMain")
        return w
    }
}
