import Foundation

/// „Morgen mitnehmen“: aus den Stunden (Sport, Schwimmen) und dem Wetter ableiten, was einzupacken ist.
public enum Mitnehmen {
    public static func hinweise(_ bloecke: [Block], wetter: WetterTag?) -> [String] {
        var h: [String] = []
        let text = bloecke.filter { $0.art == .unterricht || $0.art == .vertretung }
            .map { ($0.text + " " + ($0.ersetzt ?? "")).lowercased() }.joined(separator: " · ")
        if text.contains("schwimm") { h.append("Schwimmsachen") }
        if text.contains("sport") && !h.contains("Schwimmsachen") { h.append("Sportzeug") }
        if let w = wetter {
            if Wetter.glaette(w) { h.append("Vorsicht, glatt") }
            else if w.regen >= 50 { h.append("Regenjacke") }
        }
        return h
    }

    /// Ein Satz fürs Briefing, oder leer
    public static func satz(_ bloecke: [Block], wetter: WetterTag?, wann: String) -> String {
        let h = hinweise(bloecke, wetter: wetter)
        guard !h.isEmpty else { return "" }
        return (wann.isEmpty ? "Mitnehmen" : "\(wann) mitnehmen") + ": " + h.joined(separator: ", ") + "."
    }
}
