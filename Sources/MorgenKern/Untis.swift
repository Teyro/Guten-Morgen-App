import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Eine Stunde aus WebUntis
public struct UntisStunde: Codable, Hashable, Sendable {
    /// „2026-11-09“
    public var datum: String
    /// Minuten nach Mitternacht
    public var von: Int
    public var bis: Int
    public var fach: String
    public var fachLang: String
    public var klassen: [String]
    /// Kürzel der Lehrkräfte (bei Vertretung die ursprünglich geplante)
    public var lehrer: [String]
    public var lehrerIds: [Int]
    public var raum: String
    /// „cancelled“, „irregular“ oder leer
    public var code: String
    public init(datum: String, von: Int, bis: Int, fach: String, fachLang: String = "", klassen: [String], lehrer: [String], lehrerIds: [Int] = [], raum: String = "", code: String = "") {
        self.datum = datum; self.von = von; self.bis = bis; self.fach = fach; self.fachLang = fachLang; self.klassen = klassen
        self.lehrer = lehrer; self.lehrerIds = lehrerIds; self.raum = raum; self.code = code
    }
    public var entfaellt: Bool { code == "cancelled" }
    /// Förderkreis/Förderunterricht (am Fachnamen erkannt)
    public var foerder: Bool {
        let t = (fach + " " + fachLang).lowercased()
        return t.contains("förder") || t.contains("foerder") || ["fö", "foe", "fk", "fök", "fö-k"].contains(fach.lowercased())
    }
}

/// Was aus WebUntis geladen wurde: die eigenen Stunden und die Pläne der eigenen Klassen (für „wer ist noch in der Klasse“)
public struct UntisStand: Codable, Hashable, Sendable {
    public var meine: [UntisStunde]
    public var klassen: [String: [UntisStunde]]
    /// eigene Lehrer-ID in WebUntis (zum Erkennen in fremden Plänen)
    public var ich: Int
    public var kuerzel: String
    public var stand: Date
    public init(meine: [UntisStunde], klassen: [String: [UntisStunde]], ich: Int, kuerzel: String, stand: Date = Date()) {
        self.meine = meine; self.klassen = klassen; self.ich = ich; self.kuerzel = kuerzel; self.stand = stand
    }
}

/// Eine Klasse aus meiner Sicht: meine Fächer, Förderkreis, Doppelbesetzung, wer dort sonst unterrichtet
public struct KlassenInfo: Hashable, Sendable, Identifiable {
    public struct Fach: Hashable, Sendable { public var kurz: String; public var lang: String; public var stunden: Int }
    public struct Kollege: Hashable, Sendable { public var kuerzel: String; public var faecher: [String]; public var stunden: Int }
    public var id: String { klasse }
    public var klasse: String
    /// meine Fächer in der Klasse, nach Wochenstunden
    public var faecher: [Fach]
    public var stunden: Int
    /// Wochenstunden im Förderkreis
    public var foerder: Int
    /// mit wem ich zusammen in der Klasse stehe (Doppelbesetzung)
    public var doppel: [String]
    /// alle anderen Lehrkräfte der Klasse, nach Wochenstunden
    public var andere: [Kollege]
}

public enum Untis {
    public enum Fehler: LocalizedError {
        case text(String)
        public var errorDescription: String? { if case .text(let t) = self { return t }; return nil }
    }

    /// Wie in WebUntis unter Freigaben → Untis Mobile: Url („hh5586.webuntis.com“, auch mit https:// oder ganzer Anmelde-Adresse)
    /// und Schule („hh5586“) – fehlt die Schule, steckt sie meist im Servernamen
    public static func server(url: String, schule: String) -> (basis: String, schule: String)? {
        if let z = zerlege(url) { return (z.basis, schule.trimmingCharacters(in: .whitespaces).isEmpty ? z.schule : schule.trimmingCharacters(in: .whitespaces)) }
        var t = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for p in ["https://", "http://"] where t.hasPrefix(p) { t.removeFirst(p.count) }
        let host = String(t.split(whereSeparator: { "/?#".contains($0) }).first ?? "")
        guard host.contains("."), !host.contains(" ") else { return nil }
        var s = schule.trimmingCharacters(in: .whitespaces)
        if s.isEmpty, host.hasSuffix(".webuntis.com"), let erst = host.split(separator: ".").first, !["webuntis", "mese", "nessa", "neilo", "arche", "ajax", "erato", "kephiso", "melpomene", "poly", "peleus", "terpsichore", "thalia", "tipo", "urania", "herakles", "hepta", "asopo", "cissa"].contains(String(erst)) {
            s = String(erst)
        }
        guard !s.isEmpty else { return nil }
        return ("https://" + host, s)
    }

