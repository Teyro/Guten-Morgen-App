import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Zugang zu IServ (wie in den Scriptable-Skripten Abwesenheiten/Störungen – dieselben Daten)
public struct IServZugang: Codable, Hashable, Sendable {
    public var server: String     // „schule.de“ (ohne https://)
    public var benutzer: String
    public var passwort: String
    /// optional: 2FA-Schlüssel (Text unter dem QR-Code) – dann erzeugt die App die Codes selbst
    public var totp: String
    public init(server: String, benutzer: String, passwort: String, totp: String = "") {
        self.server = IServ.bereinige(server); self.benutzer = benutzer; self.passwort = passwort; self.totp = totp
    }
    public var vollstaendig: Bool { !server.isEmpty && !benutzer.isEmpty && !passwort.isEmpty }
}

/// Wo die Daten eines Moduls liegen (einmal gefunden, dann direkt geladen)
public struct IServQuelle: Codable, Hashable, Sendable {
    public var url: String
    public var art: String          // "direkt" oder "daten" (Datenadresse einer Modulseite)
    public var referer: String = ""
    public var spalten: [String] = []
}

public enum IServFehler: Error, LocalizedError, Equatable {
    case zugangsdaten(String)       // abgelehnt – nicht wieder probieren (Kontosperre)
    case zweiFaktor(String)         // Code nötig bzw. nicht angenommen
    case neuerHost(String)          // Anmeldung läuft über eine andere Seite – erst bestätigen
    case nichtGefunden(String)      // Modul/Daten nicht gefunden
    case allgemein(String)
    public var errorDescription: String? {
        switch self {
        case .zugangsdaten(let t), .zweiFaktor(let t), .nichtGefunden(let t), .allgemein(let t): return t
        case .neuerHost(let h): return "Die Anmeldung läuft über \(h) – bitte in der App bestätigen."
        }
    }
    public var kurz: String {
        switch self {
        case .zugangsdaten: return "Zugangsdaten prüfen"
        case .zweiFaktor: return "Code nötig"
        case .neuerHost: return "Anmeldeseite bestätigen"
        case .nichtGefunden: return "Modul nicht gefunden"
        case .allgemein: return "nicht aktuell"
        }
    }
}

/// Eine IServ-Sitzung wie im Browser: folgt Weiterleitungen, vorgeschalteter Anmeldung (Schuldock), Rücksprung-Formularen
/// und dem zweiten Faktor. Cookies bleiben (Sitzung hält, solange IServ sie lässt).
public final class IServ: @unchecked Sendable {
    public struct Seite: Sendable { public var body: String; public var url: String; public var status: Int; public var typ: String }

    public let zugang: IServZugang
    /// Bestätigte fremde Anmeldeseiten (z. B. Schuldock) – Passwort geht nur dorthin oder an IServ selbst
    public var erlaubteHosts: Set<String>
    /// Zwei-Faktor-Code von Hand (nur in der App; im Widget nil)
    public var codeAbfrage: (@Sendable (_ hinweis: String) async -> String?)?
    let sitzung: URLSession
    static let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    public init(_ z: IServZugang, erlaubteHosts: Set<String> = [], codeAbfrage: (@Sendable (String) async -> String?)? = nil) {
        zugang = z; self.erlaubteHosts = erlaubteHosts; self.codeAbfrage = codeAbfrage
        let k = URLSessionConfiguration.default
        k.timeoutIntervalForRequest = 20
        k.httpCookieStorage = .shared
        k.httpCookieAcceptPolicy = .always
        sitzung = URLSession(configuration: k)
    }

    var basis: String { "https://" + zugang.server }

    /// „https://schule.de/iserv/…“ → „schule.de“
    public static func bereinige(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: #"^https?://"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"/.*$"#, with: "", options: .regularExpression).lowercased()
    }

    // MARK: Netz

