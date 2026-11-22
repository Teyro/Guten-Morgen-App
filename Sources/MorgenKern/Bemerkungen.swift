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

    /// Bemerkungen für [kuerzel] aus den Absätzen der „Wichtig“-Zeile ableiten
    static func bemerkungen(_ absaetze: [String], kuerzel k: String) -> [Bemerkung] {
        guard !k.isEmpty else { return [] }
        var aus: [Bemerkung] = []
        for absatz in absaetze where hat(absatz, k) {
            // Kontext: alles vor der ersten Stunden- bzw. Kürzelangabe („FSJ Ella (Paul) 2c krank Begleitung Kim“)
            let klasse = treffer(#"(?<![\w])(VSK\s?[a-c1-3]?|[1-4][a-d])(?![\w])"#, absatz, gruppe: 1).first ?? ""
            let begleitung = treffer(#"(Begleitung|begleitet|Betreuung|Schulbegleitung)\s+([A-ZÄÖÜ][\p{L}-]+)"#, absatz, gruppe: 0).first ?? ""
            let zeit = treffer(#"(\d{1,2}[:.]\d{2})\s*[-–]\s*(\d{1,2}[:.]\d{2})"#, absatz, gruppe: 0).first.map { $0.replacingOccurrences(of: "-", with: "–").replacingOccurrences(of: " ", with: "") } ?? ""
            // in Abschnitte zerlegen: „… 1.-3. Xyz, 4. Def“ → [„… 1.-3. Xyz“, „4. Def“]
            for teil in absatz.components(separatedBy: CharacterSet(charactersIn: ",;")) where hat(teil, k) {
                var stunden: [Int] = []
                if let re = try? NSRegularExpression(pattern: stundenMuster) {
                    let ns = teil as NSString
                    for m in re.matches(in: teil, range: NSRange(location: 0, length: ns.length)) {
                        let a = Int(ns.substring(with: m.range(at: 1))) ?? 0
                        let b = m.range(at: 2).location != NSNotFound ? Int(ns.substring(with: m.range(at: 2))) ?? a : a
                        stunden += Array(min(a, b)...max(a, b))
                    }
                }
                // Was: hinter Kürzel/Stunden stehende Wörter („Xyz 4. Std Termin“ → „Termin“), sonst die Begleitung, sonst der Anfang
                let rest = teil.replacingOccurrences(of: stundenMuster, with: " ", options: .regularExpression)
                    .replacingOccurrences(of: #"(?i)(?<![\p{L}])"# + NSRegularExpression.escapedPattern(for: k) + #"(?![\p{L}])"#, with: " ", options: .regularExpression)
                var was = ""
                if let r = teil.range(of: #"(?i)(?<![\p{L}])"# + NSRegularExpression.escapedPattern(for: k) + #"(?![\p{L}])"#, options: .regularExpression) {
                    let danach = String(teil[r.upperBound...]).replacingOccurrences(of: stundenMuster, with: " ", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                    if !danach.isEmpty, danach.count <= 40, !danach.contains("krank") { was = danach }
                }
                if was.isEmpty { was = begleitung }
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
