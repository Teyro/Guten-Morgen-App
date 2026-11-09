import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Ein Gericht aus dem Speiseplan der Kantine
public struct Gericht: Codable, Hashable, Sendable {
    public var menue: String      // „Menü 1“
    public var text: String       // „Spaghetti Bolognese“
    public var bestellt: Bool
    /// Zusatzstoffe/Allergene („1,3,A“) – auch beim Meiden durchsucht
    public var zusatz: String
    public init(menue: String, text: String, bestellt: Bool = false, zusatz: String = "") { self.menue = menue; self.text = text; self.bestellt = bestellt; self.zusatz = zusatz }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        menue = try c.decode(String.self, forKey: .menue); text = try c.decode(String.self, forKey: .text)
        bestellt = (try? c.decode(Bool.self, forKey: .bestellt)) ?? false; zusatz = (try? c.decode(String.self, forKey: .zusatz)) ?? ""
    }

    /// Kommt eins der Stichwörter („Pizza, Nudeln“) vor? [mitZusatz]: auch in den Zusatzstoffen suchen (zum Meiden)
    public func passt(_ stichwoerter: String, mitZusatz: Bool = false) -> Bool {
        let woerter = stichwoerter.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        let t = (text + (mitZusatz ? " " + zusatz : "")).lowercased()
        return woerter.contains { t.contains($0) }
    }
}

/// Ein Tag im Speiseplan
public struct MensaTag: Codable, Hashable, Sendable {
    public var datum: String      // ISO „2026-11-09“
    public var gerichte: [Gericht] = []
    /// Feiertag/Ferien: Grund aus dem Portal (sonst nil)
    public var frei: String?
    public init(datum: String, gerichte: [Gericht] = [], frei: String? = nil) { self.datum = datum; self.gerichte = gerichte; self.frei = frei }

    /// Was es (für mich) gibt: das bestellte Gericht, sonst das erste
    public var haupt: Gericht? { haupt() }
    /// Wie im Kantinen-Widget: bestellt → Lieblingsessen → erstes nicht gemiedenes → erstes
    public func haupt(favoriten: String = "", meiden: String = "") -> Gericht? {
        gerichte.first(where: \.bestellt) ?? gerichte.first { !favoriten.isEmpty && $0.passt(favoriten) }
            ?? gerichte.first { meiden.isEmpty || !$0.passt(meiden, mitZusatz: true) } ?? gerichte.first
    }

    public func satz(heute: Bool = true) -> String {
        if let f = frei { return "Die Mensa hat \(heute ? "heute" : "an dem Tag") geschlossen\(f.isEmpty ? "" : " (\(f))")." }
        guard let h = haupt else { return "" }
        return h.bestellt ? "In der Mensa gibt es für dich \(h.text)." : "In der Mensa gibt es \(h.text)."
    }
}

/// Mehrere Wochen Speiseplan und das Guthaben
public struct MensaPlan: Codable, Hashable, Sendable {
    public var tage: [MensaTag]
    public var guthaben: Double?
    public var stand: Date
    public init(tage: [MensaTag], guthaben: Double? = nil, stand: Date = Date()) { self.tage = tage; self.guthaben = guthaben; self.stand = stand }
    public func tag(_ iso: String) -> MensaTag? { tage.first { $0.datum == iso } }
}