    /// „https://server.webuntis.com/WebUntis/?school=xyz#/basic/login“ → (https://server.webuntis.com, xyz)
    public static func zerlege(_ link: String) -> (basis: String, schule: String)? {
        let l = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: String(l.split(separator: "#").first ?? "")), let host = u.host, u.scheme == "https" else { return nil }
        guard let r = l.range(of: #"[?&]school=([^&#]+)"#, options: .regularExpression) else { return nil }
        let schule = String(l[r]).components(separatedBy: "=").dropFirst().joined(separator: "=").removingPercentEncoding ?? ""
        guard !schule.isEmpty else { return nil }
        return ("https://" + host + (u.port.map { ":\($0)" } ?? ""), schule)
    }

    static func iso(_ zahl: Int) -> String { String(format: "%04d-%02d-%02d", zahl / 10000, zahl / 100 % 100, zahl % 100) }
    static func minuten(_ hhmm: Int) -> Int { hhmm / 100 * 60 + hhmm % 100 }

    /// Ergebnis von getTimetable lesen (ohne Netz, testbar)
    public static func stunden(_ ergebnis: Any) -> [UntisStunde] {
        (ergebnis as? [[String: Any]] ?? []).compactMap { o in
            func namen(_ feld: String, original: Bool = false) -> [String] {
                (o[feld] as? [[String: Any]] ?? []).compactMap { e in
                    let org = original ? (e["orgname"] as? String).flatMap { $0.isEmpty ? nil : $0 } : nil
                    return org ?? (e["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                }
            }
            guard let datum = (o["date"] as? NSNumber)?.intValue, let von = (o["startTime"] as? NSNumber)?.intValue, let bis = (o["endTime"] as? NSNumber)?.intValue else { return nil }
            let su = (o["su"] as? [[String: Any]] ?? []).first
            return UntisStunde(datum: iso(datum), von: minuten(von), bis: minuten(bis),
                               fach: su?["name"] as? String ?? "", fachLang: (su?["longname"] as? String) ?? (su?["longName"] as? String) ?? "",
                               klassen: namen("kl"), lehrer: namen("te", original: true),
                               lehrerIds: (o["te"] as? [[String: Any]] ?? []).compactMap { ($0["orgid"] as? NSNumber)?.intValue ?? ($0["id"] as? NSNumber)?.intValue },
                               raum: namen("ro").joined(separator: ", "), code: o["code"] as? String ?? "")
        }
        .sorted { ($0.datum, $0.von) < ($1.datum, $1.von) }
    }

    /// Je Wochentag der erste Tag mit regulärem Unterricht – so stören Ferien- und Projekttage nicht
    public static func grundwoche(_ s: [UntisStunde]) -> [UntisStunde] {
        let regulaer = s.filter { $0.code != "irregular" }
        var tage: [Int: String] = [:]
        for x in regulaer {
            guard let d = Zeit.tag(x.datum) else { continue }
            let wt = Zeit.kalender.component(.weekday, from: d)
            if tage[wt] == nil || x.datum < tage[wt]! { tage[wt] = x.datum }
        }
        let gewaehlt = Set(tage.values)
        return regulaer.filter { gewaehlt.contains($0.datum) }
    }

    /// Meine Klassen mit Fächern, Förderkreis, Doppelbesetzung und den anderen Lehrkräften (Grundwoche)
    public static func klassen(_ st: UntisStand) -> [KlassenInfo] {
        let meine = grundwoche(st.meine)
        let ichBin: (UntisStunde, Int) -> Bool = { s, i in
            (s.lehrerIds.indices.contains(i) && s.lehrerIds[i] == st.ich) || (!st.kuerzel.isEmpty && s.lehrer.indices.contains(i) && s.lehrer[i].lowercased() == st.kuerzel.lowercased())
        }
        let namen = Set(meine.flatMap(\.klassen))
        return namen.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { k in
            let hier = meine.filter { $0.klassen.contains(k) }
            var faecher: [String: KlassenInfo.Fach] = [:]
            for s in hier where !s.foerder { faecher[s.fach, default: .init(kurz: s.fach, lang: s.fachLang, stunden: 0)].stunden += 1 }
            let doppel = Set(hier.flatMap { s in s.lehrer.indices.filter { !ichBin(s, $0) }.map { s.lehrer[$0] } })
            var andere: [String: KlassenInfo.Kollege] = [:]
            for s in grundwoche(st.klassen[k] ?? []) {
                for i in s.lehrer.indices where !ichBin(s, i) {
                    var kol = andere[s.lehrer[i], default: .init(kuerzel: s.lehrer[i], faecher: [], stunden: 0)]
                    kol.stunden += 1
                    if !s.fach.isEmpty && !kol.faecher.contains(s.fach) { kol.faecher.append(s.fach) }
                    andere[s.lehrer[i]] = kol
                }
            }
            return KlassenInfo(klasse: k, faecher: faecher.values.sorted { ($0.stunden, $1.kurz) > ($1.stunden, $0.kurz) },
                               stunden: hier.count, foerder: hier.filter(\.foerder).count, doppel: doppel.sorted(),
                               andere: andere.values.sorted { ($0.stunden, $1.kuerzel) > ($1.stunden, $0.kuerzel) })
        }
    }

    /// Grundwoche als eigener Stundenplan: je Stunde (nach Beginn in den Klingelzeiten) Klasse, Fach, Raum
    public static func unterricht(_ st: UntisStand, zeiten: [Schulzeit]) -> [Unterricht] {
        var liste: [Unterricht] = []
        for s in grundwoche(st.meine) {
            guard let d = Zeit.tag(s.datum) else { continue }
            let wt = Zeit.kalender.component(.weekday, from: d)
            // alle Stunden des Rasters, die in diese Untis-Stunde fallen (Doppelstunden)
            for z in zeiten where !z.pause && z.von < s.bis && z.bis > s.von {
                guard !liste.contains(where: { $0.tag == wt && $0.stunde == z.name }) else { continue }
                liste.append(Unterricht(tag: wt, stunde: z.name, klasse: s.klassen.joined(separator: ", "), fach: s.fachLang.isEmpty ? s.fach : s.fachLang, raum: s.raum))
            }
        }
        return liste
    }

    // MARK: Netz (JSON-RPC wie in DammTable)

    /// QR-Code aus WebUntis (Profil → Freigaben → Untis Mobile): untis://setschool?url=…&school=…&user=…&key=…
    public static func qr(_ text: String) -> (basis: String, schule: String, benutzer: String, schluessel: String)? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.lowercased().hasPrefix("untis://"), let c = URLComponents(string: t) else { return nil }
        func w(_ n: String) -> String { c.queryItems?.first { $0.name.lowercased() == n }?.value ?? "" }
        var host = w("url")
        guard !host.isEmpty, !w("school").isEmpty else { return nil }  // Schlüssel darf fehlen (liegt dann im Schlüsselbund)
        if !host.hasPrefix("https://") { host = "https://" + host.replacingOccurrences(of: "http://", with: "") }
        while host.hasSuffix("/") { host.removeLast() }
        if host.lowercased().hasSuffix("/webuntis") { host = String(host.dropLast(9)) }
        return (host, w("school"), w("user"), w("key"))
    }

    final class Sitzung: @unchecked Sendable {
        let basis: String
        let schule: String
        let url: URL
        let netz = URLSession(configuration: .ephemeral)
        var nr = 0
        init(basis: String, schule: String) throws {
            self.basis = basis; self.schule = schule
            guard let u = URL(string: basis + "/WebUntis/jsonrpc.do?school=" + (schule.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? schule)) else { throw Fehler.text("Der WebUntis-Link ist ungültig.") }
            url = u
        }

        /// Anmeldung wie die App Untis Mobile: Benutzer + Einmalcode aus dem Schlüssel (funktioniert auch mit zweitem Faktor)
        func anmeldenMitSchluessel(benutzer: String, schluessel: String) async throws -> (typ: Int, id: Int) {
            let s = schule.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? schule
            guard let u = URL(string: basis + "/WebUntis/jsonrpc_intern.do?m=getUserData2017&school=\(s)&v=i2.2") else { throw Fehler.text("Der WebUntis-Link ist ungültig.") }
            let jetzt = Date()
            let auth: [String: Any] = ["clientTime": Int64(jetzt.timeIntervalSince1970 * 1000), "user": benutzer, "otp": IServ.totp(schluessel.replacingOccurrences(of: " ", with: ""), zeit: jetzt)]
            let e = try await senden(u, ["id": "0", "method": "getUserData2017", "params": [["auth": auth]], "jsonrpc": "2.0"]) as? [String: Any] ?? [:]
            let daten = e["userData"] as? [String: Any] ?? [:]
            let typ: Int
            switch (daten["elemType"] as? String ?? "").uppercased() {
            case "TEACHER": typ = 2
            case "STUDENT": typ = 5
            case "CLASS": typ = 1
            default: typ = 0
            }
            return (typ, (daten["elemId"] as? NSNumber)?.intValue ?? 0)
        }

        func rufe(_ methode: String, _ params: [String: Any] = [:]) async throws -> Any {
            nr += 1
            return try await senden(url, ["id": "\(nr)", "method": methode, "params": params, "jsonrpc": "2.0"])
        }

        private func senden(_ url: URL, _ koerper: [String: Any]) async throws -> Any {
            var r = URLRequest(url: url, timeoutInterval: 30)
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.setValue("GutenMorgen", forHTTPHeaderField: "User-Agent")
            r.httpBody = try JSONSerialization.data(withJSONObject: koerper)
            let (d, a) = try await netz.data(for: r)
            let status = (a as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 { throw Fehler.text("WebUntis nicht gefunden – Link prüfen.") }
            guard (200..<300).contains(status), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw Fehler.text("WebUntis antwortet nicht wie erwartet (\(status)).") }
            if let f = o["error"] as? [String: Any] {
                let code = (f["code"] as? NSNumber)?.intValue ?? 0
                switch code {
                case -8504: throw Fehler.text("WebUntis: Benutzername oder Passwort falsch. Mit zweitem Faktor bitte den QR-Code „Untis Mobile“ verwenden.")
                case -8998, -8997: throw Fehler.text("WebUntis: Der Schlüssel aus dem QR-Code passt nicht (oder die Uhr des iPhones geht falsch).")
                case -8500: throw Fehler.text("WebUntis: Schule nicht gefunden – Link prüfen.")
                case -8509, -8510: throw Fehler.text("Dieses WebUntis-Konto darf den Stundenplan nicht abrufen.")
                default: throw Fehler.text("WebUntis meldet: \(f["message"] as? String ?? "Fehler") (\(code))")
                }
            }
            guard let e = o["result"] else { throw Fehler.text("Leere Antwort von WebUntis.") }
            return e
        }
    }

    static func zahl(_ d: Date) -> Int {
        let c = Zeit.kalender.dateComponents([.year, .month, .day], from: d)
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    /// Eigene Stunden (diese und nächste Woche) und die Pläne meiner Klassen laden
    /// [link]: Adresse der Anmeldeseite oder der Text des QR-Codes; [schluessel] (aus dem QR-Code) geht vor dem Passwort
    public static func laden(link: String, schule: String = "", benutzer: String, passwort: String, schluessel: String = "", kuerzel: String, jetzt: Date = Date()) async throws -> UntisStand {
        let q = qr(link)
        guard let z = q.map({ (basis: $0.basis, schule: $0.schule) }) ?? server(url: link, schule: schule) else {
            throw Fehler.text("Bitte Url (z. B. hh5586.webuntis.com) und Schule (z. B. hh5586) eintragen – beides steht in WebUntis unter Freigaben → Untis Mobile.")
        }
        let s = try Sitzung(basis: z.basis, schule: z.schule)
        let nutzer = (q?.benutzer).flatMap { $0.isEmpty ? nil : $0 } ?? benutzer.trimmingCharacters(in: .whitespaces)
        let geheim = (q?.schluessel).flatMap { $0.isEmpty ? nil : $0 } ?? schluessel
        var typ = 0, ich = 0
        if !geheim.isEmpty {
            (typ, ich) = try await s.anmeldenMitSchluessel(benutzer: nutzer, schluessel: geheim)
        } else {
            guard !passwort.isEmpty else { throw Fehler.text("Bitte Passwort oder – bei zweitem Faktor – den QR-Code „Untis Mobile“ eintragen.") }
            let a = try await s.rufe("authenticate", ["user": nutzer, "password": passwort, "client": "GutenMorgen"]) as? [String: Any] ?? [:]
            typ = (a["personType"] as? NSNumber)?.intValue ?? 0
            ich = (a["personId"] as? NSNumber)?.intValue ?? 0
        }
        defer { Task { _ = try? await s.rufe("logout") } }
        if typ != 2 {
            // kein Lehrer-Konto: über das Kürzel suchen (falls erlaubt)
            let lehrer = try await s.rufe("getTeachers") as? [[String: Any]] ?? []
            guard let t = lehrer.first(where: { ($0["name"] as? String)?.lowercased() == kuerzel.lowercased() }), let id = (t["id"] as? NSNumber)?.intValue else {
                throw Fehler.text("Das WebUntis-Konto ist keinem Lehrer zugeordnet – bitte das eigene Kürzel bei „Vertretung“ eintragen.")
            }
            typ = 2; ich = id
        }
        let k = Zeit.kalender
        var montag = k.date(from: k.dateComponents([.yearForWeekOfYear, .weekOfYear], from: jetzt)) ?? jetzt
        if [1, 7].contains(k.component(.weekday, from: jetzt)) { montag = k.date(byAdding: .day, value: 7, to: montag) ?? montag }
        let bis = k.date(byAdding: .day, value: 11, to: montag) ?? montag
        func plan(_ typ: Int, _ id: Int) async throws -> [UntisStunde] {
            let o: [String: Any] = ["element": ["id": id, "type": typ], "startDate": zahl(montag), "endDate": zahl(bis),
                                    "showSubstText": true, "klasseFields": ["id", "name", "longname"], "teacherFields": ["id", "name", "longname"],
                                    "subjectFields": ["id", "name", "longname"], "roomFields": ["id", "name", "longname"]]
            return stunden(try await s.rufe("getTimetable", ["options": o]))
        }
        let meine = try await plan(typ, ich)
        if meine.isEmpty { throw Fehler.text("In WebUntis stehen für dich in diesen zwei Wochen keine Stunden.") }
        // Klassen-Ids holen, dann deren Pläne (für „wer ist noch in der Klasse“); darf ein Konto das nicht, bleibt es leer
        var klassen: [String: [UntisStunde]] = [:]
        if let liste = try? await s.rufe("getKlassen") as? [[String: Any]] {
            for name in Set(meine.flatMap(\.klassen)) {
                guard let id = liste.first(where: { ($0["name"] as? String) == name }).flatMap({ ($0["id"] as? NSNumber)?.intValue }) else { continue }
                klassen[name] = (try? await plan(1, id)) ?? []
            }
        }
        return UntisStand(meine: meine, klassen: klassen, ich: ich, kuerzel: kuerzel)
    }
}
