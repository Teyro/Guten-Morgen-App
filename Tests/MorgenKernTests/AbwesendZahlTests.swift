import XCTest
@testable import MorgenKern

final class AbwesendZahlTests: XCTestCase {
    func tag(_ t: Int) -> Date { Zeit.kalender.date(from: DateComponents(year: 2026, month: 11, day: t, hour: 7))! }
    let liste = [Abwesenheit(name: "Anna Beispiel", klasse: "", von: "2026-11-23", bis: "2026-11-23", art: "krank"),
                 Abwesenheit(name: "Ben Muster", klasse: "", von: "2026-11-23", bis: "2026-11-23", art: "krank"),
                 Abwesenheit(name: "Cem Probe", klasse: "", von: "2026-11-23", bis: "2026-11-23", art: "krank")]

    /// Morgens: IServ ohne Ausgegraute
    func testMorgensIServOhneAusgegraute() {
        XCTAssertEqual(Abwesenheiten.zahl(liste, aus: [], plan: nil, ziel: tag(23)).zahl, "3")
        let z = Abwesenheiten.zahl(liste, aus: [" ben muster "], plan: nil, ziel: tag(23))
        XCTAssertEqual(z.zahl, "2"); XCTAssertEqual(z.text, "abwesend")
        XCTAssertTrue(Abwesenheiten.ausgegraut(liste[1], ["Ben Muster"]))
    }

    /// Ab Vertretungsplan (echte Zeilen vom 23.11.): „Es fehlen: Kru, Kut, Reh, Kha, Beu“, „Außer Haus: Ayd, Wa+Hoff (8:30-12:15)“ → 5 + 3
    func testAbVertretungsplan() {
        var p = VertretungsPlan(); p.datum = "2026-11-23"
        p.fehlen = ["Kru", "Kut", "Reh", "Kha", "Beu"]; p.ausserListe = ["Ayd", "Wa+Hoff (8:30-12:15)"]
        let z = Abwesenheiten.zahl(liste, aus: [], plan: p, ziel: tag(23))
        XCTAssertEqual(z.zahl, "5 + 3"); XCTAssertEqual(z.text, "krank + außer Haus")
        p.ausserListe = []
        XCTAssertEqual(Abwesenheiten.zahl(liste, aus: [], plan: p, ziel: tag(23)).zahl, "5")
        // Plan für einen anderen Tag zählt nicht
        XCTAssertEqual(Abwesenheiten.zahl(liste, aus: [], plan: p, ziel: tag(24)).zahl, "3")
    }
}
