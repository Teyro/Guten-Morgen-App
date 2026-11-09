import Foundation
#if canImport(Compression)
import Compression
#endif

/// Was im Vertretungsplan (Word-Datei im Cloud-Ordner der Schule) für ein Kürzel steht
public struct VertretungsPlan: Codable, Hashable, Sendable {
    public struct Stunde: Codable, Hashable, Sendable { public var stunde: String; public var klasse: String; public init(stunde: String, klasse: String) { self.stunde = stunde; self.klasse = klasse } }
    public struct Pause: Codable, Hashable, Sendable { public var pause: String; public var ort: String; public init(pause: String, ort: String) { self.pause = pause; self.ort = ort } }
    public var datum: String?
    public var stunden: [Stunde] = []
    public var pausen: [Pause] = []
    public var fehlt = false
    public var ausserHaus = false
    public var hinweise: [String] = []
    public var fehlen: [String] = []
    public var datei = ""
    /// Wie viele Zellen im Stundenteil ausgefüllt sind (leere Vorlage = 0)
    public var belegt = 0
    public init() {}

    /// „2. Stunde 2c, 2. Pause Aufsicht Mensa.“ – leer, wenn nichts für das Kürzel drinsteht
    public func satz() -> String {
        var t: [String] = []
        if fehlt { t.append("du bist als fehlend eingetragen") }
        t += stunden.map { (Int($0.stunde) != nil ? "\($0.stunde). Stunde" : $0.stunde) + " " + $0.klasse }
        t += pausen.map { "\($0.pause) Aufsicht \($0.ort)" }
        return t.isEmpty ? "Laut Vertretungsplan hast du keine Vertretung." : "Vertretung: " + t.joined(separator: ", ") + "."
    }
}

public enum Vertretung {
    // MARK: Ordner (Nextcloud-Freigabe, nur lesen)

