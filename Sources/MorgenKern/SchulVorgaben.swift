import Foundation
#if canImport(CryptoKit)
import CryptoKit
import CommonCrypto
#endif

/// Die eingebauten Zugangsdaten der Schule (Vertretungsplan-Ordner, Mensa-Portal, Obst-Kalender, Untis-Schule, IServ …).
/// Liegen verschlüsselt im öffentlichen Repo (schule/vorgaben.enc) – der Schlüssel ist der Schul-Code (das Passwort
/// des Schul-Ordners), den alle Kolleg:innen kennen. Persönliche Zugänge (Mensa-Benutzer, Untis, IServ) sind nicht dabei.
public struct SchulVorgaben: Codable, Equatable, Sendable {
    public var vertretungLink = ""
    public var freigabe = ""
    public var schulOrdner = ""
    public var mensaAdresse = ""
    public var obstKalender = ""
    public var schulKalender = ""
    public var iservServer = ""
    public var untisLink = ""
    public var untisSchule = ""
    public var bundesland = ""
    public var haeuser: [String: [String]] = [:]
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func w(_ k: CodingKeys) -> String { (try? c.decodeIfPresent(String.self, forKey: k)) ?? nil ?? "" }
        vertretungLink = w(.vertretungLink); freigabe = w(.freigabe); schulOrdner = w(.schulOrdner); mensaAdresse = w(.mensaAdresse)
        obstKalender = w(.obstKalender); schulKalender = w(.schulKalender); iservServer = w(.iservServer); untisLink = w(.untisLink)
        untisSchule = w(.untisSchule); bundesland = w(.bundesland)
        haeuser = (try? c.decodeIfPresent([String: [String]].self, forKey: .haeuser)) ?? nil ?? [:]
    }

    public static let quelle = URL(string: "https://raw.githubusercontent.com/Teyro/Guten-Morgen-App/main/schule/vorgaben.enc")!

    public enum Fehler: LocalizedError {
        case falscherCode, kaputt
        public var errorDescription: String? {
            switch self {
            case .falscherCode: return "Der Schul-Code stimmt nicht."
            case .kaputt: return "Die Vorgaben der Schule konnten nicht gelesen werden."
            }
        }
    }

    /// Hülle: {"v":1,"runden":N,"salz":base64,"daten":base64(nonce 12 | text | tag 16)} – AES-256-GCM, Schlüssel per PBKDF2-SHA256
    struct Huelle: Codable { var v: Int; var runden: Int; var salz: String; var daten: String }

    #if canImport(CryptoKit)
    static func schluessel(_ code: String, salz: Data, runden: Int) -> SymmetricKey {
        var aus = [UInt8](repeating: 0, count: 32)
        let pw = Array(code.utf8)
        _ = salz.withUnsafeBytes { s in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), code, pw.count, s.bindMemory(to: UInt8.self).baseAddress, salz.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(runden), &aus, 32)
        }
        return SymmetricKey(data: aus)
    }

    public static func entschluesseln(_ daten: Data, code: String) throws -> SchulVorgaben {
        guard let h = try? JSONDecoder().decode(Huelle.self, from: daten), h.v == 1,
              let salz = Data(base64Encoded: h.salz), let inhalt = Data(base64Encoded: h.daten) else { throw Fehler.kaputt }
        let k = schluessel(code.trimmingCharacters(in: .whitespacesAndNewlines), salz: salz, runden: h.runden)
        guard let box = try? AES.GCM.SealedBox(combined: inhalt), let klar = try? AES.GCM.open(box, using: k) else { throw Fehler.falscherCode }
        guard let v = try? JSONDecoder().decode(SchulVorgaben.self, from: klar) else { throw Fehler.kaputt }
        return v
    }

    public static func laden(code: String) async throws -> SchulVorgaben {
        var r = URLRequest(url: quelle); r.cachePolicy = .reloadIgnoringLocalCacheData; r.timeoutInterval = 20
        let (d, a) = try await URLSession.shared.data(for: r)
        guard (a as? HTTPURLResponse)?.statusCode == 200 else { throw Fehler.kaputt }
        return try entschluesseln(d, code: code)
    }
    #endif

    /// In die Einstellungen übernehmen (nur Schul-weite Werte, nichts Persönliches); Rückgabe: Freigabe- und Schul-Ordner-Passwort
    public func anwenden(_ e: inout MorgenEinstellungen) -> (freigabe: String, schulOrdner: String) {
        if !vertretungLink.isEmpty { e.vertretungLink = vertretungLink }
        if !mensaAdresse.isEmpty { e.mensaAdresse = mensaAdresse }
        if !obstKalender.isEmpty { e.obstKalender = obstKalender }
        if !schulKalender.isEmpty { e.schulKalender = schulKalender }
        if !iservServer.isEmpty { e.iservServer = IServ.bereinige(iservServer) }
        if !untisLink.isEmpty { e.untisLink = untisLink }
        if !untisSchule.isEmpty { e.untisSchule = untisSchule }
        if !bundesland.isEmpty { e.bundesland = bundesland }
        if !haeuser.isEmpty { e.haeuser = haeuser }
        return (freigabe, schulOrdner)
    }
}
