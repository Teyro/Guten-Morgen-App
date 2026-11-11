import Foundation
import WatchConnectivity
import MorgenKern

/// Verbindung zur Apple Watch: schickt Weckzeit und Tagesablauf (die Uhr rechnet „jetzt / danach“ selbst)
@MainActor
final class Uhr: NSObject, WCSessionDelegate {
    static let shared = Uhr()
    private weak var kern: Kern?

    func starten(_ k: Kern) {
        kern = k
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func senden(_ k: Kern) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isWatchAppInstalled else { return }
        let enc = JSONEncoder()
        let w = k.naechsterWecker
        let paket = UhrPaket(wecker: Wecker.gestellt ?? w.datum, grund: w.grund, schultag: k.schultag, schulName: k.schulTagName,
                             heute: k.heuteBloecke, farbton: k.einstellungen.farbton, stand: Date())
        guard let d = try? enc.encode(paket) else { return }
        try? WCSession.default.updateApplicationContext(["paket": d])
    }

    nonisolated func session(_ s: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in if let k = self.kern { self.senden(k) } }
    }
    nonisolated func sessionDidBecomeInactive(_ s: WCSession) {}
    nonisolated func sessionDidDeactivate(_ s: WCSession) { WCSession.default.activate() }
}
