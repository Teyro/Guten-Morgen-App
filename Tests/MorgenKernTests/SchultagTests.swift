import XCTest
@testable import MorgenKern

final class SchultagTests: XCTestCase {
    let k = Zeit.kalender
    func tag(_ j: Int, _ m: Int, _ t: Int, _ h: Int = 12, _ min: Int = 0) -> Date { k.date(from: DateComponents(year: j, month: m, day: t, hour: h, minute: min))! }
    func uhr(_ d: Date) -> String { Zeit.hhmm(k.component(.hour, from: d) * 60 + k.component(.minute, from: d)) }

    /// Montag, 9.11.2026: 1. 5a Mathe, 4. 6b Deutsch; Vertretung 3. Stunde 2c, Aufsicht 2. Pause Hof
    func beispiel() -> (MorgenEinstellungen, VertretungsPlan) {
        var e = MorgenEinstellungen()
        e.unterricht = [Unterricht(tag: 2, stunde: "1", klasse: "5a", fach: "Mathe", raum: "R12"), Unterricht(tag: 2, stunde: "4", klasse: "6b", fach: "Deutsch")]
        e.haeuser = ["Haus 2": ["2c"]]
        var v = VertretungsPlan(); v.datum = "2026-11-09"
        v.stunden = [.init(stunde: "3", klasse: "2c")]; v.pausen = [.init(pause: "2. Pause", ort: "Hof")]
        return (e, v)
    }

    func testTagesablauf() {
        let (e, v) = beispiel()
        let b = e.schultag(tag(2026, 11, 9), vertretung: v)
        XCTAssertEqual(b.map(\.name), ["1", "2", "1. Pause", "3", "4", "2. Pause"])
        XCTAssertEqual(b.map(\.art), [.unterricht, .frei, .pause, .vertretung, .unterricht, .aufsicht])
        XCTAssertEqual(b[0].text, "5a Mathe · R12")
        XCTAssertEqual(b[3].text, "Vertretung 2c · Haus 2")
        XCTAssertEqual(b[5].text, "Aufsicht Hof")
        XCTAssertEqual(uhr(Stundenplan.beginn(b)!), "08:30")
        // Dienstag: nichts geplant, keine Vertretung für den Tag → leer
        XCTAssertTrue(e.schultag(tag(2026, 11, 10), vertretung: v).isEmpty)
        let s = Stundenplan.satz(b)
        XCTAssertTrue(s.contains("1. 5a Mathe in R12"), s)
        XCTAssertTrue(s.contains("Aufsicht in der 2. Pause: Hof"), s)
    }

    func testJetztUndDanach() {
        let (e, v) = beispiel()
        let b = e.schultag(tag(2026, 11, 9), vertretung: v)
        let (j, d) = Stundenplan.jetzt(b, tag(2026, 11, 9, 9, 0))
        XCTAssertEqual(j?.name, "1")
        XCTAssertEqual(d?.name, "1. Pause")   // die freie 2. Stunde wird übersprungen
        let (j2, d2) = Stundenplan.jetzt(b, tag(2026, 11, 9, 7, 0))
        XCTAssertNil(j2)
        XCTAssertEqual(d2?.name, "1")
        XCTAssertTrue(Stundenplan.wechsel(b).contains(tag(2026, 11, 9, 10, 0)))
    }

    func testGlaetteUndHinweise() {
        let frost = WetterTag(code: 3, max: 2, min: -2, regen: 60, wind: 10)
        XCTAssertTrue(Wetter.glaette(frost))
        XCTAssertTrue(Wetter.hinweise(frost, auto: true).contains("Scheibe kratzen"))
        XCTAssertTrue(Wetter.hinweise(frost, auto: true).contains("Schirm mitnehmen"))
        let mild = WetterTag(code: 2, max: 12, min: 6, regen: 10, wind: 10)
        XCTAssertFalse(Wetter.glaette(mild))
        XCTAssertTrue(Wetter.hinweise(mild, auto: true).isEmpty)
        XCTAssertTrue(Wetter.glaette(WetterTag(code: 73, max: 1, min: -1, regen: 80, wind: 5)))
    }

