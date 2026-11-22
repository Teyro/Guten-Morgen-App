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
