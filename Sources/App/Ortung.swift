import CoreLocation
import MorgenKern

/// Standort einmal holen (nur wenn Schule oder Zuhause gespeichert sind, bzw. zum Speichern eines Ortes)
@MainActor
final class Ortung: NSObject, CLLocationManagerDelegate {
    private let m = CLLocationManager()
    private var warten: [CheckedContinuation<CLLocation?, Never>] = []
    private(set) var letzter: CLLocation?

    override init() {
        super.init()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyHundredMeters
        letzter = m.location
    }

    var ort: Kontext.Ort? { letzter.map { Kontext.Ort(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude) } }

    func einmal() async -> CLLocation? {
        switch m.authorizationStatus {
        case .notDetermined: m.requestWhenInUseAuthorization()
        case .denied, .restricted: return nil
        default: break
        }
        return await withCheckedContinuation { k in
            warten.append(k)
            m.requestLocation()
            // nicht ewig warten
            Task { try? await Task.sleep(nanoseconds: 15_000_000_000); self.fertig(nil) }
        }
    }

    private func fertig(_ l: CLLocation?) {
        if let l { letzter = l }
        let w = warten; warten = []
        w.forEach { $0.resume(returning: l ?? letzter) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let l = locations.last
        Task { @MainActor in self.fertig(l) }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { Task { @MainActor in self.fertig(nil) } }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in if !self.warten.isEmpty, [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus) { manager.requestLocation() } }
    }
}
