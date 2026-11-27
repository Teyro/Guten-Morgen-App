import Foundation

/// Eine Störungsmeldung aus IServ
public struct Stoerung: Codable, Hashable, Sendable {
    public var titel: String
    public var inhalt: String
    public var autor: String
    public var bearbeiter: String
    public var datum: Date?
    public var status: String
    public var ort: String
    public var erledigt: Bool
    /// Status heißt: noch niemand hat sie übernommen („wer macht's?“)
    public var unbesetzt: Bool
    public var url: String

    public init(titel: String, inhalt: String, autor: String, bearbeiter: String, datum: Date?, status: String, ort: String, erledigt: Bool, unbesetzt: Bool, url: String) {
        self.titel = titel; self.inhalt = inhalt; self.autor = autor; self.bearbeiter = bearbeiter; self.datum = datum
        self.status = status; self.ort = ort; self.erledigt = erledigt; self.unbesetzt = unbesetzt; self.url = url
    }

    public var uebernommen: Bool { !erledigt && (!bearbeiter.isEmpty || !unbesetzt) }
    /// „🛠 in Arbeit (Kim)“ bzw. „🆕 noch niemand“
    public var zustand: String {
        if erledigt { return "✅ erledigt" }
        if !bearbeiter.isEmpty { return "🛠 \(bearbeiter)" }
        return unbesetzt ? "🆕 noch niemand" : "🛠 " + (status.isEmpty ? "in Arbeit" : status)
    }
}

public struct StoerungenStand: Codable, Hashable, Sendable {
    public var meldungen: [Stoerung]
    public var stand: Date
    public init(meldungen: [Stoerung], stand: Date = Date()) { self.meldungen = meldungen; self.stand = stand }
    /// Neueste zuerst
    public var offen: [Stoerung] { meldungen.filter { !$0.erledigt }.sorted { ($0.datum ?? .distantPast) > ($1.datum ?? .distantPast) } }
    public var alle: [Stoerung] { meldungen.sorted { ($0.datum ?? .distantPast) > ($1.datum ?? .distantPast) } }
}

public enum Stoerungen {
    public static let modulKandidaten = ["/iserv/defect", "/iserv/defect/", "/iserv/defects", "/iserv/troubleticket", "/iserv/ticket"]
    public static let modulMuster = "st(ö|oe|&ouml;)rung|defect|trouble|ticket"
    static let erledigtMuster = "erledigt|geschlossen|behoben|gel(ö|oe)st|abgeschlossen|closed|resolved|done|fertig"
    static let unbesetztMuster = "wer mach|niemand|unbearbeitet|^neu$|^offen$|new|open"
    /// Spaltenüberschriften → Felder; Reihenfolge zählt („erstellt von“ ist der Autor, nicht das Datum)
    static let spalten: [(String, String)] = [
        ("bearbeiter", "bearbeit|zust(ä|ae)ndig|(ü|ue)bernommen|zugewiesen|verantwortlich|assign|techniker|admin"),
        ("autor", "gemeldet von|erstellt von|eingereicht von|^von$|autor|verfasser|melder|ersteller|absender|benutzer|gemeldet durch"),
        ("titel", "betreff|titel|title|st(ö|oe)rung|problem|bezeichnung|thema|subject|kurzbeschreibung"),
        ("inhalt", "beschreibung|inhalt|nachricht|text|details|fehlerbeschreibung|description|body"),
        ("status", "status|zustand"),
        ("ort", "raum|ort|ger(ä|ae)t|standort|location"),
        ("kategorie", "kategorie|bereich|typ|art$"),
        ("aktualisiert", "aktualisier|ge(ä|ae)ndert|update"),
        ("datum", "datum|erstellt|gemeldet|zeit|eingang|date|created"),
    ]

    public static func laden(_ s: IServ, quelle: IServQuelle?) async throws -> (StoerungenStand, IServQuelle) {
        if let q = quelle, let l = lesen(try await s.lade(q), spalten: q.spalten) { return (StoerungenStand(meldungen: l), q) }
        guard let (q, l) = try await s.erkunde(muster: modulMuster, kandidaten: modulKandidaten, lesen: { lesen($0, spalten: $1) }) else {
            throw IServFehler.nichtGefunden("Störungsmeldungen nicht gefunden.")
        }
        return (StoerungenStand(meldungen: l), q)
    }

    static func zuordnen(_ kopf: [String]) -> [String: Int] {
        var z: [String: Int] = [:], belegt = Set<Int>()
        for (feld, m) in spalten {
            if let i = kopf.indices.first(where: { !belegt.contains($0) && kopf[$0].trimmingCharacters(in: .whitespaces).range(of: m, options: [.regularExpression, .caseInsensitive]) != nil }) {
                z[feld] = i; belegt.insert(i)
            }
        }
        return z
    }

