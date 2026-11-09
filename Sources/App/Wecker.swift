import Foundation
import SwiftUI
import MorgenKern
#if canImport(AlarmKit)
import AlarmKit
#endif

/// Echter Wecker über AlarmKit (ab iOS 26): stellt genau einen Wecker – die errechnete Weckzeit – und ersetzt ihn bei Änderung
@MainActor
enum Wecker {
    private static let schluessel = "weckerID"
    private static let zeitSchluessel = "weckerZeit"

    static var verfuegbar: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    /// Gestellte Zeit (zur Anzeige) oder nil
    static var gestellt: Date? {
        let t = UserDefaults.standard.double(forKey: zeitSchluessel)
        return t > 0 && Date(timeIntervalSince1970: t) > Date() ? Date(timeIntervalSince1970: t) : nil
    }

    /// Wecker auf [datum] stellen (nil = keinen); gibt eine Meldung zurück
    @discardableResult
    static func stellen(_ datum: Date?) async -> String {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let m = AlarmManager.shared
            do {
                if m.authorizationState != .authorized {
                    guard try await m.requestAuthorization() == .authorized else { return "Wecker nicht erlaubt – in den iPhone-Einstellungen bei „Guten Morgen“ erlauben." }
                }
                if let alt = UserDefaults.standard.string(forKey: schluessel).flatMap(UUID.init(uuidString:)) { try? m.cancel(id: alt) }
                UserDefaults.standard.removeObject(forKey: schluessel)
                UserDefaults.standard.removeObject(forKey: zeitSchluessel)
                guard let datum, datum > Date() else { return "Kein Wecker gestellt." }
                let id = UUID()
                let alarm = AlarmPresentation.Alert(title: "Guten Morgen", stopButton: AlarmButton(text: "Aus", textColor: .white, systemImageName: "sun.max.fill"))
                let attribute = AlarmAttributes<WeckerDaten>(presentation: AlarmPresentation(alert: alarm), tintColor: .orange)
                let konfiguration = AlarmManager.AlarmConfiguration<WeckerDaten>(schedule: .fixed(datum), attributes: attribute)
                _ = try await m.schedule(id: id, configuration: konfiguration)
                UserDefaults.standard.set(id.uuidString, forKey: schluessel)
                UserDefaults.standard.set(datum.timeIntervalSince1970, forKey: zeitSchluessel)
                let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "EEEE, HH:mm"
                return "Wecker gestellt: \(f.string(from: datum)) Uhr"
            } catch {
                return "Wecker konnte nicht gestellt werden: \(error.localizedDescription)"
            }
        }
        #endif
        return "Der Wecker braucht iOS 26 – bis dahin per Kurzbefehl „Wecker erstellen“ mit der Weckzeit."
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct WeckerDaten: AlarmMetadata {}
#endif
