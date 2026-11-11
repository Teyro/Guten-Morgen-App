import Foundation
import UserNotifications
import MorgenKern

/// Mitteilungen bei neuen Störungsmeldungen und neuen bzw. verschobenen Edupool-Aufgaben.
/// Geprüft wird beim Laden im Widget (läuft regelmäßig im Hintergrund); beim allerersten Mal wird nur gemerkt.
enum Melder {
    static func pruefen(stoerungen: StoerungenStand?, aufgaben: AufgabenStand?, _ d: UserDefaults = .standard) {
        if let s = stoerungen {
            let jetzt = s.offen.map { $0.titel + "|" + ($0.datum.map { String(Int($0.timeIntervalSince1970)) } ?? "") }
            let neu = vergleiche(jetzt, schluessel: "gemeldetStoerungen", d)
            for m in s.offen where neu.contains(m.titel + "|" + (m.datum.map { String(Int($0.timeIntervalSince1970)) } ?? "")) {
                melde(id: "stoerung-\(stabil(m.titel))", titel: "Neue Störung" + (m.ort.isEmpty ? "" : " · \(m.ort)"),
                      text: m.titel + (m.autor.isEmpty ? "" : " (von \(m.autor))"), link: "gutenmorgen://stoerungen")
            }
            // Zustand geändert: übernommen, anderer Bearbeiter, erledigt
            let zustaende = Dictionary(s.meldungen.map { ($0.titel + "|" + ($0.datum.map { String(Int($0.timeIntervalSince1970)) } ?? ""), $0.zustand) }, uniquingKeysWith: { a, _ in a })
            if let alt = d.dictionary(forKey: "zustandStoerungen") as? [String: String] {
                for m in s.meldungen {
                    let k = m.titel + "|" + (m.datum.map { String(Int($0.timeIntervalSince1970)) } ?? "")
                    guard let vorher = alt[k], vorher != m.zustand else { continue }
                    melde(id: "stoerung-\(stabil(k + m.zustand))", titel: m.erledigt ? "Störung erledigt" : "Störung: \(m.zustand)",
                          text: m.titel + (m.ort.isEmpty ? "" : " · \(m.ort)"), link: "gutenmorgen://stoerungen")
                }
            }
            d.set(zustaende, forKey: "zustandStoerungen")
        }
        if let a = aufgaben {
            let jetzt = a.aufgaben.map { "\($0.id)|\($0.kategorie)" }
            let neu = vergleiche(jetzt, schluessel: "gemeldetAufgaben", d)
            for x in a.aufgaben where neu.contains("\(x.id)|\(x.kategorie)") {
                let kat = Aufgaben.kategorien[x.kategorie].name
                melde(id: "aufgabe-\(x.id)", titel: kat == "Erledigt" ? "Aufgabe erledigt" : "Aufgabe · \(kat)", text: x.titel, link: "gutenmorgen://aufgaben")
            }
        }
    }

    /// Was ist neu gegenüber dem letzten Stand? Erster Lauf: nichts (nur merken).
    private static func vergleiche(_ jetzt: [String], schluessel: String, _ d: UserDefaults) -> Set<String> {
        let alt = d.stringArray(forKey: schluessel)
        d.set(Array(Set(jetzt)), forKey: schluessel)
        guard let alt else { return [] }
        return Set(jetzt).subtracting(alt)
    }

    /// Gleiche Eingabe → gleiche Zahl in App und Widget (hashValue ist je Prozess anders) – gleiche Mitteilung ersetzt sich
    private static func stabil(_ s: String) -> UInt64 { s.utf8.reduce(5381) { ($0 << 5) &+ $0 &+ UInt64($1) } }

    private static func melde(id: String, titel: String, text: String, link: String) {
        let c = UNMutableNotificationContent()
        c.title = titel
        c.body = text
        c.sound = .default
        c.userInfo = ["link": link]
        c.threadIdentifier = link
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    static func erlauben() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
}
