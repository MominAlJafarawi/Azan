import AppKit
import SwiftUI

// MARK: - data (Tanzil Uthmani text + page metadata, offline)

struct Verse: Identifiable {
    let sura: Int
    let aya: Int
    let text: String
    var id: Int { sura * 1000 + aya }
}

struct SuraInfo {
    let number: Int
    let name: String
    let ayas: Int
    let meccan: Bool
}

final class Mushaf {
    static let shared = Mushaf()

    private(set) var verses: [[String]] = []          // [sura-1][aya-1]
    private(set) var suras: [SuraInfo] = []
    private(set) var pageStarts: [(Int, Int)] = []     // first (sura, aya) of every page
    private(set) var juzStarts: [(Int, Int)] = []

    var loaded: Bool { verses.count == 114 && pageStarts.count == Quran.pages }
    var verseCount: Int { verses.reduce(0) { $0 + $1.count } }

    init(text: URL? = Res.url("Quran/quran-uthmani.txt"), meta: URL? = Res.url("Quran/quran-meta.json")) {
        if let t = text, let m = meta { load(text: t, meta: m) }
    }

    private struct Meta: Decodable {
        let suras: [[Meta.Field]]
        let pages: [[Int]]
        let juz: [[Int]]
        enum Field: Decodable {
            case int(Int), str(String)
            init(from d: Decoder) throws {
                let c = try d.singleValueContainer()
                if let i = try? c.decode(Int.self) { self = .int(i) } else { self = .str(try c.decode(String.self)) }
            }
            var int: Int { if case .int(let i) = self { return i }; return 0 }
            var str: String { if case .str(let s) = self { return s }; return "" }
        }
    }

    func load(text: URL, meta: URL) {
        guard let raw = try? String(contentsOf: text, encoding: .utf8),
              let md = try? Data(contentsOf: meta), let m = try? JSONDecoder().decode(Meta.self, from: md) else { return }
        var v = Array(repeating: [String](), count: 114)
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let f = line.first, f.isNumber else { continue }
            let parts = line.split(separator: "|", maxSplits: 2)
            guard parts.count == 3, let s = Int(parts[0]), (1...114).contains(s) else { continue }
            v[s - 1].append(String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        verses = v
        suras = m.suras.enumerated().map { i, r in SuraInfo(number: i + 1, name: r[0].str, ayas: r[1].int, meccan: r[2].str == "Meccan") }
        pageStarts = m.pages.map { ($0[0], $0[1]) }
        juzStarts = m.juz.map { ($0[0], $0[1]) }
    }

    private static func less(_ a: (Int, Int), _ b: (Int, Int)) -> Bool { a.0 < b.0 || (a.0 == b.0 && a.1 < b.1) }

    /// verses printed on a page of the Madani mushaf (1...604)
    func page(_ p: Int) -> [Verse] {
        guard loaded, (1...Quran.pages).contains(p) else { return [] }
        let start = pageStarts[p - 1]
        let end: (Int, Int) = p < Quran.pages ? pageStarts[p] : (115, 1)
        var out: [Verse] = []
        var s = start.0, a = start.1
        while Self.less((s, a), end) && s <= 114 {
            if a <= verses[s - 1].count { out.append(Verse(sura: s, aya: a, text: verses[s - 1][a - 1])); a += 1 }
            else { s += 1; a = 1 }
        }
        return out
    }

    func pageOf(sura: Int, aya: Int = 1) -> Int {
        var p = 1
        for (i, st) in pageStarts.enumerated() where !Self.less((sura, aya), st) { p = i + 1 }
        return p
    }

    func juz(ofPage p: Int) -> Int {
        guard loaded, (1...Quran.pages).contains(p) else { return Quran.juz(ofPage: p) }
        let st = pageStarts[p - 1]
        var j = 1
        for (i, js) in juzStarts.enumerated() where !Self.less(st, js) { j = i + 1 }
        return j
    }

    /// verses for an adhkar reference: "2/255" (one verse) or "112" (whole surah)
    func verses(ref: String) -> [Verse] {
        let parts = ref.split(separator: "/").compactMap { Int($0) }
        guard loaded, let s = parts.first, (1...114).contains(s) else { return [] }
        let list = verses[s - 1].enumerated().map { Verse(sura: s, aya: $0.offset + 1, text: $0.element) }
        if parts.count > 1 { return list.filter { $0.aya == parts[1] } }
        return list
    }

    var basmala: String { verses.first?.first ?? "بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ" }
}

// MARK: - justified, right-to-left page text

/// NSTextView based text so the page can be justified like a printed mushaf.
struct MushafText: NSViewRepresentable {
    var text: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSTextView.scrollableTextView()
        sv.drawsBackground = false
        sv.hasVerticalScroller = true
        sv.autohidesScrollers = true
        sv.scrollerStyle = .overlay
        if let tv = sv.documentView as? NSTextView {
            tv.isEditable = false
            tv.isSelectable = true
            tv.drawsBackground = false
            tv.textContainerInset = NSSize(width: 6, height: 8)
            tv.baseWritingDirection = .rightToLeft
        }
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let tv = sv.documentView as? NSTextView else { return }
        if tv.attributedString() != text {
            tv.textStorage?.setAttributedString(text)
            tv.scrollToBeginningOfDocument(nil)
        }
    }
}