    static func meldung(_ zellen: [String], _ z: [String: Int], link: String) -> Stoerung? {
        func w(_ f: String) -> String { z[f].map { $0 < zellen.count ? zellen[$0].trimmingCharacters(in: .whitespaces) : "" } ?? "" }
        let titel = w("titel").isEmpty ? String(w("inhalt").prefix(80)) : w("titel")
        guard !titel.isEmpty else { return nil }
        let status = w("status")
        let erledigt = status.range(of: erledigtMuster, options: [.regularExpression, .caseInsensitive]) != nil
        let bearbeiter = w("bearbeiter").range(of: #"^[-–—]$|^(niemand|keine?r?)$"#, options: [.regularExpression, .caseInsensitive]) != nil ? "" : w("bearbeiter")
        return Stoerung(titel: titel, inhalt: z["titel"] != nil ? w("inhalt") : "", autor: HTML.nameSchoen(w("autor")), bearbeiter: HTML.nameSchoen(bearbeiter),
                        datum: zeit(w("datum")), status: status, ort: w("ort"), erledigt: erledigt,
                        unbesetzt: !erledigt && (status.isEmpty || status.range(of: unbesetztMuster, options: [.regularExpression, .caseInsensitive]) != nil), url: link)
    }

    public static func lesen(_ s: IServ.Seite, spalten sp: [String]) -> [Stoerung]? {
        let body = s.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.typ.lowercased().contains("json") || body.hasPrefix("{") || body.hasPrefix("[") {
            guard let j = try? JSONSerialization.jsonObject(with: Data(body.utf8)) else { return nil }
            let zeilen = (j as? [[Any]]) ?? ((j as? [String: Any]).flatMap { ($0["data"] ?? $0["aaData"] ?? $0["rows"]) as? [[Any]] })
            guard let zz = zeilen, !sp.isEmpty else { return nil }
            let z = zuordnen(sp)
            guard z["titel"] != nil else { return nil }
            return zz.compactMap { r in meldung(r.map { c in HTML.text((c as? String) ?? ((c as? [String: Any])?["display"] as? String) ?? "\(c)") }, z, link: "") }
        }
        if s.typ.lowercased().contains("csv") {
            let zeilen = HTML.csv(body)
            if let kopf = zeilen.first { let z = zuordnen(kopf); if z["titel"] != nil { return zeilen.dropFirst().compactMap { meldung($0, z, link: "") } } }
        }
        var liste: [Stoerung] = []
        for tab in HTML.tabellen(body) where tab.count >= 2 {
            let z = zuordnen(tab[0].zellen)
            guard z["titel"] != nil, z["datum"] != nil || z["autor"] != nil else { continue }
            for r in tab.dropFirst() where r.zellen.count >= 2 {
                if let m = meldung(r.zellen, z, link: r.link.map { HTML.absolut(HTML.entities($0), von: s.url) } ?? "") { liste.append(m) }
            }
        }
        return liste.isEmpty ? nil : liste
    }

    /// „12.10.2026, 08:15“, „2026-10-12T…“, „heute 9:30“, „gestern“
    public static func zeit(_ s: String) -> Date? {
        let k = Zeit.kalender
        if s.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil {
            let f = ISO8601DateFormatter()
            if let d = f.date(from: s) { return d }
            return Zeit.tag(String(s.prefix(10)))
        }
        func uhr(_ d: Date) -> Date {
            guard let u = HTML.erster(#"(\d{1,2}:\d{2})"#, s), let m = Zeit.minuten(u) else { return d }
            return k.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: d) ?? d
        }
        if let iso = Abwesenheiten.datum(s), s.range(of: #"\d{1,2}\.\d{1,2}\.\d{2,4}"#, options: .regularExpression) != nil, let d = Zeit.tag(iso) {
            return uhr(k.startOfDay(for: d))
        }
        if s.range(of: "heute", options: .caseInsensitive) != nil { return uhr(k.startOfDay(for: Date())) }
        if s.range(of: "gestern", options: .caseInsensitive) != nil { return uhr(k.startOfDay(for: Date().addingTimeInterval(-86400))) }
        return nil
    }
}

// MARK: Verlauf einer Meldung (Detailseite in IServ) und Antworten

/// Gesprächsverlauf einer Störungsmeldung und – falls IServ eins anbietet – das Formular zum Antworten
public struct StoerungVerlauf: Sendable {
    public struct Eintrag: Hashable, Sendable {
        public var autor: String
        public var zeit: String
        public var text: String
        public init(autor: String, zeit: String, text: String) { self.autor = autor; self.zeit = zeit; self.text = text }
    }
    public struct Formular: Sendable {
        public var aktion: String
        public var felder: [(String, String)]
        public var textFeld: String
    }
    public var eintraege: [Eintrag]
    public var formular: Formular?
}

extension Stoerungen {
    // ganze Wörter: „comment“, „comment-item“ ja – Sammelbehälter wie „comments“/„messages“ nicht
    static let eintragMuster = #"<(div|li|article|section|tr)\b[^>]*class=["'](?:[^"']*[\s])?(comment|kommentar|reply|antwort|answer|message|nachricht|activity|timeline-item|post)(?:-[\w-]*)?(?=[\s"'])[^"']*["'][^>]*>"#

