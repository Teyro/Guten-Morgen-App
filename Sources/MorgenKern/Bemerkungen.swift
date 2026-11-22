import Foundation

/// Eine Bemerkung aus der „Wichtig!“-Zeile des Vertretungsplans, die das eigene Kürzel betrifft –
/// z. B. „FSJ Ella (Paul) 2c krank Begleitung Kim 1.-3. Xyz, 4. Def“ → Xyz: 1.–3. Stunde „Begleitung Kim“ (2c).
public struct Bemerkung: Codable, Hashable, Sendable {
    /// Stunden (1 … 6); leer = ganzer Tag bzw. nur Uhrzeit bekannt
    public var stunden: [Int]
    /// Was zu tun ist: „Begleitung Kim“, „Termin“ …
    public var was: String
    public var klasse: String
    /// Uhrzeit, wenn der Plan eine nennt („8:30–11:55“)
    public var zeit: String
    /// Der ganze Absatz (zum Nachlesen)
    public var text: String
    public init(stunden: [Int], was: String, klasse: String = "", zeit: String = "", text: String) {
        self.stunden = stunden; self.was = was; self.klasse = klasse; self.zeit = zeit; self.text = text
    }
    /// „Begleitung Kim · 2c“
    public var titel: String { [was, klasse].filter { !$0.isEmpty }.joined(separator: " · ") }
}

public extension VertretungsPlan {
    /// Muster einer Stundenangabe: „1.-3.“, „4.“, „4. Std“, „1.–4. Std.“
    static let stundenMuster = #"(?<!\d)([0-6])\.\s*(?:[-–]\s*([0-6])\.)?\s*(?:Std\.?|Stunde)?"#
    private static let kl = #"(?:VSK\s?[a-c1-3]?|[1-4][a-d])"#
    private static let klasseMuster = #"(?<![\p{L}\d])("# + kl + #")(?![\p{L}\d])"#
    private static let zeitMuster = #"(\d{1,2}[:.]\d{2})\s*[-–]\s*(\d{1,2}[:.]\d{2})"#
    /// „Begleitung Kim:“, „Begleitungen: Kim:“, „->Kim:“ oder „Kim (2c):“ am Absatzanfang
    private static let werMuster = #"(?:Schul)?[Bb]egleitung(?:en)?\s*:?\s*([A-ZÄÖÜ][\p{L}-]+)(?:\s*\(?\s*"# + kl + #"\s*\)?)?\s*:?|(?:^|->|>|/|;)\s*([A-ZÄÖÜ][\p{L}-]+)(?:\s*\(?\s*"# + kl + #"\s*\)?)?\s*:"#
    private static let keinName: Set<String> = ["wichtig", "achtung", "hinweis", "info", "begleitung", "begleitungen", "fsj", "sb", "vertretung"]