/// Für welchen Tag Schul-Infos gelten: bis 16 Uhr heute, danach der nächste Schultag (Wochenende und freie Tage übersprungen)
public enum Tagwahl {
    public static let umschaltStunde = 16
    public static func ziel(_ jetzt: Date = Date(), frei: [FreierTag] = []) -> Date {
        let k = Zeit.kalender
        var d = k.startOfDay(for: jetzt)
        if k.component(.hour, from: jetzt) >= umschaltStunde { d = k.date(byAdding: .day, value: 1, to: d) ?? d }
        for _ in 0..<30 {
            let wt = k.component(.weekday, from: d)
            if wt != 1 && wt != 7 && FreieTage.am(frei, d) == nil { break }
            d = k.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return d
    }
    /// „heute“, „morgen“ oder „Montag“
    public static func name(_ tag: Date, jetzt: Date = Date()) -> String {
        let k = Zeit.kalender
        if k.isDate(tag, inSameDayAs: jetzt) { return "heute" }
        if let m = k.date(byAdding: .day, value: 1, to: jetzt), k.isDate(tag, inSameDayAs: m) { return "morgen" }
        return Zeit.wochentag(tag)
    }
}

/// Speiseplan aus dem Kantinen-Portal (PCA, PrimeFaces) – wie das Scriptable-Widget „PCA-Kantine“.
/// Die Adresse kommt aus den Einstellungen (nicht im Code: das Repository ist öffentlich).
public enum Mensa {
    static let pfadLogin = "/web-cantine/app/login"
    static let pfadDash = "/web-cantine/app/portal/dashboard"
    static let pfadPlan = "/web-cantine/app/portal/food/menuPlan?menuplanEdit=false"

    public enum Fehler: Error, LocalizedError {
        case adresse, anmeldung(String), portal(String)
        public var errorDescription: String? {
            switch self {
            case .adresse: return "Kantinen-Adresse fehlt"
            case .anmeldung(let t): return "Anmeldung abgelehnt: \(t)"
            case .portal(let t): return t
            }
        }
    }

