import Foundation
import WidgetKit
import MorgenKern
#if os(iOS)
import ActivityKit

/// Übergabe von Einstellungen und Home-Assistant-Token an das Widget, wenn die Signatur (z. B. Signulous) keine
/// App-Gruppe erlaubt: Die App zeigt kurz diese Live-Aktivität; beim Zeichnen merkt sich die Widget-Erweiterung alles.
struct MorgenUebergabe: ActivityAttributes {
    struct ContentState: Codable, Hashable { var fertig: Bool }
    var einstellungen: String
    var token: String
    /// Geheimnisse (Kantine, Freigabe) als JSON
    var geheim: String = "{}"
}
#endif

/// Was das Widget weiß: App-Gruppe (wenn vorhanden), sonst die eigene Ablage aus der Übergabe
enum WidgetSpeicher {
    static func einstellungen() -> (MorgenEinstellungen, String, Geheimnisse)? {
        if MorgenAblage.gruppeDa, let e = MorgenAblage.einstellungen() { return (e, MorgenAblage.token(), MorgenAblage.geheim()) }
        if let e = MorgenAblage.einstellungen(.standard) { return (e, MorgenAblage.token(.standard), MorgenAblage.geheim(.standard)) }
        return nil
    }

    /// Aus der Live-Aktivität übernehmen; bei Änderung die Widgets neu laden
    @discardableResult
    static func uebernehmen(json: String, token: String, geheim: String) -> Bool {
        guard let e = MorgenEinstellungen.aus(json: json) else { return false }
        let d = UserDefaults.standard
        guard d.string(forKey: "einstellungen") != json || d.string(forKey: "token") != token || d.string(forKey: "geheim") != geheim else { return false }
        MorgenAblage.speichern(e, token: token, geheim: Geheimnisse.aus(json: geheim) ?? Geheimnisse(), d)
        WidgetCenter.shared.reloadAllTimelines()
        return true
    }
}
