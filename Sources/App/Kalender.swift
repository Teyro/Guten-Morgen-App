import EventKit
import MorgenKern

/// Termine und Erinnerungen (EventKit)
@MainActor
final class Kalender {
    let speicher = EKEventStore()

    func erlauben() async {
        _ = try? await speicher.requestFullAccessToEvents()
        _ = try? await speicher.requestFullAccessToReminders()
    }

    var termineErlaubt: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func termine(von: Date, tage: Int) -> [Termin] {
        guard termineErlaubt else { return [] }
        let bis = Zeit.kalender.date(byAdding: .day, value: tage, to: von) ?? von
        let p = speicher.predicateForEvents(withStart: von, end: bis, calendars: nil)
        return Termin.ohneDoppelte(speicher.events(matching: p).map { Termin(titel: $0.title ?? "Termin", start: $0.startDate, ganztags: $0.isAllDay) })
    }

    func erinnerungenHeute() async -> [String] {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return [] }
        let k = Zeit.kalender
        let ende = k.date(byAdding: .day, value: 1, to: k.startOfDay(for: Date())) ?? Date()
        let p = speicher.predicateForIncompleteReminders(withDueDateStarting: nil, ending: ende, calendars: nil)
        return await withCheckedContinuation { (c: CheckedContinuation<[String], Never>) in
            speicher.fetchReminders(matching: p) { r in c.resume(returning: (r ?? []).compactMap(\.title)) }
        }
    }
}
