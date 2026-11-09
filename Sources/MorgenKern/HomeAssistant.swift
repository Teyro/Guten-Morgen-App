import Foundation

public struct HomeAssistant: Sendable {
    public let basis: String
    public let token: String
    public init(adresse: String, token: String) {
        var b = adresse.trimmingCharacters(in: .whitespacesAndNewlines)
        while b.hasSuffix("/") { b.removeLast() }
        basis = b
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public var eingerichtet: Bool { !basis.isEmpty && !token.isEmpty && URL(string: basis) != nil }

    private func anfrage(_ pfad: String, koerper: [String: Any]? = nil) async throws -> Any {
        guard eingerichtet, let url = URL(string: basis + pfad) else { throw URLError(.userAuthenticationRequired) }
        let k = ["Authorization": "Bearer \(token)", "Content-Type": "application/json"]
        return try await Netz.json(url, methode: koerper == nil ? "GET" : "POST", kopf: k, koerper: koerper.flatMap { try? JSONSerialization.data(withJSONObject: $0) })
    }

    /// Aktion ausführen (z. B. light.turn_off auf all); true = geklappt
    public func ausfuehren(_ a: HAAktion) async -> Bool {
        let teile = a.dienst.split(separator: ".")
        guard teile.count == 2 else { return false }
        let ziel = a.ziel.trimmingCharacters(in: .whitespaces)
        do {
            _ = try await anfrage("/api/services/\(teile[0])/\(teile[1])", koerper: ziel.isEmpty ? [:] : ["entity_id": ziel])
            return true
        } catch { return false }
    }

    /// Post und Pakete von heute (Integration „Briefankündigung“, Aktion briefankuendigung.heute) – "" wenn nichts kommt
    public func postHeute() async -> String {
        guard let j = try? await anfrage("/api/services/briefankuendigung/heute?return_response", koerper: [:]) as? [String: Any] else { return "" }
        let r = j["service_response"] as? [String: Any] ?? j
        let pakete = (r["pakete_heute"] as? NSNumber)?.intValue ?? 0, briefe = (r["briefe_heute"] as? NSNumber)?.intValue ?? 0
        guard pakete + briefe > 0 else { return "" }
        var t = r["text"] as? String ?? ""
        if let bereich = t.range(of: #" Unterwegs sind \d+\.$"#, options: .regularExpression) { t.removeSubrange(bereich) }
        return t
    }

    /// Offene Fenster/Türen (binary_sensor mit device_class window/door/opening, Zustand on) – Namen
    public func offeneFenster() async -> [String] {
        guard let liste = try? await anfrage("/api/states") as? [[String: Any]] else { return [] }
        return liste.compactMap { s in
            guard let id = s["entity_id"] as? String, id.hasPrefix("binary_sensor."), s["state"] as? String == "on",
                  let a = s["attributes"] as? [String: Any], ["window", "door", "opening", "garage_door"].contains(a["device_class"] as? String ?? "") else { return nil }
            return a["friendly_name"] as? String ?? id
        }
    }
}
