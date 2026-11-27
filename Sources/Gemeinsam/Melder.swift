import Foundation
import UserNotifications
import MorgenKern

/// Mitteilungen bei neuen Störungsmeldungen und neuen bzw. verschobenen Edupool-Aufgaben.
/// Geprüft wird beim Laden im Widget (läuft regelmäßig im Hintergrund); beim allerersten Mal wird nur gemerkt.
enum Melder {
    /// [vertretung]: Plan prüfen (siehe VertretungsMeldung); [planDa] = melden, sobald der Plan für einen neuen Tag da ist,
    /// [betrifft] = melden, wenn sich die eigenen Einträge ändern, [dringend] = zeitkritisch (kommt auch im Fokus durch).
    static func pruefen(stoerungen: StoerungenStand?, aufgaben: AufgabenStand?, vertretung: VertretungsPlan? = nil,
                        planDa: Bool = false, betrifft: Bool = false, dringend: Bool = false, _ d: UserDefaults = .standard) {
        // Merkstand in der App Group: App und Widget prüfen beide – so meldet nur, wer es zuerst sieht
        if let v = vertretung, planDa || betrifft {
            let g = MorgenAblage.defaults
            if let r = VertretungsMeldung.pruefen(v, altDatum: g.string(forKey: "gemeldetPlanDatum"), altSig: g.string(forKey: "gemeldetVertretung"),
                                                  planDa: planDa, betrifft: betrifft) {
                g.set(r.datum, forKey: "gemeldetPlanDatum")
                g.set(r.sig, forKey: "gemeldetVertretung")
                if let m = r.meldung { melde(id: m.id, titel: m.titel, text: m.text, link: Marke.link("vertretung"), dringend: dringend) }
            }
        }
        if let s = stoerungen {
            let jetzt = s.offen.map { $0.titel + "|" + ($0.datum.map { String(Int($0.timeIntervalSince1970)) } ?? "") }
            let neu = vergleiche(jetzt, schluessel: "gemeldetStoerungen", d)
            for m in s.offen where neu.contains(m.titel + "|" + (m.datum.map { String(Int($0.timeIntervalSince1970)) } ?? "")) {
                melde(id: "stoerung-\(stabil(m.titel))", titel: "Neue Störung" + (m.ort.isEmpty ? "" : " · \(m.ort)"),
                      text: m.titel + (m.autor.isEmpty ? "" : " (von \(m.autor))"), link: Marke.link("stoerungen"))
            }
            // Zustand geändert: übernommen, anderer Bearbeiter, erledigt
            let zustaende = Dictionary(s.meldungen.map { ($0.titel + "|" + ($0.datum.map { String(Int($0.timeIntervalSince1970)) } ?? ""), $0.zustand) }, uniquingKeysWith: { a, _ in a })
            if let alt = d.dictionary(forKey: "zustandStoerungen") as? [String: String] {
                for m in s.meldungen {
                    let k = m.titel + "|" + (m.datum.map { String(Int($0.timeIntervalSince1970)) } ?? "")
                    guard let vorher = alt[k], vorher != m.zustand else { continue }
                    melde(id: "stoerung-\(stabil(k + m.zustand))", titel: m.erledigt ? "Störung erledigt" : "Störung: \(m.zustand)",
                          text: m.titel + (m.ort.isEmpty ? "" : " · \(m.ort)"), link: Marke.link("stoerungen"))
                }
            }
            d.set(zustaende, forKey: "zustandStoerungen")
        }
        if let a = aufgaben {
            let jetzt = a.aufgaben.map { "\($0.id)|\($0.kategorie)" }
            let neu = vergleiche(jetzt, schluessel: "gemeldetAufgaben", d)
            for x in a.aufgaben where neu.contains("\(x.id)|\(x.kategorie)") {
                let kat = Aufgaben.kategorien[x.kategorie].name
                melde(id: "aufgabe-\(x.id)", titel: kat == "Erledigt" ? "Aufgabe erledigt" : "Aufgabe · \(kat)", text: x.titel, link: Marke.link("aufgaben"))
            }
            // Neue Kommentare an deinen Karten (Anzahl gestiegen)
            let zahlen = Dictionary(a.aufgaben.compactMap { x in x.kommentarAnzahl.map { (x.id, $0) } }, uniquingKeysWith: { a, _ in a })
            if let alt = d.dictionary(forKey: "kommentareAufgaben") as? [String: Int] {
                for x in a.aufgaben {
                    guard let n = zahlen[x.id], let vorher = alt[x.id], n > vorher else { continue }
                    melde(id: "kommentar-\(x.id)-\(n)", titel: n - vorher == 1 ? "Neuer Kommentar" : "\(n - vorher) neue Kommentare", text: x.titel, link: Marke.link("aufgaben"))
                }
            }
            d.set(zahlen, forKey: "kommentareAufgaben")
        }
    }

