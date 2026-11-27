import XCTest
@testable import MorgenKern

final class GemeldetTests: XCTestCase {
    /// Export mit Spalte „Erstellt“: Zeitpunkt der Meldung; ohne Uhrzeit oder ohne Spalte: nichts
    func testMeldezeitpunkt() {
        let csv = "Name;Klasse;Von;Bis;Art;Erstellt\nMuster, Kim;;23.11.2026;23.11.2026;krank;23.11.2026 07:12\nProbe, Cem;;23.11.2026;24.11.2026;krank;22.11.2026 18:40:00\n"
        let l = Abwesenheiten.ausCSV(csv)!
        XCTAssertEqual(l[0].gemeldet, "2026-11-23T07:12")
        let heute = Zeit.kalender.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 9))!
        XCTAssertEqual(Abwesenheiten.gemeldetText(l[0], heute: heute), "gemeldet um 07:12 Uhr")
        XCTAssertEqual(Abwesenheiten.gemeldetText(l[1], heute: heute), "gemeldet So, 22.11. um 18:40 Uhr")
        XCTAssertNil(Abwesenheiten.ausCSV("Name;Von\nKim;23.11.2026\n")![0].gemeldet)
    }
}
