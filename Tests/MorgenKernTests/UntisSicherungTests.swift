import XCTest
@testable import MorgenKern

final class UntisSicherungTests: XCTestCase {
    func testSicherungLesen() {
        let json = """
        {"version":1,"erstellt":"2026-11-23T05:30:00.000Z","faecher":[{"name":"Ma","lang":"Mathe"}],
         "plaene":{"klassen":{"2b":[{"datum":"2026-11-23","von":"08:30","bis":"09:15","faecher":["Ma"],"lehrer":["Sta","Kla"],"raeume":["R1"],"klassen":["2b"]}]},
                   "lehrer":{"Sta":[{"datum":"2026-11-23","von":"08:30","bis":"09:15","faecher":["Ma"],"lehrer":["Ver"],"lehrerVorher":["Sta"],"raeume":["R1"],"klassen":["2b"]}]}}}
        """
        let st = Untis.ausSicherung(Data(json.utf8), kuerzel: "sta")!
        XCTAssertEqual(st.meine.count, 1)
        XCTAssertEqual(st.meine[0].von, 510)
        XCTAssertEqual(st.meine[0].fachLang, "Mathe")
        XCTAssertEqual(st.meine[0].lehrer, ["Sta"])
        XCTAssertEqual(st.klassen["2b"]?.first?.lehrer, ["Sta", "Kla"])
        XCTAssertNil(Untis.ausSicherung(Data(json.utf8), kuerzel: "Xyz"))
    }

    func testHandSchlaegtUntis() {
        let vorher = [Unterricht(tag: 2, stunde: "1", klasse: "2b", fach: "Ma"), Unterricht(tag: 3, stunde: "1", klasse: "2b", fach: "Ma")]
        let hand = [vorher[0], Unterricht(tag: 3, stunde: "1", klasse: "4a", fach: "Eigen")]
        let neu = [Unterricht(tag: 2, stunde: "1", klasse: "2b", fach: "De"), Unterricht(tag: 3, stunde: "1", klasse: "2b", fach: "De"), Unterricht(tag: 4, stunde: "2", klasse: "3a", fach: "Mu")]
        let z = Untis.zusammenfuehren(hand: hand, untis: neu, vorher: vorher)
        XCTAssertEqual(z.first { $0.tag == 2 }?.fach, "De")      // noch von Untis → aktualisiert
        XCTAssertEqual(z.first { $0.tag == 3 }?.fach, "Eigen")   // von Hand → bleibt
        XCTAssertEqual(z.first { $0.tag == 4 }?.fach, "Mu")      // freie Stunde → gefüllt
        XCTAssertEqual(z.count, 3)
    }
}

final class UntisSucheTests: XCTestCase {
    func testElementeUndPlanAusSicherung() {
        let json = """
        {"faecher":[{"name":"Ma","lang":"Mathe"}],"klassen":[{"name":"2b","lang":""}],"lehrer":[{"name":"Sta","lang":"Anna Stark"}],
         "plaene":{"klassen":{"2b":[{"datum":"2026-11-23","von":"08:30","bis":"09:15","faecher":["Ma"],"lehrer":["Sta"],"raeume":["R1"],"klassen":["2b"]}]},"lehrer":{}}}
        """
        let d = Data(json.utf8)
        let e = Untis.elemente(sicherung: d)
        XCTAssertEqual(e.map(\.titel), ["2b", "Sta – Anna Stark"])
        let p = Untis.plan(sicherung: d, element: e[0])
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p[0].fachLang, "Mathe")
        XCTAssertEqual(p[0].lehrer, ["Sta"])
    }
}

final class UntisRasterTests: XCTestCase {
    func testZeilenVonErsterBisLetzterStunde() {
        let st = [UntisStunde(datum: "2026-11-23", von: 480, bis: 510, fach: "FF", klassen: [], lehrer: []),   // Mo 0. Stunde
                  UntisStunde(datum: "2026-11-27", von: 555, bis: 600, fach: "Ma", klassen: [], lehrer: [])]   // Fr 2. Stunde
        let z = Untis.zeilen(st, zeiten: Schulzeit.standard)
        XCTAssertEqual(z.first?.name, "0")
        XCTAssertEqual(z.last?.name, "2")
        XCTAssertTrue(Untis.in_(st, datum: "2026-11-27", zeile: z[1]).isEmpty)   // Freitag 1. Stunde frei
        XCTAssertEqual(Untis.in_(st, datum: "2026-11-27", zeile: z[2]).first?.fach, "Ma")
        // ohne 0. Stunde beginnt das Raster mit der 1. (die 1. Stunde bleibt als freie Zeile stehen)
        XCTAssertEqual(Untis.zeilen([st[1]], zeiten: Schulzeit.standard).first?.name, "1")
    }
}
