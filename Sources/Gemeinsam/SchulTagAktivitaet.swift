import Foundation
import MorgenKern
#if os(iOS)
import ActivityKit

/// Live-Aktivität im Schulalltag: der ganze Tagesablauf steckt im Zustand, die Ansicht wählt beim Zeichnen den laufenden Abschnitt
struct SchulTagAktivitaet: ActivityAttributes {
    struct ContentState: Codable, Hashable { var bloecke: [Block] }
    var datum: String
}
#endif