enum MushafStyle {
    static func page(_ verses: [Verse], latin: Bool, size: CGFloat, look: SkyLook) -> NSAttributedString {
        let m = Mushaf.shared
        let out = NSMutableAttributedString()
        let text = NSColor(look.text), gold = NSColor(look.gold)
        let body = NSFont(name: "Amiri", size: size) ?? .systemFont(ofSize: size)
        let head = NSFont(name: "Amiri-Bold", size: size * 0.85) ?? .boldSystemFont(ofSize: size * 0.85)

        func para(_ align: NSTextAlignment, spaceBefore: CGFloat = 0) -> NSMutableParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.alignment = align
            p.baseWritingDirection = .rightToLeft
            p.lineHeightMultiple = 1.35
            p.paragraphSpacingBefore = spaceBefore
            p.paragraphSpacing = 4
            return p
        }
        var running = NSMutableAttributedString()
        func flush() {
            guard running.length > 0 else { return }
            running.addAttribute(.paragraphStyle, value: para(.justified), range: NSRange(location: 0, length: running.length))
            out.append(running); out.append(NSAttributedString(string: "\n"))
            running = NSMutableAttributedString()
        }
        for v in verses {
            if v.aya == 1 {
                flush()
                let name = v.sura <= m.suras.count ? m.suras[v.sura - 1].name : ""
                out.append(NSAttributedString(string: "سورة \(name)\n", attributes: [
                    .font: head, .foregroundColor: gold, .paragraphStyle: para(.center, spaceBefore: out.length > 0 ? 10 : 0)]))
                if v.sura != 1 && v.sura != 9 {
                    out.append(NSAttributedString(string: m.basmala + "\n", attributes: [
                        .font: body, .foregroundColor: text, .paragraphStyle: para(.center)]))
                }
            }
            running.append(NSAttributedString(string: v.text, attributes: [.font: body, .foregroundColor: text]))
            running.append(NSAttributedString(string: " ﴿\(Fmt.num(v.aya, latin: latin))﴾ ", attributes: [.font: body, .foregroundColor: gold]))
        }
        flush()
        return out
    }
}

// MARK: - Mushaf tab

