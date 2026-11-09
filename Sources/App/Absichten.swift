import AppIntents
import MorgenKern

/// Siri und Kurzbefehle: „Guten Morgen“ (Briefing), „Gute Nacht“, „Weckzeit“
struct BriefingAbsicht: AppIntent {
    static let title: LocalizedStringResource = "Morgen-Briefing"
    static let description = IntentDescription("Wetter, Termine, Post und Vertretung – zum Vorlesen.")
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let k = Kern()
        await k.aktualisieren()
        let t = k.briefing()
        return .result(value: t, dialog: IntentDialog(stringLiteral: t))
    }
}

struct GuteNachtAbsicht: AppIntent {
    static let title: LocalizedStringResource = "Gute Nacht"
    static let description = IntentDescription("Home-Assistant-Aktionen, offene Fenster, Wecker für morgen.")
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let k = Kern()
        let t = await k.guteNacht(vorlesen: false)
        return .result(value: t, dialog: IntentDialog(stringLiteral: t))
    }
}

struct WeckzeitAbsicht: AppIntent {
    static let title: LocalizedStringResource = "Weckzeit für morgen"
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let k = Kern()
        await k.aktualisieren()
        return .result(value: k.naechsterWecker.minuten.map(Zeit.hhmm) ?? "")
    }
}

struct MorgenKurzbefehle: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: BriefingAbsicht(), phrases: ["Guten Morgen mit \(.applicationName)", "\(.applicationName) Briefing"], shortTitle: "Briefing", systemImageName: "sun.max.fill")
        AppShortcut(intent: GuteNachtAbsicht(), phrases: ["Gute Nacht mit \(.applicationName)"], shortTitle: "Gute Nacht", systemImageName: "moon.stars.fill")
    }
}
