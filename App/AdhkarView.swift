import SwiftUI

enum AdhkarKind: String, CaseIterable {
    case morning, evening, after
    var short: String { switch self { case .morning: return "الصباح"; case .evening: return "المساء"; case .after: return "بعد الصلاة" } }
    var title: String { switch self { case .morning: return "أذكار الصباح"; case .evening: return "أذكار المساء"; case .after: return "أذكار بعد الصلاة" } }
    var symbol: String { switch self { case .morning: return "sunrise.fill"; case .evening: return "sunset.fill"; case .after: return "hands.sparkles.fill" } }
}

struct Dhikr: Codable, Identifiable {
    var text: String?
    var title: String?
    var ref: String?
    var count: Int
    var note: String?
    var id: String { (text ?? title ?? "") + (ref ?? "") }
}

struct AdhkarBook: Codable {
    var source: String?
    var morning: [Dhikr]
    var evening: [Dhikr]
    var after: [Dhikr]
    func list(_ k: AdhkarKind) -> [Dhikr] { switch k { case .morning: return morning; case .evening: return evening; case .after: return after } }

    static func load(_ url: URL? = Res.url("adhkar.json")) -> AdhkarBook? {
        guard let u = url, let d = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(AdhkarBook.self, from: d)
    }
}

/// counters survive switching tabs inside the main window; they start fresh every day
final class AdhkarProgress: ObservableObject {
    static let shared = AdhkarProgress()
    @Published private var counts: [AdhkarKind: [String: Int]] = [:]
    private var day = ""
    private var today: String { Calendar.current.startOfDay(for: Date()).description }
    func get(_ k: AdhkarKind) -> [String: Int] { day == today ? counts[k] ?? [:] : [:] }
    func set(_ k: AdhkarKind, _ id: String, _ v: Int) {
        if day != today { day = today; counts = [:] }
        counts[k, default: [:]][id] = v
    }
}

struct AdhkarView: View {
    @ObservedObject var model: AppModel
    @Binding var kind: AdhkarKind
    var embedded = false
    var openQuran: (Int) -> Void = { _ in }
    @ObservedObject private var progress = AdhkarProgress.shared
    private var done: [String: Int] { progress.get(kind) }
    let book = AdhkarBook.load()

    var body: some View {
        let look = model.sky
        ZStack {
            if !embedded { SkyBackground(look: look).ignoresSafeArea() }
            VStack(spacing: 12) {
                GoldTabs(look: look, items: AdhkarKind.allCases.map { ($0, $0.short, $0.symbol) }, selection: $kind)

                Text(kind.title).font(AppFont.naskh(28, bold: true))
                let items = book?.list(kind) ?? []
                let finished = items.filter { (done[$0.id] ?? 0) >= $0.count }.count
                Text("\(Fmt.num(finished, latin: model.latin)) من \(Fmt.num(items.count, latin: model.latin))")
                    .font(.system(size: 12)).foregroundStyle(look.secondary)
                GoldBar(value: items.isEmpty ? 0 : Double(finished) / Double(items.count), look: look).frame(width: 220)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(items) { d in card(d, look) }
                        if let s = book?.source { Text("المصدر: \(s)").font(.system(size: 10)).foregroundStyle(look.secondary).padding(.top, 6) }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 18)
                }
            }
            .padding(.top, 14)
        }
        .foregroundStyle(look.text)
        .environment(\.layoutDirection, .rightToLeft)
        .focusEffectDisabled()
        .preferredColorScheme(.dark)
        .frame(minWidth: 460, minHeight: embedded ? 0 : 560)
    }

    private func card(_ d: Dhikr, _ look: SkyLook) -> some View {
        let count = done[d.id] ?? 0
        let complete = count >= d.count
        return Button {
            guard !complete else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { progress.set(kind, d.id, count + 1) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                if let t = d.text {
                    Text(t).font(AppFont.naskh(20)).lineSpacing(8).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let title = d.title {
                    Text(title).font(AppFont.naskh(20, bold: true)).foregroundStyle(look.gold)
                    if let r = d.ref {
                        let vs = Mushaf.shared.verses(ref: r)
                        if !vs.isEmpty {
                            (vs.reduce(Text("")) { t, v in
                                t + Text(v.text) + Text(" ﴿\(Fmt.num(v.aya, latin: model.latin))﴾ ").foregroundColor(look.gold)
                            })
                            .font(AppFont.naskh(22)).lineSpacing(10).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            if let f = vs.first {
                                Button { openQuran(Mushaf.shared.pageOf(sura: f.sura, aya: f.aya)) } label: {
                                    Label("سورة \(Mushaf.shared.suras[f.sura - 1].name)\(vs.count == 1 ? "، آية " + Fmt.num(f.aya, latin: model.latin) : "") · افتح بالمصحف", systemImage: "book")
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.plain).foregroundStyle(look.secondary)
                            }
                        }
                    }
                }
                HStack {
                    if let n = d.note { Text(n).font(.system(size: 11)).foregroundStyle(look.secondary) }
                    Spacer()
                    ZStack {
                        Circle().stroke(look.text.opacity(0.15), lineWidth: 3)
                        Circle().trim(from: 0, to: CGFloat(min(1, Double(count) / Double(d.count))))
                            .stroke(look.gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        if complete { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(look.gold) }
                        else { Text(Fmt.num(d.count - count, latin: model.latin)).font(.system(size: 12, weight: .bold)) }
                    }
                    .frame(width: 34, height: 34)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(look.isDark ? Color.white.opacity(complete ? 0.04 : 0.10) : Color.white.opacity(complete ? 0.2 : 0.45)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(complete ? look.gold.opacity(0.5) : Color.white.opacity(0.15), lineWidth: 0.8))
            .opacity(complete ? 0.65 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
