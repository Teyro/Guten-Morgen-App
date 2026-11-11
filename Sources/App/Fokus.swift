import AppIntents
import MorgenKern

/// Fokus-Filter: Im Fokus „Schule“ zeigt Guten Morgen die Schul-Infos zuerst.
/// Den Fokus selbst schaltet iOS nach Ort oder Zeit ein (Einstellungen → Fokus → Schule → Zeitplan → Ort) –
/// Apps dürfen einen Fokus nicht selbst einschalten.
struct SchulFokusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Guten Morgen"
    static let description: IntentDescription? = "Im Fokus die Schul-Infos (Stunden, Vertretung, Aufsicht) zuerst zeigen."

    /// Standard aus: Ohne aktiven Fokus liefert iOS die Standardwerte – dann gilt wie sonst der Standort
    @Parameter(title: "Schul-Infos zuerst", default: false)
    var schule: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: schule ? "Schul-Infos zuerst" : "wie sonst (nach Standort)")
    }

    func perform() async throws -> some IntentResult {
        await MainActor.run { NotificationCenter.default.post(name: .fokusGeaendert, object: nil) }
        return .result()
    }

    /// true = gerade ein Fokus mit „Schul-Infos zuerst“ aktiv
    static func schuleAktiv() async -> Bool { (try? await SchulFokusFilter.current)?.schule ?? false }
}

extension Notification.Name {
    static let fokusGeaendert = Notification.Name("fokusGeaendert")
}
