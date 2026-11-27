import XCTest
@testable import MorgenKern

final class StatistikTests: XCTestCase {
    func testZaehlen() {
        var s = VertretungsStatistik()
        var p = VertretungsPlan(); p.datum = "2026-11-23"; p.belegt = 5
        p.stunden = [.init(stunde: "2", klasse: "2c"), .init(stunde: "3", klasse: "2c")]
        p.pausen = [.init(pause: "1. Pause", ort: "Hof"), .init(pause: "2. Pause", ort: "Mensa", reserve: true)]
        p.bemerkungen = [Bemerkung(stunden: [3, 4, 5], was: "Begleitung Nelson", klasse: "2c", text: "")]
        s.merken(p)
        p.stunden = [.init(stunde: "1", klasse: "4a")]   // späterer Stand desselben Tages ersetzt
        s.merken(p)
        var q = VertretungsPlan(); q.datum = "2026-11-24"; q.belegt = 3; q.stunden = [.init(stunde: "5", klasse: "4a")]
        s.merken(q)
        var leer = VertretungsPlan(); leer.datum = "2026-11-25"; s.merken(leer)   // leere Vorlage zählt nicht
        let z = s.zahlen(ab: "2026-11-01")
        XCTAssertEqual(z.tage, 2); XCTAssertEqual(z.vertretungen, 2); XCTAssertEqual(z.rotTage, 2)
        XCTAssertEqual(z.aufsichten, 1); XCTAssertEqual(z.begleitungen, 3); XCTAssertEqual(z.klasse, "4a")
        XCTAssertEqual(s.zahlen(ab: "2026-11-24").vertretungen, 1)
        XCTAssertEqual(VertretungsStatistik.schuljahrBeginn(Zeit.tag("2026-03-02")!), "2025-08-01")
        XCTAssertEqual(VertretungsStatistik.schuljahrBeginn(Zeit.tag("2026-11-27")!), "2026-08-01")
    }
}