struct MushafView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var nav: Nav
    @State private var query = ""
    @State private var showIndex = false
    @FocusState private var searching: Bool

    private var m: Mushaf { Mushaf.shared }
    private var page: Int { nav.state.quranPage }

    var body: some View {
        let look = model.sky
        let latin = model.latin
        VStack(spacing: 12) {
            toolbar(look)
            if showIndex || !query.isEmpty {
                index(look)
            } else if !m.loaded {
                GlassCard(look: look) { Text("ملف المصحف ناقص. البرنامج رح يحاول يصلّحه بالتشغيل الجاي.").font(.system(size: 15)) }
                Spacer()
            } else {
                MushafText(text: MushafStyle.page(m.page(page), latin: latin, size: 24, look: look))
                    .id("\(page)-\(latin)")
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background {
                        // blurred, even navy behind the text: easy on the eyes
                        RoundedRectangle(cornerRadius: UI.radius, style: .continuous).fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: UI.radius, style: .continuous).fill(Color(red: 9/255, green: 14/255, blue: 38/255).opacity(0.85))
                    }
                    .overlay(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).strokeBorder(look.gold.opacity(0.25), lineWidth: 0.8))
                pageBar(look)
                if model.settings.khatmaOn { wird(look) }
            }
        }
        .onAppear { model.settings.quranPage = page }
        .onChange(of: nav.state.quranPage) { _, p in if model.settings.quranPage != p { model.settings.quranPage = p } }
        .background {
            // arrow keys flip pages (left = next, like turning a printed mushaf)
            Group {
                Button("") { go(page + 1) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { go(page - 1) }.keyboardShortcut(.rightArrow, modifiers: [])
            }
            .opacity(0).allowsHitTesting(false)
        }
    }

    private func go(_ p: Int) { nav.state.quranPage = min(Quran.pages, max(1, p)) }
    private func jump(_ p: Int) { nav.go { $0.quranPage = min(Quran.pages, max(1, p)) }; query = ""; showIndex = false; searching = false }

    private func toolbar(_ look: SkyLook) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(look.secondary)
                TextField("ابحث عن سورة أو اكتب رقم صفحة…", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 14)).focused($searching)
                    .onSubmit {
                        let digits = query.map { c -> Character in
                            if let v = c.wholeNumberValue { return Character(String(v)) }; return c }
                        if let n = Int(String(digits)) { jump(n) }
                        else if let first = matches.first { jump(m.pageOf(sura: first.number)) }
                    }
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(look.secondary) }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(look.text.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(look.gold.opacity(0.25), lineWidth: 0.8))
            pill(showIndex ? "الصفحة" : "الفهرس", showIndex ? "book" : "list.bullet", look, on: showIndex) { showIndex.toggle(); query = "" }
            if let b = model.settings.quranMark {
                pill("علامتي", "bookmark.fill", look) { jump(b) }
                    .help("صفحة \(Fmt.num(b, latin: model.latin))")
            }
        }
    }

    private var matches: [SuraInfo] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return m.suras }
        let norm = { (s: String) in s.replacingOccurrences(of: "أ", with: "ا").replacingOccurrences(of: "إ", with: "ا").replacingOccurrences(of: "آ", with: "ا") }
        return m.suras.filter { norm($0.name).contains(norm(q)) || String($0.number) == q }
    }

    private func index(_ look: SkyLook) -> some View {
        let latin = model.latin
        return ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 6) {
                ForEach(matches, id: \.number) { s in
                    let p = m.pageOf(sura: s.number)
                    Button { jump(p) } label: {
                        HStack(spacing: 12) {
                            Text(Fmt.num(s.number, latin: latin)).font(.system(size: 13, weight: .bold, design: .rounded))
                                .frame(width: 34, height: 34).background(Circle().fill(look.gold.opacity(0.18))).foregroundStyle(look.gold)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("سورة \(s.name)").font(AppFont.naskh(19, bold: true))
                                Text("\(s.meccan ? "مكية" : "مدنية") · \(Fmt.num(s.ayas, latin: latin)) آية").font(.system(size: 12)).foregroundStyle(look.secondary)
                            }
                            Spacer()
                            Text("صفحة \(Fmt.num(p, latin: latin))").font(.system(size: 13)).foregroundStyle(look.secondary)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .glass(look, radius: 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if matches.isEmpty { Text("ما في سورة بهالاسم").foregroundStyle(look.secondary).padding(.top, 20) }
                Text("نص المصحف: مشروع تنزيل tanzil.net").font(.system(size: 11)).foregroundStyle(look.secondary).padding(.top, 8)
            }
            .padding(.bottom, 8)
        }
    }

    private func pageBar(_ look: SkyLook) -> some View {
        let latin = model.latin
        let isMark = model.settings.quranMark == page
        return HStack(spacing: 8) {
            Text("صفحة \(Fmt.num(page, latin: latin)) · الجزء \(Fmt.num(m.juz(ofPage: page), latin: latin)) · سورة \(Quran.surah(onPage: page))")
                .font(.system(size: 14)).foregroundStyle(look.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            Button { model.settings.quranMark = isMark ? nil : page } label: {
                Image(systemName: isMark ? "bookmark.fill" : "bookmark").font(.system(size: 15)).foregroundStyle(look.gold)
            }
            .buttonStyle(.plain).help(isMark ? "شيل العلامة" : "حط علامة على هالصفحة")
            pill("السابقة", "arrow.right", look) { go(page - 1) }.disabled(page <= 1).opacity(page <= 1 ? 0.4 : 1)
            pill("التالية", "arrow.left", look) { go(page + 1) }.disabled(page >= Quran.pages).opacity(page >= Quran.pages ? 0.4 : 1)
        }
    }

    private func wird(_ look: SkyLook) -> some View {
        let k = model.settings.khatma
        let latin = model.latin
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                if k.finished {
                    Text("ختمت القرآن، تقبّل الله منك").font(.system(size: 15, weight: .semibold))
                } else if let r = k.nextPortion(model.now) {
                    Button { jump(r.lowerBound) } label: {
                        Text("وردك اليوم: صفحة \(Fmt.num(r.lowerBound, latin: latin))–\(Fmt.num(r.upperBound, latin: latin))").font(.system(size: 15, weight: .semibold))
                    }.buttonStyle(.plain)
                }
                GoldBar(value: Double(k.lastRead) / Double(Quran.pages), look: look).frame(width: 220)
            }
            Spacer()
            if k.finished {
                pill("ختمة جديدة", "arrow.clockwise", look, filled: true) { model.newKhatma(days: model.settings.khatmaDays) }
            } else if let r = k.nextPortion(model.now) {
                pill("قرأت", "checkmark", look, filled: true) { model.markRead(to: r.upperBound) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .glass(look)
    }

    private func pill(_ t: String, _ icon: String, _ look: SkyLook, filled: Bool = false, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // icon on the side the arrow points to (right for back/previous, left for next)
            HStack(spacing: 6) {
                if icon == "arrow.left" { Text(t); Image(systemName: icon) } else { Image(systemName: icon); Text(t) }
            }
            .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(Capsule().fill(filled || on ? look.gold : look.text.opacity(0.10)))
                .foregroundStyle(filled || on ? Color(red: 0.06, green: 0.08, blue: 0.2) : look.text)
                .fixedSize()
        }
        .buttonStyle(.plain)
    }
}
