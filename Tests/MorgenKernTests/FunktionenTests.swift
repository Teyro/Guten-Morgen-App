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
        // Schwimmen hat Vorrang vor Sport; bei Glätte trotzdem nur Einpackbares
        let glatt = WetterTag(code: 66, max: 1, min: -1, regen: 80, wind: 5)
        XCTAssertEqual(Mitnehmen.hinweise([block("3", "4a Schwimmen")], wetter: glatt), ["Schwimmsachen", "Regenjacke"])   // Glätte meldet das Briefing selbst
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
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20261112
        DTEND;VALUE=DATE:20261115
        SUMMARY:Projektwoche
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20261110
        DTEND;VALUE=DATE:20261114
        SUMMARY:Gestern zu Ende
        END:VEVENT
        END:VCALENDAR
        """
        let t = SchulKalender.termine(ics, ab: ab, tage: 45)
        XCTAssertEqual(t.map(\.titel), ["Projektwoche", "Laternenfest", "Elternabend 4a"])   // sortiert, Vergangenes raus, Laufendes mit heute
        XCTAssertEqual(t.first?.datum, "2026-11-14")
        XCTAssertEqual(SchulKalender.datumText("2026-11-15", jetzt: ab), "morgen")
        XCTAssertEqual(SchulKalender.datumText("2026-11-14", jetzt: ab), "heute")
    }
func testGehaltAbruf() {
        let k = Zeit.kalender
        // Zielminute ist stabil je Tag und liegt zwischen 11:00 und 15:00
        let tag = k.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 12))!
        let z = GehaltAbruf.zielMinute(tag)
        XCTAssertTrue(z >= 660 && z <= 900)
        XCTAssertEqual(z, GehaltAbruf.zielMinute(k.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 8))!))
        // Montag vor der Zielzeit: nicht fällig; danach schon; am Samstag nie
        let vor = k.date(bySettingHour: (z-1)/60, minute: (z-1)%60, second: 0, of: tag)!   // 16.11.2026 ist ein Montag
        let nach = k.date(bySettingHour: (z+1)/60, minute: (z+1)%60, second: 0, of: tag)!
        XCTAssertFalse(GehaltAbruf.faellig(vor, letzterTag: ""))
        XCTAssertTrue(GehaltAbruf.faellig(nach, letzterTag: ""))
        XCTAssertFalse(GehaltAbruf.faellig(nach, letzterTag: "2026-11-16")) // heute schon
        let samstag = k.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 13))!
        XCTAssertFalse(GehaltAbruf.faellig(samstag, letzterTag: ""))
        // ein ganzes Jahr: immer 11–15 Uhr, kein Absturz, und nicht jeden Tag dieselbe Uhrzeit
        let minuten = (0..<366).map { GehaltAbruf.zielMinute(k.date(byAdding: .day, value: $0, to: tag)!) }
        XCTAssertTrue(minuten.allSatisfy { $0 >= 660 && $0 <= 900 })
        XCTAssertGreaterThan(Set(minuten).count, 200)
    }
}

final class StartseiteTests: XCTestCase {
    func testAutomatischUndAusgeblendet() {
        XCTAssertEqual(Startseite.ordnung(eigen: [], aus: [], inDerSchule: true).prefix(3), ["wecker", "schule", "mensa"])
        XCTAssertEqual(Startseite.ordnung(eigen: [], aus: [], inDerSchule: false).prefix(3), ["wecker", "termine", "post"])
        XCTAssertFalse(Startseite.ordnung(eigen: [], aus: ["wetter", "personal"], inDerSchule: true).contains("wetter"))
    }

    func testAlteReihenfolgeBekommtNeueKachelnHinterSchule() {
        // gespeichert mit 2.4 (nur 5 Kacheln): Speiseplan, Zahlen, Schultermine waren Teil der Schule
        let r = Startseite.vollstaendig(["termine", "schule", "wecker", "wetter", "post"], inDerSchule: true)
        XCTAssertEqual(r, ["termine", "schule", "mensa", "zahlen", "schultermine", "wecker", "wetter", "post", "personal", "fussball"])
        XCTAssertEqual(Set(r).count, Startseite.alle.count)
        // Unbekanntes aus einer neueren Version wird ignoriert
        XCTAssertFalse(Startseite.vollstaendig(["schule", "gibtsnicht"], inDerSchule: true).contains("gibtsnicht"))
    }
}

final class PausenWetterTests: XCTestCase {
    /// Open-Meteo-Antwort wie echt: 1. Pause (10:00–10:25) Regen, 2. Pause (11:55–12:20) trocken
    private func wetter() -> Wetter {
        let zeiten = ["2026-11-17T10:00", "2026-11-17T10:15", "2026-11-17T10:30", "2026-11-17T11:45", "2026-11-17T12:00", "2026-11-17T12:15", "2026-11-17T12:30"]
        let json: [String: Any] = [
            "minutely_15": ["time": zeiten,
                            "weather_code": [3, 61, 63, 2, 1, 1, 61],   // 12:30 regnet es wieder – liegt aber nach der 2. Pause
                            "temperature_2m": [6.0, 5.5, 5.4, 7.0, 7.2, 7.4, 7.0],
                            "precipitation": [0.0, 0.4, 0.6, 0.0, 0.0, 0.0, 0.8],
                            "wind_gusts_10m": [20, 25, 30, 15, 15, 18, 22]],
            "hourly": ["time": ["2026-11-17T10:00", "2026-11-17T11:00", "2026-11-17T12:00"], "precipitation_probability": [80, 20, 10]],
        ]
        return Wetter.lesen(json)
    }
    private func zeit(_ h: Int, _ m: Int) -> Date { Zeit.kalender.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: h, minute: m))! }

    func testRegenpauseUndTrocken() {
        let w = wetter()
        XCTAssertEqual(w.verlauf?.count, 7)
        let erste = w.pause(von: zeit(10, 0), bis: zeit(10, 25))!
        XCTAssertTrue(erste.drinnen)
        XCTAssertEqual(erste.text, "Regenpause")
        XCTAssertEqual(erste.symbol, "cloud.rain.fill")
        let zweite = w.pause(von: zeit(11, 55), bis: zeit(12, 20))!
        XCTAssertFalse(zweite.drinnen)
        XCTAssertEqual(zweite.text, "trocken")
        XCTAssertNil(w.pause(von: zeit(15, 0), bis: zeit(15, 25)))   // keine Daten → nichts anzeigen
    }

    func testGewitterUndSchnee() {
        let s = { (code: Int, mm: Double) in WetterSchritt(zeit: self.zeit(10, 15), code: code, temp: 1, regen: mm, chance: 30, boeen: 20) }
        func p(_ x: WetterSchritt) -> PausenWetter { Wetter(jetzt: nil, jetztCode: nil, heute: nil, morgen: nil, stand: Date(), verlauf: [x]).pause(von: zeit(10, 0), bis: zeit(10, 25))! }
        XCTAssertEqual(p(s(95, 0)).text, "Gewitter – Regenpause")
        XCTAssertFalse(p(s(73, 0.8)).drinnen)          // Schnee: meist trotzdem raus
        XCTAssertTrue(p(s(75, 2.0)).drinnen)           // starker Schneefall
        XCTAssertTrue(p(WetterSchritt(zeit: zeit(10, 15), code: 2, temp: 8, regen: 0, chance: 0, boeen: 80)).drinnen)  // Sturm
    }

    func testBriefingNurEigeneAufsicht() {
        let w = wetter()
        let bloecke = [
            Block(name: "1. Pause", von: zeit(10, 0), bis: zeit(10, 25), art: .aufsicht, text: "Aufsicht Hof"),
            Block(name: "2. Pause", von: zeit(11, 55), bis: zeit(12, 20), art: .aufsicht, text: "Aufsicht Mensa"),
        ]
        XCTAssertEqual(Briefing.aufsichtWetter(bloecke, w), "Hofaufsicht: erste Pause vermutlich Regenpause, zweite Pause trocken.")
        XCTAssertEqual(Briefing.aufsichtWetter([Block(name: "1. Pause", von: zeit(10, 0), bis: zeit(10, 25), art: .pause, text: "Pause")], w), "")
    }
}

final class VertretungsMeldungTests: XCTestCase {
    private func plan(_ datum: String, stunden: [VertretungsPlan.Stunde] = []) -> VertretungsPlan {
        var p = VertretungsPlan(); p.datum = datum; p.stunden = stunden; return p
    }

    func testNeuerPlanMitUndOhneEigeneEintraege() {
        // erster Lauf: nur merken
        let a = VertretungsMeldung.pruefen(plan("2026-11-17"), altDatum: nil, altSig: nil, planDa: true, betrifft: true)!
        XCTAssertNil(a.meldung)
        // neuer Tag (18.11. = Mittwoch), nichts für mich
        let b = VertretungsMeldung.pruefen(plan("2026-11-18"), altDatum: a.datum, altSig: a.sig, planDa: true, betrifft: true)!
        XCTAssertEqual(b.meldung?.titel, "Vertretungsplan für Mittwoch ist da")
        XCTAssertEqual(b.meldung?.text, "Keine Vertretung für dich.")
        // neuer Tag mit Vertretung: eine Mitteilung (nicht zusätzlich „betrifft dich“)
        let c = VertretungsMeldung.pruefen(plan("2026-11-19", stunden: [.init(stunde: "3", klasse: "2c")]), altDatum: b.datum, altSig: b.sig, planDa: true, betrifft: true)!
        XCTAssertEqual(c.meldung?.text, "3. Vertretung 2c")
        XCTAssertEqual(c.meldung?.id, "vertretung-plan-2026-11-19")
        // gleicher Tag, Plan geändert und betrifft mich: „betrifft dich“
        let d = VertretungsMeldung.pruefen(plan("2026-11-19", stunden: [.init(stunde: "3", klasse: "2c"), .init(stunde: "5", klasse: "4a")]), altDatum: c.datum, altSig: c.sig, planDa: true, betrifft: true)!
        XCTAssertEqual(d.meldung?.titel, "Vertretungsplan betrifft dich")
        // unverändert: nichts
        XCTAssertNil(VertretungsMeldung.pruefen(plan("2026-11-19", stunden: [.init(stunde: "3", klasse: "2c"), .init(stunde: "5", klasse: "4a")]), altDatum: d.datum, altSig: d.sig, planDa: true, betrifft: true)!.meldung)
    }

    func testNurBetrifftOhnePlanDa() {
        let a = VertretungsMeldung.pruefen(plan("2026-11-17"), altDatum: "2026-11-16", altSig: "x", planDa: false, betrifft: true)!
        XCTAssertNil(a.meldung)   // neuer Plan ohne eigene Einträge, „Plan ist da“ aus → still
        XCTAssertNil(VertretungsMeldung.pruefen(VertretungsPlan(), altDatum: nil, altSig: nil, planDa: true, betrifft: true))  // ohne Datum
    }
}

final class VerlaufTests: XCTestCase {
    func testEdupoolKommentare() {
        let json: [[String: Any]] = [
            ["id": 2, "content": "<p>Erledigt, danke!</p>", "user": ["name": "Kim Muster"], "created_at": "2026-11-20T10:00:00Z"],
            ["id": 1, "content": "Bitte bis Freitag", "author_name": "Alex", "created_at": "2026-11-19T08:00:00Z"],
            ["id": 3, "content": "  "],
        ]
        let k = Aufgaben.kommentareAus(json)
        XCTAssertEqual(k.map(\.text), ["Bitte bis Freitag", "Erledigt, danke!"])
        XCTAssertEqual(k.map(\.autor), ["Alex", "Kim Muster"])
    }

    func testStoerungVerlaufUndFormular() {
        let html = """
        <html><body><nav>Menü</nav><main>
        <div class="comment"><span class="author">Muster, Kim</span><time>19.11.2026 08:15</time><p>Beamer in 2b geht nicht.</p></div>
        <div class="comment"><span class="author">Admin, IT</span><time>20.11.2026 09:00</time><p>Lampe bestellt.</p></div>
        <form method="post" action="/iserv/defect/42/comment"><input type="hidden" name="_token" value="abc&amp;1">
        <textarea name="defect_comment[content]"></textarea><button type="submit" name="defect_comment[submit]">Senden</button></form>
        </main></body></html>
        """
        let v = Stoerungen.verlaufAus(html, von: "https://schule.de/iserv/defect/42")
        XCTAssertEqual(v.eintraege.map(\.text), ["Beamer in 2b geht nicht.", "Lampe bestellt."])
        XCTAssertEqual(v.eintraege.first?.zeit, "19.11.2026 08:15")
        XCTAssertEqual(v.formular?.aktion, "https://schule.de/iserv/defect/42/comment")
        XCTAssertEqual(v.formular?.textFeld, "defect_comment[content]")
        XCTAssertEqual(v.formular?.felder.first?.1, "abc&1")
        XCTAssertTrue(v.formular?.felder.contains { $0.0 == "defect_comment[submit]" } ?? false)
    }

    func testStoerungOhneKommentarbloecke() {
        let v = Stoerungen.verlaufAus("<main><h1>Drucker</h1><p>Papierstau</p></main>", von: "https://schule.de/x")
        XCTAssertEqual(v.eintraege.count, 1)
        XCTAssertTrue(v.eintraege[0].text.contains("Papierstau"))
        XCTAssertNil(v.formular)
    }
}