    /// Neue Chat-Nachrichten: in der Schule/unterwegs sofort je Nachricht, zu Hause gesammelt als eine Zusammenfassung am Abend.
    /// Merkstand in der App-Gruppe; gleiche Nachricht = gleiche Mitteilungs-ID, falls App und Widget beide melden.
    static func chat(_ e: MorgenEinstellungen, geheim: Geheimnisse, hier: Kontext.Ort?, frei: [FreierTag]) async {
        let teile = geheim.matrix.split(separator: "\t", maxSplits: 1).map(String.init)
        guard teile.count == 2 else { return }
        let g = MorgenAblage.defaults, m = Matrix(token: teile[1], ich: teile[0])
        guard let j = try? await m.sync(seit: g.string(forKey: "chatWeiter") ?? "") else { return }
        let erstes = g.string(forKey: "chatWeiter") == nil
        g.set(j["next_batch"] as? String, forKey: "chatWeiter")
        var namen = g.dictionary(forKey: "chatNamen") as? [String: String] ?? [:]
        let neu = ChatMelden.neue(j, ich: m.ich, namen: &namen)
        g.set(namen, forKey: "chatNamen")
        guard !erstes, !neu.isEmpty else { return } // beim ersten Mal nur merken
        if ChatMelden.art(frei: frei, hier: hier, zuhause: e.zuhauseOrt) == .sofort {
            for n in neu { melde(id: "chat-\(n.id)", titel: n.raum, text: (n.raum == n.absender ? "" : "\(n.absender): ") + n.text, link: Marke.link("chat")) }
            return
        }
        var gesammelt = g.dictionary(forKey: "chatGesammelt") as? [String: Int] ?? [:]
        for n in neu { gesammelt[n.raum, default: 0] += 1 }
        g.set(gesammelt, forKey: "chatGesammelt")
        let z = ChatMelden.zusammenfassung(gesammelt)
        let c = UNMutableNotificationContent()
        c.title = z.titel; c.body = z.text; c.sound = .default; c.userInfo = ["link": Marke.link("chat")]; c.threadIdentifier = Marke.link("chat")
        let k = Zeit.kalender.dateComponents([.year, .month, .day, .hour, .minute], from: ChatMelden.zeitpunkt(e.chatZusammenfassung))
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "chat-zusammenfassung", content: c,
                                                                              trigger: UNCalendarNotificationTrigger(dateMatching: k, repeats: false)))
    }

    /// Chat geöffnet: Gesammeltes und die anstehende Zusammenfassung verwerfen
    static func chatGelesen() {
        MorgenAblage.defaults.removeObject(forKey: "chatGesammelt")
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["chat-zusammenfassung"])
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

    private static func melde(id: String, titel: String, text: String, link: String, dringend: Bool = false) {
        let c = UNMutableNotificationContent()
        // zeitkritisch: durchbricht Fokus und Zusammenfassung (braucht das Recht „Time Sensitive“; fehlt es, kommt sie normal)
        if dringend { c.interruptionLevel = .timeSensitive }
        c.title = titel
        c.body = text
        c.sound = .default
        c.userInfo = ["link": link]
        c.threadIdentifier = link
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    /// Neue Version auf GitHub: einmal je Version melden (Tippen öffnet die Release-Seite mit der IPA)
    static func neueVersion(_ v: String) {
        let d = UserDefaults.standard
        guard d.string(forKey: "updateGemeldet") != v else { return }
        d.set(v, forKey: "updateGemeldet")
        melde(id: "update-\(v)", titel: "\(Marke.name) \(v) ist da", text: "Tippen öffnet die neue IPA – in Signulous neu signieren und installieren.",
              link: "https://github.com/Teyro/Guten-Morgen-App/releases/latest")
    }

    static func erlauben() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
}