    func testWeckerMitGlaetteUndAnfahrt() {
        var (e, v) = beispiel()
        let tagMo = tag(2026, 11, 9)
        let frost = WetterTag(code: 71, max: 1, min: -3, regen: 70, wind: 5)
        // Standard 6:15, Glätte 15 Minuten früher → 6:00
        XCTAssertEqual(e.wecker(tag: tagMo, termine: [], frei: nil, wetter: frost, vertretung: v, fahrtMinuten: nil).minuten, 360)
        // Anfahrt: Beginn 8:30, Puffer 10, Fahrt 50, Fertig 45 → losfahren 7:30, wecken spätestens 6:45 – Standard 6:15 bleibt
        e.fahrt = true
        XCTAssertEqual(e.wecker(tag: tagMo, termine: [], frei: nil, wetter: nil, vertretung: v, fahrtMinuten: 50).minuten, 375)
        // Stau: 100 Minuten → losfahren 6:40, wecken 5:55
        let w = e.wecker(tag: tagMo, termine: [], frei: nil, wetter: nil, vertretung: v, fahrtMinuten: 100)
        XCTAssertEqual(w.minuten, 355)
        XCTAssertTrue(w.grund.contains("100 Minuten mit dem Auto"), w.grund)
        // nie vor „frühestens“ 5:00
        XCTAssertEqual(e.wecker(tag: tagMo, termine: [], frei: nil, wetter: nil, vertretung: v, fahrtMinuten: 300).minuten, 300)
        // ohne Stunden an dem Tag: keine Anfahrt
        v.datum = "2026-11-10"
        e.unterricht = []
        XCTAssertEqual(e.wecker(tag: tagMo, termine: [], frei: nil, wetter: nil, vertretung: v, fahrtMinuten: 100).minuten, 375)
    }

    func testRoutine() {
        XCTAssertEqual(Routine.versatz(-20), "-00:20:00")
        XCTAssertEqual(Routine.versatz(5), "00:05:00")
        let a = Routine.automation([
            RoutinenSchritt(name: "Bad warm", dienst: "script.turn_on", ziel: "script.bad_heizen", minuten: -20),
            RoutinenSchritt(name: "Licht", dienst: "light.turn_on", ziel: "light.schlafzimmer", minuten: -10, langsam: 600),
        ])
        let t = a["triggers"] as! [[String: Any]]
        XCTAssertEqual(t.count, 2)
        XCTAssertEqual((t[0]["at"] as! [String: Any])["offset"] as? String, "-00:20:00")
        let wahl = ((a["actions"] as! [[String: Any]])[0]["choose"] as! [[String: Any]])
        let licht = (wahl[1]["sequence"] as! [[String: Any]])[0]
        XCTAssertEqual((licht["data"] as! [String: Any])["transition"] as? Int, 600)
        XCTAssertNotNil(try? JSONSerialization.data(withJSONObject: a))
    }

    func testEinstellungenAltBleibenLesbar() {
        let alt = #"{"weckzeiten":{"2":"06:15"},"kuerzel":"Sta"}"#
        let e = MorgenEinstellungen.aus(json: alt)
        XCTAssertEqual(e?.kuerzel, "Sta")
        XCTAssertEqual(e?.schulzeiten.count, Schulzeit.standard.count)
        XCTAssertEqual(e?.glaetteFrueher, 15)
        var n = MorgenEinstellungen(); n.unterricht = [Unterricht(tag: 3, stunde: "2", klasse: "4a")]
        XCTAssertEqual(MorgenEinstellungen.aus(json: n.json())?.unterricht.first?.klasse, "4a")
    }
}

final class UntisTests: XCTestCase {
    func testQRUndLink() {
        let q = Untis.qr("untis://setschool?url=nessa.webuntis.com&school=gs-oejendorf&user=Sta&key=ABCDEFGH&schoolNumber=123")
        XCTAssertEqual(q?.basis, "https://nessa.webuntis.com")
        XCTAssertEqual(q?.schule, "gs-oejendorf")
        XCTAssertEqual(q?.benutzer, "Sta")
        XCTAssertEqual(q?.schluessel, "ABCDEFGH")
        XCTAssertNotNil(Untis.qr("untis://setschool?url=nessa.webuntis.com&school=x&user=Sta"))
        let l = Untis.zerlege("https://nessa.webuntis.com/WebUntis/?school=gs-oejendorf#/basic/login")
        XCTAssertEqual(l?.basis, "https://nessa.webuntis.com")
        XCTAssertEqual(l?.schule, "gs-oejendorf")
        XCTAssertNil(Untis.zerlege("http://unsicher.de/?school=x"))
        // so, wie es in WebUntis unter „Untis Mobile“ steht
        XCTAssertEqual(Untis.server(url: "https://hh5586.webuntis.com", schule: "")?.schule, "hh5586")
        XCTAssertEqual(Untis.server(url: "hh5586.webuntis.com", schule: "hh5586")?.basis, "https://hh5586.webuntis.com")
        XCTAssertNil(Untis.server(url: "nessa.webuntis.com", schule: ""))
        XCTAssertEqual(Untis.server(url: "nessa.webuntis.com", schule: "gs-x")?.schule, "gs-x")
    }