    /// "https://host/s/TOKEN" → (host, token)
    public static func zerlege(_ link: String) -> (host: String, token: String)? {
        let s = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let r = s.range(of: #"^(https://[^/\s]+)(?:/index\.php)?/s/([A-Za-z0-9]+)/?$"#, options: .regularExpression) else { return nil }
        let teil = String(s[r])
        let host = teil.components(separatedBy: "/s/")[0].replacingOccurrences(of: "/index.php", with: "")
        let token = teil.components(separatedBy: "/s/")[1].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return (host, token)
    }

    /// Der Plan für heute (Wochenende: Freitag): Datum im Dateinamen zählt am meisten, dann ein bloßer Wochentag
    /// (als dieser Tag der aktuellen Woche), das Datum im Dokument nur als Notlösung (Word-Feld = Speichertag).
    /// Bei Gleichstand gewinnt der Plan mit mehr Einträgen, dann die zuletzt gespeicherte Datei.
    public static func laden(link: String, kuerzel: String, jetzt: Date = Date()) async throws -> VertretungsPlan {
        guard let teile = zerlege(link) else { throw URLError(.badURL) }
        let host = teile.host, token = teile.token
        let auth = "Basic " + Data("\(token):".utf8).base64EncodedString()
        let propfind = Data(#"<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:getlastmodified/></d:prop></d:propfind>"#.utf8)
        var basis = "\(host)/public.php/dav/files/\(token)/"
        var (d, s) = try await Netz.daten(URL(string: basis)!, methode: "PROPFIND", kopf: ["Authorization": auth, "Depth": "1"], koerper: propfind)
        if s != 207 {
            basis = "\(host)/public.php/webdav/"
            (d, s) = try await Netz.daten(URL(string: basis)!, methode: "PROPFIND", kopf: ["Authorization": auth, "Depth": "1"], koerper: propfind)
        }
        guard s == 207 else { throw URLError(.cannotConnectToHost) }
        let ziel = zielTag(jetzt)
        let reihe = reihenfolge(wordDateien(String(decoding: d, as: UTF8.self)), ziel: ziel)
        var beste: (plan: VertretungsPlan, wert: (Int, Double, Int, Double))?
        for k in reihe.prefix(4) {
            if let b = beste, k.rang > b.wert.0 { break }
            guard let pfad = k.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: basis + pfad),
                  let antwort = try? await Netz.daten(url, kopf: ["Authorization": auth], zeit: 30), antwort.1 == 200,
                  let xml = dokument(antwort.0) else { continue }
            var p = auswerten(xml, kuerzel: kuerzel)
            p.datei = k.name
            if let t = k.tag { p.datum = t }
            let wert = (k.rang, k.abstand, -p.belegt, -k.zeit.timeIntervalSince1970)
            if beste == nil || wert < beste!.wert { beste = (p, wert) }
        }
        guard let b = beste else { throw URLError(.cannotParseResponse) }
        return b.plan
    }

    public struct Kandidat: Sendable { public var name: String; public var zeit: Date; public var rang: Int; public var abstand: Double; public var tag: String? }

    /// Wochentag im Dateinamen (1 = Montag … 5 = Freitag) oder 0
    public static func nameWochentag(_ name: String) -> Int {
        let n = name.lowercased()
        return (["montag", "dienstag", "mittwoch", "donnerstag", "freitag"].firstIndex { n.contains($0) } ?? -1) + 1
    }

    /// Derselbe Wochentag in der Woche von [ziel]
    static func tagDerWoche(_ ziel: String, _ wt: Int) -> String? {
        guard let d = Zeit.tag(ziel) else { return nil }
        let k = Zeit.kalender
        let wochentag = (k.component(.weekday, from: d) + 5) % 7 // Montag = 0
        return k.date(byAdding: .day, value: wt - 1 - wochentag, to: d).map(Zeit.iso)
    }

    /// rang 0: Datum im Namen = Ziel, 1: Wochentag im Namen = Ziel, 2: Rest nach Abstand; innerhalb zuerst die neueste
    public static func reihenfolge(_ dateien: [(name: String, zeit: Date)], ziel: String) -> [Kandidat] {
        dateien.map { f -> Kandidat in
            let ausName = nameDatum(f.name, f.zeit)
            let wt = nameWochentag(f.name)
            let woche = wt > 0 ? tagDerWoche(ziel, wt) : nil
            if ausName == ziel { return Kandidat(name: f.name, zeit: f.zeit, rang: 0, abstand: 0, tag: ausName) }
            if ausName == nil, woche == ziel { return Kandidat(name: f.name, zeit: f.zeit, rang: 1, abstand: 0, tag: woche) }
            let tag = ausName ?? woche
            let a = tag.map { Double(abstand($0, ziel)) + ($0 > ziel ? 0.5 : 0) } ?? 99
            return Kandidat(name: f.name, zeit: f.zeit, rang: 2, abstand: a, tag: tag)
        }.sorted { ($0.rang, $0.abstand, -$0.zeit.timeIntervalSince1970) < ($1.rang, $1.abstand, -$1.zeit.timeIntervalSince1970) }
    }

    public static func zielTag(_ jetzt: Date) -> String {
        let k = Zeit.kalender
        var d = k.startOfDay(for: jetzt)
        switch k.component(.weekday, from: d) {
        case 7: d = k.date(byAdding: .day, value: -1, to: d) ?? d
        case 1: d = k.date(byAdding: .day, value: -2, to: d) ?? d
        default: break
        }
        return Zeit.iso(d)
    }

    static func abstand(_ a: String, _ b: String) -> Int {
        guard let x = Zeit.tag(a), let y = Zeit.tag(b) else { return 999 }
        return Int((abs(x.timeIntervalSince(y)) / 86400).rounded())
    }

    /// Datum nur, wenn es im Dateinamen steht („3. Mittwoch 411“ = 4.11., „Freitag_09.10.“)
    public static func nameDatum(_ name: String, _ zeit: Date) -> String? {
        var n = name.replacingOccurrences(of: ".docx", with: "", options: .caseInsensitive)
        if let r = n.range(of: #"^\s*\d\.\s*"#, options: .regularExpression) { n.removeSubrange(r) }
        var t = 0, m = 0
        if let r = n.range(of: #"\d{1,2}\.\d{1,2}"#, options: .regularExpression) {
            let z = n[r].split(separator: ".").compactMap { Int($0) }; t = z[0]; m = z[1]
        } else if let r = n.range(of: #"(?<![\d.])\d{3,4}(?![\d.])"#, options: .regularExpression) {
            let z = String(n[r]); t = Int(z.dropLast(2)) ?? 0; m = Int(z.suffix(2)) ?? 0
        }
        guard (1...31).contains(t), (1...12).contains(m) else { return nil }
        let k = Zeit.kalender
        let jahr = k.component(.year, from: zeit)
        let kandidaten = [jahr - 1, jahr, jahr + 1].compactMap { k.date(from: DateComponents(year: $0, month: m, day: t, hour: 12)) }
        return kandidaten.min { abs($0.timeIntervalSince(zeit)) < abs($1.timeIntervalSince(zeit)) }.map(Zeit.iso)
    }

    /// PROPFIND-Antwort → Word-Dateien mit Änderungszeit, neueste zuerst
    public static func wordDateien(_ xml: String) -> [(name: String, zeit: Date)] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return treffer(#"<d:response>([\s\S]*?)</d:response>"#, xml).compactMap { r -> (String, Date)? in
            guard let href = treffer(#"<d:href>([^<]*)</d:href>"#, r).first,
                  let z = treffer(#"<d:getlastmodified>([^<]*)</d:getlastmodified>"#, r).first, let zeit = f.date(from: z) else { return nil }
            let name = (href.split(separator: "/").last.map(String.init) ?? "").removingPercentEncoding ?? ""
            guard name.lowercased().hasSuffix(".docx"), !name.hasPrefix("~$") else { return nil }
            return (name, zeit)
        }.sorted { $0.1 > $1.1 }.map { (name: $0.0, zeit: $0.1) }
    }

    // MARK: Word-Datei

    /// word/document.xml aus der .docx (ZIP über das zentrale Verzeichnis, Deflate mit Compression)
    public static func dokument(_ b: Data) -> String? {
        let z = [UInt8](b)
        func u16(_ i: Int) -> Int { Int(z[i]) | Int(z[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        guard z.count > 22 else { return nil }
        var ende = -1
        var i = z.count - 22
        while i >= max(0, z.count - 66000) { if u32(i) == 0x06054b50 { ende = i; break }; i -= 1 }
        guard ende >= 0 else { return nil }
        var p = u32(ende + 16)
        for _ in 0..<u16(ende + 10) {
            guard p + 46 <= z.count, u32(p) == 0x02014b50 else { break }
            let methode = u16(p + 10), groesse = u32(p + 20), echt = u32(p + 24), nl = u16(p + 28), el = u16(p + 30), kl = u16(p + 32), lokal = u32(p + 42)
            let name = String(decoding: z[(p + 46)..<(p + 46 + nl)], as: UTF8.self)
            if name == "word/document.xml" {
                let start = lokal + 30 + u16(lokal + 26) + u16(lokal + 28)
                guard start + groesse <= z.count, echt < 40_000_000 else { return nil }
                let roh = Data(z[start..<(start + groesse)])
                if methode == 0 { return String(decoding: roh, as: UTF8.self) }
                #if canImport(Compression)
                var ziel = [UInt8](repeating: 0, count: echt + 64)
                let n = roh.withUnsafeBytes { q in
                    compression_decode_buffer(&ziel, ziel.count, q.bindMemory(to: UInt8.self).baseAddress!, roh.count, nil, COMPRESSION_ZLIB)
                }
                return n > 0 ? String(decoding: ziel[0..<n], as: UTF8.self) : nil
                #else
                return nil
                #endif
            }
            p += 46 + nl + el + kl
        }
        return nil
    }

    struct Zelle { var text: String; var xml: String; var von: Int; var bis: Int; var mitte: Double { Double(von + bis) / 2 } }

    static func treffer(_ muster: String, _ s: String, gruppe: Int = 1) -> [String] {
        guard let re = try? NSRegularExpression(pattern: muster) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            m.numberOfRanges > gruppe && m.range(at: gruppe).location != NSNotFound ? ns.substring(with: m.range(at: gruppe)) : ns.substring(with: m.range)
        }
    }

    static func text(_ xml: String) -> String {
        var s = xml.replacingOccurrences(of: "</w:p>", with: " ").replacingOccurrences(of: "<w:tab/>", with: " ").replacingOccurrences(of: "<w:br/>", with: " ")
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (a, b) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'")] { s = s.replacingOccurrences(of: a, with: b) }
        return s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    static func zeilen(_ xml: String) -> [[Zelle]] {
        treffer(#"<w:tr[ >][\s\S]*?</w:tr>"#, xml, gruppe: 0).map { tr in
            var pos = 0
            return treffer(#"<w:tc>[\s\S]*?</w:tc>"#, tr, gruppe: 0).map { tc in
                let b = Int(treffer(#"<w:tcW w:w="(\d+)""#, tc).first ?? "0") ?? 0
                defer { pos += b }
                return Zelle(text: text(tc), xml: tc, von: pos, bis: pos + b)
            }
        }
    }

    /// Kommt das Kürzel als eigenes Wort vor? „Wal+4“ ja, „Walter“ nein
    static func hat(_ text: String, _ k: String) -> Bool {
        let w = text.lowercased().components(separatedBy: CharacterSet.letters.inverted)
        return w.contains(k.lowercased())
    }

    static func kuerzelListe(_ t: String) -> [String] {
        t.split(whereSeparator: { ",;/".contains($0) }).flatMap { teil -> [String] in
            let w = teil.split(separator: " ").map(String.init)
            return w.allSatisfy({ $0.count <= 8 && $0.allSatisfy(\.isLetter) }) ? w : [w.joined(separator: " ")]
        }.filter { !$0.isEmpty }
    }

    public static func auswerten(_ xml: String, kuerzel: String) -> VertretungsPlan {
        var p = VertretungsPlan()
        if let r = text(xml).range(of: #"\d{1,2}\.\d{1,2}\.\d{4}"#, options: .regularExpression) {
            let z = text(xml)[r].split(separator: ".").compactMap { Int($0) }
            p.datum = String(format: "%04d-%02d-%02d", z[2], z[1], z[0])
        }
        let alle = zeilen(xml)
        let k = kuerzel.trimmingCharacters(in: .whitespaces)
        guard let kopfI = alle.firstIndex(where: { $0.first?.text.lowercased() == "klasse" }) else { return p }
        let kopf = Array(alle[kopfI].dropFirst()).filter { !$0.text.isEmpty }
        var pausenSpalten: [Zelle]? = nil
        for (i, z) in alle.enumerated() {
            guard let titel = z.first?.text else { continue }
            let t = titel.lowercased()
            if t.hasPrefix("es fehlen") {
                let s = z.dropFirst().map(\.text).joined(separator: " ")
                p.fehlen = kuerzelListe(s); if !k.isEmpty && hat(s, k) { p.fehlt = true }; continue
            }
            if t.hasPrefix("außer haus") || t.hasPrefix("ausser haus") {
                if !k.isEmpty && z.dropFirst().contains(where: { hat($0.text, k) }) { p.ausserHaus = true }; continue
            }
            if t.hasPrefix("wichtig"), z.count > 1, !k.isEmpty {
                p.hinweise += treffer(#"<w:p[ >][\s\S]*?</w:p>"#, z[1].xml, gruppe: 0).map(text).filter { !$0.isEmpty && hat($0, k) }
            }
            let pausen = z.filter { $0.text.range(of: #"^\d\.\s*[Pp]ause$"#, options: .regularExpression) != nil }
            if !pausen.isEmpty { pausenSpalten = pausen; continue }
            if let sp = pausenSpalten, !k.isEmpty {
                let ort = z.filter { $0.bis <= sp[0].von + 5 && !$0.text.isEmpty }.last?.text ?? ""
                for s in sp {
                    if let c = z.first(where: { $0.mitte >= Double(s.von) && $0.mitte < Double(s.bis) }), hat(c.text, k) {
                        p.pausen.append(.init(pause: s.text, ort: ort))
                    }
                }
                continue
            }
            guard i > kopfI, !titel.isEmpty, !t.hasPrefix("wichtig") else { continue }
            p.belegt += z.dropFirst().filter { !$0.text.isEmpty }.count
            guard !k.isEmpty else { continue }
            for c in z.dropFirst() where !c.text.isEmpty && hat(c.text, k) {
                let ueber = kopf.filter { $0.von < c.bis && $0.bis > c.von }
                let klasse = ueber.count > 1 ? "\(ueber.first!.text)–\(ueber.last!.text)" : (kopf.first { c.mitte >= Double($0.von) && c.mitte < Double($0.bis) }?.text ?? "")
                if !p.stunden.contains(where: { $0.stunde == titel && $0.klasse == klasse }) { p.stunden.append(.init(stunde: titel, klasse: klasse)) }
            }
        }
        return p
    }
}