    // Abgelehnte Zugangsdaten nicht immer wieder probieren (sonst sperrt das Portal das Konto) – erst nach einer Änderung
    static func merkmal(_ benutzer: String, _ passwort: String) -> String { String((benutzer + "\u{1}" + passwort).utf8.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1) }) }
    public static func darfAnmelden(_ d: UserDefaults, benutzer: String, passwort: String) -> Bool {
        d.string(forKey: "mensaAbgelehnt") != merkmal(benutzer, passwort)
    }
    /// Nach einem Abruf aufrufen: bei abgelehnter Anmeldung merken, sonst vergessen
    public static func merke(_ d: UserDefaults, fehler: Error?, benutzer: String, passwort: String) {
        if case .anmeldung? = fehler as? Fehler { d.set(merkmal(benutzer, passwort), forKey: "mensaAbgelehnt") }
        else if fehler == nil { d.removeObject(forKey: "mensaAbgelehnt") }
    }

    /// Heute – am Wochenende schon der Montag
    public static func zielTag(_ jetzt: Date = Date()) -> String {
        let k = Zeit.kalender
        let d = k.startOfDay(for: jetzt)
        let plus = [1: 1, 7: 2][k.component(.weekday, from: d)] ?? 0
        return Zeit.iso(k.date(byAdding: .day, value: plus, to: d) ?? d)
    }

    /// Tag [ziel] (ISO) aus dem Portal
    public static func laden(adresse: String, benutzer: String, passwort: String, ziel: String) async throws -> MensaTag? {
        try await ladePlan(adresse: adresse, benutzer: benutzer, passwort: passwort).tage.first { $0.datum == ziel }
    }

    /// Diese und die nächste Woche samt Guthaben (wie die Übersicht im Kantinen-Widget)
    public static func ladePlan(adresse: String, benutzer: String, passwort: String) async throws -> MensaPlan {
        let basis = adresse.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard basis.hasPrefix("https://"), URL(string: basis) != nil else { throw Fehler.adresse }
        // Eigene Sitzung: Cookies nur für diesen Abruf
        let konfig = URLSessionConfiguration.ephemeral
        konfig.timeoutIntervalForRequest = 20
        let s = URLSession(configuration: konfig)
        defer { s.finishTasksAndInvalidate() }

        func hole(_ url: String, referer: String) async throws -> (String, URL?) {
            guard let u = URL(string: url.hasPrefix("http") ? url : basis + url) else { throw Fehler.adresse }
            var r = URLRequest(url: u)
            r.setValue(referer, forHTTPHeaderField: "Referer")
            let (d, a) = try await s.data(for: r)
            return (String(decoding: d, as: UTF8.self), a.url)
        }
        func post(_ url: String, _ felder: [(String, String)], referer: String) async throws -> String {
            guard let u = URL(string: url.hasPrefix("http") ? url : basis + url) else { throw Fehler.adresse }
            var r = URLRequest(url: u)
            r.httpMethod = "POST"
            r.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            r.setValue("partial/ajax", forHTTPHeaderField: "Faces-Request")
            r.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            r.setValue(referer, forHTTPHeaderField: "Referer")
            var erlaubt = CharacterSet.alphanumerics; erlaubt.insert(charactersIn: "-._~")
            r.httpBody = Data(felder.map { "\($0.0.addingPercentEncoding(withAllowedCharacters: erlaubt)!)=\($0.1.addingPercentEncoding(withAllowedCharacters: erlaubt)!)" }.joined(separator: "&").utf8)
            let (d, _) = try await s.data(for: r)
            return String(decoding: d, as: UTF8.self)
        }

        // Anmelden
        let (login, _) = try await hole(pfadLogin, referer: basis)
        guard let action = erster(#"<form[^>]*id="loginForm"[^>]*action="([^"]+)""#, login) else {
            throw Fehler.portal(login.range(of: "wartung", options: .caseInsensitive) != nil ? "Kantinenportal wird gewartet" : "Anmeldeseite nicht erkannt")
        }
        let vs = erster(#"name="javax\.faces\.ViewState"[^>]*value="([^"]*)""#, login) ?? "e1s1"
        let antwort = try await post(entities(action), [
            ("javax.faces.partial.ajax", "true"), ("javax.faces.source", "loginButton"), ("javax.faces.partial.execute", "loginForm"),
            ("javax.faces.partial.render", "loginForm"), ("loginButton", "loginButton"), ("loginForm", "loginForm"), ("loginInfo", ""),
            ("username", benutzer), ("password", passwort), ("javax.faces.ViewState", vs)
        ], referer: basis + pfadLogin)
        guard antwort.range(of: "<redirect", options: .caseInsensitive) != nil else { throw Fehler.anmeldung(String(text(antwort).prefix(80))) }

        let (dash, _) = try await hole(pfadDash, referer: basis + pfadLogin)
        let guthaben = guthabenAus(dash)
        var (plan, planUrl) = try await hole(pfadPlan, referer: basis + pfadDash)
        if plan.contains("id=\"loginForm\"") { throw Fehler.anmeldung("Sitzung abgelehnt") }
        var tage = tageAus(plan)
        // Nächste Woche gleich mitholen (Freitagnachmittag, Wochenende, Wochenübersicht)
        if let vs2 = erster(#"name="javax\.faces\.ViewState"[^>]*value="([^"]*)""#, plan) {
            var ziel2 = erster(#"<form[^>]*id="itemsForm"[^>]*action="([^"]+)""#, plan).map(entities) ?? ""
            if !ziel2.contains("execution=") { ziel2 = planUrl?.absoluteString ?? basis + pfadPlan }
            let xml = try await post(ziel2, [
                ("javax.faces.partial.ajax", "true"), ("javax.faces.source", "nextButton"), ("javax.faces.partial.execute", "@form"),
                ("javax.faces.partial.render", "@form"), ("javax.faces.ViewState", vs2), ("nextButton", "nextButton"), ("itemsForm", "itemsForm")
            ], referer: planUrl?.absoluteString ?? basis + pfadPlan)
            plan = alle(#"<!\[CDATA\[([\s\S]*?)\]\]>"#, xml).joined(separator: "\n")
            planUrl = nil
            let weiter = tageAus(plan).filter { neu in !tage.contains { $0.datum == neu.datum } }
            tage += weiter
        }
        return MensaPlan(tage: tage.sorted { $0.datum < $1.datum }, guthaben: guthaben, stand: Date())
    }

    /// „Verfügbar: 12,40 €“ aus dem Dashboard (sonst Gesamt)
    public static func guthabenAus(_ html: String) -> Double? {
        let ab = html.range(of: "balancePanel").map { String(html[$0.lowerBound...].prefix(6000)) } ?? html
        let t = text(ab)
        func greif(_ muster: String) -> Double? {
            guard let r = t.range(of: muster, options: [.regularExpression, .caseInsensitive]) else { return nil }
            let zahl = String(t[r]).replacingOccurrences(of: #"^.*?(-?[d.]+,d{2}).*$"#, with: "$1", options: .regularExpression)
            return Double(zahl.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "."))
        }
        return greif(#"Verf(ü|ue)gbar:?s*-?[d.]+,d{2}s*€"#) ?? greif(#"GUTHABENs*(GESAMT)s*-?[d.]+,d{2}s*€"#)
    }

    // MARK: Lesen (öffentlich für Tests)

    /// Speiseplan-Tabelle → Tage (Spalten „Menü 1/2/…“ aus dem Tabellenkopf)
    public static func tageAus(_ html: String) -> [MensaTag] {
        let kopf = erster(#"(<thead[\s\S]*?</thead>)"#, html) ?? ""
        let namen = alle(#"(<th[\s\S]*?</th>)"#, kopf).map(text).filter { $0.range(of: #"Men(ü|ue)"#, options: .regularExpression) != nil }
            .map { $0.replacingOccurrences(of: #"\s*-?[\d.]+,\d{2}\s*€\s*"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
        let koerper = html.components(separatedBy: "id=\"menuplan_data\"").dropFirst().first ?? html
        var tage: [MensaTag] = []
        for zeile in alle(#"(<tr[^>]*data-ri="\d+"[\s\S]*?</tr>)"#, koerper) {
            let zellen = alle(#"(<td\b[\s\S]*?</td>)"#, zeile)
            guard let erste = zellen.first, let datum = isoDatum(text(erste)) else { continue }
            var tag = MensaTag(datum: datum)
            var i = 0
            for z in zellen.dropFirst() {
                let klassen = erster(#"class="([^"]*)""#, z) ?? ""
                guard klassen.split(separator: " ").contains("menu-cell") else { continue }
                defer { i += 1 }
                if z.contains("dayOffOverlay") {
                    tag.frei = text(erster(#"dayOffOverlay[^>]*>([\s\S]*?)</div>"#, z) ?? "")
                    continue
                }
                guard let roh = erster(#"innerFoodNameContainer[^>]*>([\s\S]*?)</div>"#, z) else { continue }
                let gericht = text(roh.replacingOccurrences(of: #"<span class="additive-info">[\s\S]*?</span>"#, with: "", options: .regularExpression))
                let zusatz = text(erster(#"<span class="additive-info">([\s\S]*?)</span>"#, roh) ?? "")
                guard !gericht.isEmpty else { continue }
                let bestellt = klassen.range(of: #"\b(selected|ordered|reserved|reservation|booked|ui-state-active|is-ordered)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
                    || z.range(of: #"aria-checked="true"|checked="checked"|\bfa-check\b"#, options: .regularExpression) != nil
                tag.gerichte.append(Gericht(menue: i < namen.count ? namen[i] : "Menü \(i + 1)", text: gericht, bestellt: bestellt, zusatz: zusatz))
            }
            if tag.frei != nil && !tag.gerichte.isEmpty { tag.frei = nil }
            tage.append(tag)
        }
        return tage
    }

    static func isoDatum(_ s: String) -> String? {
        guard let r = s.range(of: #"\d{2}\.\d{2}\.\d{4}"#, options: .regularExpression) else { return nil }
        let z = s[r].split(separator: ".")
        return "\(z[2])-\(z[1])-\(z[0])"
    }

    static func erster(_ muster: String, _ s: String) -> String? { alle(muster, s).first }
    static func alle(_ muster: String, _ s: String) -> [String] { Vertretung.treffer(muster, s) }

    static func entities(_ s: String) -> String {
        var t = s
        for (a, b) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&euro;", "€"),
                       ("&auml;", "ä"), ("&ouml;", "ö"), ("&uuml;", "ü"), ("&Auml;", "Ä"), ("&Ouml;", "Ö"), ("&Uuml;", "Ü"), ("&szlig;", "ß"),
                       ("&eacute;", "é"), ("&ndash;", "–"), ("&mdash;", "—"), ("&amp;", "&")] { t = t.replacingOccurrences(of: a, with: b) }
        // &#228; und &#xE4;
        for m in alle(#"(&#x?[0-9a-fA-F]+;)"#, t) {
            let roh = m.dropFirst(2).dropLast()
            let wert = roh.hasPrefix("x") || roh.hasPrefix("X") ? UInt32(roh.dropFirst(), radix: 16) : UInt32(roh)
            if let w = wert, let z = Unicode.Scalar(w) { t = t.replacingOccurrences(of: m, with: String(Character(z))) }
        }
        return t
    }

    static func text(_ html: String) -> String {
        var s = html.replacingOccurrences(of: #"<!\[CDATA\[|\]\]>"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<script[\s\S]*?</script>|<style[\s\S]*?</style>"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression)
        return entities(s).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }
}

/// Termine aus einem öffentlichen Kalender (ICS), z. B. Schulobst
public enum SchulKalender {
    /// Alle Tage (ISO) mit Termin – ganztägig bis vor DTEND, mit Uhrzeit nur der Starttag
    public static func tage(_ ics: String) -> Set<String> {
        let zeilen = ics.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n ", with: "").replacingOccurrences(of: "\n\t", with: "")
            .split(separator: "\n", omittingEmptySubsequences: false)
        var erg = Set<String>()
        var start: Date?, ende: Date?, ganztags = false
        let k = Zeit.kalender
        func datum(_ w: Substring) -> Date? {
            let z = Array(w.prefix(8))
            guard z.count == 8, let j = Int(String(z[0..<4])), let m = Int(String(z[4..<6])), let t = Int(String(z[6..<8])) else { return nil }
            return k.date(from: DateComponents(year: j, month: m, day: t, hour: 12))
        }
        for z in zeilen {
            guard let doppel = z.firstIndex(of: ":") else { continue }
            let name = z[..<doppel].split(separator: ";").first.map { $0.uppercased() } ?? ""
            let wert = z[z.index(after: doppel)...].trimmingCharacters(in: .whitespaces)
            switch name {
            case "BEGIN" where wert == "VEVENT": start = nil; ende = nil; ganztags = false
            case "DTSTART": start = datum(Substring(wert)); ganztags = wert.count == 8
            case "DTEND": ende = datum(Substring(wert))
            case "END" where wert == "VEVENT":
                guard let s = start else { continue }
                var e = (ganztags ? ende : nil).flatMap { $0 > s ? $0 : nil } ?? k.date(byAdding: .day, value: 1, to: s)!
                e = min(e, k.date(byAdding: .day, value: 60, to: s)!)
                var d = s
                while d < e { erg.insert(Zeit.iso(d)); d = k.date(byAdding: .day, value: 1, to: d)! }
            default: break
            }
        }
        return erg
    }

    public static func laden(_ adresse: String) async throws -> Set<String> {
        guard let u = URL(string: adresse.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "webcal://", with: "https://")) else { throw URLError(.badURL) }
        let (d, s) = try await Netz.daten(u, zeit: 20)
        guard s == 200 else { throw URLError(.badServerResponse) }
        return tage(String(decoding: d, as: UTF8.self))
    }
}
