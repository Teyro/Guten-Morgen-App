import XCTest
@testable import MorgenKern

final class FunktionenTests: XCTestCase {
    private func block(_ name: String, _ text: String, art: Block.Art = .unterricht) -> Block {
        Block(name: name, von: Date(), bis: Date().addingTimeInterval(2700), art: art, text: text)
    }

    func testMitnehmen() {
        let regen = WetterTag(code: 61, max: 10, min: 6, regen: 70, wind: 10)
        let b = [block("1", "4a Sport · Halle"), block("2", "4a Deutsch")]
        XCTAssertEqual(Mitnehmen.hinweise(b, wetter: regen), ["Sportzeug", "Regenjacke"])
        // Schwimmen hat Vorrang vor Sport, Glätte statt Regenjacke
        let glatt = WetterTag(code: 66, max: 1, min: -1, regen: 80, wind: 5)
        XCTAssertEqual(Mitnehmen.hinweise([block("3", "4a Schwimmen")], wetter: glatt), ["Schwimmsachen", "Vorsicht, glatt"])
        XCTAssertTrue(Mitnehmen.hinweise([block("1", "4a Mathe")], wetter: nil).isEmpty)
        XCTAssertEqual(Mitnehmen.satz([block("1", "4a Sport")], wetter: nil, wann: "Morgen"), "Morgen mitnehmen: Sportzeug.")
    }

    func testSchulTermine() {
        let ab = Zeit.kalender.date(from: DateComponents(year: 2026, month: 11, day: 14))!
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20261117
        SUMMARY:Elternabend 4a
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20261115
        SUMMARY:Laternenfest
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20260101
        SUMMARY:Vorbei
        END:VEVENT
        END:VCALENDAR
        """
        let t = SchulKalender.termine(ics, ab: ab, tage: 45)
        XCTAssertEqual(t.map(\.titel), ["Laternenfest", "Elternabend 4a"])   // sortiert, Vergangenes raus
        XCTAssertEqual(SchulKalender.datumText("2026-11-15", jetzt: ab), "morgen")
        XCTAssertEqual(SchulKalender.datumText("2026-11-14", jetzt: ab), "heute")
    }
}