    /// Detailseite laden (abgelaufene Sitzung → neu anmelden) und lesen
    public static func verlauf(_ s: IServ, url: String) async throws -> StoerungVerlauf {
        try s.hostPruefen(url)
        let seite = try await s.lade(IServQuelle(url: url, art: "direkt"))
        return verlaufAus(seite.body, von: seite.url)
    }

    /// Antwort über das Formular der Detailseite schicken (nur an IServ selbst)
    public static func antworten(_ s: IServ, formular f: StoerungVerlauf.Formular, text: String) async throws {
        guard f.aktion.lowercased().hasPrefix("https:"), URL(string: f.aktion)?.host?.lowercased() == s.zugang.server else { throw IServFehler.allgemein("Antworten geht nur direkt an IServ.") }
        let felder = f.felder.filter { $0.0 != f.textFeld } + [(f.textFeld, text)]
        let antwort = try await s.anfrage(f.aktion, methode: "POST", kopf: ["Referer": f.aktion], felder: felder)
        guard (200..<400).contains(antwort.status), !IServ.istLoginSeite(antwort) else { throw IServFehler.allgemein("Antwort nicht gesendet (HTTP \(antwort.status)).") }
    }

    public static func verlaufAus(_ html: String, von: String) -> StoerungVerlauf {
        let ohneSkript = html.replacingOccurrences(of: #"<script[\s\S]*?</script>|<style[\s\S]*?</style>|<nav[\s\S]*?</nav>|<header[\s\S]*?</header>|<footer[\s\S]*?</footer>"#,
                                                   with: " ", options: [.regularExpression, .caseInsensitive])
        // Formular mit Textfeld = Antworten
        var formular: StoerungVerlauf.Formular?
        for f in HTML.formulare(ohneSkript) {
            guard let ta = HTML.erster(#"(<textarea\b[^>]*>)"#, f), !HTML.name(ta).isEmpty else { continue }
            var felder: [(String, String)] = []
            for i in HTML.eingaben(f) {
                let n = HTML.name(i), t = HTML.typ(i)
                guard !n.isEmpty, !["submit", "button", "file", "image", "reset"].contains(t) else { continue }
                if (t == "checkbox" || t == "radio") && i.range(of: #"\bchecked\b"#, options: [.regularExpression, .caseInsensitive]) == nil { continue }
                felder.append((n, HTML.entities(HTML.attr(i, "value") ?? "")))
            }
            // benannter Absende-Knopf (Symfony-Formulare erwarten ihn mitunter)
            if let k = HTML.erster(#"(<button\b[^>]*type=["']submit["'][^>]*>)"#, f) ?? HTML.erster(#"(<input\b[^>]*type=["']submit["'][^>]*>)"#, f), !HTML.name(k).isEmpty {
                felder.append((HTML.name(k), HTML.entities(HTML.attr(k, "value") ?? "")))
            }
            let aktion = HTML.entities(HTML.attr(HTML.erster(#"(<form\b[^>]*>)"#, f) ?? "", "action") ?? "")
            formular = .init(aktion: aktion.isEmpty ? von : HTML.absolut(aktion, von: von), felder: felder, textFeld: HTML.name(ta))
            break
        }
        let ohneFormulare = ohneSkript.replacingOccurrences(of: #"<form[\s\S]*?</form>"#, with: " ", options: [.regularExpression, .caseInsensitive])
        // Einträge: Blöcke mit „comment/reply/…“ in der Klasse bis zum nächsten solchen Block
        let ns = ohneFormulare as NSString
        let starts = HTML.alleI(eintragMuster, ohneFormulare).map(\.range.location)
        var eintraege: [StoerungVerlauf.Eintrag] = []
        for (n, start) in starts.enumerated() {
            let ende = n + 1 < starts.count ? starts[n + 1] : min(ns.length, start + 6000)
            let block = ns.substring(with: NSRange(location: start, length: max(0, ende - start)))
            let autor = HTML.text(HTML.erster(#"class=["'][^"']*\b(?:author|autor|user|username|name|creator)\b[^"']*["'][^>]*>([\s\S]*?)</"#, block) ?? "")
            let zeit = HTML.text(HTML.erster(#"<time\b[^>]*>([\s\S]*?)</time>"#, block) ?? HTML.erster(#"(\d{1,2}\.\d{1,2}\.\d{2,4}(?:,?\s*\d{1,2}:\d{2})?)"#, block) ?? "")
            var text = absatzText(block)
            for weg in [autor, zeit] where !weg.isEmpty { text = text.replacingOccurrences(of: weg, with: "") }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty, !eintraege.contains(where: { $0.text == text }) { eintraege.append(.init(autor: HTML.nameSchoen(autor), zeit: zeit, text: text)) }
        }
        // Nichts erkannt: der ganze Inhaltsbereich als ein Eintrag
        if eintraege.isEmpty {
            let inhalt = HTML.erster(#"<main\b[^>]*>([\s\S]*?)</main>"#, ohneFormulare) ?? HTML.erster(#"<div[^>]*id=["']content["'][^>]*>([\s\S]*)"#, ohneFormulare) ?? ohneFormulare
            let t = absatzText(inhalt)
            if !t.isEmpty { eintraege.append(.init(autor: "", zeit: "", text: String(t.prefix(8000)))) }
        }
        // Ein Block mit mehreren Kommentaren (Sammelbehälter oder ganze Seite): an „Name am 18.11.2026 11:03“ trennen
        return StoerungVerlauf(eintraege: eintraege.flatMap(aufteilen), formular: formular)
    }

    /// Kommentarkopf wie in IServ: „Christian Stake am 18.11.2026 11:03“ (auch „…, 11:03 Uhr“) am Zeilenanfang
    static let kopfMuster = #"(?m)^[ \t]*([A-ZÄÖÜ][\p{L}'.]+(?:[ -][A-ZÄÖÜ][\p{L}'.]+){0,3})[ \t]+am[ \t]+(\d{1,2}\.\d{1,2}\.\d{2,4})(?:,?[ \t]*(?:um[ \t]*)?(\d{1,2}:\d{2}))?(?:[ \t]*Uhr)?[ \t]*:?[ \t]*\n?"#

    /// Ein Eintrag mit mehreren Kommentarköpfen → je Kommentar ein Eintrag (der Text davor bleibt beim ursprünglichen Absender)
    static func aufteilen(_ e: StoerungVerlauf.Eintrag) -> [StoerungVerlauf.Eintrag] {
        guard let re = try? NSRegularExpression(pattern: kopfMuster) else { return [e] }
        let ns = e.text as NSString
        let treffer = re.matches(in: e.text, range: NSRange(location: 0, length: ns.length))
        guard !treffer.isEmpty else { return [e] }
        func g(_ m: NSTextCheckingResult, _ i: Int) -> String { m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i)) }
        func sauber(_ t: String) -> String {
            // Überschriften der Seite („Kommentare“, „Dateien“) am Rand weg
            t.replacingOccurrences(of: #"(?m)^[ \t]*(Kommentare|Kommentar|Dateien|Antworten)[ \t]*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var aus: [StoerungVerlauf.Eintrag] = []
        let vorn = sauber(ns.substring(to: treffer[0].range.location))
        if !vorn.isEmpty { aus.append(.init(autor: e.autor, zeit: e.zeit, text: vorn)) }
        for (i, m) in treffer.enumerated() {
            let start = m.range.location + m.range.length
            let ende = i + 1 < treffer.count ? treffer[i + 1].range.location : ns.length
            let text = sauber(ns.substring(with: NSRange(location: start, length: max(0, ende - start))))
            let zeit = [g(m, 2), g(m, 3)].filter { !$0.isEmpty }.joined(separator: " ")
            if !text.isEmpty { aus.append(.init(autor: HTML.nameSchoen(g(m, 1)), zeit: zeit, text: text)) }
        }
        return aus.isEmpty ? [e] : aus
    }

    /// Bin das ich? IServ-Benutzer „christian.stake“ ↔ „Christian Stake“ / „Christian Stake-Admin“
    public static func istIch(_ autor: String, benutzer: String, ichName: String = "") -> Bool {
        func norm(_ s: String) -> String {
            s.lowercased().replacingOccurrences(of: #"[-\s]*\(?admin\)?$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"[._-]"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        }
        let a = norm(autor)
        guard !a.isEmpty else { return false }
        if !ichName.isEmpty { return a == norm(ichName) }
        let b = norm(benutzer.components(separatedBy: "@")[0])
        return !b.isEmpty && (a == b || a.hasPrefix(b + " ") )
    }

    /// HTML → Text mit Absätzen (statt alles in einer Zeile)
    static func absatzText(_ h: String) -> String {
        var s = h.replacingOccurrences(of: #"<br\s*/?>|</p>|</div>|</li>|</h\d>|</tr>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression)
        s = HTML.entities(s).replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #" *\n[ \n]*"#, with: "\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
