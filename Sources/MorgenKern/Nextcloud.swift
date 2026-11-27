import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Nextcloud der Schule über WebDAV: Ordner auflisten und Dateien laden (z. B. die Fußballplatz-Pläne in „DammAPP“).
public struct Nextcloud: Sendable {
    public var server: String
    public var benutzer: String
    public var passwort: String
    public init(server: String, benutzer: String, passwort: String) { self.server = server; self.benutzer = benutzer; self.passwort = passwort }

    public struct Datei: Hashable, Sendable, Codable {
        public var name: String
        public var etag: String
        public var groesse: Int
        public var ordner: Bool
    }

    public enum Fehler: LocalizedError {
        case text(String)
        public var errorDescription: String? { if case .text(let t) = self { return t }; return nil }
    }

    /// WebDAV-Adresse einer Datei/eines Ordners (Ordnernamen mit Umlauten werden kodiert)
    func url(_ pfad: String) -> URL? {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if !s.hasPrefix("http") { s = "https://" + s }
        let teile = ([benutzer] + pfad.split(separator: "/").map(String.init)).map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? $0 }
        return URL(string: s + "/remote.php/dav/files/" + teile.joined(separator: "/"))
    }

    private func anfrage(_ u: URL, methode: String = "GET") -> URLRequest {
        var r = URLRequest(url: u, timeoutInterval: 30)
        r.httpMethod = methode
        r.setValue("Basic " + Data("\(benutzer):\(passwort)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        return r
    }

    private static func pruefen(_ a: URLResponse, _ was: String) throws {
        let c = (a as? HTTPURLResponse)?.statusCode ?? 0
        if c == 401 { throw Fehler.text("Nextcloud: App-Passwort falsch.") }
        if c == 404 { throw Fehler.text("Nextcloud: \(was) fehlt.") }
        guard (200..<300).contains(c) else { throw Fehler.text("Nextcloud nicht erreichbar (HTTP \(c)).") }
    }

    /// Inhalt eines Ordners (ohne den Ordner selbst)
    public func liste(_ pfad: String) async throws -> [Datei] {
        guard let u = url(pfad) else { throw Fehler.text("Nextcloud-Adresse ungültig.") }
        var r = anfrage(u, methode: "PROPFIND")
        r.setValue("1", forHTTPHeaderField: "Depth")
        r.httpBody = Data(#"<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:getetag/><d:getcontentlength/><d:resourcetype/></d:prop></d:propfind>"#.utf8)
        let (d, a) = try await URLSession.shared.data(for: r)
        try Self.pruefen(a, "Ordner „\(pfad)“")
        return Self.lesen(String(decoding: d, as: UTF8.self))
    }

    /// PROPFIND-Antwort → Dateien (der erste Eintrag ist der Ordner selbst)
    static func lesen(_ xml: String) -> [Datei] {
        guard let re = try? NSRegularExpression(pattern: #"<(?:d|D):response>([\s\S]*?)</(?:d|D):response>"#) else { return [] }
        let ns = xml as NSString
        return re.matches(in: xml, range: NSRange(location: 0, length: ns.length)).dropFirst().compactMap { m in
            let r = ns.substring(with: m.range(at: 1))
            guard let href = HTML.erster(#"<(?:d|D):href>([\s\S]*?)</"#, r) else { return nil }
            let name = (href.removingPercentEncoding ?? href).split(separator: "/").last.map(String.init) ?? ""
            let etag = HTML.entities(HTML.erster(#"<(?:d|D):getetag>([\s\S]*?)</"#, r) ?? "").replacingOccurrences(of: "\"", with: "")
            let groesse = Int(HTML.erster(#"<(?:d|D):getcontentlength>(\d+)</"#, r) ?? "") ?? 0
            return Datei(name: name, etag: etag, groesse: groesse, ordner: r.contains("collection"))
        }
    }

    /// Datei laden
    public func laden(_ pfad: String) async throws -> Data {
        guard let u = url(pfad) else { throw Fehler.text("Nextcloud-Adresse ungültig.") }
        let (d, a) = try await URLSession.shared.data(for: anfrage(u))
        try Self.pruefen(a, "„\(pfad)“")
        return d
    }

    /// Ordner der Fußballplatz-Pläne
    public static let planOrdner = "DammAPP"

    /// Lesbarer Name: „Fußballplatz_Haus1_Pausenbelegung.pdf“ → „Haus 1“, „…_TH_…“ → „Turnhalle“
    public static func planName(_ datei: String) -> String {
        var n = (datei as NSString).deletingPathExtension
        for weg in ["Fußballplatz", "Fussballplatz", "Pausenbelegung"] { n = n.replacingOccurrences(of: weg, with: "", options: .caseInsensitive) }
        n = n.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        n = n.replacingOccurrences(of: #"(?i)^haus\s*(\d)"#, with: "Haus $1", options: .regularExpression)
        if n.uppercased() == "TH" { n = "Turnhalle" }
        return n.isEmpty ? datei : n
    }
}
