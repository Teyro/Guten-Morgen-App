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

    /// Weckzeit nach Home Assistant melden (sensor.guten_morgen_wecker, Zeitstempel) – daran hängt die Morgenroutine.
    /// nil = kein Wecker („unknown“). Der Sensor lebt nur bis zum nächsten HA-Neustart; die App meldet ihn bei jedem Aktualisieren neu.
    @discardableResult
    public func weckzeitMelden(_ datum: Date?) async -> Bool {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = Zeit.kalender.timeZone
        let koerper: [String: Any] = ["state": datum.map { f.string(from: $0) } ?? "unknown",
                                      "attributes": ["device_class": "timestamp", "friendly_name": "Guten Morgen – Wecker", "icon": "mdi:alarm"]]
        do { _ = try await anfrage("/api/states/\(Routine.sensor)", koerper: koerper); return true } catch { return false }
    }

    /// Automation „Guten Morgen – Morgenroutine“ in Home Assistant anlegen bzw. ersetzen (leer = löschen)
    public func routineEinrichten(_ schritte: [RoutinenSchritt]) async throws {
        guard eingerichtet, let url = URL(string: basis + "/api/config/automation/config/\(Routine.id)") else { throw URLError(.userAuthenticationRequired) }
        let k = ["Authorization": "Bearer \(token)", "Content-Type": "application/json"]
        let (_, s): (Data, Int)
        if schritte.isEmpty {
            (_, s) = try await Netz.daten(url, methode: "DELETE", kopf: k)
            guard (200..<300).contains(s) || s == 404 || s == 400 else { throw URLError(.badServerResponse) }
            return
        }
        (_, s) = try await Netz.daten(url, methode: "POST", kopf: k, koerper: try JSONSerialization.data(withJSONObject: Routine.automation(schritte)))
        if s == 401 || s == 403 { throw URLError(.userAuthenticationRequired) }
        guard (200..<300).contains(s) else { throw URLError(.badServerResponse) }
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

/// Morgenroutine als Home-Assistant-Automation: je Schritt ein Zeit-Auslöser relativ zum Wecker-Sensor
public enum Routine {
    public static let sensor = "sensor.guten_morgen_wecker"
    public static let id = "guten_morgen_routine"

    /// „-00:20:00“ für 20 Minuten vorher, „00:05:00“ für 5 Minuten danach
    public static func versatz(_ minuten: Int) -> String {
        let m = abs(minuten)
        return (minuten < 0 ? "-" : "") + String(format: "%02d:%02d:00", m / 60, m % 60)
    }

    public static func automation(_ schritte: [RoutinenSchritt]) -> [String: Any] {
        var ausloeser: [[String: Any]] = []
        var wahl: [[String: Any]] = []
        for (i, s) in schritte.enumerated() {
            let kennung = "schritt\(i)"
            ausloeser.append(["trigger": "time", "at": ["entity_id": sensor, "offset": versatz(s.minuten)], "id": kennung])
            var aktion: [String: Any] = ["action": s.dienst]
            let ziel = s.ziel.trimmingCharacters(in: .whitespaces)
            if !ziel.isEmpty { aktion["target"] = ["entity_id": ziel] }
            if s.dienst == "light.turn_on" && s.langsam > 0 { aktion["data"] = ["transition": s.langsam, "brightness_pct": 100] }
            wahl.append(["conditions": [["condition": "trigger", "id": kennung]], "sequence": [aktion]])
        }
        return [
            "alias": "Guten Morgen – Morgenroutine",
            "description": "Angelegt von der App „Guten Morgen“. Die Zeiten richten sich nach dem Wecker (\(sensor)). Ändern bitte in der App – sie überschreibt diese Automation.",
            "mode": "parallel",
            "triggers": ausloeser,
            "conditions": [],
            "actions": [["choose": wahl]],
        ]
    }
}