    func testStundenUndKlassen() {
        // Mo 9.11.: 1. Std 5a Ma (ich, id 7), 2. Std 5a FÖ (ich + Kla), Di 10.11.: 6b De (ich)
        let meine: [[String: Any]] = [
            ["date": 20261109, "startTime": 830, "endTime": 915, "kl": [["name": "5a"]], "te": [["id": 7, "name": "Sta"]], "su": [["name": "Ma", "longname": "Mathematik"]], "ro": [["name": "R12"]]],
            ["date": 20261109, "startTime": 915, "endTime": 1000, "kl": [["name": "5a"]], "te": [["id": 3, "name": "Kla"], ["id": 7, "name": "Sta"]], "su": [["name": "FÖ", "longname": "Förderkreis"]]],
            ["date": 20261110, "startTime": 830, "endTime": 915, "kl": [["name": "6b"]], "te": [["id": 7, "name": "Sta"]], "su": [["name": "De"]], "code": "cancelled"],
        ]
        let klasse5a: [[String: Any]] = [
            ["date": 20261109, "startTime": 830, "endTime": 915, "kl": [["name": "5a"]], "te": [["id": 7, "name": "Sta"]], "su": [["name": "Ma"]]],
            ["date": 20261109, "startTime": 1025, "endTime": 1110, "kl": [["name": "5a"]], "te": [["id": 3, "name": "Kla"]], "su": [["name": "De"]]],
            ["date": 20261110, "startTime": 1025, "endTime": 1110, "kl": [["name": "5a"]], "te": [["id": 4, "name": "Mül"]], "su": [["name": "Sp"]]],
        ]
        let s = Untis.stunden(meine)
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s[0].von, 510)
        XCTAssertTrue(s[1].foerder)
        XCTAssertTrue(s[2].entfaellt)
        let st = UntisStand(meine: s, klassen: ["5a": Untis.stunden(klasse5a)], ich: 7, kuerzel: "Sta")
        let k = Untis.klassen(st)
        XCTAssertEqual(k.map(\.klasse), ["5a", "6b"])
        XCTAssertEqual(k[0].faecher.map(\.kurz), ["Ma"])
        XCTAssertEqual(k[0].foerder, 1)
        XCTAssertEqual(k[0].doppel, ["Kla"])
        XCTAssertEqual(Set(k[0].andere.map(\.kuerzel)), ["Kla", "Mül"])
        // als eigener Stundenplan: Mo 1. und 2. Stunde, Di 1. Stunde
        let u = Untis.unterricht(st, zeiten: Schulzeit.standard)
        XCTAssertEqual(u.filter { $0.tag == 2 }.map(\.stunde).sorted(), ["1", "2"])
        XCTAssertEqual(u.first { $0.tag == 2 && $0.stunde == "1" }?.fach, "Mathematik")
    }

    func testPostLesen() {
        let j: [String: Any] = ["briefe": [
            ["id": "p1", "art": "paket", "datum": "2026-11-11T08:00:00+01:00", "absender": "Thalia", "dienst_name": "DHL", "stand": "zustellung", "abholcode": "", "ereignisse": [["text": "In Zustellung", "zeit": "2026-11-11T07:30:00+01:00"]]],
            ["id": "b1", "art": "brief", "datum": "2026-11-11", "absender": "Finanzamt", "wichtig": true, "bild": true],
        ]]
        let p = PostStand.lesen(j)!
        XCTAssertEqual(p.pakete.count, 1)
        XCTAssertEqual(p.briefe.first?.absender, "Finanzamt")
        XCTAssertEqual(p.gruppen().heute.map(\.id), ["p1"])
        XCTAssertEqual(p.pakete[0].ereignisse.count, 1)
    }

    func testUnterwegs() {
        var e = MorgenEinstellungen()
        e.zuhauseOrt = Kontext.Ort(lat: 53.55, lon: 10.10)
        let barsbuettel = Kontext.Ort(lat: 53.567, lon: 10.17)
        XCTAssertFalse(e.unterwegs(hier: barsbuettel))   // Schalter aus
        e.unterwegsAn = true
        XCTAssertTrue(e.unterwegs(hier: barsbuettel))
        XCTAssertFalse(e.unterwegs(hier: Kontext.Ort(lat: 53.551, lon: 10.101)))
        XCTAssertFalse(e.unterwegs(hier: nil))
    }
}