    private static func treffer(_ muster: String, _ s: String) -> [NSTextCheckingResult] {
        guard let re = try? NSRegularExpression(pattern: muster) else { return [] }
        return re.matches(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }
    private static func gruppe(_ m: NSTextCheckingResult, _ i: Int, _ s: String) -> String {
        m.range(at: i).location == NSNotFound ? "" : (s as NSString).substring(with: m.range(at: i))
    }

    /// „1. Abc, 2.-4. Xyz, 4.,5.Def“ → [abc: [1], xyz: [2, 3, 4], def: [4, 5]]
    static func zuteilung(_ liste: String) -> [String: [Int]] {
        let t = liste.replacingOccurrences(of: zeitMuster, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\d{1,2}\s*Uhr|\d{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: klasseMuster, with: " ", options: .regularExpression)
        var aus: [String: Set<Int>] = [:], nums = Set<Int>(), vor: Int?, bis = false
        for m in treffer(#"\d|[-–]|[\p{L}?]+"#, t) {
            let w = gruppe(m, 0, t)
            if let d = Int(w) {
                if bis, let v = vor { nums.formUnion(min(v, d)...max(v, d)) } else { nums.insert(d) }
                vor = d; bis = false
            } else if w == "-" || w == "–" { bis = vor != nil }
            else if ["std", "stunde", "stunden", "und", "fsj", "sb"].contains(w.lowercased()) || nums.isEmpty { continue }
            else { aus[w.lowercased(), default: []].formUnion(nums); nums = []; vor = nil; bis = false }
        }
        return aus.mapValues { $0.sorted() }
    }

    /// Begleitungen im Absatz, an denen das Kürzel beteiligt ist
    private static func begleitungen(_ p: String, _ k: String) -> [Bemerkung] {
        var aus: [Bemerkung] = []
        let ns = p as NSString
        // „Xyz 2.-4. Lio (2c)“ – Kürzel vorn, dann Stunden und das Kind
        for m in treffer(#"(?:^|;)\s*(?i:"# + NSRegularExpression.escapedPattern(for: k) + #")\s*:?\s*((?:\d\.?\s*[-–+,]?\s*(?:und\s*)?)+)(?:Std\.?\s*)?([A-ZÄÖÜ][\p{L}-]+)(?:\s*\(?\s*("# + kl + #")\s*\)?)?"#, p) {
            let st = zuteilung(gruppe(m, 1, p) + " x")["x"] ?? []
            if !st.isEmpty, !keinName.contains(gruppe(m, 2, p).lowercased()) { aus.append(Bemerkung(stunden: st, was: "Begleitung " + gruppe(m, 2, p), klasse: gruppe(m, 3, p), text: p)) }
        }
        let wer = treffer(werMuster, p).filter { m in
            let n = gruppe(m, 1, p).isEmpty ? gruppe(m, 2, p) : gruppe(m, 1, p)
            return !keinName.contains(n.lowercased()) && n.lowercased() != k.lowercased()
        }
        for (i, m) in wer.enumerated() {
            let start = m.range.location + m.range.length
            let semi = ns.range(of: ";", range: NSRange(location: start, length: ns.length - start)).location
            let ende = max(start, min(i + 1 < wer.count ? wer[i + 1].range.location : ns.length, semi == NSNotFound ? ns.length : semi))
            guard let st = zuteilung(ns.substring(with: NSRange(location: start, length: ende - start)))[k.lowercased()] else { continue }
            // Klasse: direkt beim Namen, sonst die letzte davor im selben Satzteil („FSJ Ella 2c krank-> Begleitung Kim“)
            let vorn = ns.substring(to: m.range.location)
            let satz = vorn.range(of: ";", options: .backwards).map { String(vorn[$0.upperBound...]) } ?? vorn
            let beim = ns.substring(with: m.range)
            let klasse = treffer(klasseMuster, beim).first.map { gruppe($0, 1, beim) } ?? treffer(klasseMuster, satz).last.map { gruppe($0, 1, satz) } ?? ""
            let name = gruppe(m, 1, p).isEmpty ? gruppe(m, 2, p) : gruppe(m, 1, p)
            aus.append(Bemerkung(stunden: st, was: "Begleitung " + name, klasse: klasse.replacingOccurrences(of: " ", with: ""), text: p))
        }
        return aus
    }

    /// Bemerkungen für [kuerzel] aus den Absätzen der „Wichtig“-Zeile ableiten – für jedes Kürzel
    static func bemerkungen(_ absaetze: [String], kuerzel k: String) -> [Bemerkung] {
        guard !k.isEmpty else { return [] }
        var aus: [Bemerkung] = []
        for absatz in absaetze where Vertretung.hat(absatz, k) {
            let b = begleitungen(absatz, k)
            if !b.isEmpty { aus += b; continue }
            // sonst: freie Bemerkung („Xyz 3. Std Elterngespräch“, „Beratung 8:00-10:00 Xyz“)
            let klasse = treffer(klasseMuster, absatz).first.map { gruppe($0, 1, absatz) } ?? ""
            let zeit = treffer(zeitMuster, absatz).first.map { gruppe($0, 0, absatz).replacingOccurrences(of: "-", with: "–").replacingOccurrences(of: " ", with: "") } ?? ""
            for teil in absatz.components(separatedBy: CharacterSet(charactersIn: ",;")) where Vertretung.hat(teil, k) {
                var stunden: [Int] = []
                for m in treffer(stundenMuster, teil) {
                    let a = Int(gruppe(m, 1, teil)) ?? 0
                    let b = Int(gruppe(m, 2, teil)) ?? a
                    stunden += Array(min(a, b)...max(a, b))
                }
                let kRe = #"(?i)(?<![\p{L}])"# + NSRegularExpression.escapedPattern(for: k) + #"(?![\p{L}])"#
                let rest = teil.replacingOccurrences(of: stundenMuster, with: " ", options: .regularExpression).replacingOccurrences(of: kRe, with: " ", options: .regularExpression)
                var was = ""
                if let r = teil.range(of: kRe, options: .regularExpression) {
                    let danach = String(teil[r.upperBound...]).replacingOccurrences(of: stundenMuster, with: " ", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                    if !danach.isEmpty, danach.count <= 40, !danach.contains("krank") { was = danach }
                }
                if was.isEmpty {
                    was = rest.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                    if was.count > 50 { was = String(was.prefix(50)) + "…" }
                }
                aus.append(Bemerkung(stunden: Array(Set(stunden)).sorted(), was: was, klasse: klasse, zeit: stunden.isEmpty ? zeit : "", text: absatz))
            }
        }
        return aus
    }
}