    func anfrage(_ url: String, methode: String = "GET", kopf: [String: String] = [:], felder: [(String, String)]? = nil) async throws -> Seite {
        guard let u = URL(string: url) else { throw IServFehler.allgemein("Ungültige Adresse") }
        var r = URLRequest(url: u)
        r.httpMethod = methode
        r.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
        r.setValue("de-DE,de;q=0.9", forHTTPHeaderField: "Accept-Language")
        kopf.forEach { r.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let f = felder {
            r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            r.httpBody = Data(HTML.kodiere(f).utf8)
        }
        let (d, a) = try await sitzung.data(for: r)
        let h = a as? HTTPURLResponse
        return Seite(body: String(decoding: d, as: UTF8.self), url: a.url?.absoluteString ?? url, status: h?.statusCode ?? 0,
                     typ: (h?.value(forHTTPHeaderField: "Content-Type")) ?? "")
    }

    /// Seite laden; folgt auch <meta refresh> und IServs Zwischenseite /iserv/auth/auth
    public func hole(_ pfad: String, kopf: [String: String] = [:]) async throws -> Seite {
        var url = pfad.lowercased().hasPrefix("http") ? pfad : basis + pfad
        for _ in 0..<4 {
            let s = try await anfrage(url, kopf: kopf)
            guard let weiter = Self.weiterleitung(s.body, von: s.url) else { return s }
            url = weiter
        }
        throw IServFehler.allgemein("Zu viele Weiterleitungen")
    }

    static func weiterleitung(_ b: String, von: String) -> String? {
        for m in HTML.alle(#"(<meta\b[^>]*>)"#, b) where m.range(of: #"http-equiv=["']?refresh"#, options: [.regularExpression, .caseInsensitive]) != nil {
            if let u = HTML.erster(#"content=["'][^"']*?url=([^"'>]+)["']"#, m) { return HTML.absolut(HTML.entities(u.trimmingCharacters(in: .whitespaces)), von: von) }
        }
        if von.range(of: #"/iserv/auth/auth\b"#, options: .regularExpression) != nil {
            if let u = HTML.erster(#"url=([^"'\s>]+)"#, b) ?? HTML.erster(#"(?:window\.)?location(?:\.href)?\s*=\s*["']([^"']+)["']"#, b)
                ?? HTML.erster(#"data-(?:redirect|url|target|href)[a-z-]*=["']([^"']+)["']"#, b) { return HTML.absolut(HTML.entities(u), von: von) }
        }
        return nil
    }

    // MARK: Anmeldung

    public static func istLoginSeite(_ s: Seite) -> Bool {
        s.url.range(of: #"/iserv/(auth|app)/login"#, options: [.regularExpression, .caseInsensitive]) != nil
            || s.body.range(of: #"name=["']_password["']"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    struct CodeFormular { var action: String; var felder: [(String, String)]; var codeFeld: String; var ziffern: [String]; var versteckt: [String] }

    /// Formular mit Feld für einen Einmal-Code (IServ: sechs Ziffernfelder + verstecktes „otp“)
    static func codeFormular(_ html: String) -> CodeFormular? {
        for f in HTML.formulare(html) where f.range(of: #"name=["']_password["']"#, options: [.regularExpression, .caseInsensitive]) == nil {
            let eingaben = HTML.eingaben(f)
            guard let code = eingaben.first(where: { i in
                !["hidden", "checkbox", "radio", "submit", "button", "password"].contains(HTML.typ(i))
                    && HTML.name(i).range(of: "code|otp|totp|token|2fa|auth|factor", options: [.regularExpression, .caseInsensitive]) != nil
            }) else { continue }
            var felder: [(String, String)] = []
            for i in eingaben {
                let n = HTML.name(i); guard !n.isEmpty else { continue }
                if HTML.typ(i) == "hidden" { felder.append((n, HTML.entities(HTML.attr(i, "value") ?? ""))) }
                // „Diesem Gerät vertrauen“ ankreuzen → Sitzung hält länger
                if HTML.typ(i) == "checkbox", i.range(of: "trust|remember|vertrau|merken", options: [.regularExpression, .caseInsensitive]) != nil { felder.append((n, HTML.attr(i, "value") ?? "1")) }
            }
            let ziffern = eingaben.filter { HTML.typ($0) != "hidden" && HTML.name($0).range(of: #"digit_?\d"#, options: [.regularExpression, .caseInsensitive]) != nil }
                .map(HTML.name).sorted { (Int(HTML.erster(#"digit_?(\d)"#, $0) ?? "0") ?? 0) < (Int(HTML.erster(#"digit_?(\d)"#, $1) ?? "0") ?? 0) }
            let versteckt = eingaben.filter { HTML.typ($0) == "hidden" && HTML.name($0).range(of: "otp|code|totp", options: [.regularExpression, .caseInsensitive]) != nil
                && HTML.name($0).range(of: "csrf|token", options: [.regularExpression, .caseInsensitive]) == nil }.map(HTML.name)
            if let k = HTML.erster(#"(<button[^>]*name=["'][^"']+["'][^>]*>)"#, f), HTML.typ(k) != "button" { felder.append((HTML.name(k), HTML.attr(k, "value") ?? "")) }
            return CodeFormular(action: HTML.entities(HTML.erster(#"<form[^>]*action=["']([^"']*)["']"#, f) ?? ""), felder: felder, codeFeld: HTML.name(code), ziffern: ziffern, versteckt: versteckt)
        }
        return nil
    }

    /// Anmeldeformular: das mit Passwortfeld, sonst eins mit Benutzerfeld
    static func anmeldeFormular(_ html: String) -> String? {
        let formen = HTML.formulare(html).filter { (HTML.erster(#"(<form[^>]*>)"#, $0) ?? "").range(of: "logout|abmelden", options: [.regularExpression, .caseInsensitive]) == nil }
        return formen.first { HTML.eingaben($0).contains { HTML.typ($0) == "password" } }
            ?? formen.first { HTML.eingaben($0).contains { i in HTML.name(i).range(of: "user|login|account|mail", options: [.regularExpression, .caseInsensitive]) != nil && !["hidden", "checkbox", "submit"].contains(HTML.typ(i)) } }
    }

    /// Link zur vorgeschalteten Anmeldung („Login mit Schuldock“, SSO …) oder ein Formular dafür
    static func ssoLink(_ html: String, von: String) -> (url: String?, formular: String?)? {
        for (href, t) in HTML.links(html) {
            let h = HTML.entities(href)
            if (HTML.text(t) + " " + h).range(of: "schuldock|single sign|sso|oauth|openid|oidc|saml|login mit|anmelden mit", options: [.regularExpression, .caseInsensitive]) != nil,
               h.range(of: "logout|hilfe|help|datenschutz", options: [.regularExpression, .caseInsensitive]) == nil { return (HTML.absolut(h, von: von), nil) }
        }
        for f in HTML.formulare(html) where !HTML.eingaben(f).contains(where: { HTML.typ($0) == "password" }) {
            if f.range(of: "schuldock|sso|oauth|openid|oidc|saml|login mit", options: [.regularExpression, .caseInsensitive]) != nil { return (nil, f) }
        }
        return nil
    }

    /// Formulare, die sich im Browser selbst abschicken (Rücksprung von der Anmeldung)
    func autoFormulare(_ start: Seite) async throws -> Seite {
        var s = start
        for _ in 0..<4 {
            guard let f = HTML.formulare(s.body).first(where: { x in
                let e = HTML.eingaben(x)
                return !e.isEmpty && e.allSatisfy { ["hidden", "submit"].contains(HTML.typ($0)) }
                    && (x.range(of: #"SAMLResponse|RelayState|name=["'](code|state|id_token|session_state)["']"#, options: [.regularExpression, .caseInsensitive]) != nil
                        || s.body.range(of: #"\.submit\(\)|onload="#, options: .regularExpression) != nil)
            }) else { return s }
            let felder = HTML.eingaben(f).filter { HTML.typ($0) == "hidden" && !HTML.name($0).isEmpty }.map { (HTML.name($0), HTML.entities(HTML.attr($0, "value") ?? "")) }
            let ziel = HTML.absolut(HTML.entities(HTML.erster(#"<form[^>]*action=["']([^"']*)["']"#, f) ?? s.url), von: s.url)
            let get = (HTML.erster(#"<form[^>]*method=["']?(\w+)"#, f) ?? "").lowercased() == "get"
            s = try await anfrage(get ? ziel + (ziel.contains("?") ? "&" : "?") + HTML.kodiere(felder) : ziel, methode: get ? "GET" : "POST", kopf: ["Referer": s.url], felder: get ? nil : felder)
        }
        return s
    }

    func hostPruefen(_ url: String) throws {
        guard url.lowercased().hasPrefix("https:") else { throw IServFehler.zugangsdaten("Die Anmeldeseite ist nicht verschlüsselt – abgebrochen.") }
        let host = URL(string: url)?.host?.lowercased() ?? ""
        if host == zugang.server || erlaubteHosts.contains(host) { return }
        throw IServFehler.neuerHost(host)
    }

    /// Zweiten Faktor eingeben: selbst erzeugter Code (Schlüssel hinterlegt), sonst von Hand (nur in der App)
    func zweiterFaktor(_ start: Seite) async throws -> Seite {
        var s = start
        var quellen: [String] = []
        if !zugang.totp.isEmpty { quellen.append("erzeugt") }
        if codeAbfrage != nil { quellen += ["hand", "hand"] }
        var hinweis = ""
        for q in quellen {
            guard let f = Self.codeFormular(s.body) else { return s }
            var code = ""
            if q == "erzeugt" {
                let rest = 30 - Int(Date().timeIntervalSince1970) % 30
                if rest < 4 { try? await Task.sleep(nanoseconds: UInt64(rest + 1) * 1_000_000_000) }
                code = Self.totp(zugang.totp)
            } else {
                guard let c = await codeAbfrage?(hinweis) else { throw IServFehler.zweiFaktor("Abgebrochen") }
                code = c.filter(\.isNumber)
            }
            var felder = f.felder
            if f.ziffern.count >= 4 { for (i, n) in f.ziffern.enumerated() { felder.append((n, i < code.count ? String(Array(code)[i]) : "")) } }
            else { felder.append((f.codeFeld, code)) }
            for n in f.versteckt { felder.append((n, code)) }
            let ziel = HTML.absolut(f.action.isEmpty ? s.url : f.action, von: s.url)
            try hostPruefen(ziel)
            let antwort = try await anfrage(ziel, methode: "POST", kopf: ["Referer": s.url, "Origin": HTML.erster(#"^(https?://[^/]+)"#, s.url) ?? basis], felder: felder)
            var nach = try await autoFormulare(antwort)
            if Self.codeFormular(nach.body) == nil {
                nach = try await hole("/iserv/")
                if Self.codeFormular(nach.body) == nil { return nach }
            }
            hinweis = q == "erzeugt" ? "Der erzeugte Code wurde nicht angenommen – 2FA-Schlüssel prüfen." : "Der Code wurde nicht angenommen."
            s = nach
        }
        throw IServFehler.zweiFaktor(quellen.isEmpty ? "IServ will einen Zwei-Faktor-Code – bitte in der App eingeben oder den 2FA-Schlüssel hinterlegen." : "IServ hat den Zwei-Faktor-Code nicht angenommen.")
    }

    /// Anmeldung wie im Browser (auch mehrstufig: erst Benutzername, dann Passwort), danach ggf. zweiter Faktor
    func anmelden() async throws -> Seite {
        guard zugang.vollstaendig else { throw IServFehler.zugangsdaten("IServ-Zugang fehlt (Adresse, Benutzer, Passwort).") }
        var s = try await hole("/iserv/auth/login")
        if let sso = Self.ssoLink(s.body, von: s.url) {
            if let u = sso.url { s = try await hole(u) }
            else if let f = sso.formular {
                s = try await autoFormulare(Seite(body: f.replacingOccurrences(of: #"<input[^>]*type=["'](?!hidden)[^"']*["'][^>]*>"#, with: "", options: [.regularExpression, .caseInsensitive]), url: s.url, status: 200, typ: ""))
            }
            s = try await autoFormulare(s)
        }
        var passwortGeschickt = false
        for _ in 0..<5 {
            s = try await autoFormulare(s)
            if Self.codeFormular(s.body) != nil { s = try await zweiterFaktor(s); break }
            guard let form = Self.anmeldeFormular(s.body) else { break }
            var felder: [(String, String)] = []
            var hatPasswort = false
            for i in HTML.eingaben(form) {
                let n = HTML.name(i), t = HTML.typ(i)
                guard !n.isEmpty else { continue }
                if t == "hidden" { felder.append((n, HTML.entities(HTML.attr(i, "value") ?? ""))) }
                else if t == "password" { felder.append((n, zugang.passwort)); hatPasswort = true }
                else if ["text", "email"].contains(t), n.range(of: "user|login|name|mail|account", options: [.regularExpression, .caseInsensitive]) != nil { felder.append((n, zugang.benutzer)) }
                else if t == "checkbox", n.range(of: "remember|merken|angemeldet", options: [.regularExpression, .caseInsensitive]) != nil { felder.append((n, HTML.attr(i, "value") ?? "on")) }
            }
            if let k = HTML.erster(#"(<button[^>]*name=["'][^"']+["'][^>]*>)"#, form), HTML.typ(k) != "button" { felder.append((HTML.name(k), HTML.attr(k, "value") ?? "")) }
            if hatPasswort && passwortGeschickt { throw IServFehler.zugangsdaten("IServ hat die Anmeldung nicht angenommen – Passwort prüfen.") }
            passwortGeschickt = passwortGeschickt || hatPasswort
            let ziel = HTML.absolut(HTML.entities(HTML.erster(#"<form[^>]*action=["']([^"']*)["']"#, form) ?? s.url), von: s.url)
            try hostPruefen(ziel)
            s = try await anfrage(ziel, methode: "POST", kopf: ["Referer": s.url, "Origin": HTML.erster(#"^(https?://[^/]+)"#, s.url) ?? basis], felder: felder)
            let b = s.body
            if b.range(of: #"Anmeldung fehlgeschlagen|falsches Passwort|Passwort (ist )?(falsch|ungültig)|Benutzername oder Passwort|Invalid (credentials|username or password)|Ungültige(r)? (Benutzername|Anmelde)"#, options: [.regularExpression, .caseInsensitive]) != nil {
                throw IServFehler.zugangsdaten("IServ hat die Zugangsdaten abgelehnt.")
            }
            if b.range(of: "gesperrt|zu viele|too many", options: [.regularExpression, .caseInsensitive]) != nil, b.range(of: "anmeld|login", options: [.regularExpression, .caseInsensitive]) != nil {
                throw IServFehler.zugangsdaten("IServ hat die Anmeldung vorübergehend gesperrt – später erneut versuchen.")
            }
            s = try await autoFormulare(s)
            if !Self.istLoginSeite(s) && Self.anmeldeFormular(s.body) == nil && Self.codeFormular(s.body) == nil { break }
        }
        var start = try await hole("/iserv/")
        if Self.codeFormular(start.body) != nil { start = try await zweiterFaktor(start) }
        if Self.istLoginSeite(start) { throw IServFehler.zugangsdaten("Nach der Anmeldung wieder auf der Login-Seite – Anmeldung nicht erkannt.") }
        return start
    }

    /// Startseite mit gültiger Sitzung (meldet sich nur an, wenn nötig – spart den Zwei-Faktor-Code)
    public func startseite() async throws -> Seite {
        let s = try await hole("/iserv/")
        if Self.istLoginSeite(s) { return try await anmelden() }
        if Self.codeFormular(s.body) != nil { return try await zweiterFaktor(s) }
        return s
    }

    /// Eine Datenquelle laden; abgelaufene Sitzung → neu anmelden
    public func lade(_ q: IServQuelle) async throws -> Seite {
        let kopf = q.art == "daten" ? ["Accept": "application/json, text/html;q=0.8", "X-Requested-With": "XMLHttpRequest", "Referer": q.referer.isEmpty ? basis + "/iserv/" : q.referer] : [:]
        var s = try await hole(q.url, kopf: kopf)
        if Self.istLoginSeite(s) || Self.codeFormular(s.body) != nil {
            if Self.codeFormular(s.body) != nil { _ = try await zweiterFaktor(s) } else { _ = try await anmelden() }
            s = try await hole(q.url, kopf: kopf)
        }
        return s
    }

    /// Erkundung: Navigation → Modulseite → Datenadressen auf der Modulseite (nur lesen, nichts anklicken, was etwas ändert)
    public func erkunde<T>(muster: String, kandidaten: [String], lesen: (Seite, [String]) -> T?) async throws -> (IServQuelle, T)? {
        let start = try await startseite()
        let nav = HTML.links(start.body).compactMap { (href, t) -> String? in
            let h = HTML.entities(href)
            return (h + " " + HTML.text(t)).range(of: muster, options: [.regularExpression, .caseInsensitive]) != nil ? HTML.absolut(h, von: start.url) : nil
        }
        var gesehen = Set<String>()
        for url in (nav + kandidaten.map { basis + $0 }).filter({ !Self.aendert($0) }) where !gesehen.contains(url) && gesehen.count < 8 {
            gesehen.insert(url)
            guard let s = try? await hole(url), s.status < 400 else { continue }
            if let d = lesen(s, []) { return (IServQuelle(url: s.url, art: "direkt"), d) }
            let spalten = HTML.spalten(s.body)
            let kand = Self.datenKandidaten(s.body, von: s.url).sorted { ($0.range(of: "export|csv", options: .regularExpression) != nil ? 0 : 1) < ($1.range(of: "export|csv", options: .regularExpression) != nil ? 0 : 1) }
            for d in kand.prefix(8) where !gesehen.contains(d) {
                gesehen.insert(d)
                let q = IServQuelle(url: d, art: "daten", referer: s.url, spalten: spalten)
                guard let x = try? await lade(q), x.status < 400 else { continue }
                if let erg = lesen(x, spalten) { return (q, erg) }
            }
        }
        return nil
    }

    /// Adressen, die etwas ändern würden – nie aufrufen
    static func aendert(_ u: String) -> Bool {
        u.range(of: #"logout|abmelden|delete|loeschen|löschen|remove|/add\b|hinzu|/edit\b|bearbeit|/new\b|create|update|confirm|accept|reject|assign|toggle"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Datenadressen auf einer Modulseite (data-*, Export-Links, fetch-Pfade)
    static func datenKandidaten(_ html: String, von: String) -> [String] {
        var urls: [String] = []
        for u in HTML.alle(#"(?:data-[a-z-]*(?:url|source|src|endpoint|api)[a-z-]*|src|href|action)=["']([^"']+)["']"#, html) {
            let e = HTML.entities(u)
            if e.range(of: "json|api|list|data|export|csv|absence|abwesen|sick|krank|defect|ticket", options: [.regularExpression, .caseInsensitive]) != nil,
               e.range(of: #"\.(css|js|png|svg|ico|woff2?)(\?|$)"#, options: [.regularExpression, .caseInsensitive]) == nil { urls.append(HTML.absolut(e, von: von)) }
        }
        var gesehen = Set<String>()
        return urls.filter { !aendert($0) && gesehen.insert($0).inserted }
    }

    // MARK: TOTP (RFC 6238, SHA-1, 30 s, 6 Stellen)

    public static func base32(_ s: String) -> [UInt8] {
        let abc = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var bytes: [UInt8] = [], puffer = 0, bits = 0
        for c in s.uppercased() {
            guard let i = abc.firstIndex(of: c) else { continue }
            puffer = (puffer << 5) | i; bits += 5
            if bits >= 8 { bytes.append(UInt8((puffer >> (bits - 8)) & 255)); bits -= 8 }
        }
        return bytes
    }

    public static func totp(_ geheim: String, zeit: Date = Date()) -> String {
        #if canImport(CryptoKit)
        var zaehler = UInt64(zeit.timeIntervalSince1970 / 30).bigEndian
        let nachricht = Data(bytes: &zaehler, count: 8)
        let h = Array(HMAC<Insecure.SHA1>.authenticationCode(for: nachricht, using: SymmetricKey(data: Data(base32(geheim)))))
        let o = Int(h[19] & 15)
        let zahl = (Int(h[o] & 127) << 24) | (Int(h[o + 1]) << 16) | (Int(h[o + 2]) << 8) | Int(h[o + 3])
        return String(format: "%06d", zahl % 1_000_000)
        #else
        return ""
        #endif
    }
}

/// Kleine HTML-Werkzeuge (ohne Bibliothek – wie in den Skripten)
public enum HTML {
    /// Alle Treffer (Gruppe 1, sonst ganzer Treffer), Groß-/Kleinschreibung egal
    public static func alle(_ muster: String, _ s: String) -> [String] {
        let ns = s as NSString
        return alleI(muster, s).map { m in m.numberOfRanges > 1 && m.range(at: 1).location != NSNotFound ? ns.substring(with: m.range(at: 1)) : ns.substring(with: m.range) }
    }
    public static func erster(_ muster: String, _ s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: muster, options: [.caseInsensitive]) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let g = m.numberOfRanges > 1 && m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range
        return ns.substring(with: g)
    }
    static func alleI(_ muster: String, _ s: String) -> [NSTextCheckingResult] {
        guard let re = try? NSRegularExpression(pattern: muster, options: [.caseInsensitive]) else { return [] }
        return re.matches(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }
    public static func formulare(_ h: String) -> [String] { alleI(#"<form[\s\S]*?</form>"#, h).map { (h as NSString).substring(with: $0.range) } }
    public static func eingaben(_ f: String) -> [String] { alleI(#"<input[^>]*>"#, f).map { (f as NSString).substring(with: $0.range) } }
    public static func attr(_ tag: String, _ name: String) -> String? { erster(#"\b"# + name + #"=["']([^"']*)["']?"#, tag) }
    public static func name(_ i: String) -> String { attr(i, "name") ?? "" }
    public static func typ(_ i: String) -> String { (attr(i, "type") ?? "text").lowercased() }
    /// (href, Linktext)
    public static func links(_ h: String) -> [(String, String)] {
        let ns = h as NSString
        return alleI(#"<a\b[^>]*href=["']([^"'#][^"']*)["'][^>]*>([\s\S]*?)</a>"#, h).map { (ns.substring(with: $0.range(at: 1)), ns.substring(with: $0.range(at: 2))) }
    }
    /// Spaltenüberschriften der ersten Tabelle
    public static func spalten(_ h: String) -> [String] {
        guard let t = alleI(#"<table[\s\S]*?</table>"#, h).first.map({ (h as NSString).substring(with: $0.range) }) else { return [] }
        return alleI(#"<th[\s\S]*?</th>"#, t).map { text((t as NSString).substring(with: $0.range)) }
    }
    /// Tabellen als Zeilen von Zellen (Text) – erste Zeile = Kopf; dazu je Zeile der erste Link
    public static func tabellen(_ h: String) -> [[(zellen: [String], link: String?)]] {
        alleI(#"<table[\s\S]*?</table>"#, h).map { m in
            let t = (h as NSString).substring(with: m.range)
            return alleI(#"<tr[\s\S]*?</tr>"#, t).map { z in
                let zeile = (t as NSString).substring(with: z.range)
                let zellen = alleI(#"<t[hd][\s\S]*?</t[hd]>"#, zeile).map { text((zeile as NSString).substring(with: $0.range)) }
                return (zellen, erster(#"<a\b[^>]*href=["']([^"'#][^"']*)["']"#, zeile))
            }
        }
    }
    public static func absolut(_ href: String, von: String) -> String {
        if href.range(of: #"^https?://"#, options: [.regularExpression, .caseInsensitive]) != nil { return href }
        guard let wurzel = erster(#"^(https?://[^/]+)"#, von) else { return href }
        if href.hasPrefix("//") { return "https:" + href }
        if href.hasPrefix("/") { return wurzel + href }
        let pfad = erster(#"^https?://[^/]+(/[^?#]*)"#, von) ?? "/"
        return wurzel + pfad.replacingOccurrences(of: #"[^/]*$"#, with: "", options: .regularExpression) + href
    }
    public static func kodiere(_ f: [(String, String)]) -> String {
        var ok = CharacterSet.alphanumerics; ok.insert(charactersIn: "-._~")
        return f.map { "\($0.0.addingPercentEncoding(withAllowedCharacters: ok) ?? "")=\($0.1.addingPercentEncoding(withAllowedCharacters: ok) ?? "")" }.joined(separator: "&")
    }
    public static func entities(_ s: String) -> String { Mensa.entities(s) }
    public static func text(_ h: String) -> String { Mensa.text(h.replacingOccurrences(of: #"<br\s*/?>"#, with: " ", options: [.regularExpression, .caseInsensitive])) }

    /// CSV mit erkanntem Trenner (; Tab ,) und Anführungszeichen
    public static func csv(_ body: String) -> [[String]] {
        let zeilen = body.replacingOccurrences(of: "\u{FEFF}", with: "").components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let erste = zeilen.first else { return [] }
        let trenner: Character = [";", "\t", ","].max { erste.split(separator: $0, omittingEmptySubsequences: false).count < erste.split(separator: $1, omittingEmptySubsequences: false).count } ?? ";"
        return zeilen.map { z in
            var aus: [String] = [], feld = "", inQ = false
            let c = Array(z)
            var i = 0
            while i < c.count {
                if c[i] == "\"" { if inQ && i + 1 < c.count && c[i + 1] == "\"" { feld.append("\""); i += 1 } else { inQ.toggle() } }
                else if c[i] == trenner && !inQ { aus.append(feld); feld = "" }
                else { feld.append(c[i]) }
                i += 1
            }
            aus.append(feld)
            return aus.map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }

    /// „Mustermann, Max“ → „Max Mustermann“
    public static func nameSchoen(_ n: String) -> String {
        let t = n.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard let r = t.range(of: #"^([^,]+),\s*(.+)$"#, options: .regularExpression) else { return t }
        let teile = String(t[r]).split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        return teile.count == 2 ? "\(teile[1]) \(teile[0])" : t
    }
}
