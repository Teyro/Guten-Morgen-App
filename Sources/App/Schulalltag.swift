import Foundation
import MapKit
import UserNotifications
import BackgroundTasks
import MorgenKern
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Fahrzeit zur Schule über Apple Karten (ohne Schlüssel): Auto mit Verkehrsprognose, Bus und Bahn nach Fahrplan, zu Fuß
enum Fahrt {
    static func minuten(von: Kontext.Ort, nach: Kontext.Ort, art: String, ankunft: Date) async -> Int? {
        let r = MKDirections.Request()
        r.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: von.lat, longitude: von.lon)))
        r.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: nach.lat, longitude: nach.lon)))
        switch art {
        case "oepnv": r.transportType = .transit; r.arrivalDate = ankunft
        case "fuss": r.transportType = .walking
        default: r.transportType = .automobile; r.departureDate = ankunft.addingTimeInterval(-45 * 60)
        }
        guard let eta = try? await MKDirections(request: r).calculateETA() else { return nil }
        return Int((eta.expectedTravelTime / 60).rounded(.up))
    }
}

/// Mitteilung 5 Minuten vor jeder Hofaufsicht des Schultags
enum AufsichtErinnerung {
    static func planen(_ bloecke: [Block], an: Bool) async {
        let c = UNUserNotificationCenter.current()
        let alt = await c.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("aufsicht-") }
        c.removePendingNotificationRequests(withIdentifiers: alt)
        guard an else { return }
        let aufsichten = bloecke.filter { $0.art == .aufsicht && $0.von.addingTimeInterval(-300) > Date() }
        guard !aufsichten.isEmpty else { return }
        _ = try? await c.requestAuthorization(options: [.alert, .sound])
        for b in aufsichten {
            let i = UNMutableNotificationContent()
            i.title = b.text.hasPrefix("Reserve") ? "Reserve-Aufsicht in 5 Minuten" : "Hofaufsicht in 5 Minuten"
            i.body = "\(b.titel): \(b.text.replacingOccurrences(of: "Aufsicht ", with: "").replacingOccurrences(of: "Reserve ", with: ""))"
            i.sound = .default
            i.userInfo = ["link": "gutenmorgen://vertretung"]
            let z = Zeit.kalender.dateComponents([.year, .month, .day, .hour, .minute], from: b.von.addingTimeInterval(-300))
            try? await c.add(UNNotificationRequest(identifier: "aufsicht-\(Int(b.von.timeIntervalSince1970))", content: i,
                                                   trigger: UNCalendarNotificationTrigger(dateMatching: z, repeats: false)))
        }
    }
}

/// Live-Aktivität im Schulalltag: von einer Stunde vor dem ersten bis zum letzten Abschnitt
enum Schulalltag {
    @MainActor
    static func aktualisieren(_ bloecke: [Block], an: Bool) async {
        #if canImport(ActivityKit)
        let jetzt = Date()
        let laufend = Activity<SchulTagAktivitaet>.activities
        guard an, ActivityAuthorizationInfo().areActivitiesEnabled, let erst = bloecke.first?.von, let letzt = bloecke.last?.bis,
              jetzt >= erst.addingTimeInterval(-3600), jetzt < letzt else {
            for a in laufend { await a.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let (j, d) = Stundenplan.jetzt(bloecke, jetzt)
        // veraltet, sobald der laufende Abschnitt endet → das System zeichnet neu (und zeigt den nächsten)
        let inhalt = ActivityContent(state: SchulTagAktivitaet.ContentState(bloecke: bloecke), staleDate: j?.bis ?? d?.von ?? letzt, relevanceScore: 60)
        let tag = Zeit.iso(jetzt)
        if let a = laufend.first(where: { $0.attributes.datum == tag }) {
            await a.update(inhalt)
            for b in laufend where b.id != a.id { await b.end(nil, dismissalPolicy: .immediate) }
        } else {
            for a in laufend { await a.end(nil, dismissalPolicy: .immediate) }
            _ = try? Activity.request(attributes: SchulTagAktivitaet(datum: tag), content: inhalt)
        }
        #endif
    }
}

/// Hintergrund: vor dem Wecken Fahrzeit und Wetter prüfen (früher wecken), im Schulalltag die Live-Aktivität weiterschalten
enum Hintergrund {
    static let kennung = "de.teyro.gutenmorgen.aktualisieren"

    @MainActor
    static func anmelden(_ kern: Kern) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: kennung, using: nil) { aufgabe in
            let arbeit = Task { @MainActor in
                await kern.aktualisieren()
                aufgabe.setTaskCompleted(success: true)
            }
            aufgabe.expirationHandler = { arbeit.cancel() }
        }
    }

    /// Nächster Lauf: zum nächsten Wechsel im Schultag, sonst 70 Minuten vor dem Wecker
    static func planen(wecker: Date?, bloecke: [Block]) {
        let jetzt = Date()
        var ziele = Stundenplan.wechsel(bloecke).filter { $0 > jetzt }
        if let w = wecker?.addingTimeInterval(-70 * 60), w > jetzt { ziele.append(w) }
        guard let ziel = ziele.min() else { return }
        let r = BGAppRefreshTaskRequest(identifier: kennung)
        r.earliestBeginDate = ziel
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: kennung)
        try? BGTaskScheduler.shared.submit(r)
    }
}
