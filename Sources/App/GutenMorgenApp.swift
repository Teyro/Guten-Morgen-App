import SwiftUI
import MorgenKern

@main
struct GutenMorgenApp: App {
    @State private var kern = Kern()
    var body: some Scene {
        WindowGroup {
            HauptAnsicht(kern: kern)
                .tint(.orange)
                .onOpenURL { url in
                    // gutenmorgen://vorlesen (z. B. aus einem Kurzbefehl nach dem Wecker), gutenmorgen://gutenacht
                    switch url.host {
                    case "vorlesen": Task { await kern.briefingVorlesen() }
                    case "gutenacht": Task { await kern.guteNacht() }
                    default: break
                    }
                }
                .onAppear {
                    if kern.vorschau, ProcessInfo.processInfo.environment["GM_ANSICHT"] == "einstellungen" { kern.einstellungenOffen = true }
                }
        }
    }
}
