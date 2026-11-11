import SwiftUI
import WatchConnectivity
import MorgenKern

/// Guten Morgen auf der Apple Watch: Wecker, was jetzt läuft und was danach kommt, der Tagesablauf.
/// Die Daten schickt das iPhone (App einmal öffnen); die Uhr rechnet „jetzt / danach“ selbst weiter.
@main
struct GutenMorgenUhr: App {
    @State private var zustand = UhrZustand.shared
    var body: some Scene {
        WindowGroup {
            NavigationStack { UhrAnsicht(zustand: zustand) }
                .task { zustand.starten() }
        }
    }
}

@MainActor
@Observable
final class UhrZustand: NSObject, WCSessionDelegate {
    static let shared = UhrZustand()
    private(set) var paket: UhrPaket?

    override init() {
        super.init()
        if let d = UserDefaults.standard.data(forKey: "paket") { paket = try? JSONDecoder().decode(UhrPaket.self, from: d) }
    }

    func starten() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    nonisolated func session(_ s: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let k = s.receivedApplicationContext
        Task { @MainActor in self.uebernehmen(k) }
    }
    nonisolated func session(_ s: WCSession, didReceiveApplicationContext k: [String: Any]) {
        Task { @MainActor in self.uebernehmen(k) }
    }

    private func uebernehmen(_ k: [String: Any]) {
        guard let d = k["paket"] as? Data, let p = try? JSONDecoder().decode(UhrPaket.self, from: d) else { return }
        paket = p
        UserDefaults.standard.set(d, forKey: "paket")
    }
}

struct UhrAnsicht: View {
    let zustand: UhrZustand
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { t in
            List {
                if let p = zustand.paket {
                    if let w = p.wecker, w > t.date {
                        Section("Wecker") {
                            Label(w.formatted(.dateTime.weekday(.wide).hour().minute()), systemImage: "alarm.fill").font(.headline)
                            if !p.grund.isEmpty { Text(p.grund).font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                    let jd = Stundenplan.jetzt(p.heute, t.date)
                    let jetzt = jd.jetzt
                    let danach = jd.danach
                    if jetzt != nil || danach != nil {
                        Section("Jetzt") {
                            if let j = jetzt {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(j.titel)").font(.footnote).foregroundStyle(.secondary)
                                    Text(j.text).font(.headline)
                                    Text(timerInterval: j.von...j.bis, countsDown: true).font(.title3.monospacedDigit()).foregroundStyle(.orange)
                                }
                            }
                            if let d = danach {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Danach · \(d.von.formatted(date: .omitted, time: .shortened))").font(.footnote).foregroundStyle(.secondary)
                                    Text(d.art == .pause ? d.titel : "\(d.marke) \(d.text)").font(.body)
                                }
                            }
                        }
                    }
                    if !p.schultag.isEmpty {
                        Section("Schule \(p.schulName)") {
                            ForEach(p.schultag.filter { $0.art != .pause }, id: \.von) { b in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(b.marke).font(.footnote.monospacedDigit()).frame(width: 30, alignment: .leading)
                                    Text(b.text).font(.footnote).foregroundStyle(b.art == .frei ? Color.secondary : b.art == .unterricht ? Color.primary : Color.orange)
                                }
                            }
                        }
                    }
                } else {
                    Text("Bitte einmal Guten Morgen auf dem iPhone öffnen.").font(.footnote)
                }
            }
        }
        .navigationTitle("Guten Morgen")
    }
}
