import SwiftUI
import UserNotifications
import MorgenKern

/// Mitteilungen: auch im Vordergrund zeigen; Antippen öffnet den Bereich (gutenmorgen://stoerungen …)
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @MainActor static var oeffnen: ((URL) -> Void)?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let l = response.notification.request.content.userInfo["link"] as? String, let u = URL(string: l) else { return }
        await MainActor.run { AppDelegate.oeffnen?(u) }
    }
}

@main
struct GutenMorgenApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var kern: Kern

    init() {
        let k = Kern()
        _kern = State(initialValue: k)
        // Hintergrund-Lauf muss vor dem Ende des Starts angemeldet sein
        if !k.vorschau { Hintergrund.anmelden(k) }
    }
    var body: some Scene {
        WindowGroup {
            HauptAnsicht(kern: kern)
                .tint(.orange)
                .onOpenURL { url in
                    // gutenmorgen://vorlesen (z. B. aus einem Kurzbefehl nach dem Wecker), gutenmorgen://gutenacht
                    switch url.host {
                    case "vorlesen": Task { await kern.briefingVorlesen() }
                    case "gutenacht": Task { await kern.guteNacht() }
                    // aus Mein Tag: Einstellungen übernehmen (mit Rückfrage)
                    case "import": kern.importAnfrage = ImportDaten.aus(url: url)
                    // aus dem Widget: Bereich öffnen
                    case let b?: kern.bereich = Bereich(rawValue: b)
                    default: break
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .fokusGeaendert)) { _ in
                    Task { kern.kontext = await SchulFokusFilter.schuleAktiv() ? .schule : Kontext.bestimme(frei: kern.frei, hier: kern.ortung.ort, schule: kern.einstellungen.schulOrt, zuhause: kern.einstellungen.zuhauseOrt) }
                }
                .onAppear {
                    if !kern.vorschau { Uhr.shared.starten(kern) }
                    AppDelegate.oeffnen = { u in kern.bereich = Bereich(rawValue: u.host ?? "") }
                    if kern.vorschau, ProcessInfo.processInfo.environment["GM_ANSICHT"] == "einstellungen" { kern.einstellungenOffen = true }
                }
        }
    }
}
