import SwiftUI
import MorgenKern

/// Eigener Stundenplan: je Wochentag die Stunden (Klasse, Fach, Raum) und die Klingelzeiten der Schule
struct StundenplanAnsicht: View {
    @Bindable var kern: Kern
    private let tage = [(2, "Montag"), (3, "Dienstag"), (4, "Mittwoch"), (5, "Donnerstag"), (6, "Freitag")]

    private func feld(_ tag: Int, _ stunde: String, _ pfad: WritableKeyPath<Unterricht, String>) -> Binding<String> {
        Binding(
            get: { kern.einstellungen.unterricht.first { $0.tag == tag && $0.stunde == stunde }?[keyPath: pfad] ?? "" },
            set: { neu in
                var liste = kern.einstellungen.unterricht
                if let i = liste.firstIndex(where: { $0.tag == tag && $0.stunde == stunde }) {
                    liste[i][keyPath: pfad] = neu
                    let u = liste[i]
                    if u.klasse.isEmpty && u.fach.isEmpty && u.raum.isEmpty { liste.remove(at: i) }
                } else if !neu.isEmpty {
                    var u = Unterricht(tag: tag, stunde: stunde, klasse: "")
                    u[keyPath: pfad] = neu
                    liste.append(u)
                }
                kern.einstellungen.unterricht = liste
            })
    }

    private func uhr(_ i: Int, _ pfad: WritableKeyPath<Schulzeit, Int>) -> Binding<String> {
        Binding(
            get: { kern.einstellungen.schulzeiten.indices.contains(i) ? Zeit.hhmm(kern.einstellungen.schulzeiten[i][keyPath: pfad]) : "" },
            set: { neu in if let m = Zeit.minuten(neu), kern.einstellungen.schulzeiten.indices.contains(i) { kern.einstellungen.schulzeiten[i][keyPath: pfad] = m } })
    }

    var body: some View {
        Form {
            ForEach(tage, id: \.0) { t in
                Section(t.1) {
                    ForEach(kern.einstellungen.schulzeiten.filter { !$0.pause }) { z in
                        HStack(spacing: 8) {
                            Text("\(z.name).").font(.callout.monospacedDigit().bold()).frame(width: 26, alignment: .leading)
                            TextField("Klasse", text: feld(t.0, z.name, \.klasse)).frame(maxWidth: 70)
                            TextField("Fach", text: feld(t.0, z.name, \.fach))
                            TextField("Raum", text: feld(t.0, z.name, \.raum)).frame(maxWidth: 70)
                        }
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                }
            }
            Section {
                ForEach(kern.einstellungen.schulzeiten.indices, id: \.self) { i in
                    HStack {
                        Text(kern.einstellungen.schulzeiten[i].pause ? kern.einstellungen.schulzeiten[i].name : "\(kern.einstellungen.schulzeiten[i].name). Stunde")
                        Spacer()
                        TextField("08:30", text: uhr(i, \.von)).multilineTextAlignment(.trailing).frame(width: 60).keyboardType(.numbersAndPunctuation)
                        Text("–")
                        TextField("09:15", text: uhr(i, \.bis)).multilineTextAlignment(.trailing).frame(width: 60).keyboardType(.numbersAndPunctuation)
                    }
                }
                Button("Raster der Schule wiederherstellen") { kern.einstellungen.schulzeiten = Schulzeit.standard }
            } header: { Text("Klingelzeiten") } footer: { Text("Vorgabe wie in DammTable: 8:30–13:30, Pausen um 10:00 und 11:55.") }
        }
        .scrollContentBackground(.hidden)
        .background(Hintergrund(farbton: kern.farbton))
        .navigationTitle("Mein Stundenplan")
        .navigationBarTitleDisplayMode(.inline)
    }
}
