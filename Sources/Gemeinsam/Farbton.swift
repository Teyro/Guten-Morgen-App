import SwiftUI

/// Farbtöne für App und Widget (Einstellungen → Aussehen)
struct Farbton: Identifiable, Hashable {
    let id: String
    let name: String
    /// Verlauf hell (oben → unten) und dunkel
    let hell: [Color]
    let dunkel: [Color]
    /// Widget-Hintergrund (immer kräftig, weiße Schrift)
    let widget: [Color]
    let akzent: Color

    static let alle: [Farbton] = [
        Farbton(id: "morgenrot", name: "Morgenrot",
                hell: [Color(red: 1, green: 0.94, blue: 0.86), Color(red: 0.95, green: 0.93, blue: 1)],
                dunkel: [Color(red: 0.09, green: 0.08, blue: 0.18), Color(red: 0.2, green: 0.1, blue: 0.16)],
                widget: [Color(red: 0.2, green: 0.2, blue: 0.5), Color(red: 0.88, green: 0.46, blue: 0.4)], akzent: .orange),
        Farbton(id: "ozean", name: "Ozean",
                hell: [Color(red: 0.88, green: 0.95, blue: 1), Color(red: 0.9, green: 0.98, blue: 0.97)],
                dunkel: [Color(red: 0.03, green: 0.1, blue: 0.18), Color(red: 0.02, green: 0.16, blue: 0.2)],
                widget: [Color(red: 0.05, green: 0.27, blue: 0.5), Color(red: 0.1, green: 0.6, blue: 0.68)], akzent: Color(red: 0.05, green: 0.5, blue: 0.75)),
        Farbton(id: "wald", name: "Wald",
                hell: [Color(red: 0.92, green: 0.97, blue: 0.9), Color(red: 0.97, green: 0.97, blue: 0.9)],
                dunkel: [Color(red: 0.05, green: 0.12, blue: 0.08), Color(red: 0.1, green: 0.14, blue: 0.06)],
                widget: [Color(red: 0.1, green: 0.33, blue: 0.2), Color(red: 0.45, green: 0.6, blue: 0.25)], akzent: Color(red: 0.2, green: 0.55, blue: 0.3)),
        Farbton(id: "lavendel", name: "Lavendel",
                hell: [Color(red: 0.95, green: 0.92, blue: 1), Color(red: 1, green: 0.93, blue: 0.97)],
                dunkel: [Color(red: 0.12, green: 0.07, blue: 0.2), Color(red: 0.18, green: 0.06, blue: 0.18)],
                widget: [Color(red: 0.36, green: 0.22, blue: 0.62), Color(red: 0.82, green: 0.45, blue: 0.7)], akzent: Color(red: 0.5, green: 0.3, blue: 0.8)),
        Farbton(id: "tafel", name: "Schultafel",
                hell: [Color(red: 0.9, green: 0.95, blue: 0.92), Color(red: 0.95, green: 0.95, blue: 0.93)],
                dunkel: [Color(red: 0.07, green: 0.15, blue: 0.12), Color(red: 0.05, green: 0.1, blue: 0.09)],
                widget: [Color(red: 0.16, green: 0.3, blue: 0.25), Color(red: 0.24, green: 0.4, blue: 0.33)], akzent: Color(red: 0.2, green: 0.5, blue: 0.4)),
        Farbton(id: "nacht", name: "Nacht",
                hell: [Color(red: 0.92, green: 0.93, blue: 0.96), Color(red: 0.88, green: 0.9, blue: 0.95)],
                dunkel: [Color(red: 0.04, green: 0.05, blue: 0.08), Color(red: 0.08, green: 0.09, blue: 0.13)],
                widget: [Color(red: 0.06, green: 0.07, blue: 0.12), Color(red: 0.16, green: 0.18, blue: 0.28)], akzent: Color(red: 0.4, green: 0.5, blue: 0.95)),
    ]

    static func zu(_ id: String) -> Farbton { alle.first { $0.id == id } ?? alle[0] }
}
